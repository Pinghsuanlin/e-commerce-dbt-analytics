-- Grain: one row per (product_id, week_start) for regular-selling products,
-- covering every week from the product's first to last sale in the window.
--
-- PROXY, NOT A MEASUREMENT. Olist publishes no inventory or listing data, so we
-- cannot observe a stock-out. We flag runs of zero-sale weeks that would be
-- unlikely if the product kept selling at its usual rate:
--   p = share of weeks the product sold (weekly_sell_probability)
--   chance of r empty weeks in a row by luck = (1 - p) ^ r
-- A run is a "likely availability gap" when it lasts at least gap_min_run_weeks
-- and that chance is below gap_probability_threshold. A flag can equally mean
-- the seller paused the listing, changed price, or demand moved elsewhere.
with regular_products as (

    select * from {{ ref('int_product_sales_profile') }}
    where is_regular_seller

),

spine as (

    select week_start from {{ ref('int_week_spine') }}

),

product_weeks as (

    select
        products.product_id,
        products.product_category,
        spine.week_start,
        products.weekly_sell_probability,
        products.avg_units_per_span_week
    from regular_products as products
    inner join spine
        on spine.week_start between products.first_sale_week and products.last_sale_week

),

filled as (

    select
        product_weeks.*,
        coalesce(sales.units_sold, 0) as units_sold,
        coalesce(sales.units_sold, 0) = 0 as is_zero_week
    from product_weeks
    left join {{ ref('int_product_weekly_sales') }} as sales
        on product_weeks.product_id = sales.product_id
        and product_weeks.week_start = sales.week_start

),

-- Gaps-and-islands: consecutive weeks with the same is_zero_week value share
-- the same (row number) minus (row number within that value).
islands as (

    select
        *,
        row_number() over (partition by product_id order by week_start)
        - row_number() over (partition by product_id, is_zero_week order by week_start) as run_group
    from filled

),

runs as (

    select
        *,
        count(*) over (partition by product_id, is_zero_week, run_group) as run_length,
        min(week_start) over (partition by product_id, is_zero_week, run_group) as run_start_week,
        max(week_start) over (partition by product_id, is_zero_week, run_group) as run_end_week
    from islands

),

scored as (

    select
        *,
        case
            when is_zero_week then pow(1 - weekly_sell_probability, run_length)
        end as prob_zero_run_by_chance
    from runs

)

select
    product_id || '-' || cast(week_start as varchar) as product_week_key,
    product_id,
    product_category,
    week_start,
    units_sold,
    is_zero_week,
    case when is_zero_week then run_length end as zero_run_length,
    case when is_zero_week then run_start_week end as zero_run_start_week,
    case when is_zero_week then run_end_week end as zero_run_end_week,
    weekly_sell_probability,
    avg_units_per_span_week,
    prob_zero_run_by_chance,
    coalesce(
        is_zero_week
        and run_length >= {{ var('gap_min_run_weeks') }}
        and prob_zero_run_by_chance < {{ var('gap_probability_threshold') }},
        false
    ) as is_likely_availability_gap
from scored
