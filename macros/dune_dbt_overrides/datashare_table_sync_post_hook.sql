{% macro _datashare_sql_string(value) %}
    {{ return("'" ~ (value | string | replace("'", "''")) ~ "'") }}
{%- endmacro -%}

{% macro _datashare_unique_key_columns_sql(unique_key_columns) %}
    {%- if unique_key_columns is string -%}
        {%- set unique_key_columns = [unique_key_columns] -%}
    {%- elif unique_key_columns is not iterable or unique_key_columns is mapping -%}
        {{ return("CAST(ARRAY[] AS ARRAY(VARCHAR))") }}
    {%- endif -%}
    {%- set quoted = [] -%}
    {%- for col in unique_key_columns -%}
        {%- do quoted.append(_datashare_sql_string(col)) -%}
    {%- endfor -%}
    {{ return("CAST(ARRAY[] AS ARRAY(VARCHAR))" if quoted | length == 0 else "ARRAY[" ~ quoted | join(', ') ~ "]") }}
{%- endmacro -%}

{% macro _datashare_optional_time_sql(value) %}
    {{ return('NULL' if value is none else 'CAST(' ~ value ~ ' AS VARCHAR)') }}
{%- endmacro -%}

{#
    Datashare sync macro - generates ALTER TABLE ... EXECUTE datashare() SQL.
    Config reference and usage: docs/dune-datashares.md
#}
{% macro _datashare_table_sync_sql(
    schema_name
    , table_name
    , meta
    , materialized
    , unique_key=None
    , time_start=None
    , time_end=None
    , full_refresh=False
    , catalog_name=target.database
) %}
    {%- set model_ref = schema_name ~ '.' ~ table_name -%}
    {%- if meta is not mapping or meta.get('datashare') is none or meta.get('datashare') is not mapping -%}
        {{ log('Skipping datashare sync for ' ~ model_ref ~ ': meta.datashare is not configured.', info=True) }}
        {{ return(none) }}
    {%- endif -%}
    {%- set datashare = meta.get('datashare') -%}
    {%- if datashare.get('enabled') is not sameas true -%}
        {{ log('Skipping datashare sync for ' ~ model_ref ~ ': meta.datashare.enabled is not true.', info=True) }}
        {{ return(none) }}
    {%- endif -%}
    {%- if materialized not in ['incremental', 'table'] -%}
        {{ log('Skipping datashare sync for ' ~ model_ref ~ ': materialization "' ~ materialized ~ '" is not incremental/table.') }}
        {{ return(none) }}
    {%- endif -%}
    {%- set time_column = datashare.get('time_column') -%}
    {%- set resolved_time_start = time_start if time_start is not none else datashare.get('time_start') -%}
    {%- set resolved_time_end = time_end if time_end is not none else datashare.get('time_end', 'now()') -%}
    {%- set target_type = datashare.get('target_type') -%}
    {%- set target_region = datashare.get('target_region') -%}
    {%- set include_target_type = target_type is not none and target_type | string | trim != '' -%}
    {%- set include_target_region = target_region is not none and target_region | string | trim != '' -%}

    {%- set sql -%}
ALTER TABLE {{ catalog_name }}.{{ schema_name }}.{{ table_name }} EXECUTE datashare(
    time_column => {{ _datashare_sql_string(time_column | default('', true)) }},
    unique_key_columns => {{ _datashare_unique_key_columns_sql(datashare.get('unique_key_columns', unique_key)) }},
    time_start => {{ _datashare_optional_time_sql(resolved_time_start) }},
    time_end => {{ _datashare_optional_time_sql(resolved_time_end) }},
    full_refresh => {{ 'true' if full_refresh else 'false' }}
{%- if include_target_type -%}
    , target_type => {{ _datashare_sql_string(target_type) }}
{%- endif -%}
{%- if include_target_region -%}
    , target_region => {{ _datashare_sql_string(target_region) }}
{%- endif -%}
)
    {%- endset -%}
    {{ log('datashare sync preview for ' ~ model_ref ~ ':\n' ~ sql, info=True) }}
    {{ return(sql) }}
{%- endmacro -%}

{% macro datashare_trigger_sync() %}
    {%- if target.name != 'prod' -%}
        {{ log('Skipping datashare sync for ' ~ this.schema ~ '.' ~ this.identifier ~ ': datashare post-hook only runs on the prod target.', info=True) }}
        {{ return('') }}
    {%- endif -%}
    {#- Resolve time_start at execution time. meta.datashare is frozen at parse
        time and is_incremental() always returns false during parsing, so the
        picker must live here. meta.datashare.time_start_incremental is optional
        and falls back to meta.datashare.time_start. -#}
    {%- set meta = model.config.get('meta', {}) -%}
    {%- set datashare = meta.get('datashare') if meta is mapping else none -%}
    {%- set resolved_time_start = none -%}
    {%- if datashare is mapping and is_incremental() -%}
        {%- set resolved_time_start = datashare.get('time_start_incremental') -%}
    {%- endif -%}
    {{ return(_datashare_table_sync_sql(
        schema_name=this.schema,
        table_name=this.identifier,
        meta=meta,
        materialized=model.config.materialized,
        unique_key=model.config.get('unique_key'),
        time_start=resolved_time_start,
        full_refresh=(not is_incremental())
    ) or '') }}
{%- endmacro -%}

{% macro _datashare_resolve_model_node(model_selector) %}
    {%- set matches = [] -%}
    {%- for node in graph.nodes.values() -%}
        {%- if node.resource_type == 'model' -%}
            {%- set fqn_name = node.fqn | join('.') -%}
            {%- if node.unique_id == model_selector or node.name == model_selector or node.alias == model_selector or fqn_name == model_selector -%}
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

{% macro datashare_trigger_sync_operation(model_selector, time_start=None, time_end=None, dry_run=False, full_refresh=False) %}
    {%- set node = _datashare_resolve_model_node(model_selector) -%}
    {%- set node_config = node.config if node.config is mapping else {} -%}
    {%- set materialized = node_config.get('materialized', 'view') -%}
    {%- set table_name = node.alias if node.alias is not none else node.name -%}
    {%- set is_full_refresh = materialized == 'table' or full_refresh is sameas true -%}

    {#- Mirror the post-hook picker: when running an incremental sync and no
        explicit time_start was passed, prefer meta.datashare.time_start_incremental
        if set. Falls back to meta.datashare.time_start otherwise. -#}
    {%- set resolved_time_start = time_start -%}
    {%- if resolved_time_start is none and not is_full_refresh -%}
        {%- set meta = node_config.get('meta', {}) -%}
        {%- set datashare = meta.get('datashare') if meta is mapping else none -%}
        {%- if datashare is mapping -%}
            {%- set resolved_time_start = datashare.get('time_start_incremental') -%}
        {%- endif -%}
    {%- endif -%}

    {%- set sql = _datashare_table_sync_sql(
        schema_name=node.schema,
        table_name=table_name,
        meta=node_config.get('meta', {}),
        materialized=materialized,
        unique_key=node_config.get('unique_key'),
        time_start=resolved_time_start,
        time_end=time_end,
        full_refresh=is_full_refresh,
        catalog_name=node.database or target.database
    ) -%}

    {%- if sql is none -%}
        {{ exceptions.raise_compiler_error("Cannot sync " ~ node.schema ~ "." ~ table_name ~ ": model must be incremental or table with meta.datashare.enabled = true.") }}
    {%- endif -%}

    {%- set is_dry_run = dry_run is sameas true or (dry_run is string and dry_run | lower in ['true', '1', 'yes', 'y']) -%}
    {%- if not is_dry_run -%}
        {% do run_query(sql) %}
        {{ log('Executed datashare sync for selector ' ~ model_selector, info=True) }}
    {%- endif -%}
    {{ return(sql) }}
{%- endmacro -%}
