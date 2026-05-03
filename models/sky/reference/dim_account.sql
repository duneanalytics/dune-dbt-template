{{ config(
    alias = 'dim_account'
    , materialized = 'table'
) }}

-- Known accounts only. For unknown counterparties surfaced by the trade
-- ledger, see dim_account_discovered (depends on fct_trade_step).

select
    {{ dbt_utils.generate_surrogate_key(['domain_id', 'account_ref']) }} as account_id
    , domain_id
    , account_ref
    , name
    , purpose
    , entity_id
from {{ ref('dim_account_seed') }}
