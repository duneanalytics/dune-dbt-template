{#
    key notes on table model:
    - file_format defaults to delta (TODO: confirm this is dune hive metastore setting)
        - when providing file_format config to model, dbt fails on unable to support 'format' property
#}

{{ config(
    alias = 'dbt_template_table_model'
    , materialized = 'table'
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