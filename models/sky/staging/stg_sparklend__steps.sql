{{ config(
    alias = 'stg_sparklend__steps'
    , materialized = 'incremental'
    , incremental_strategy = 'merge'
    , unique_key = ['trade_step_id']
    , partitioned_by = ['block_date']
) }}

-- SparkLend Pool events (Supply, Withdraw, Borrow, Repay) as 2-step trades.
-- Each event emits the underlying transfer plus the matching position mint/burn:
--
--   Supply   = Transfer (user      → Pool, reserve)  + Mint     (Pool → onBehalfOf, aToken)
--   Withdraw = Burn     (user      → Pool, aToken)   + Transfer (Pool → to,         reserve)
--   Borrow   = Mint     (Pool      → onBehalfOf, debt) + Transfer (Pool → user,     reserve)
--   Repay    = Transfer (repayer   → Pool, reserve)  + Burn     (user → Pool,       debt)
--
-- aToken / debt position assets use synthetic asset_refs so they can be added
-- to dim_asset_seed later with their real aToken/debt-token addresses & decimals:
--   sparklend_a_<reserve>  → aToken (supply position)
--   sparklend_v_<reserve>  → variable debt position

{% set pool_ref = '0xc13e21b648a5ee794902342038ff3adab66be987' %}

with known_assets as (
    select asset_ref, decimals
    from {{ ref('dim_asset') }}
    where domain_id = 'ethereum'
)

, events as (
    select
        s.evt_tx_hash as tx_hash
        , s.evt_index as log_index
        , s.evt_block_time as ts
        , cast(s.evt_block_time as date) as block_date
        , 'Supply' as category
        , lower(cast(s.reserve as varchar)) as asset_ref
        , lower(cast(s.user as varchar)) as underlying_account_ref
        , lower(cast(s.onBehalfOf as varchar)) as position_account_ref
        , s.amount as raw_amount
    from {{ source('spark_protocol_ethereum', 'pool_evt_supply') }} s
    {% if is_incremental() %}
    where cast(s.evt_block_time as date) >= (select coalesce(max(block_date), date '2024-01-01') from {{ this }})
    {% else %}
    where cast(s.evt_block_time as date) >= date '2024-01-01'
    {% endif %}

    union all

    select
        w.evt_tx_hash
        , w.evt_index
        , w.evt_block_time
        , cast(w.evt_block_time as date)
        , 'Withdraw'
        , lower(cast(w.reserve as varchar))
        , lower(cast(w.to as varchar))
        , lower(cast(w.user as varchar))
        , w.amount
    from {{ source('spark_protocol_ethereum', 'pool_evt_withdraw') }} w
    {% if is_incremental() %}
    where cast(w.evt_block_time as date) >= (select coalesce(max(block_date), date '2024-01-01') from {{ this }})
    {% else %}
    where cast(w.evt_block_time as date) >= date '2024-01-01'
    {% endif %}

    union all

    select
        b.evt_tx_hash
        , b.evt_index
        , b.evt_block_time
        , cast(b.evt_block_time as date)
        , 'Borrow'
        , lower(cast(b.reserve as varchar))
        , lower(cast(b.user as varchar))
        , lower(cast(b.onBehalfOf as varchar))
        , b.amount
    from {{ source('spark_protocol_ethereum', 'pool_evt_borrow') }} b
    {% if is_incremental() %}
    where cast(b.evt_block_time as date) >= (select coalesce(max(block_date), date '2024-01-01') from {{ this }})
    {% else %}
    where cast(b.evt_block_time as date) >= date '2024-01-01'
    {% endif %}

    union all

    select
        r.evt_tx_hash
        , r.evt_index
        , r.evt_block_time
        , cast(r.evt_block_time as date)
        , 'Repay'
        , lower(cast(r.reserve as varchar))
        , lower(cast(r.repayer as varchar))
        , lower(cast(r.user as varchar))
        , r.amount
    from {{ source('spark_protocol_ethereum', 'pool_evt_repay') }} r
    {% if is_incremental() %}
    where cast(r.evt_block_time as date) >= (select coalesce(max(block_date), date '2024-01-01') from {{ this }})
    {% else %}
    where cast(r.evt_block_time as date) >= date '2024-01-01'
    {% endif %}
)

