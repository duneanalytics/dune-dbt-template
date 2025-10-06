{#
    profiles.yml is used to set environments, target specific schema name:
        - <team_name> : use this for prod deployments
        - <team_name>__tmp_ : use this for general dev/CI deployments
        - <team_name>__tmp_<dev_name> : use this for dev deployments by a specific developer or PR
#}

{#
    TEMP: force `test_schema` for all runs
    actual macro will look similar to this:
    {% macro generate_schema_name(custom_schema_name, node) -%}

        {%- set dev_suffix = env_var('DEV_SCHEMA_SUFFIX', '') -%}

        {%- if target.schema.startswith("wizard") -%}
            {# temp: until we use new API connection and generic GH runners #}
            {{ 'test_schema' }}
        {%- elif target.name == 'prod' -%}
            {# prod environment, writes to target schema #}
            {{ target.schema }}
        {%- elif target.name != 'prod' and dev_suffix != '' -%}
            {# dev environments, writes to target schema with dev suffix #}
            {{ target.schema }}__tmp_{{ dev_suffix | trim }}
        {%- else -%}
            {{ target.schema }}__tmp_
        {%- endif -%}

    {%- endmacro %}
#}

{% macro generate_schema_name(custom_schema_name, node) -%}
    {{ 'test_schema' }}
{%- endmacro %}