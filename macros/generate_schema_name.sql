{#
    Use the custom schema name as-is (staging, intermediate, marts,
    data_quality) instead of dbt's default "<target_schema>_<custom>".
    There is one local target, so prefixing adds noise without protecting
    anything.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
