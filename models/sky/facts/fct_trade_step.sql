{{ config(
    alias = 'fct_trade_step'
    , materialized = 'incremental'
    , incremental_strategy = 'merge'
    , unique_key = ['trade_step_id']
    , partitioned_by = ['block_date']
) }}

-- Source-of-truth ledger. Every protocol's staging model UNIONs in here.
-- Adding a new protocol = adding a new `union all select * from ref(...)` block.

with all_steps as (
    select
        trade_id
        , trade_step_id
        , step_index
        , step_type
        , category
        , settlement
        , status
        , ts
        , ts_settled
        , refs
        , source_domain_id
        , source_account_ref
        , target_domain_id
        , target_account_ref
        , asset_domain_id
        , asset_ref
        , amount
        , block_date
    from {{ ref('stg_ethereum__erc20_transfers') }}
    -- union all
    -- select ... from {{ "{{ ref('stg_sparklend__steps') }}" }}
    -- union all
    -- select ... from {{ "{{ ref('stg_morpho__steps') }}" }}
)

select
    s.trade_step_id
    , s.trade_id
    , s.step_index
    , s.step_type
    , s.category
    , s.settlement
    , s.status
    , s.ts
    , s.ts_settled
    , s.refs
    , s.source_domain_id
    , s.source_account_ref
    , {{ dbt_utils.generate_surrogate_key(['s.source_domain_id', 's.source_account_ref']) }} as source_account_id
    , s.target_domain_id
    , s.target_account_ref
    , {{ dbt_utils.generate_surrogate_key(['s.target_domain_id', 's.target_account_ref']) }} as target_account_id
    , s.asset_domain_id
    , s.asset_ref
    , {{ dbt_utils.generate_surrogate_key(['s.asset_domain_id', 's.asset_ref']) }} as asset_id
    , s.amount
    , s.block_date
from all_steps s
{% if is_incremental() %}
where s.block_date >= (select coalesce(max(block_date), date '1970-01-01') from {{ this }})
{% endif %}
