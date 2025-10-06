{#
    profiles.yml is used to set environments, target specific schema name:
        - <team_name> : use this for prod deployments
        - <team_name>__tmp_ : use this for general dev/CI deployments
        - <team_name>__tmp_<dev_name> : use this for dev deployments by a specific developer or PR

        
    TEMP: force `test_schema` for all runs
#}

{% macro generate_schema_name(custom_schema_name, node) -%}
    {{ 'test_schema' }}
{%- endmacro %}