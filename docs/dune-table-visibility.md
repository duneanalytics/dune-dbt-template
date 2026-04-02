# Dune Table Visibility

Control whether a table is accessible to other Dune users using the `meta.dune.public` config.

By default, tables created by dbt are **private** — only your team can see or query them. Public tables are accessible to all Dune users: they appear in the data explorer, can be queried via the SQL editor or API, and can be referenced in other users' queries and dashboards.

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
| `true` | Public — queryable by all Dune users, visible in data explorer, SQL editor, API |
| `false` or absent | Private (default) — only accessible to your team |

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
