-- Grain: one row per cohort_month (month of a customer's first valid order).
-- Repeat purchase rate at N days = share of the cohort whose second valid order
-- (as defined in dim_customers) came within N days of the first.
--
-- Right-censoring: a customer who first ordered near the end of the data has
-- not had N days to come back. A cohort's N-day rate is only reported once
-- the last day of the cohort month plus N days falls inside the data;
-- otherwise it is null and is_complete_<N>d is false.
{%- set windows = var('retention_windows_days') %}

with customers as (

    select * from {{ ref('dim_customers') }}
    where cohort_month is not null

),

data_end as (

    select max(purchase_date) as data_end_date
    from {{ ref('fct_orders') }}
    where is_valid_order

),

cohorts as (

    select
        cohort_month,
        count(*) as cohort_size,
        {%- for days in windows %}
        count(*) filter (where days_to_repeat_purchase <= {{ days }}) as repeaters_{{ days }}d,
        {%- endfor %}
        count(*) filter (where has_repeat_purchase) as repeaters_ever
    from customers
    group by cohort_month

)

select
    cohorts.cohort_month,
    cohorts.cohort_size,
    {%- for days in windows %}
    cohorts.repeaters_{{ days }}d,
    cast(last_day(cohorts.cohort_month) + interval {{ days }} day as date) <= data_end.data_end_date
        as is_complete_{{ days }}d,
    case
        when cast(last_day(cohorts.cohort_month) + interval {{ days }} day as date) <= data_end.data_end_date
            then {{ safe_divide('cohorts.repeaters_' ~ days ~ 'd', 'cohorts.cohort_size') }}
    end as repeat_rate_{{ days }}d,
    {%- endfor %}
    cohorts.repeaters_ever,
    {{ safe_divide('cohorts.repeaters_ever', 'cohorts.cohort_size') }} as repeat_rate_to_date,
    data_end.data_end_date
from cohorts
cross join data_end
