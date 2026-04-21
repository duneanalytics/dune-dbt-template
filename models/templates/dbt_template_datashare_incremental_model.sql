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
