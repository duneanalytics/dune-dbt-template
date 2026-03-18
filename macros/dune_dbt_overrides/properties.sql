{# Override of the dbt-trino adapter's properties() macro to inject dune.public into extra_properties at CREATE TABLE time. #}
{% macro properties(temporary=False) %}
  {%- set _properties = config.get('properties') -%}
  {%- set table_format = config.get('table_format') -%}
  {%- set file_format = config.get('file_format') -%}

  {%- if file_format -%}
    {%- if _properties -%}
      {%- if _properties.format -%}
        {% set msg %}
          You can specify either 'file_format' or 'properties.format' configurations, but not both.
        {% endset %}
        {% do exceptions.raise_compiler_error(msg) %}
      {%- else -%}
        {%- do _properties.update({'format': "'" ~ file_format ~ "'"}) -%}
      {%- endif -%}
    {%- else -%}
      {%- set _properties = {'format': "'" ~ file_format ~ "'"} -%}
    {%- endif -%}
  {%- endif -%}

  {%- if table_format -%}
    {%- if _properties -%}
      {%- if _properties.type -%}
        {% set msg %}
          You can specify either 'table_format' or 'properties.type' configurations, but not both.
        {% endset %}
        {% do exceptions.raise_compiler_error(msg) %}
      {%- else -%}
        {%- do _properties.update({'type': "'" ~ table_format ~ "'"}) -%}
      {%- endif -%}
    {%- else -%}
      {%- set _properties = {'type': "'" ~ table_format ~ "'"} -%}
    {%- endif -%}
  {%- endif -%}

  {%- if temporary -%}
    {%- if _properties -%}
      {%- if _properties.location -%}
          {%- do _properties.update({'location': _properties.location[:-1] ~ "__dbt_tmp'"}) -%}
      {%- endif -%}
    {%- endif -%}
  {%- endif -%}

  {%- set dune_public = config.get('meta', {}).get('dune', {}).get('public') -%}
  {%- if dune_public is not none and target.name == 'prod' -%}
    {%- set visibility_value = 'true' if dune_public else 'false' -%}
    {%- set extra_props_sql = "map_from_entries(ARRAY[ROW('dune.public', '" ~ visibility_value ~ "')])" -%}
    {%- if _properties is none -%}
      {%- set _properties = {'extra_properties': extra_props_sql} -%}
    {%- else -%}
      {%- do _properties.update({'extra_properties': extra_props_sql}) -%}
    {%- endif -%}
  {%- endif -%}

  {%- if _properties is not none -%}
      WITH (
          {%- for key, value in _properties.items() -%}
            {{ key }} = {{ value }}
            {%- if not loop.last -%}{{ ',\n  ' }}{%- endif -%}
          {%- endfor -%}
      )
  {%- endif -%}
{%- endmacro -%}
