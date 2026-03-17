{%- macro dune_properties(properties) -%}
  map_from_entries(ARRAY[
  {%- for key, value in properties.items() %}
      ROW('{{ key }}', '{{ value }}')
      {%- if not loop.last -%},{%- endif -%}
    {%- endfor %}
  ])
{%- endmacro -%}

{#
  set_table_visibility: post-hook macro that sets the dune.public extra property on tables/incrementals.

  Configure per model via config():
    , dune_public = true   -- make table publicly visible on Dune
    , dune_public = false  -- (default) keep table private

  Or set for an entire folder in dbt_project.yml:
    models:
      my_project:
        public_models:
          +dune_public: true

  Only runs in prod. Views are not supported yet.
#}
{% macro set_table_visibility(this, materialization) %}
{%- if target.name == 'prod' and materialization in ('table', 'incremental') -%}
  {%- set dune_public = config.get('dune_public', false) -%}
  {%- set properties = {'dune.public': 'true' if dune_public else 'false'} -%}
  ALTER TABLE {{ this }}
    SET PROPERTIES extra_properties = {{ dune_properties(properties) }}
{%- endif -%}
{%- endmacro -%}
