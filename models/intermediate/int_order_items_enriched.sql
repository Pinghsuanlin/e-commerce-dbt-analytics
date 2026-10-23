-- Grain: one row per order item (order_id, order_item_id) = one unit sold.
-- Joins each item to its order, customer, product category, seller and the
-- order-level review score. All joins are many-to-one onto the item, so the
-- row count equals stg_olist__order_items (tested in the schema file).
with items as (

    select * from {{ ref('stg_olist__order_items') }}

),

orders as (

    select * from {{ ref('stg_olist__orders') }}

),

customers as (

    select * from {{ ref('stg_olist__customers') }}

),

products as (

    select * from {{ ref('stg_olist__products') }}

),

translation as (

    select * from {{ ref('stg_olist__category_translation') }}

),

sellers as (

    select * from {{ ref('stg_olist__sellers') }}

),

reviews as (

    select * from {{ ref('int_order_reviews') }}

)

select
    items.order_id || '-' || cast(items.order_item_id as varchar) as order_item_key,
    items.order_id,
    items.order_item_id,
    items.product_id,
    items.seller_id,
    orders.customer_id,
    customers.customer_unique_id,
    orders.order_status,
    {{ is_valid_order('orders.order_status') }} as is_valid_order,
    orders.purchased_at,
    cast(orders.purchased_at as date) as purchase_date,
    {{ week_start('orders.purchased_at') }} as purchase_week_start,
    {{ product_category_label('translation.product_category_name_en', 'products.product_category_name_pt') }}
        as product_category,
    products.product_category_name_pt,
    customers.customer_state,
    sellers.seller_state,
    customers.customer_state = sellers.seller_state as is_same_state_shipment,
    items.shipping_limit_at,
    items.item_price,
    items.freight_value,
    items.item_price + items.freight_value as item_gross_value,
    reviews.review_score as order_review_score
from items
inner join orders
    on items.order_id = orders.order_id
left join customers
    on orders.customer_id = customers.customer_id
left join products
    on items.product_id = products.product_id
left join translation
    on products.product_category_name_pt = translation.product_category_name_pt
left join sellers
    on items.seller_id = sellers.seller_id
left join reviews
    on items.order_id = reviews.order_id
