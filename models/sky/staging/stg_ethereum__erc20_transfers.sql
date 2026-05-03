{{ config(
    alias = 'stg_ethereum__erc20_transfers'
    , materialized = 'incremental'
    , incremental_strategy = 'merge'
    , unique_key = ['trade_step_id']
    , partitioned_by = ['block_date']
) }}

-- Worked example: turns every ERC-20 transfer involving a known account
-- into a 1-step Trade (category=Transfer, settlement=Sync, status=Settled).
--
-- Pattern for new staging models:
--   1. Filter raw events to just the protocol you care about.
--   2. For each event, emit one row per TradeStep (1 for Transfer/Fee,
--      2 for atomic deposit/withdraw which is Transfer + Mint or Burn + Transfer).
--   3. Build trade_id from a deterministic hash of (tx_hash, log_index window).
--   4. Reference accounts/assets by (domain_id, ref) — surrogate keys are
--      generated downstream in fct_trade_step.

with known_assets as (
    select asset_ref, decimals
    from {{ ref('dim_asset') }}
    where domain_id = 'ethereum'
)

, known_accounts as (
    select account_ref
    from {{ ref('dim_account') }}
    where domain_id = 'ethereum'
)

, transfers as (
    select
        t.evt_tx_hash as tx_hash
        , t.evt_index as log_index
        , t.evt_block_time as block_time
        , cast(t.evt_block_time as date) as block_date
        , lower(cast(t.contract_address as varchar)) as asset_ref
        , lower(cast(t."from" as varchar)) as source_account_ref
        , lower(cast(t.to as varchar)) as target_account_ref
        , t.value as raw_amount
    from {{ source('erc20_ethereum', 'evt_Transfer') }} t
    {% if is_incremental() %}
    where cast(t.evt_block_time as date) >= (select coalesce(max(block_date), date '2024-01-01') from {{ this }})
    {% else %}
    where cast(t.evt_block_time as date) >= date '2024-01-01'
    {% endif %}
)

, filtered as (
    select tr.*
    from transfers tr
    inner join known_assets a on a.asset_ref = tr.asset_ref
    where exists (
        select 1 from known_accounts ka
        where ka.account_ref in (tr.source_account_ref, tr.target_account_ref)
    )
)

select
    {{ dbt_utils.generate_surrogate_key(['f.tx_hash', 'f.log_index']) }} as trade_id
    , 'Transfer' as category
    , 'Sync' as settlement
    , 'Settled' as status
    , f.block_time as ts
    , f.block_time as ts_settled
    , array[cast(f.tx_hash as varchar)] as refs
    , 0 as step_index
    , 'Transfer' as step_type
    , 'ethereum' as source_domain_id
    , f.source_account_ref
    , 'ethereum' as target_domain_id
    , f.target_account_ref
    , 'ethereum' as asset_domain_id
    , f.asset_ref
    , cast(f.raw_amount as decimal(38, 0)) / power(cast(10 as decimal(38, 0)), a.decimals) as amount
    , {{ dbt_utils.generate_surrogate_key(['f.tx_hash', 'f.log_index', "'0'"]) }} as trade_step_id
    , f.block_date
from filtered f
inner join known_assets a on a.asset_ref = f.asset_ref
