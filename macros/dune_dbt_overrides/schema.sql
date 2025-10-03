{#
    TODO: remove this macro override, have the backend handle s3 bucket names
      - prod: trino-prod-datasets-118330671040/write/<customer_team_name>/…
      - dev:  trino-dev-datasets-118330671040/write/<customer_team_name>/…
#}

{% macro trino__create_schema(relation) -%}
  {%- call statement('create_schema') -%}
   CREATE SCHEMA {{ relation }} WITH (location = 's3a://prod-spellbook-trino-118330671040/{{relation}}/')
  {% endcall %}
{% endmacro %}