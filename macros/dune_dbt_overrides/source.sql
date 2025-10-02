{#
    once we change the connection to dune connectivity / api, QES should auto-resolve delta_prod database for sources?
    goal: remove this macro override, have the backend handle applying delta_prod database for sources
#}

{% macro source(source_name, table_name, database="delta_prod") %}
  {% set rel = builtins.source(source_name, table_name) %}
  {% set newrel = rel.replace_path(database=database) %}
  {% do return(newrel) %}
{% endmacro %}