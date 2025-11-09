{% macro optimize_table(this, materialization) %}
{%- if target.name == 'prod' and materialization in ('table', 'incremental') -%}
    alter table {{this}} execute optimize
{%- endif -%}
{%- endmacro -%}