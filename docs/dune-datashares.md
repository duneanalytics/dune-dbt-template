# Dune Datashares

This template uses datashares with change data feed (CDF). Dune copies the source snapshot on the first sync, then applies changes from the last completed watermark. Dune resolves your team's registered destination.

## Prerequisites

1. Enable datashares through your enterprise contract with Dune.
2. Configure your team's destination with Dune.
3. Use a Dune API key with Data Transformations access.

Syncs are billed for bytes transferred and byte-months of storage. Automated dbt runs also consume query credits.

## Enable a Model

The global post-hook in `dbt_project.yml` calls `datashare_trigger_sync()` from `macros/dune_dbt_overrides/datashare_sync_post_hook.sql`. It skips views, models without enabled sync metadata, and targets other than `prod`.

Configure a `table` or `incremental` model:

```sql
{{ config(
    materialized = 'incremental'
    , incremental_strategy = 'merge'
    , unique_key = ['block_number', 'block_date']
    , meta = {
        "datashare_sync": {
            "enabled": true,
            "partitioning": "block_date"
        }
    }
    , properties = {
        "partitioned_by": "ARRAY['block_date']"
        , "change_data_feed_enabled": "true"
    }
) }}

select ...
```

Use `models/templates/dbt_template_datashare_sync_model.sql` as the starting example. Its date filters bound dbt source reads only. The changefeed sync includes all table changes since the last completed watermark.

### Required Configuration

- Set `meta.datashare_sync.enabled` to the boolean `true`.
- Set a non-empty model-level `unique_key` to a column name or list of column names. The hook passes these as `unique_key_columns` to `sync_datashare`, so Dune can identify rows when applying changes.
- Enable `properties.change_data_feed_enabled` when dbt creates the source table.

Use the model's `unique_key` as the single source of row identity. Do not repeat it under `meta.datashare_sync`.

The hook fails compilation if an enabled model lacks CDF or unique keys. Unknown keys under `meta.datashare_sync` also fail compilation.

**Recreate an existing source table if it lacks CDF.** Adding the property to its model config does not change the existing table:

```bash
uv run dbt run --select dbt_template_datashare_sync_model --target prod --full-refresh
```

### Optional Partitioning

Set `meta.datashare_sync.partitioning` to a raw date/timestamp column name. Do not use an expression or transform. This partitions the delivered share; `properties.partitioned_by` configures the source table separately.

Changing an existing share's partitioning requires a full refresh. Dune rejects the change while a bootstrap is in flight.

## Generated SQL

```sql
ALTER TABLE dune.<schema>.<table> EXECUTE sync_datashare(
    unique_key_columns => ARRAY['block_number', 'block_date'],
    full_refresh => false,
    partitioning => 'block_date'
)
```

The hook omits `partitioning` when it is not configured. It does not query the destination before generating SQL.

## Run Cadence

The example schedule runs every 15 minutes and remains disabled until you enable it. A 10–30 minute cadence is a useful starting point. Incremental syncs apply changes since the last completed watermark; frequent runs do not resend a full snapshot. dbt model queries still consume credits.

## Full Refresh

A full refresh copies the current source snapshot again instead of advancing the watermark.

| Context | `full_refresh` |
| --- | --- |
| Normal incremental post-hook | `false` |
| First incremental run or dbt `--full-refresh` | `true` |
| Table materialization post-hook | `true` |
| Incremental `run-operation` | `false` unless explicitly requested |
| Table `run-operation` | `true` |

## Manual Syncs

Use `run-operation` to sync an existing source table without rebuilding its dbt model.

**Pass `--target prod` for execution.** The macro resolves the schema from the manifest. It refuses non-prod execution to avoid registering ephemeral dev schemas.

Preview SQL without executing it:

```bash
uv run dbt run-operation datashare_trigger_sync_operation --target prod --args '
model_selector: dbt_template_datashare_sync_model
dry_run: true
'
```

Execute a sync:

```bash
uv run dbt run-operation datashare_trigger_sync_operation --target prod --args '
model_selector: dbt_template_datashare_sync_model
'
```

Add `full_refresh: true` to copy the destination snapshot again. This refreshes the share, not the dbt source table.

`model_selector` accepts a model name, alias, fully qualified name, or dbt `unique_id`. Missing or ambiguous selectors fail compilation. A dry run is allowed on any target and never queries Dune.

An explicit `allow_prod_only: false` permits non-prod execution. Avoid it for ephemeral schemas: the destination persists under the temp schema name.

## Remove a Share

```sql
ALTER TABLE dune.<schema>.<table> EXECUTE delete_datashare_sync
```

This stops replication and revokes destination access. It does not drop the dbt source table. Disable `meta.datashare_sync.enabled` to prevent the next prod run from registering the share again.

## Further Reading

- [Supported SQL Operations](https://docs.dune.com/api-reference/connectors/sql-operations)
- [dbt connector overview](https://docs.dune.com/api-reference/connectors/dbt/overview)
