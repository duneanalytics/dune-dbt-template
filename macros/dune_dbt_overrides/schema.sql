{#
    goal: remove this macro override, have the backend handle s3 bucket names
      - prod: trino-prod-datasets-118330671040/write/<customer_team_name>/…
      - dev:  trino-dev-datasets-118330671040/write/<customer_team_name>/…
    goal: remove the trino__create_schema macro override and ensure backend applies <WITH location> logic
#}

{%- macro s3_bucket() -%}
  {%- if target.name == 'prod' -%}
    {{- return('prod-spellbook-trino-118330671040') -}}
  {%- else -%}
    {{- return('trino-dev-datasets-118330671040') -}}
  {%- endif -%}
{%- endmacro -%}

{% macro trino__create_schema(relation) -%}
  {%- call statement('create_schema') -%}
   CREATE SCHEMA {{ relation }} WITH (location = 's3a://{{s3_bucket()}}/')
  {% endcall %}
{% endmacro %}