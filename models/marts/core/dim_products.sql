-- Grain: one row per product_id (every product in the catalogue, sold or not).
-- Lifetime sales cover all valid orders. Regularity fields cover the analysis
-- window only and are null for products with no sale in it.
with products as (

    select * from {{ ref('stg_olist__products') }}

),

translation as (

    select * from {{ ref('stg_olist__category_translation') }}

),

lifetime_sales as (

    select
        product_id,
        sum(units_sold) as lifetime_units_sold,
        sum(n_orders) as lifetime_orders,
        sum(item_revenue) as lifetime_item_revenue,
        sum(n_reviewed_units) as lifetime_reviewed_units,
        sum(review_score_sum) as lifetime_review_score_sum,
        min(week_start) as first_sale_week_all_time,
        max(week_start) as last_sale_week_all_time
    from {{ ref('int_product_weekly_sales') }}
    group by product_id

),

profile as (

    select * from {{ ref('int_product_sales_profile') }}

)

select
    products.product_id,
    {{ product_category_label('translation.product_category_name_en', 'products.product_category_name_pt') }}
        as product_category,
    products.product_category_name_pt,
    translation.product_category_name_en,
    products.product_category_name_pt is not null as has_category,
    translation.product_category_name_en is not null as has_english_category,
    products.product_name_length,
    products.product_description_length,
    products.product_photos_qty,
    products.product_weight_g,
    products.product_length_cm,
    products.product_height_cm,
    products.product_width_cm,
    products.product_length_cm * products.product_height_cm * products.product_width_cm as product_volume_cm3,
    coalesce(lifetime_sales.lifetime_units_sold, 0) as lifetime_units_sold,
    coalesce(lifetime_sales.lifetime_orders, 0) as lifetime_orders,
    coalesce(lifetime_sales.lifetime_item_revenue, 0) as lifetime_item_revenue,
    {{ safe_divide('lifetime_sales.lifetime_item_revenue', 'lifetime_sales.lifetime_units_sold') }}
        as lifetime_avg_unit_price,
    {{ safe_divide('lifetime_sales.lifetime_review_score_sum', 'lifetime_sales.lifetime_reviewed_units') }}
        as avg_review_score,
    lifetime_sales.first_sale_week_all_time,
    lifetime_sales.last_sale_week_all_time,
    profile.active_weeks as active_weeks_in_window,
    profile.span_weeks as span_weeks_in_window,
    profile.weekly_sell_probability,
    coalesce(profile.is_regular_seller, false) as is_regular_seller
from products
left join translation
    on products.product_category_name_pt = translation.product_category_name_pt
left join lifetime_sales
    on products.product_id = lifetime_sales.product_id
left join profile
    on products.product_id = profile.product_id
