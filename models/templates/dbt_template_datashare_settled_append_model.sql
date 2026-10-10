-- DataShare sync example for Databricks over a source that keeps changing
-- recent rows (see docs/dune-datashares.md "DataShare sync").
--
-- tokens.transfers re-merges its last 3 days (spellbook DBT_ENV_INCREMENTAL_TIME)
-- and rewrites price and token-metadata columns. Databricks only accepts
-- insert-only changes, so this model appends whole days once they are older
-- than settle_days, and keeps only columns that never change after a transfer
-- is written. Every run is a plain INSERT; existing rows are never touched.
--
-- Trade-offs: data lags by settle_days, and upstream corrections to days that
-- are already synced do not flow through; pick them up with --full-refresh.
-- settle_days must stay above the source's re-merge window.
--
-- unique_key is not used by the append write; DataShare sync requires it.
{%- set settle_days = 4 -%}
{%- set start_date = "current_date - interval '14' day" -%}

{{ config(
    alias = 'dbt_template_datashare_settled_append_model'
    , materialized = 'incremental'
    , incremental_strategy = 'append'
    , unique_key = ['blockchain', 'block_date', 'unique_key']
    , meta = {
        "dune": {
            "public": false
        },
        "datashare_sync": {
            "enabled": true,
            "partitioning": "block_date"
        }
    }
    , properties = {
        "partitioned_by": "ARRAY['block_date']"
        , "change_data_feed_enabled": "true"
    }
)
}}

select
	blockchain
	, block_date
	, block_time
	, block_number
	, tx_hash
	, evt_index
	, trace_address
	, tx_index
	, tx_from
	, tx_to
	, token_standard
	, contract_address
	, "from"
	, "to"
	, amount_raw
	, unique_key
from
	{{ source('tokens', 'transfers') }}
where
	blockchain = 'ethereum'
	and block_date < current_date - interval '{{ settle_days }}' day
	{%- if is_incremental() %}
	-- whole days newer than the last synced day; a rerun resumes where the last successful run stopped
	and block_date > (select coalesce(max(block_date), {{ start_date }} - interval '1' day) from {{ this }})
	{%- else %}
	and block_date >= {{ start_date }}
	{%- endif %}
