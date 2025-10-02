{#
    goal: depending on how we handle dev vs. prod environments (i.e. s3), we may not need this macro override

    Custom schema naming logic for dev vs prod environments
    
    Purpose:
    - PROD: Use clean schema names directly (e.g., "dbt_template")
      Allows production tables to live in well-defined schemas without prefixes
    
    - DEV: Prefix schemas with developer namespace (e.g., "dev_user_dbt_template")
      Prevents developers from overwriting each other's work and isolates testing
      
    Usage:
    - In prod target: custom_schema_name becomes the schema name
    - In dev targets: default_schema + custom_schema_name for namespacing
    - No custom_schema_name: uses default target.schema
#}

{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- set default_schema = target.schema -%}
    {%- if target.name == 'prod' and custom_schema_name is not none -%}
        {# prod environment #}
        {{ custom_schema_name | trim }}

    {%- elif target.schema.startswith("github_actions") -%}
        {# test environment, CI pipeline #}
        {{ 'test_schema' }}

    {%- elif custom_schema_name is none -%}
        
        {{ default_schema }}

    {%- else -%}
        {# dev environment, running locally #}
        {{ default_schema }}_{{ custom_schema_name | trim }}

    {%- endif -%}

{%- endmacro %}