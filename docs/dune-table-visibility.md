# Dune Table Visibility

Control whether a table is visible in Dune's data explorer using the `meta.dune.public` config.

For the full SQL reference, see the [official Dune docs on Table Visibility](https://docs.dune.com/api-reference/connectors/sql-operations#table-visibility).

Implemented by [`macros/dune_dbt_overrides/set_table_visibility.sql`](../macros/dune_dbt_overrides/set_table_visibility.sql).

## dbt config

Set `meta.dune.public` in your model config:

```sql
{{ config(
    alias = 'my_public_table'
    , materialized = 'table'
    , meta = {
        "dune": {
            "public": true
        }
    }
) }}

select ...
```

The `set_table_visibility` post-hook runs `ALTER TABLE ... SET PROPERTIES extra_properties = ...` automatically after each model run.

| `meta.dune.public` | Visibility |
|---|---|
| `true` | Public — visible to all Dune users in data explorer |
| `false` or absent | Private (default) — only visible to your team |

Visibility is only applied in the **`prod` target** — it has no effect in development.

## Folder-level config

Make all models in a folder public via `dbt_project.yml`:

```yaml
models:
  your_project:
    public_models:
      +meta:
        dune:
          public: true
```

## Incremental models

Same config — the post-hook runs on every `dbt run`, so visibility is kept in sync:

```sql
{{ config(
    alias = 'public_eth_transactions'
    , materialized = 'incremental'
    , incremental_strategy = 'merge'
    , unique_key = ['block_date', 'tx_hash']
    , meta = {
        "dune": {
            "public": true
        }
    }
    , properties = {
        "partitioned_by": "ARRAY['block_date']"
    }
) }}

select ...
```

## Views

View visibility is **not supported** by the post-hook macro at this time.

## Combining with datashare

A model can be both public and datashare-enabled. Both use `meta`:

```sql
{% set time_start = "now() - interval '1' day" if is_incremental() else "timestamp '2026-01-01'" %}

{{ config(
    alias = 'public_datashared_model'
    , materialized = 'incremental'
    , incremental_strategy = 'merge'
    , unique_key = ['block_date', 'id']
    , meta = {
        "dune": {
            "public": true
        },
        "datashare": {
            "enabled": true,
            "time_column": "block_date",
            "time_start": time_start,
            "time_end": "now()"
        }
    }
    , properties = {
        "partitioned_by": "ARRAY['block_date']"
    }
) }}

select ...
```

## Changing visibility on existing tables

Via any Trino client or `dbt run-operation`:

```sql
-- Make public
ALTER TABLE dune.<schema>.<table> SET PROPERTIES
    extra_properties = MAP_FROM_ENTRIES(ARRAY[ROW('dune.public', 'true')]);

-- Make private
ALTER TABLE dune.<schema>.<table> SET PROPERTIES
    extra_properties = MAP_FROM_ENTRIES(ARRAY[ROW('dune.public', 'false')]);
```
