{{ config(materialized = 'view') }}

-- Per-(account, token) balances for the tokens listed in `tokens`.
-- Derived from ERC-20 transfers; balances are scaled to token units via decimals.

with token_meta as (
    select * from (values
        (lower('0xdC035D45d973E3EC169d2276DDab16f1e407384F'), 18),
        (lower('0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD'), 18),
        (lower('0x28B3a8fb53B741A8Fd78c0fb9A6B2393d896a43d'),  6),
        (lower('0xe2e7a17dFf93280dec073C995595155283e3C372'),  6),
        (lower('0xfE6eb3b609a7C8352A241f7F3A21CEA4e9209B8f'), 18)
    ) as t(address, decimals)
)

, transfers as (
    select
        lower(cast(contract_address as varchar)) as token,
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

, deltas as (
    select to_address as account, token, raw_amount as delta from transfers
    union all
    select from_address as account, token, -raw_amount as delta from transfers
)

, balances as (
    select
        account,
        token,
        sum(delta) as raw_balance
    from deltas
    where account != lower('0x0000000000000000000000000000000000000000')
    group by account, token
)

select
    b.account,
    b.token,
    b.raw_balance / power(cast(10 as decimal(38, 0)), m.decimals) as amount
from balances b
inner join token_meta m on m.address = b.token
where b.raw_balance > 0
