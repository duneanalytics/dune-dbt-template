{{ config(materialized = 'view') }}

-- Tokens of interest: Sky USDS plus Spark Savings vaults.
-- `underlying` is NULL for base tokens, otherwise the ERC4626 asset() address.
-- `totalSupply` is derived from ERC-20 transfers (mints from 0x0 minus burns to 0x0),
-- scaled by each token's decimals.

with token_meta as (
    select * from (values
        (lower('0xdC035D45d973E3EC169d2276DDab16f1e407384F'), 'USDS',   cast(null as varchar),                                      18),
        (lower('0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD'), 'sUSDS',  lower('0xdC035D45d973E3EC169d2276DDab16f1e407384F'),         18),
        (lower('0x28B3a8fb53B741A8Fd78c0fb9A6B2393d896a43d'), 'spUSDC', lower('0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48'),          6),
        (lower('0xe2e7a17dFf93280dec073C995595155283e3C372'), 'spUSDT', lower('0xdAC17F958D2ee523a2206206994597C13D831ec7'),          6),
        (lower('0xfE6eb3b609a7C8352A241f7F3A21CEA4e9209B8f'), 'spETH',  lower('0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2'),         18)
    ) as t(address, name, underlying, decimals)
)

, transfers as (
    select
        lower(cast(contract_address as varchar)) as address,
        lower(cast("from" as varchar)) as from_address,
        lower(cast(to as varchar)) as to_address,
        cast(value as decimal(38, 0)) as raw_amount
    from {{ source('erc20_ethereum', 'evt_Transfer') }}
    where lower(cast(contract_address as varchar)) in (
        lower('0xdC035D45d973E3EC169d2276DDab16f1e407384F'),
        lower('0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD'),
        lower('0x28B3a8fb53B741A8Fd78c0fb9A6B2393d896a43d'),
        lower('0xe2e7a17dFf93280dec073C995595155283e3C372'),
        lower('0xfE6eb3b609a7C8352A241f7F3A21CEA4e9209B8f')
    )
)

, supply as (
    select
        address,
        sum(case when from_address = lower('0x0000000000000000000000000000000000000000') then raw_amount else 0 end)
          - sum(case when to_address = lower('0x0000000000000000000000000000000000000000') then raw_amount else 0 end) as raw_supply
    from transfers
    group by address
)

select
    m.address,
    m.name,
    m.underlying,
    coalesce(s.raw_supply, 0) / power(cast(10 as decimal(38, 0)), m.decimals) as "totalSupply"
from token_meta m
left join supply s on s.address = m.address
