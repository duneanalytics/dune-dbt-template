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
    Returns true if an active (non-deleted) datashare sync exists for this table.
    Scoped to a target only when both target_type and target_region are given,
    since a partial key would match a different target of the same table.
    Returns true on probe failure so the caller keeps its is_incremental() behavior.
#}
{% macro _datashare_active_sync_exists(schema_name, table_name, target_type=None, target_region=None) %}
    {%- if not execute -%}
        {{ return(true) }}
    {%- endif -%}
    {%- set has_type = target_type is not none and target_type | string | trim != '' -%}
    {%- set has_region = target_region is not none and target_region | string | trim != '' -%}
    {%- set where = [] -%}
    {%- do where.append('source_schema = ' ~ _datashare_sql_string(schema_name)) -%}
    {%- do where.append('source_table = ' ~ _datashare_sql_string(table_name)) -%}
    {%- do where.append('deleted_at IS NULL') -%}
    {%- if has_type and has_region -%}
        {%- do where.append('target_type = ' ~ _datashare_sql_string(target_type)) -%}
        {%- do where.append('target_region = ' ~ _datashare_sql_string(target_region)) -%}
    {%- endif -%}
    {%- set probe_sql = 'SELECT count(*) AS c FROM dune.datashare.table_syncs WHERE ' ~ (where | join(' AND ')) -%}
    {%- set result = none -%}
    {%- set probe = run_query(probe_sql) -%}
    {%- if probe is not none and probe.columns | length > 0 and probe.columns[0].values() | length > 0 -%}
        {%- set result = probe.columns[0].values()[0] -%}
    {%- endif -%}
    {%- if result is none -%}
        {{ log('datashare sync probe for ' ~ schema_name ~ '.' ~ table_name ~ ' returned no rows; assuming sync exists.', info=True) }}
        {{ return(true) }}
    {%- endif -%}
    {{ return(result | int > 0) }}
{%- endmacro -%}

