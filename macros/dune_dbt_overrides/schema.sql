-- This could best be handled by the backend.

{% macro trino__create_schema(relation) -%}
  {%- call statement('create_schema') -%}
   CREATE SCHEMA {{ relation }} WITH (location = 's3a://prod-spellbook-trino-118330671040/')
  {% endcall %}
{% endmacro %}