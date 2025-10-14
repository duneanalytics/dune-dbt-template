{#
    key notes on append model:
    - Uses append strategy with custom deduplication logic
    - On incremental runs, filters out rows that already exist in the target table
    - Checks target table using unique key columns to prevent duplicates
#}

{{ config(
    alias = 'dbt_template_append_incremental_model'
    , materialized = 'incremental'
    , incremental_strategy = 'append'
)
}}

with source_data as (
	select
		block_number
		, block_date
		, count(1) as total_tx_per_block -- count per block
	from
		{{ source('ethereum', 'transactions') }}
	where
		1 = 1
		{%- if is_incremental() %}
		AND block_date >= now() - interval '1' day -- on incremental runs, we only want to process the last day of data
		{%- else %}
		AND block_date >= now() - interval '7' day -- on full refresh runs, we want to process all data (to expedite, keep one week's worth of data)
		{%- endif %}
	group by
		block_number
		, block_date
)

select
	s.block_number
	, s.block_date
	, s.total_tx_per_block
from
	source_data as s
{%- if is_incremental() %}
left join {{ this }} as t
	on s.block_number = t.block_number
	and s.block_date = t.block_date
	and t.block_date >= now() - interval '1' day -- filter target to same time window as source
where
	t.block_number is null -- only insert rows that don't already exist
{%- endif %}