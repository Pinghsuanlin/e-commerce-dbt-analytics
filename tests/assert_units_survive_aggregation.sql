-- Every unit sold must survive each aggregation step:
-- valid item lines -> product-weeks -> category-weeks.
-- Compared inside the complete weeks the weekly marts cover.
with spine as (
    select week_start from {{ ref('int_week_spine') }}
),
items as (
    select count(*) as units
    from {{ ref('int_order_items_enriched') }}
    where is_valid_order
      and purchase_week_start in (select week_start from spine)
),
product_weeks as (
    select coalesce(sum(units_sold), 0) as units
    from {{ ref('int_product_weekly_sales') }}
    where week_start in (select week_start from spine)
),
category_weeks as (
    select coalesce(sum(units_sold), 0) as units
    from {{ ref('mart_product_performance_weekly') }}
)
select items.units as item_units, product_weeks.units as product_week_units,
       category_weeks.units as category_week_units
from items cross join product_weeks cross join category_weeks
where items.units != product_weeks.units
   or product_weeks.units != category_weeks.units
