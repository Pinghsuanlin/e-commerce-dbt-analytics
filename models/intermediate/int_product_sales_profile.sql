-- Grain: one row per product_id that sold at least once inside the analysis window.
-- Describes how regularly a product sells, which is the baseline the
-- availability-gap proxy compares against.
with weekly as (

    select sales.*
    from {{ ref('int_product_weekly_sales') }} as sales
    inner join {{ ref('int_week_spine') }} as spine
        on sales.week_start = spine.week_start

),

profile as (

    select
        product_id,
        any_value(product_category) as product_category,
        min(week_start) as first_sale_week,
        max(week_start) as last_sale_week,
        count(*) as active_weeks,
        cast(date_diff('day', min(week_start), max(week_start)) / 7 as integer) + 1 as span_weeks,
        sum(units_sold) as units_in_window
    from weekly
    group by product_id

)

select
    product_id,
    product_category,
    first_sale_week,
    last_sale_week,
    active_weeks,
    span_weeks,
    units_in_window,
    -- Share of weeks between first and last sale in which the product sold.
    -- Computed over a span that includes any gaps, so it is conservative:
    -- real gaps pull it down and make a gap less likely to be flagged.
    {{ safe_divide('active_weeks', 'span_weeks') }} as weekly_sell_probability,
    {{ safe_divide('units_in_window', 'span_weeks') }} as avg_units_per_span_week,
    active_weeks >= {{ var('regular_min_active_weeks') }}
    and {{ safe_divide('active_weeks', 'span_weeks') }} >= {{ var('regular_min_sell_probability') }}
        as is_regular_seller
from profile