{#
    Datashare sync macro - generates ALTER TABLE ... EXECUTE datashare()/sync_datashare()
    SQL depending on which meta block is configured. Config reference: docs/dune-datashares.md
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
    {%- set legacy_datashare = meta.get('datashare') if meta is mapping else none -%}
    {%- set datashare_sync = meta.get('datashare_sync') if meta is mapping else none -%}
    {%- set has_legacy = legacy_datashare is mapping -%}
    {%- set has_sync = datashare_sync is mapping -%}

    {%- if has_legacy and has_sync -%}
        {{ exceptions.raise_compiler_error(
            "Model " ~ model_ref ~ " has both meta.datashare and meta.datashare_sync configured."
            ~ " Keep exactly one: meta.datashare to sync a time window,"
            ~ " meta.datashare_sync to sync without one."
        ) }}
    {%- endif -%}

    {%- if not has_legacy and not has_sync -%}
        {{ log('Skipping datashare sync for ' ~ model_ref ~ ': neither meta.datashare nor meta.datashare_sync is configured.', info=True) }}
        {{ return(none) }}
    {%- endif -%}

    {%- if materialized not in ['incremental', 'table'] -%}
        {{ log('Skipping datashare sync for ' ~ model_ref ~ ': materialization "' ~ materialized ~ '" is not incremental/table.') }}
        {{ return(none) }}
    {%- endif -%}

    {%- if has_sync -%}
        {#- Reject anything this block does not act on, so a misspelled key fails
            loudly instead of silently syncing a different shape than asked for. -#}
        {%- set supported_sync_keys = ['enabled', 'partitioning'] -%}
        {%- set unsupported_keys = [] -%}
        {%- for key in datashare_sync.keys() -%}
            {%- if key not in supported_sync_keys -%}
                {%- do unsupported_keys.append(key) -%}
            {%- endif -%}
        {%- endfor -%}
        {%- if unsupported_keys | length > 0 -%}
            {{ exceptions.raise_compiler_error(
                "Model " ~ model_ref ~ " has unsupported meta.datashare_sync keys: "
                ~ (unsupported_keys | sort | join(', '))
                ~ ". Supported keys: " ~ (supported_sync_keys | join(', ')) ~ "."
            ) }}
        {%- endif -%}
        {%- if time_start is not none or time_end is not none -%}
            {{ exceptions.raise_compiler_error(
                "Model " ~ model_ref ~ " uses meta.datashare_sync, which syncs without a time window."
                ~ " Drop time_start/time_end."
            ) }}
        {%- endif -%}
        {%- if datashare_sync.get('enabled') is not sameas true -%}
            {{ log('Skipping datashare sync for ' ~ model_ref ~ ': meta.datashare_sync.enabled is not true.', info=True) }}
            {{ return(none) }}
        {%- endif -%}
        {%- set partitioning = datashare_sync.get('partitioning') -%}
        {%- set include_partitioning = partitioning is not none and partitioning | string | trim != '' -%}
        {%- set sql -%}
ALTER TABLE {{ catalog_name }}.{{ schema_name }}.{{ table_name }} EXECUTE sync_datashare(
    unique_key_columns => {{ _datashare_unique_key_columns_sql(unique_key) }},
    full_refresh => {{ 'true' if full_refresh else 'false' }}
{%- if include_partitioning -%}
    , partitioning => {{ _datashare_sql_string(partitioning) }}
{%- endif -%}
)
        {%- endset -%}
        {{ log('datashare sync preview for ' ~ model_ref ~ ':\n' ~ sql, info=True) }}
        {{ return(sql) }}
    {%- endif -%}

    {%- set datashare = legacy_datashare -%}
    {%- if datashare.get('enabled') is not sameas true -%}
        {{ log('Skipping datashare sync for ' ~ model_ref ~ ': meta.datashare.enabled is not true.', info=True) }}
        {{ return(none) }}
    {%- endif -%}
    {%- set time_column = datashare.get('time_column') -%}
    {%- set resolved_time_start = time_start if time_start is not none else datashare.get('time_start') -%}
    {%- set resolved_time_end = time_end if time_end is not none else datashare.get('time_end', 'now()') -%}
    {%- set target_type = datashare.get('target_type') -%}
    {%- set target_region = datashare.get('target_region') -%}
    {%- set include_target_type = target_type is not none and target_type | string | trim != '' -%}
    {%- set include_target_region = target_region is not none and target_region | string | trim != '' -%}

    {#- An incremental sync targets an existing destination via MERGE. If the
        destination sync was revoked while the source table still exists, dbt
        builds incrementally but there is nothing to merge into. Force a full
        refresh when no active sync is registered for this table/target. -#}
    {%- if not full_refresh and not _datashare_active_sync_exists(schema_name, table_name, target_type, target_region) -%}
        {{ log('No active datashare sync for ' ~ model_ref ~ '; forcing full_refresh.', info=True) }}
        {%- set full_refresh = true -%}
    {%- endif -%}

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

{% macro datashare_trigger_sync_operation(model_selector, time_start=None, time_end=None, dry_run=False, full_refresh=False, allow_prod_only=True) %}
    {%- set node = _datashare_resolve_model_node(model_selector) -%}
    {%- set node_config = node.config if node.config is mapping else {} -%}
    {%- set materialized = node_config.get('materialized', 'view') -%}
    {%- set table_name = node.alias if node.alias is not none else node.name -%}
    {%- set is_full_refresh = materialized == 'table' or full_refresh is sameas true -%}
    {%- set is_dry_run = dry_run is sameas true or (dry_run is string and dry_run | lower in ['true', '1', 'yes', 'y']) -%}
    {%- set allow_prod_only = false if (allow_prod_only is sameas false or (allow_prod_only is string and allow_prod_only | lower in ['false', '0', 'no', 'n'])) else true -%}

    {#- The post-hook guards on target, but this path resolves the schema straight
        from the manifest, so on a dev target it registers the temp schema as a
        real datashare and ships it to the destination. Fail loudly rather than
        skip silently: the caller explicitly asked for a sync. -#}
    {%- if target.name != 'prod' and allow_prod_only and not is_dry_run -%}
        {{ exceptions.raise_compiler_error(
            "Refusing datashare sync for '" ~ model_selector ~ "' on target '" ~ target.name
            ~ "': the source schema would be '" ~ node.schema ~ "'. Datashare syncs must run against prod."
            ~ " Re-run with --target prod, or pass dry_run: true to preview the SQL."
        ) }}
    {%- endif -%}

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
        {{ exceptions.raise_compiler_error("Cannot sync " ~ node.schema ~ "." ~ table_name ~ ": model must be incremental or table with meta.datashare.enabled or meta.datashare_sync.enabled set to true.") }}
    {%- endif -%}

    {%- if not is_dry_run -%}
        {% do run_query(sql) %}
        {{ log('Executed datashare sync for selector ' ~ model_selector, info=True) }}
    {%- endif -%}
    {{ return(sql) }}
{%- endmacro -%}
