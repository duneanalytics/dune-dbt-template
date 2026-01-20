{{ config(
    alias = 'dbt_template_view_model'
    , materialized = 'view'
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
