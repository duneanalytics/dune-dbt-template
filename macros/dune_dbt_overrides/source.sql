{% macro source(source_name, table_name, database="delta_prod") %}
  {% set rel = builtins.source(source_name, table_name) %}
  {% set newrel = rel.replace_path(database=database) %}
  {% do return(newrel) %}
{% endmacro %}
