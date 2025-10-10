{#
    profiles.yml is used to set environments, target specific schema name:
        - --target prod: <team_name>
        - --target dev, no DEV_SCHEMA_SUFFIX value set: <team_name>__tmp_
        - --target dev, DEV_SCHEMA_SUFFIX value set: <team_name>__tmp_<DEV_SCHEMA_SUFFIX>
            --note: in CI workflow, DEV_SCHEMA_SUFFIX is set to PR_NUMBER
#}

{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- set dev_suffix = env_var('DEV_SCHEMA_SUFFIX', '') -%}

    {%- if target.name == 'prod' -%}
        {# prod environment, writes to target schema #}
        {{ target.schema }}
    {%- elif target.name != 'prod' and dev_suffix != '' -%}
        {# dev environments, writes to target schema with dev suffix #}
        {{ target.schema }}__tmp_{{ dev_suffix | trim }}
    {%- else -%}
        {# default to dev environment, no dev suffix #}
        {{ target.schema }}__tmp_
    {%- endif -%}

{%- endmacro %}