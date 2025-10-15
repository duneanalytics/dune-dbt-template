{{ config(
	alias = 'humidifi_solana_trades'
	, materialized = 'incremental'
	, incremental_strategy = 'merge'
	, unique_key = ['dt', 'block_slot', 'tx_id', 'outer_instruction_index', 'inner_instruction_index']
	, incremental_predicates = ["DBT_INTERNAL_DEST.dt >= now() - interval '1' day"]
)
}}

/* TODO: update to actual start date when moving to prod */
{% set project_start_date = '2025-10-01' %}

with trades as (
	select
		ic.block_time
        , ic.block_slot
		, ic.tx_id
		, ic.outer_instruction_index
		, ic.inner_instruction_index
		, p.pool
		, p.quote_mint_address
		, p.base_mint_address
	from
		{{ source('solana', 'instruction_calls') }} as ic
	inner join {{ ref('humidifi_solana_pools') }} as p
		on ic.account_arguments[2] = p.pool
	where
		ic.executing_account = '9H6tua7jkLhdm3w8BvgpTn5LZNU7g4ZynDmCiNN3q6Rp'
		and bytearray_substring(bytearray_reverse(ic.data), 1, 8) = 0x3dc3e9bae0ff2dff -- discriminator is reversed
		and ic.tx_success
        {%- if is_incremental() or true %}
        and ic.block_time >= now() - interval '1' day
        {%- else %}
        and ic.block_time >= timestamp '{{ project_start_date }}'
        {%- endif %}
)

select
	t.block_time as dt
	, t.block_slot
	, t.tx_id
	, t.outer_instruction_index
	, t.inner_instruction_index
	, xfer.tx_signer as trader_id
	, xfer.outer_executing_account
	, xfer.token_mint_address as token_bought_mint_address
	, case
		when xfer.token_mint_address = t.base_mint_address then t.quote_mint_address
		else t.base_mint_address
		end as token_sold_mint_address
	, xfer.amount_usd
	, t.pool
from
	{{ source('tokens_solana', 'transfers') }} as xfer
inner join trades as t
	on xfer.tx_id = t.tx_id
    and xfer.block_time = t.block_time
    and xfer.block_slot = t.block_slot
	and xfer.outer_instruction_index = t.outer_instruction_index
	and xfer.inner_instruction_index = t.inner_instruction_index + 1
where
    1 = 1
    {%- if is_incremental() or true %}
    and xfer.block_time >= now() - interval '1' day
    {%- else %}
    and xfer.block_time >= timestamp '{{ project_start_date }}'
    {%- endif %}