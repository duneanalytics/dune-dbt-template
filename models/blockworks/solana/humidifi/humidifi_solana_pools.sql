{{ config(
	alias = 'humidifi_solana_pools'
	, materialized = 'incremental'
	, incremental_strategy = 'merge'
	, unique_key = ['launch_dt', 'creation_tx', 'pool']
)
}}

{% set project_start_date = '2025-05-26' %}

with pools as (
	select
		block_time as launch_dt
		, tx_id as creation_tx
		, account_arguments[1] as creator
		, account_arguments[2] as pool
		, account_arguments[5] as base_mint_address
		, account_arguments[6] as quote_mint_address
		, account_arguments[3] as base_token_account
		, account_arguments[4] as quote_token_account
	from
		{{ source('solana', 'instruction_calls') }}
	where
		executing_account = '9H6tua7jkLhdm3w8BvgpTn5LZNU7g4ZynDmCiNN3q6Rp'
		and length(cast(data as varchar)) = 1028
		and tx_success
		{%- if is_incremental() %}
		and block_time >= now() - interval '1' day
		{%- else %}
		and block_time >= timestamp '{{ project_start_date }}'
		{%- endif %}
)

select distinct
	pools.pool
	, pools.launch_dt
	, pools.creation_tx
	, pools.base_mint_address
	, pools.quote_mint_address
	, pools.base_token_account
	, pools.quote_token_account
	, b.symbol as base_symbol
	, q.symbol as quote_symbol
	, b.symbol || '-' || q.symbol as pair
from
	pools
left join {{ source('tokens_solana', 'fungible') }} b
	on b.token_mint_address = pools.base_mint_address
left join {{ source('tokens_solana', 'fungible') }} q
	on q.token_mint_address = pools.quote_mint_address