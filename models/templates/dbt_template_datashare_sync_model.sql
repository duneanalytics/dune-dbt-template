-- DataShare sync example (see docs/dune-datashares.md "DataShare sync").
--
-- Dune advances this share from the last completed sync, so there is no time
-- window to configure and `meta.datashare_sync` carries no time keys.
--
-- Dune delivers the share to the target your team has registered. This kind of
-- share is delivered to Snowflake only.
--
-- A model cannot carry both `meta.datashare` and `meta.datashare_sync`.
{%- set time_start_incremental = "current_date - interval '1' day" -%}
{%- set time_start = "current_date - interval '2' day" -%}
{%- set time_end = "current_date + interval '1' day" -%}

{{ config(
    alias = 'dbt_template_datashare_sync_model'
    , materialized = 'incremental'
    , incremental_strategy = 'merge'
    , unique_key = ['block_number', 'block_date']
    , incremental_predicates = ["DBT_INTERNAL_DEST.block_date >= " ~ time_start_incremental]
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
    }
) }}

select
    block_number
    , block_date
    , count(*) as total_tx_per_block
from {{ source('ethereum', 'transactions') }}
where block_date >= {{ time_start_incremental if is_incremental() else time_start }}
  and block_date < {{ time_end }}
group by 1, 2
