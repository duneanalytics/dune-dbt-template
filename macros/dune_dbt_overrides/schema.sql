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