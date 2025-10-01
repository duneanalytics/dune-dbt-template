{{ config(
    schema = 'dbt_template'
    , alias = 'view_model'
    , materialized = 'view'
)
}}

select
    block_number
    , count(1) as total_tx_per_block
from
    {{ source('ethereum', 'transactions') }}
where
    block_date >= now() - interval '1' day
group by
    block_number