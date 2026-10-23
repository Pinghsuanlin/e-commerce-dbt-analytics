-- Grain: one row per flagged gap, i.e. per (product_id, gap_start_week).
-- Drill-down list behind mart_demand_adjusted_weekly.n_products_in_gap.
-- PROXY: a gap is an unusually long run of zero-sale weeks for a product that
-- normally sells; it is not an observed stock-out (Olist has no inventory data).
with gap_weeks as (

    select * from {{ ref('int_product_availability_gaps') }}
    where is_likely_availability_gap

),

gaps as (

    select
        product_id,
        any_value(product_category) as product_category,
        zero_run_start_week as gap_start_week,
        any_value(zero_run_end_week) as gap_end_week,
        any_value(zero_run_length) as gap_weeks,
        any_value(weekly_sell_probability) as weekly_sell_probability,
        any_value(avg_units_per_span_week) as avg_units_per_span_week,
        any_value(prob_zero_run_by_chance) as prob_zero_run_by_chance
    from gap_weeks
    group by product_id, zero_run_start_week

)

select
    product_id || '-' || cast(gap_start_week as varchar) as gap_key,
    product_id,
    product_category,
    gap_start_week,
    gap_end_week,
    gap_weeks,
    weekly_sell_probability,
    prob_zero_run_by_chance,
    avg_units_per_span_week * gap_weeks as expected_units_in_gap_proxy
from gaps
