{%- macro dune_properties(properties) -%}
  map_from_entries(ARRAY[
  {%- for key, value in properties.items() %}
      ROW('{{ key }}', '{{ value }}')
      {%- if not loop.last -%},{%- endif -%}
    {%- endfor %}
  ])
{%- endmacro -%}

{#
  set_table_visibility: post-hook that sets dune.public on incremental (non-full-refresh) runs.

  For table materializations and incremental full-refreshes, extra_properties is set
  at CREATE TABLE time via the overridden properties() macro. This hook handles the
  incremental case where no CREATE is issued (INSERT/MERGE only).

  Configure per model via config():
    , dune_public = true   -- make table publicly visible on Dune
    , dune_public = false  -- (default) keep table private

  Or set for an entire folder in dbt_project.yml:
    models:
      my_project:
        public_models:
          +dune_public: true

  Only runs in prod. Views are not supported.
#}
{% macro set_table_visibility(this, materialization) %}
{%- if target.name == 'prod'
    and materialization == 'incremental'
    and not flags.FULL_REFRESH -%}
  {%- set dune_public = config.get('dune_public', false) -%}
  {%- set properties = {'dune.public': 'true' if dune_public else 'false'} -%}
  ALTER TABLE {{ this }}
    SET PROPERTIES extra_properties = {{ dune_properties(properties) }}
{%- endif -%}
{%- endmacro -%}
