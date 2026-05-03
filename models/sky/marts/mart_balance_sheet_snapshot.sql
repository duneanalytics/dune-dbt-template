{{ config(
    alias = 'mart_balance_sheet_snapshot'
    , materialized = 'incremental'
    , incremental_strategy = 'merge'
    , unique_key = ['snapshot_date', 'account_id', 'asset_id', 'balance_type']
    , partitioned_by = ['snapshot_date']
) }}

-- Daily end-of-day balance per (account, asset, balance_type).
-- Materialized incrementally: each run extends the snapshot forward to today.
--
-- For sub-daily granularity, query fct_balance_sheet_delta with a running sum
-- window function (a view-based intra-day balance is left as future work).

{% set start_date = "date '2024-01-01'" %}

with date_spine as (
    select day as snapshot_date
    from unnest(sequence(
        {% if is_incremental() %}
        coalesce((select max(snapshot_date) from {{ this }}), {{ start_date }})
        {% else %}
        {{ start_date }}
        {% endif %}
        , current_date
        , interval '1' day
    )) as t(day)
)

, deltas as (
    select
        account_id
        , asset_id
        , balance_type
        , block_date
        , sum(amount_delta) as amount_delta
    from {{ ref('fct_balance_sheet_delta') }}
    group by account_id, asset_id, balance_type, block_date
)

, running_balances as (
    select
        d.account_id
        , d.asset_id
        , d.balance_type
        , d.block_date
        , sum(d.amount_delta) over (
            partition by d.account_id, d.asset_id, d.balance_type
            order by d.block_date
            rows between unbounded preceding and current row
        ) as running_amount
    from deltas d
)

, snapshots as (
    -- For each snapshot date, take the latest running balance on or before that date.
    select
        s.snapshot_date
        , rb.account_id
        , rb.asset_id
        , rb.balance_type
        , rb.running_amount as amount
        , row_number() over (
            partition by s.snapshot_date, rb.account_id, rb.asset_id, rb.balance_type
            order by rb.block_date desc
        ) as rn
    from date_spine s
    inner join running_balances rb
        on rb.block_date <= s.snapshot_date
)

select
    snapshot_date
    , account_id
    , asset_id
    , balance_type
    , amount
from snapshots
where rn = 1
  and amount != 0
