{{ config(
    alias = 'dim_account_discovered'
    , materialized = 'view'
) }}

-- Unknown counterparties: every (domain_id, account_ref) appearing in the
-- trade ledger that isn't in dim_account. Add labelled rows to
-- dim_account_seed.csv to graduate them.

with refs as (
    select source_domain_id as domain_id, source_account_ref as account_ref
    from {{ ref('fct_trade_step') }}
    union all
    select target_domain_id as domain_id, target_account_ref as account_ref
    from {{ ref('fct_trade_step') }}
)

, all_refs as (
    select distinct domain_id, account_ref
    from refs
    where account_ref is not null
)

select
    {{ dbt_utils.generate_surrogate_key(['r.domain_id', 'r.account_ref']) }} as account_id
    , r.domain_id
    , r.account_ref
from all_refs r
left join {{ ref('dim_account') }} a
    on a.domain_id = r.domain_id
    and a.account_ref = r.account_ref
where a.account_id is null
