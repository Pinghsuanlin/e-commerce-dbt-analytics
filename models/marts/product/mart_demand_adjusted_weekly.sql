{{ config(materialized='view') }}

-- Grain: one row per (product_category, week_start), same rows as
-- mart_product_performance_weekly.
-- Adds two lenses for reading weekly demand:
--   1. Seasonal adjustment: units and revenue divided by the platform
--      week-of-year index, so a quiet January week is not read as a demand drop.
--   2. Availability-gap PROXY: how many of the category's regular-selling
--      products had an unexpected run of zero-sale weeks that week. Olist has no
--      inventory data; this flags suspicious silence, not confirmed stock-outs.
with performance as (

    select * from {{ ref('mart_product_performance_weekly') }}

),

seasonality as (

    select * from {{ ref('int_seasonality_index') }}

),

gaps as (

    select
        product_category,
        week_start,
        count(*) as n_regular_products_tracked,
        count(*) filter (where is_likely_availability_gap) as n_products_in_gap,
        sum(case when is_likely_availability_gap then avg_units_per_span_week else 0 end)
            as expected_units_in_gap_proxy
    from {{ ref('int_product_availability_gaps') }}
    group by product_category, week_start

)

select
    performance.category_week_key,
    performance.product_category,
    performance.week_start,
    performance.iso_year,
    performance.iso_week,
    performance.units_sold,
    performance.item_revenue,
    performance.avg_unit_price,
    performance.avg_review_score,
    coalesce(seasonality.seasonality_index, 1.0) as seasonality_index,
    {{ safe_divide('performance.units_sold', 'coalesce(seasonality.seasonality_index, 1.0)') }}
        as seasonally_adjusted_units,
    {{ safe_divide('performance.item_revenue', 'coalesce(seasonality.seasonality_index, 1.0)') }}
        as seasonally_adjusted_revenue,
    coalesce(gaps.n_regular_products_tracked, 0) as n_regular_products_tracked,
    coalesce(gaps.n_products_in_gap, 0) as n_products_in_gap,
    {{ safe_divide('gaps.n_products_in_gap', 'gaps.n_regular_products_tracked') }} as share_regular_products_in_gap,
    coalesce(gaps.expected_units_in_gap_proxy, 0) as expected_units_in_gap_proxy,
    coalesce(gaps.n_products_in_gap, 0) > 0 as has_availability_gap_flag
from performance
left join seasonality
    on performance.iso_week = seasonality.iso_week
left join gaps
    on performance.product_category = gaps.product_category
    and performance.week_start = gaps.week_start
