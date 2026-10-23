{#
    Builds one row of the data quality summary: how many rows of a relation
    fail a condition, out of how many checked.

    Arguments
      check_name         short snake_case id for the check
      model_name         the model (or source) the check is about
      relation           a ref(), source() or CTE name to scan
      failing_condition  SQL boolean that is true for a failing row
      severity           'error' | 'warn' | 'info'
      description        plain-English meaning of a failure
      scope_condition    optional SQL boolean restricting which rows are checked
#}
{% macro dq_check(check_name, model_name, relation, failing_condition, severity, description, scope_condition='true') -%}
    select
        '{{ check_name }}' as check_name,
        '{{ model_name }}' as model_name,
        '{{ severity }}' as severity,
        '{{ description | replace("'", "''") }}' as description,
        count(*) filter (where {{ failing_condition }}) as n_failing,
        count(*) as n_checked
    from {{ relation }}
    where {{ scope_condition }}
{%- endmacro %}
