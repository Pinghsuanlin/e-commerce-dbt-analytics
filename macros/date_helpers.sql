{#
    Calendar helpers. Weeks are ISO weeks: Monday to Sunday, so week_start is
    always a Monday. Keeping this in one macro means every weekly model agrees
    on which week an order belongs to.
#}

{% macro week_start(column) -%}
    cast(date_trunc('week', {{ column }}) as date)
{%- endmacro %}

{% macro iso_week(column) -%}
    cast(weekofyear({{ column }}) as integer)
{%- endmacro %}

{% macro iso_year(column) -%}
    cast(isoyear({{ column }}) as integer)
{%- endmacro %}
