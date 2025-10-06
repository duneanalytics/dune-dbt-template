{#
    note: ignore schema property in model configs, keep models unique based on alias
#}

{{ config(
    alias = 'uniswap_v3_trades'
    , materialized = 'view'
)
}}

WITH uniswap AS
(
    SELECT
        t.evt_block_number AS block_number
        , t.evt_block_time AS block_time
        , t.recipient AS taker
        , CASE WHEN amount0 < INT256 '0' THEN abs(amount0) ELSE abs(amount1) END AS token_bought_amount_raw -- when amount0 is negative it means trader_a is buying token0 from the pool
        , CASE WHEN amount0 < INT256 '0' THEN abs(amount1) ELSE abs(amount0) END AS token_sold_amount_raw
        , CASE WHEN amount0 < INT256 '0' THEN f.token0 ELSE f.token1 END AS token_bought_address
        , CASE WHEN amount0 < INT256 '0' THEN f.token1 ELSE f.token0 END AS token_sold_address
        , t.contract_address
        , f.fee
        , t.evt_tx_hash AS tx_hash
        , t.evt_index
    FROM
        "delta_prod"."uniswap_v3_unichain"."UniswapV3Pool_evt_Swap" t
    INNER JOIN
        "delta_prod"."uniswap_v3_unichain"."UniswapV3Factory_evt_PoolCreated" f
        ON f.pool = t.contract_address
    WHERE
        t.evt_block_time >= now() - interval '30' day
)
, metadata as (
    select
        *
    from
        tokens.erc20
    where
        blockchain = 'unichain'
)
, prices as (
    select
        minute
        , contract_address
        , price
    from
        prices.usd
    where
        blockchain = 'unichain'
        and minute >= now() - interval '30' day
)
, tx as (
    select
        block_time
        , block_date
        , hash as tx_hash
        , "from" as tx_from
    from
        unichain.transactions
    where
        block_date >= now() - interval '30' day
)
select
    u.block_time
    , u.tx_hash
    , tx.tx_from
    , u.contract_address
    , u.token_bought_address
    , tb.symbol as token_bought_symbol
    , tb.decimals as token_bought_decimals
    , u.token_sold_address
    , ts.symbol as token_sold_symbol
    , ts.decimals as token_sold_decimals
    , u.token_bought_amount_raw
    , u.token_bought_amount_raw / power(10, tb.decimals) AS token_bought_amount
    , (u.token_bought_amount_raw / power(10, tb.decimals)) * pb.price as token_bought_amount_usd
    , u.token_sold_amount_raw
    , u.token_sold_amount_raw / power(10, ts.decimals) AS token_sold_amount
    , (u.token_sold_amount_raw / power(10, ts.decimals)) * ps.price as token_sold_amount_usd
    , u.fee
from
    uniswap as u
inner join
    tx
    on u.tx_hash = tx.tx_hash
    and u.block_time = tx.block_time
left join
    metadata as tb
    on u.token_bought_address = tb.contract_address
left join
    metadata as ts
    on u.token_sold_address = ts.contract_address
left join
    prices as pb
    on u.token_bought_address = pb.contract_address
    and date_trunc('minute', u.block_time) = pb.minute
left join
    prices as ps
    on u.token_sold_address = ps.contract_address
    and date_trunc('minute', u.block_time) = ps.minute