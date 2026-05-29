# Dune Datashares

Datashares sync Dune tables to external data warehouses such as Snowflake and BigQuery so downstream consumers can query the data outside Dune.

## Prerequisites

Datashare is an enterprise feature that requires setup before any SQL statements will work:

1. Contract and feature enablement with Dune.
2. Target warehouse configuration in Dune backoffice.
3. A Dune API key with Data Transformations access.

If datashare is not enabled for your team, the SQL statements below will fail with an authorization error.

Datashare syncs are billed based on bytes transferred and byte-months of storage for the synced table.

## What This Template Includes

This template ships with datashare support already wired in:

- `macros/dune_dbt_overrides/datashare_table_sync_post_hook.sql`
- a global post-hook in `dbt_project.yml` that calls `datashare_trigger_sync()`
- an opt-in example model at `models/templates/dbt_template_datashare_incremental_model.sql`

Models without `meta.datashare` are unchanged. The hook skips them.

The built-in post-hook only executes on the `prod` target, so local `dev` runs and CI temp schemas do not create datashare syncs by default.

## Supported Models

Datashare sync is only applied to `table` and `incremental` models.

Views are skipped.

## Enable Datashare On A Model

Add `meta.datashare` to a `table` or `incremental` model:

```sql
{%- set time_start_incremental = "current_date - interval '1' day" -%}
{%- set time_start = "current_date - interval '2' day" -%}
{%- set time_end = "current_date + interval '1' day" -%}

{{ config(
    alias = 'my_datashared_model'
    , materialized = 'incremental'
    , incremental_strategy = 'merge'
    , unique_key = ['block_number', 'block_date']
    , meta = {
        "datashare": {
            "enabled": true,
            "time_column": "block_date",
            "time_start": time_start,
            "time_start_incremental": time_start_incremental,
            "time_end": time_end
        }
    }
) }}

select ...
```

The included example model in this repo follows this pattern.

### Why Two time_start Values

The `meta` dict is captured by dbt at **parse time**, before any adapter state is known. `is_incremental()` always returns `false` during parsing, so a `{% set time_start = "..." if is_incremental() else "..." %}` preamble (as used in older examples and upstream docs) silently freezes the value to the `else` branch on every run.

To actually vary the sync window by run type, provide two static expressions in `meta.datashare`:

- `time_start` — used on **full-refresh** syncs (first run, `--full-refresh`, fingerprint/stamp change)
- `time_start_incremental` — used on **normal incremental** syncs (optional; falls back to `time_start` if omitted)

The post-hook macro evaluates `is_incremental()` at execution time and picks the correct value.

## Configuration Reference

All datashare config lives under `meta.datashare` in the model `config()` block.

| Property | Required | Type | Description |
| --- | --- | --- | --- |
| `enabled` | Yes | `boolean` | Must be `true` to trigger sync. |
| `time_column` | Yes | `string` | Column used to define the sync window. |
| `time_start` | Yes | `string` | SQL expression for the start of the full-refresh sync window. |
| `time_start_incremental` | No | `string` | SQL expression for incremental runs. Falls back to `time_start` if omitted. |
| `time_end` | No | `string` | SQL expression for the end of the sync window. Defaults to `now()`. |
| `unique_key_columns` | No | `list[string]` | Row identity columns. Falls back to the model `unique_key` if omitted. |

All time expressions are SQL, not literal timestamps. The macro wraps them in `CAST(... AS VARCHAR)` before calling the table procedure.

Keep the sync window aligned with the `time_column` granularity. For example, if `time_column` is a `date`, use date-based expressions like `current_date - interval '1' day`, not hour-based timestamp windows.

## Cadence and sync windows

The `time_start_incremental` → `time_end` window and your dbt **run cadence** are not independent knobs. Every incremental sync issues a `MERGE INTO` against the destination table, which re-reads the destination data covered by that window. On **S3 Export** targets where the destination bucket is in a different region from Trino, each run pays cross-region transfer for the entire window.

The cost amplification factor is:

```
remote_read_multiplier = MERGE read window / run cadence
```

Examples:

