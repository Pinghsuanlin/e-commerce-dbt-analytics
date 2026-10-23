-- Grain: one row per (product_category, week_start), dense.
-- Every category that ever sold is paired with every complete week in the
-- analysis window, so a week with no sales shows as 0 rather than vanishing.
-- Valid orders only. Review score is the order-level score attributed to each
-- unit, by purchase week (reviews are written after delivery).
with spine as (

    select * from {{ ref('int_week_spine') }}

),

categories as (

    select distinct product_category
    from {{ ref('int_product_weekly_sales') }}

),

grid as (

    select
        categories.product_category,
        spine.week_start,
        spine.iso_year,
        spine.iso_week
    from categories
    cross join spine

),

product_weeks as (

    select
        product_category,
        week_start,
        sum(units_sold) as units_sold,
        sum(item_revenue) as item_revenue,
        sum(freight_revenue) as freight_revenue,
        count(*) as n_products_sold,
        sum(n_reviewed_units) as n_reviewed_units,
        sum(review_score_sum) as review_score_sum
    from {{ ref('int_product_weekly_sales') }}
    group by product_category, week_start

),

-- Distinct orders must be counted from items: summing product-level order
-- counts would double count orders containing several products.
category_orders as (

    select
        product_category,
        purchase_week_start as week_start,
        count(distinct order_id) as n_orders
    from {{ ref('int_order_items_enriched') }}
    where is_valid_order
    group by product_category, purchase_week_start

),

joined as (

    select
        grid.product_category,
        grid.week_start,
        grid.iso_year,
        grid.iso_week,
        coalesce(product_weeks.units_sold, 0) as units_sold,
        coalesce(category_orders.n_orders, 0) as n_orders,
        coalesce(product_weeks.item_revenue, 0) as item_revenue,
        coalesce(product_weeks.freight_revenue, 0) as freight_revenue,
        coalesce(product_weeks.n_products_sold, 0) as n_products_sold,
        {{ safe_divide('product_weeks.item_revenue', 'product_weeks.units_sold') }} as avg_unit_price,
        coalesce(product_weeks.n_reviewed_units, 0) as n_reviewed_units,
        {{ safe_divide('product_weeks.review_score_sum', 'product_weeks.n_reviewed_units') }} as avg_review_score
    from grid
    left join product_weeks
        on grid.product_category = product_weeks.product_category
        and grid.week_start = product_weeks.week_start
    left join category_orders
        on grid.product_category = category_orders.product_category
        and grid.week_start = category_orders.week_start

)

select
    product_category || '-' || cast(week_start as varchar) as category_week_key,
    *,
    avg(units_sold) over (
        partition by product_category
        order by week_start
        rows between 3 preceding and current row
    ) as units_sold_trailing_4wk_avg
from joined
