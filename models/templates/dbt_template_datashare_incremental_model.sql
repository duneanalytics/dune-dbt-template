{%- set incremental_time_start = "current_date - interval '1' day" -%}
{%- set full_refresh_time_start = "current_date - interval '2' day" -%}
{%- set time_end = "current_date + interval '1' day" -%}

{{ config(
    alias = 'dbt_template_datashare_incremental_model'
    , materialized = 'incremental'
    , incremental_strategy = 'merge'
    , unique_key = ['block_number', 'block_date']
    , incremental_predicates = ["DBT_INTERNAL_DEST.block_date >= " ~ incremental_time_start]
    , meta = {
        "dune": {
            "public": false
        },
        "datashare": {
            "enabled": true,
            "time_column": "block_date",
            "time_start": full_refresh_time_start,
            "time_start_incremental": incremental_time_start,
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
where block_date >= {{ incremental_time_start if is_incremental() else full_refresh_time_start }}
  and block_date < {{ time_end }}
group by 1, 2
