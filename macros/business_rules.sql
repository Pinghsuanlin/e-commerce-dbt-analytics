{#
    Shared business definitions. Each one is used by more than one model, so it
    lives here rather than being re-typed (and drifting) in each model.
#}

{# A valid order is any order not in an excluded status (see dbt_project.yml). #}
{% macro is_valid_order(status_column) -%}
    ({{ status_column }} not in (
        {%- for status in var('excluded_order_statuses') -%}
            '{{ status }}'{% if not loop.last %}, {% endif %}
        {%- endfor -%}
    ))
{%- endmacro %}

{# Category label used everywhere: English name, else Portuguese, else 'unknown'. #}
{% macro product_category_label(english_column, portuguese_column) -%}
    coalesce({{ english_column }}, {{ portuguese_column }}, 'unknown')
{%- endmacro %}

{# Division that returns null instead of failing or returning infinity. #}
{% macro safe_divide(numerator, denominator) -%}
    case
        when {{ denominator }} is null or {{ denominator }} = 0 then null
        else cast({{ numerator }} as double) / cast({{ denominator }} as double)
    end
{%- endmacro %}

{# Trim a raw text field and turn empty strings into nulls before casting. #}
{% macro clean_text(column) -%}
    nullif(trim({{ column }}), '')
{%- endmacro %}