, filtered as (
    select e.*, a.decimals
    from events e
    inner join known_assets a on a.asset_ref = e.asset_ref
)

, steps as (
    -- Step 0: underlying transfer for Supply/Repay; position change for Withdraw/Borrow
    select
        e.tx_hash
        , e.log_index
        , e.ts
        , e.block_date
        , e.category
        , e.raw_amount
        , e.decimals
        , 0 as step_index
        , case e.category
              when 'Supply'   then 'Transfer'
              when 'Repay'    then 'Transfer'
              when 'Withdraw' then 'Burn'
              when 'Borrow'   then 'Mint'
          end as step_type
        , case e.category
              when 'Supply'   then e.underlying_account_ref
              when 'Repay'    then e.underlying_account_ref
              when 'Withdraw' then e.position_account_ref
              when 'Borrow'   then '{{ pool_ref }}'
          end as source_account_ref
        , case e.category
              when 'Supply'   then '{{ pool_ref }}'
              when 'Repay'    then '{{ pool_ref }}'
              when 'Withdraw' then '{{ pool_ref }}'
              when 'Borrow'   then e.position_account_ref
          end as target_account_ref
        , case e.category
              when 'Withdraw' then 'sparklend_a_' || e.asset_ref
              when 'Borrow'   then 'sparklend_v_' || e.asset_ref
              else e.asset_ref
          end as step_asset_ref
    from filtered e

    union all

    -- Step 1: position change for Supply/Repay; underlying transfer for Withdraw/Borrow
    select
        e.tx_hash
        , e.log_index
        , e.ts
        , e.block_date
        , e.category
        , e.raw_amount
        , e.decimals
        , 1 as step_index
        , case e.category
              when 'Supply'   then 'Mint'
              when 'Repay'    then 'Burn'
              when 'Withdraw' then 'Transfer'
              when 'Borrow'   then 'Transfer'
          end as step_type
        , case e.category
              when 'Supply'   then '{{ pool_ref }}'
              when 'Repay'    then e.position_account_ref
              when 'Withdraw' then '{{ pool_ref }}'
              when 'Borrow'   then '{{ pool_ref }}'
          end as source_account_ref
        , case e.category
              when 'Supply'   then e.position_account_ref
              when 'Repay'    then '{{ pool_ref }}'
              when 'Withdraw' then e.underlying_account_ref
              when 'Borrow'   then e.underlying_account_ref
          end as target_account_ref
        , case e.category
              when 'Supply' then 'sparklend_a_' || e.asset_ref
              when 'Repay'  then 'sparklend_v_' || e.asset_ref
              else e.asset_ref
          end as step_asset_ref
    from filtered e
)

select
    {{ dbt_utils.generate_surrogate_key(['s.tx_hash', 's.log_index']) }} as trade_id
    , s.category
    , 'Sync' as settlement
    , 'Settled' as status
    , s.ts
    , s.ts as ts_settled
    , array[cast(s.tx_hash as varchar)] as refs
    , s.step_index
    , s.step_type
    , 'ethereum' as source_domain_id
    , s.source_account_ref
    , 'ethereum' as target_domain_id
    , s.target_account_ref
    , 'ethereum' as asset_domain_id
    , s.step_asset_ref as asset_ref
    , cast(s.raw_amount as decimal(38, 0)) / power(cast(10 as decimal(38, 0)), s.decimals) as amount
    , {{ dbt_utils.generate_surrogate_key(['s.tx_hash', 's.log_index', 'cast(s.step_index as varchar)']) }} as trade_step_id
    , s.block_date
from steps s
