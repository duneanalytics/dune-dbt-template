{{ config(
    alias = 'dbt_template_table_model'
    , materialized = 'table'
    , properties = {
        "partitioned_by": "ARRAY['block_date']"
    }
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
