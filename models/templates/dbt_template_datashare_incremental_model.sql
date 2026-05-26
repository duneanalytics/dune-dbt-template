-- Datashare cadence/window pairing (see docs/dune-datashares.md "Cadence and sync windows").
--
-- This example uses a date `time_column` (`block_date`) and is designed for
-- DAILY cadence. Each incremental run MERGEs the last 1 day of data, which on
-- S3 Export means re-reading 1 day of the destination partition per run.
--
-- If you switch to hourly cadence WITHOUT also switching to a timestamp
-- `time_column` and an hour-sized window, every hourly run will re-read the
-- full day from the destination (24x amplification on cross-region S3 buckets).
-- For hourly freshness, see the "Hourly cadence" example in the docs.
{%- set time_start_incremental = "current_date - interval '1' day" -%}
{%- set time_start = "current_date - interval '2' day" -%}
{%- set time_end = "current_date + interval '1' day" -%}

{{ config(
    alias = 'dbt_template_datashare_incremental_model'
    , materialized = 'incremental'
    , incremental_strategy = 'merge'
    , unique_key = ['block_number', 'block_date']
    , incremental_predicates = ["DBT_INTERNAL_DEST.block_date >= " ~ time_start_incremental]
    , meta = {
        "dune": {
            "public": false
        },
        "datashare": {
            "enabled": true,
            "time_column": "block_date",
            "time_start": time_start,
            "time_start_incremental": time_start_incremental,
            "time_end": time_end
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
