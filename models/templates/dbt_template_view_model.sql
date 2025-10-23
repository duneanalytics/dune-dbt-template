{{ config(
    alias = 'dbt_template_view_model'
    , materialized = 'view'
)
}}

select
    -- dummy comment to test GH workflows (CI attached to PR, deploy post-merge to main)
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