-- Order value is defined once, in fct_orders, from the item lines.
-- Fails on any order whose gross_order_value differs from the sum of its item
-- lines (price + freight) by more than the revenue tolerance.
with item_totals as (
    select order_id, sum(item_gross_value) as items_gross_value
    from {{ ref('int_order_items_enriched') }}
    group by order_id
)
select o.order_id, o.gross_order_value, coalesce(i.items_gross_value, 0) as items_gross_value
from {{ ref('fct_orders') }} as o
left join item_totals as i on o.order_id = i.order_id
where abs(o.gross_order_value - coalesce(i.items_gross_value, 0)) > {{ var('revenue_tolerance') }}
