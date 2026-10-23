-- Grain: one row per ISO week of year (1 to 53) observed in the analysis window.
--
-- Week-of-year seasonality index, estimated at platform level (all categories):
--   1. Total units per week across the analysis window.
--   2. Fit a log-linear growth trend: ln(units) = a + b * week_number. Olist grew
--      fast over 2017-2018, so comparing raw weeks would mistake growth for season.
--   3. Ratio of each week to its trend value. Average the ratios by ISO week.
--   4. Smooth with a centred 3-week moving average (most ISO weeks are observed
--      only once or twice, so the raw ratio is noisy), then rescale so the
--      index averages 1.0.
-- Platform level, not per category, because ~20 months of data cannot support a
-- separate seasonal shape for each of 70+ categories. Categories with their own
-- seasonality (toys at Christmas, say) are only partly corrected.
with spine as (

    select * from {{ ref('int_week_spine') }}

),

weekly as (

    select
        spine.week_start,
        spine.iso_week,
        spine.week_number,
        coalesce(sum(sales.units_sold), 0) as units_sold
    from spine
    left join {{ ref('int_product_weekly_sales') }} as sales
        on spine.week_start = sales.week_start
    group by spine.week_start, spine.iso_week, spine.week_number

),

trend as (

    select
        regr_slope(ln(units_sold), week_number) as slope,
        regr_intercept(ln(units_sold), week_number) as intercept
    from weekly
    where units_sold > 0

),

ratios as (

    select
        weekly.iso_week,
        weekly.units_sold,
        exp(trend.intercept + trend.slope * weekly.week_number) as trend_units,
        weekly.units_sold / exp(trend.intercept + trend.slope * weekly.week_number) as ratio_to_trend
    from weekly
    cross join trend

),

by_iso_week as (

    select
        iso_week,
        count(*) as n_weeks_observed,
        avg(ratio_to_trend) as raw_ratio
    from ratios
    group by iso_week

),

smoothed as (

    select
        *,
        avg(raw_ratio) over (order by iso_week rows between 1 preceding and 1 following) as smoothed_ratio
    from by_iso_week

)

select
    iso_week,
    n_weeks_observed,
    raw_ratio / avg(raw_ratio) over () as seasonality_index_raw,
    smoothed_ratio / avg(smoothed_ratio) over () as seasonality_index
from smoothed
