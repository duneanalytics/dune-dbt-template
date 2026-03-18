{%- macro dune_properties(properties) -%}
  map_from_entries(ARRAY[
  {%- for key, value in properties.items() %}
      ROW('{{ key }}', '{{ value }}')
      {%- if not loop.last -%},{%- endif -%}
    {%- endfor %}
  ])
{%- endmacro -%}

{# post-hook that keeps dune.public in sync on incremental (non-full-refresh) runs where no CREATE TABLE is issued #}
{% macro set_table_visibility(this, materialization) %}
{%- if target.name == 'prod'
    and materialization == 'incremental'
    and not flags.FULL_REFRESH -%}
  {%- set dune_public = config.get('meta', {}).get('dune', {}).get('public', false) -%}
  {%- set properties = {'dune.public': 'true' if dune_public else 'false'} -%}
  ALTER TABLE {{ this }}
    SET PROPERTIES extra_properties = {{ dune_properties(properties) }}
{%- endif -%}
{%- endmacro -%}
