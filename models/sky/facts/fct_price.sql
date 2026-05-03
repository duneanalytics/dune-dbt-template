{{ config(
    alias = 'fct_price'
    , materialized = 'incremental'
    , incremental_strategy = 'append'
    , partitioned_by = ['block_date']
) }}

-- Time-series of asset prices. One row per (asset, ts, type, reference_asset).
-- Sources: dune.prices.usd for chain assets, custom feeds for off-chain assets,
-- ERC4626 vault share prices for share-based assets, RWA NAV uploads for RWAs.
--
-- Stub: pulls USD prices for known on-chain assets from dune.prices.usd.
-- Replace contract_address join logic per your asset coverage needs.

with usd_asset as (
    -- Synthetic USD reference asset. Add a row to dim_asset_seed if you want
    -- a real entry; otherwise this surrogate keeps the schema aligned.
    select {{ dbt_utils.generate_surrogate_key(["'usd'", "'usd'"]) }} as asset_id
)

, source_prices as (
    select
        p.contract_address
        , p.blockchain
        , p.minute as ts
        , cast(p.minute as date) as block_date
        , p.price as value
    from {{ source('prices', 'usd') }} p
    {% if is_incremental() %}
    where cast(p.minute as date) > (select coalesce(max(block_date), date '2024-01-01') from {{ this }})
    {% else %}
    where cast(p.minute as date) >= date '2024-01-01'
    {% endif %}
)

select
    a.asset_id
    , sp.ts
    , 'Oracle' as type
    , (select asset_id from usd_asset) as reference_asset_id
    , sp.value
    , 'dune.prices.usd' as ref
    , sp.block_date
from source_prices sp
inner join {{ ref('dim_asset') }} a
    on a.domain_id = sp.blockchain
    and a.asset_ref = lower(cast(sp.contract_address as varchar))
