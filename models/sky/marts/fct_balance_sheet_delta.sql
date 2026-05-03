{{ config(
    alias = 'fct_balance_sheet_delta'
    , materialized = 'incremental'
    , incremental_strategy = 'append'
    , partitioned_by = ['block_date']
) }}

-- Each TradeStep emits 1 or 2 BalanceSheet deltas.
--
-- Transfer/Fee:  source.assets -= amount      target.assets += amount
-- Mint:          source.assets += amount      target.liabilities += amount
--                (source mints the asset; target owes it back)
-- Burn:          source.assets -= amount      target.liabilities -= amount
--                (source returns the asset; target's debt is cancelled)
--
-- This produces double-entry: every step affects exactly two account/type pairs.

with steps as (
    select
        trade_step_id
        , trade_id
        , step_index
        , step_type
        , status
        , ts
        , source_account_id
        , target_account_id
        , asset_id
        , amount
        , block_date
    from {{ ref('fct_trade_step') }}
    where status = 'Settled'
    {% if is_incremental() %}
      and block_date >= (select coalesce(max(block_date), date '1970-01-01') from {{ this }})
    {% endif %}
)

, expanded as (
    -- Source side
    select
        trade_step_id
        , trade_id
        , step_index
        , ts
        , block_date
        , source_account_id as account_id
        , asset_id
        , case
            when step_type in ('Transfer', 'Fee', 'Burn') then 'Asset'
            when step_type = 'Mint' then 'Asset'
          end as balance_type
        , case
            when step_type in ('Transfer', 'Fee', 'Burn') then -amount
            when step_type = 'Mint' then amount
          end as amount_delta
        , target_account_id as counterparty_account_id
        , 'source' as side
    from steps

    union all

    -- Target side
    select
        trade_step_id
        , trade_id
        , step_index
        , ts
        , block_date
        , target_account_id as account_id
        , asset_id
        , case
            when step_type in ('Transfer', 'Fee') then 'Asset'
            when step_type in ('Mint', 'Burn') then 'Liability'
          end as balance_type
        , case
            when step_type in ('Transfer', 'Fee') then amount
            when step_type = 'Mint' then amount
            when step_type = 'Burn' then -amount
          end as amount_delta
        , source_account_id as counterparty_account_id
        , 'target' as side
    from steps
)

select
    {{ dbt_utils.generate_surrogate_key(['trade_step_id', 'side']) }} as delta_id
    , trade_step_id
    , trade_id
    , step_index
    , ts
    , block_date
    , account_id
    , asset_id
    , balance_type
    , amount_delta
    , counterparty_account_id
from expanded
where amount_delta is not null
