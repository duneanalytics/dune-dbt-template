{{ config(
    alias = 'fct_trade'
    , materialized = 'view'
) }}

-- Derived from fct_trade_step. One row per trade with header-level columns.
-- ts is the earliest step time; ts_settled is the latest non-null step settlement.

select
    trade_id
    , any_value(category) as category
    , any_value(settlement) as settlement
    , any_value(status) as status
    , min(ts) as ts
    , max(ts_settled) as ts_settled
    , any_value(refs) as refs
    , count(*) as step_count
    , min(block_date) as block_date
from {{ ref('fct_trade_step') }}
group by trade_id
