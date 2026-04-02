# Table Visibility (Public / Private)

Tables created via dbt are **private** by default — only your team can query them. You can make a table publicly queryable by anyone on Dune by setting the `dune.public` property.

For the full SQL reference, see [Table Visibility](https://docs.dune.com/api-reference/connectors/sql-operations#table-visibility) in the Dune docs.

## dbt config

Set `dune.public` via `extra_properties` in your model's `properties` config:

```sql
{{ config(
    alias = 'my_public_table'
    , materialized = 'table'
    , properties = {
        "extra_properties": "MAP_FROM_ENTRIES(ARRAY[ROW('dune.public', 'true')])"
    }
) }}

select ...
```

The property is set at table creation time and persists across incremental runs.

## Incremental models

Same config — set on initial creation, persists:

```sql
{{ config(
    alias = 'public_eth_transactions'
    , materialized = 'incremental'
    , incremental_strategy = 'merge'
    , unique_key = ['block_date', 'tx_hash']
    , properties = {
        "partitioned_by": "ARRAY['block_date']",
        "extra_properties": "MAP_FROM_ENTRIES(ARRAY[ROW('dune.public', 'true')])"
    }
) }}

select ...
```

## Views

Views use a post-hook instead of table properties:

```sql
{{ config(
    alias = 'public_view'
    , materialized = 'view'
    , post_hook = [
        "CALL _internal.alter_view_properties('{{ this.schema }}', '{{ this.name }}', MAP_FROM_ENTRIES(ARRAY[ROW('dune.public', 'true')]))"
    ]
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
