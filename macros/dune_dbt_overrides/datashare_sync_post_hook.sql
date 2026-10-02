{% macro _datashare_sql_string(value) %}
    {{ return("'" ~ (value | string | replace("'", "''")) ~ "'") }}
{%- endmacro -%}

{% macro _datashare_unique_key_columns_sql(unique_key, model_ref) %}
    {%- set columns = [unique_key] if unique_key is string else unique_key -%}
    {%- if columns is not sequence or columns is mapping or columns | length == 0 -%}
        {{ exceptions.raise_compiler_error("Model " ~ model_ref ~ " must set a non-empty unique_key for datashare sync.") }}
    {%- endif -%}
    {%- set quoted = [] -%}
    {%- for column in columns -%}
        {%- if column is not string or column | trim == '' -%}
            {{ exceptions.raise_compiler_error("Model " ~ model_ref ~ " unique_key must contain non-empty column names.") }}
        {%- endif -%}
        {%- do quoted.append(_datashare_sql_string(column)) -%}
    {%- endfor -%}
    {{ return("ARRAY[" ~ quoted | join(', ') ~ "]") }}
{%- endmacro -%}

{% macro _datashare_sync_validate_config(model_ref, datashare_sync, properties) %}
    {%- set supported_keys = ['enabled', 'partitioning'] -%}
    {%- set unsupported_keys = [] -%}
    {%- for key in datashare_sync.keys() -%}
        {%- if key not in supported_keys -%}
            {%- do unsupported_keys.append(key) -%}
        {%- endif -%}
    {%- endfor -%}
    {%- if unsupported_keys | length > 0 -%}
        {{ exceptions.raise_compiler_error(
            "Model " ~ model_ref ~ " has unsupported meta.datashare_sync keys: "
            ~ (unsupported_keys | sort | join(', '))
            ~ ". Supported keys: " ~ (supported_keys | join(', ')) ~ "."
        ) }}
    {%- endif -%}
    {%- set props = properties if properties is mapping else {} -%}
    {%- set cdf_raw = props.get('change_data_feed_enabled') -%}
    {%- if cdf_raw is not sameas true and (cdf_raw | string | lower | trim) != 'true' -%}
        {{ exceptions.raise_compiler_error(
            "Model " ~ model_ref ~ " uses meta.datashare_sync and must set "
            ~ "properties.change_data_feed_enabled = true so Dune can sync "
            ~ "changes from the table. See docs/dune-datashares.md."
        ) }}
    {%- endif -%}
{%- endmacro -%}

{% macro _datashare_sync_sql(
    schema_name
    , table_name
    , meta
    , materialized
    , unique_key=None
    , full_refresh=False
    , catalog_name=target.database
    , properties=None
) %}
    {%- set model_ref = schema_name ~ '.' ~ table_name -%}
    {%- set datashare_sync = meta.get('datashare_sync') if meta is mapping else none -%}
    {%- if datashare_sync is not mapping or datashare_sync.get('enabled') is not sameas true -%}
        {{ return(none) }}
    {%- endif -%}
    {%- if materialized not in ['incremental', 'table'] -%}
        {{ return(none) }}
    {%- endif -%}
    {{ _datashare_sync_validate_config(model_ref, datashare_sync, properties) }}
    {%- set columns_sql = _datashare_unique_key_columns_sql(unique_key, model_ref) -%}
    {%- set partitioning = datashare_sync.get('partitioning') -%}
    {%- set sql -%}
ALTER TABLE {{ catalog_name }}.{{ schema_name }}.{{ table_name }} EXECUTE sync_datashare(
    unique_key_columns => {{ columns_sql }},
    full_refresh => {{ 'true' if full_refresh else 'false' }}
{%- if partitioning is not none and partitioning | string | trim != '' -%}
    , partitioning => {{ _datashare_sql_string(partitioning) }}
{%- endif -%}
)
    {%- endset -%}
    {{ log('datashare sync preview for ' ~ model_ref ~ ':\n' ~ sql, info=True) }}
    {{ return(sql) }}
{%- endmacro -%}

{% macro datashare_trigger_sync() %}
    {%- if target.name != 'prod' -%}
        {{ return('') }}
    {%- endif -%}
    {{ return(_datashare_sync_sql(
        schema_name=this.schema,
        table_name=this.identifier,
        meta=model.config.get('meta', {}),
        materialized=model.config.materialized,
        unique_key=model.config.get('unique_key'),
        full_refresh=(not is_incremental()),
        properties=model.config.get('properties')
    ) or '') }}
{%- endmacro -%}

{% macro _datashare_resolve_model_node(model_selector) %}
    {%- set matches = [] -%}
    {%- for node in graph.nodes.values() -%}
        {%- if node.resource_type == 'model' -%}
            {%- set fqn_name = node.fqn | join('.') -%}
            {%- if model_selector in [node.unique_id, node.name, node.alias, fqn_name] -%}
                {%- do matches.append(node) -%}
            {%- endif -%}
        {%- endif -%}
    {%- endfor -%}
    {%- if matches | length == 0 -%}
        {{ exceptions.raise_compiler_error("No model found for selector '" ~ model_selector ~ "'. Use model name, alias, fqn, or unique_id.") }}
    {%- endif -%}
    {%- if matches | length > 1 -%}
        {{ exceptions.raise_compiler_error("Model selector '" ~ model_selector ~ "' is ambiguous. Matches: " ~ (matches | map(attribute='unique_id') | join(', '))) }}
    {%- endif -%}
    {{ return(matches[0]) }}
{%- endmacro -%}

{% macro datashare_trigger_sync_operation(model_selector, dry_run=False, full_refresh=False, allow_prod_only=True) %}
    {%- set node = _datashare_resolve_model_node(model_selector) -%}
    {%- set node_config = node.config -%}
    {%- set materialized = node_config.get('materialized', 'view') -%}
    {%- set is_dry_run = dry_run is sameas true or (dry_run is string and dry_run | lower in ['true', '1', 'yes', 'y']) -%}
    {%- set allow_prod_only = false if (allow_prod_only is sameas false or (allow_prod_only is string and allow_prod_only | lower in ['false', '0', 'no', 'n'])) else true -%}
    {#- A dev manifest names a temp schema, which would register an ephemeral source. -#}
    {%- if target.name != 'prod' and allow_prod_only and not is_dry_run -%}
        {{ exceptions.raise_compiler_error(
            "Refusing datashare sync for '" ~ model_selector ~ "' on target '" ~ target.name
            ~ "': the source schema would be '" ~ node.schema ~ "'. Datashare syncs must run against prod."
            ~ " Re-run with --target prod, or pass dry_run: true to preview the SQL."
        ) }}
    {%- endif -%}
    {%- set sql = _datashare_sync_sql(
        schema_name=node.schema,
        table_name=node.alias or node.name,
        meta=node_config.get('meta', {}),
        materialized=materialized,
        unique_key=node_config.get('unique_key'),
        full_refresh=(materialized == 'table' or full_refresh is sameas true),
        catalog_name=node.database or target.database,
        properties=node_config.get('properties')
    ) -%}
    {%- if sql is none -%}
        {{ exceptions.raise_compiler_error("Cannot sync " ~ node.schema ~ "." ~ node.name ~ ": model must be incremental or table with meta.datashare_sync.enabled set to true.") }}
    {%- endif -%}
    {%- if not is_dry_run -%}
        {% do run_query(sql) %}
        {{ log('Executed datashare sync for selector ' ~ model_selector, info=True) }}
    {%- endif -%}
    {{ return(sql) }}
{%- endmacro -%}
