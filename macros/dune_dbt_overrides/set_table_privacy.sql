{%- macro dune_properties(properties) -%}
  map_from_entries(ARRAY[
  {%- for key, value in properties.items() %}
      ROW('{{ key }}', '{{ value }}')
      {%- if not loop.last -%},{%- endif -%}
    {%- endfor %}
  ])
{%- endmacro -%}

{# post-hook that sets dune.public via ALTER TABLE on every table/incremental run (prod only). Views are skipped: their privacy cannot be changed after creation, and a view over private tables stays restricted anyway. #}
{% macro set_table_privacy(this, materialization) %}
{%- if target.name == 'prod'
    and materialization in ('table', 'incremental') -%}
  {%- set dune_public = config.get('meta', {}).get('dune', {}).get('public', false) -%}
  {%- set properties = {'dune.public': 'true' if dune_public else 'false'} -%}
  ALTER TABLE {{ this }}
    SET PROPERTIES extra_properties = {{ dune_properties(properties) }}
{%- endif -%}
{%- endmacro -%}
