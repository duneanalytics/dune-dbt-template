{#
    key notes on table model:
    - on_table_exists = 'replace' is used to replace the table if it already exists
        - dunesql hive metastore does *not* allow rename of table, meaning standard dbt table operations won't work (drop temp table, create temp table, rename existing table to backup, rename temp to final, drop backup)
    - file_format defaults to delta (TODO: confirm this is dune hive metastore setting)
        - when providing file_format config to model, dbt fails on unable to support 'format' property
#}

{{ config(
    schema = 'test_schema'
    , alias = 'dbt_template_table_model'
    , materialized = 'table'
    , on_table_exists = 'replace'
)
}}

select
    block_number
    , block_date
    , count(1) as total_tx_per_block
from
    {{ source('ethereum', 'transactions') }}
where
    block_date >= now() - interval '1' day
group by
    block_number
    , block_date