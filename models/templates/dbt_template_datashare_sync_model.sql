-- CDF must be enabled when dbt creates the table; recreate existing tables
-- with --full-refresh if they lack it. See docs/dune-datashares.md.
-- These filters bound the dbt source reads, not the changefeed sync.
{%- set incremental_lookback = "current_date - interval '1' day" -%}
{%- set initial_lookback = "current_date - interval '2' day" -%}

{{ config(
    alias = 'dbt_template_datashare_sync_model'
    , materialized = 'incremental'
    , incremental_strategy = 'merge'
    , unique_key = ['block_number', 'block_date']
    , incremental_predicates = ["DBT_INTERNAL_DEST.block_date >= " ~ incremental_lookback]
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
) }}

select
    block_number
    , block_date
    , count(*) as total_tx_per_block
from {{ source('ethereum', 'transactions') }}
where block_date >= {{ incremental_lookback if is_incremental() else initial_lookback }}
  and block_date < current_date + interval '1' day
group by 1, 2
