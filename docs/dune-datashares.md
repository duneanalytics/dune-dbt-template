# Dune Datashares

Datashare syncs Dune tables to external data warehouses (Snowflake, BigQuery) so downstream consumers can query the data outside Dune.

## Prerequisites

Datashare is an **enterprise feature** that requires setup before it can be used:

1. **Contract** — your organization and Dune agree on a datashare feature contract
2. **Target configuration** — Dune support engineering configures the target data warehouse credentials (Snowflake, BigQuery, etc.) via the Dune backoffice
3. **SQL usage** — once configured, you use SQL statements to register tables and trigger sync

If datashare is not enabled for your account, the SQL statements below will fail with an authorization error.

## How it works

After each `dbt run`, a post-hook can execute an `ALTER TABLE ... EXECUTE datashare(...)` statement on Trino. This tells Dune to sync the table's data to your configured destination within a specified time window.

The sync is **opt-in per model** via the `meta.datashare` config block. Only `table` and `incremental` materializations are supported — views are skipped.

## Setup

### 1. Add the datashare macro

Copy [`datashare_table_sync_post_hook.sql`](https://github.com/duneanalytics/dbt-template-datashare/blob/main/macros/dune_dbt_overrides/datashare_table_sync_post_hook.sql) into your `macros/dune_dbt_overrides/` directory.

### 2. Register the post-hook

Add the datashare post-hook to your `dbt_project.yml`:

```yaml
models:
  your_project:
    +post-hook:
      # existing hooks...
      - sql: "{{ optimize_table(this, model.config.materialized) }}"
        transaction: true
      - sql: "{{ vacuum_table(this, model.config.materialized) }}"
        transaction: true
      # datashare hook (runs after optimize/vacuum)
      - sql: "{{ datashare_trigger_sync() }}"
        transaction: true
```

### 3. Configure a model

Add `meta.datashare` to any model you want to sync:

```sql
{% set time_start = "now() - interval '1' day" if is_incremental() else "timestamp '2026-01-01'" %}

{{ config(
    alias = 'my_model'
    , materialized = 'incremental'
    , incremental_strategy = 'merge'
    , unique_key = ['id']
    , meta = {
        "datashare": {
            "enabled": true,
            "time_column": "block_date",
            "unique_key_columns": ["id"],
            "time_start": time_start,
            "time_end": "now()"
        }
    }
) }}

select ...
```

Models without `meta.datashare` are unaffected — the post-hook skips them.

## Configuration reference

All datashare config lives under `meta.datashare` in the model's `config()` block.

| Property | Required | Type | Description |
|---|---|---|---|
| `enabled` | Yes | `boolean` | Must be `true` to trigger sync. Set to `false` to disable without removing config. |
| `time_column` | No | `string` | Column name used to define the sync time window. Omit for non-timeseries tables synced with `full_refresh`. |
| `time_start` | No | `string` | SQL expression for the start of the sync window. Evaluated at runtime. |
| `time_end` | No | `string` | SQL expression for the end of the sync window. Defaults to `now()`. |
| `unique_key_columns` | No | `list[string]` | Columns that uniquely identify a row. Falls back to model's `unique_key` if not set. |

### Time expressions

`time_start` and `time_end` are SQL expressions (not literal timestamps). They are wrapped in `CAST(... AS VARCHAR)` by the macro. Common patterns:

```sql
-- Fixed timestamp
"time_start": "timestamp '2026-01-01'"

-- Relative to now
"time_start": "now() - interval '7' day"

-- Different window for incremental vs full refresh
{% set time_start = "now() - interval '1' day" if is_incremental() else "timestamp '2026-01-01'" %}
```

### `full_refresh` behavior

The macro determines `full_refresh` automatically:

| Context | `full_refresh` value |
|---|---|
| Post-hook, incremental run | `false` |
| Post-hook, first run or `--full-refresh` | `true` |
| Post-hook, `table` materialization | `true` (always) |
| `run-operation` | `false` (unless overridden) |

## SQL reference

The underlying Trino statement is:

```sql
ALTER TABLE dune.<schema>.<table> EXECUTE datashare(
    time_column        => '<column_name>',
    unique_key_columns => ARRAY['col1', 'col2'],
    time_start         => '<timestamp_string>',
    time_end           => '<timestamp_string>',
    full_refresh       => true|false
)
```

You can run this directly via any Trino-compatible client without dbt.

To remove a table from datashare:

```sql
ALTER TABLE dune.<schema>.<table> EXECUTE delete_datashare
```

### Monitoring

Query the datashare system tables to check sync status and history:

```sql
-- List all active datashare registrations for your team
SELECT * FROM dune.datashare.table_syncs

-- View sync run history (status, duration, time window)
SELECT * FROM dune.datashare.table_sync_runs
```

`table_syncs` shows your registered datashares: source table, target type/region, share status, last successful sync time.

`table_sync_runs` shows individual sync executions: status, duration, time window, whether it was a full refresh.

Results are scoped to your team.

## Manual sync via run-operation

For one-off syncs outside of `dbt run`:

```bash
# Execute a sync
uv run dbt run-operation datashare_trigger_sync_operation --args '
model_selector: my_model
time_start: "timestamp '\''2026-01-01'\''"
time_end: "now()"
'

# Dry run (preview SQL only)
uv run dbt run-operation datashare_trigger_sync_operation --args '
model_selector: my_model
dry_run: true
'

# Force full refresh
uv run dbt run-operation datashare_trigger_sync_operation --args '
model_selector: my_model
full_refresh: true
'
```

## Further reading

- [dbt-template-datashare](https://github.com/duneanalytics/dbt-template-datashare) — reference implementation with example models
- [Supported SQL Operations](https://docs.dune.com/api-reference/connectors/sql-operations) — full DDL/DML reference including table visibility
