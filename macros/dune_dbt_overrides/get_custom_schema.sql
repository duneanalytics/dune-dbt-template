{#
    You can write to 2 different schemas.
    - <team_name> : use this for prod deployments
    - <team_name>__tmp_ : use this for general dev deployments
    - <team_name>__tmp_<dev_name> : use this for dev deployments by a specific developer or PR

reminder: target schema is set in profiles.yml
#}

{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- if target.name == 'prod' -%}
        {# prod environment, writes to target schema #}
        {{ target.schema }}
    {%- elif target.name != 'prod' and env_var('DEV_SCHEMA_SUFFIX') is not none -%}
        {# dev environments, writes to target schema with dev suffix #}
        {{ target.schema }}{{ env_var('DEV_SCHEMA_SUFFIX') | trim }}
    {%- else -%}
        {{target.schema}} 
    {%- endif -%}

{%- endmacro %}