{% macro vacuum_table(this, materialization) %}
{%- if target.name == 'prod' and materialization in ('table', 'incremental') -%}
    call delta.system.vacuum('{{ this.schema }}', '{{ this.name }}', '7d')
{%- endif -%}
{%- endmacro -%}