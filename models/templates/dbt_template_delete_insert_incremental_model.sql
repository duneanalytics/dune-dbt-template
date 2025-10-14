{#
    key notes on delete+insert model:
    - file_format defaults to delta (TODO: confirm this is dune hive metastore setting)
        - when providing file_format config to model, dbt fails on unable to support 'format' property
    - incremental_predicates filter the DELETE operation on the target table for better performance
        - this limits the rows scanned during the delete phase to match the source filter window
#}

{{ config(
    alias = 'dbt_template_delete_insert_incremental_model'
    , materialized = 'incremental'
    , incremental_strategy = 'delete+insert'
    , unique_key = ['block_number', 'block_date']
    , incremental_predicates = ["block_date >= now() - interval '1' day"]
)
}}

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