| Cadence | `time_column` | Incremental window         | Multiplier | Notes |
| ------- | ------------- | -------------------------- | ---------- | ----- |
| Daily   | `date`        | `interval '1' day`         | 1x         | Safe default. The included example model uses this shape. |
| Hourly  | `timestamp`   | `interval '2' hour`        | 2x         | Use only when `time_column` is timestamp-granular and the destination is partitioned/prunable on it. |
| Hourly  | `date`        | `interval '1' day`         | 24x        | **Cost trap.** Every hourly run re-reads the full day's partition from the destination. |

Rules of thumb:

- Date-granularity `time_column` (e.g. `block_date`) → **daily cadence**. Sub-day windows on a date column do nothing useful: the smallest prunable unit is one day.
- Hourly (or sub-day) cadence → **timestamp** `time_column` AND an hour-sized incremental window. Confirm the destination table is partitioned on that timestamp so MERGE actually prunes.
- The `time_start` (full-refresh) value can stay wider than `time_start_incremental` — full refreshes are infrequent, the multiplier only applies to incremental cadence.

### Hourly cadence example

```sql
{%- set time_start_incremental = "current_timestamp - interval '2' hour" -%}
{%- set time_start = "current_timestamp - interval '1' day" -%}
{%- set time_end = "current_timestamp" -%}

{{ config(
    materialized = 'incremental',
    incremental_strategy = 'merge',
    unique_key = ['tx_hash'],
    incremental_predicates = ["DBT_INTERNAL_DEST.block_time >= " ~ time_start_incremental],
    meta = {
        "datashare": {
            "enabled": true,
            "time_column": "block_time",
            "time_start": time_start,
            "time_start_incremental": time_start_incremental,
            "time_end": time_end
        }
    },
    properties = {"partitioned_by": "ARRAY['date(block_time)']"}
) }}
```

## Full Refresh Behavior

The macro determines `full_refresh` automatically:

| Context | `full_refresh` |
| --- | --- |
| Incremental post-hook on a normal incremental run | `false` |
| Incremental post-hook on first run or `--full-refresh` | `true` |
| Table materialization post-hook | `true` |
| `run-operation` | `false` unless overridden |

## Generated SQL

The post-hook generates this Trino statement:

```sql
ALTER TABLE dune.<schema>.<table> EXECUTE datashare(
    time_column => '<column_name>',
    unique_key_columns => ARRAY['col1', 'col2'],
    time_start => CAST(<sql_expression> AS VARCHAR),
    time_end => CAST(<sql_expression> AS VARCHAR),
    full_refresh => true|false
)
```

## Manual Syncs

Use `run-operation` when you want to trigger a sync outside `dbt run`.

Preview the generated SQL only:

```bash
uv run dbt run-operation datashare_trigger_sync_operation --args '
model_selector: dbt_template_datashare_incremental_model
dry_run: true
'
```

Execute a sync:

```bash
uv run dbt run-operation datashare_trigger_sync_operation --args '
model_selector: dbt_template_datashare_incremental_model
time_start: "current_date - interval '\''7'\'' day"
time_end: "current_date + interval '\''1'\'' day"
'
```

Force a full refresh sync:

```bash
uv run dbt run-operation datashare_trigger_sync_operation --args '
model_selector: dbt_template_datashare_incremental_model
full_refresh: true
'
```

`model_selector` accepts the model name, alias, fully qualified name, or dbt `unique_id`.

## Monitoring

Check the datashare system tables after a run:

```sql
SELECT *
FROM dune.datashare.table_syncs
WHERE source_schema = '<your_schema>';

SELECT *
FROM dune.datashare.table_sync_runs
WHERE source_schema = '<your_schema>'
ORDER BY created_at DESC;
```

`table_syncs` shows the registered share and its latest status.

`table_sync_runs` shows individual sync attempts, including the time window and whether the run was a full refresh.

## Cleanup

Remove a table from datashare with:

```sql
ALTER TABLE dune.<schema>.<table> EXECUTE delete_datashare
```

## Example Workflow

1. Configure a model with `meta.datashare`.
2. Run it with `uv run dbt run --select my_model --target prod`.
3. Confirm the datashare registration in `dune.datashare.table_syncs`.
4. Inspect run history in `dune.datashare.table_sync_runs`.

## Further Reading

- [Supported SQL Operations](https://docs.dune.com/api-reference/connectors/sql-operations)
- [dbt connector overview](https://docs.dune.com/api-reference/connectors/dbt/overview)
