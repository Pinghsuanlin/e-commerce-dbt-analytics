-- Grain: one row per (product_id, purchase week) with at least one unit sold.
-- Sparse on purpose: zero-sale weeks are filled in only where they mean
-- something (int_product_availability_gaps and the category mart).
-- Valid orders only. Review score is carried as a sum and a count so that any
-- roll-up can compute a correctly weighted average.
with items as (

    select * from {{ ref('int_order_items_enriched') }}
    where is_valid_order

)

select
    product_id,
    purchase_week_start as week_start,
    any_value(product_category) as product_category,
    count(*) as units_sold,
    count(distinct order_id) as n_orders,
    sum(item_price) as item_revenue,
    sum(freight_value) as freight_revenue,
    {{ safe_divide('sum(item_price)', 'count(*)') }} as avg_unit_price,
    count(order_review_score) as n_reviewed_units,
    sum(order_review_score) as review_score_sum
from items
group by product_id, purchase_week_start
