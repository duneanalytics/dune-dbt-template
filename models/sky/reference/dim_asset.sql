{{ config(
    alias = 'dim_asset'
    , materialized = 'table'
) }}

with seeded as (
    select
        domain_id
        , asset_ref
        , name
        , type
        , decimals
        , underlying_asset_id
        , loan_amount
        , loan_start
        , loan_end
    from {{ ref('dim_asset_seed') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['domain_id', 'asset_ref']) }} as asset_id
    , domain_id
    , asset_ref
    , name
    , type
    , decimals
    , case
        when underlying_asset_id is not null
            then {{ dbt_utils.generate_surrogate_key(['domain_id', 'underlying_asset_id']) }}
        else null
      end as underlying_asset_id
    , loan_amount
    , loan_start
    , loan_end
from seeded
