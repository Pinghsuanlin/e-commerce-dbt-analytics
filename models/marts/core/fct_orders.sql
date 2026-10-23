-- Grain: one row per order_id (all statuses; filter on is_valid_order for revenue).
-- Order value is defined once here from the item lines:
--   item_revenue      = sum of item prices
--   freight_revenue   = sum of freight charged
--   gross_order_value = item_revenue + freight_revenue
-- Payments are kept alongside (payment_total) so the two can be reconciled.
with orders as (

    select * from {{ ref('stg_olist__orders') }}

),

customers as (

    select * from {{ ref('stg_olist__customers') }}

),

items as (

    select
        order_id,
        count(*) as n_items,
        count(distinct product_id) as n_products,
        count(distinct seller_id) as n_sellers,
        sum(item_price) as item_revenue,
        sum(freight_value) as freight_revenue
    from {{ ref('stg_olist__order_items') }}
    group by order_id

),

payments as (

    select
        order_id,
        sum(payment_value) as payment_total,
        count(*) as n_payment_records,
        count(distinct payment_type) as n_payment_types,
        max(payment_installments) as max_installments,
        arg_max(payment_type, payment_value) as primary_payment_type
    from {{ ref('stg_olist__order_payments') }}
    group by order_id

),

reviews as (

    select * from {{ ref('int_order_reviews') }}

),

joined as (

    select
        orders.order_id,
        orders.customer_id,
        customers.customer_unique_id,
        customers.customer_state,
        orders.order_status,
        {{ is_valid_order('orders.order_status') }} as is_valid_order,
        orders.purchased_at,
        cast(orders.purchased_at as date) as purchase_date,
        {{ week_start('orders.purchased_at') }} as purchase_week_start,
        cast(date_trunc('month', orders.purchased_at) as date) as purchase_month,
        orders.approved_at,
        orders.delivered_to_carrier_at,
        orders.delivered_to_customer_at,
        orders.estimated_delivery_at,
        date_diff('day', orders.purchased_at, orders.delivered_to_customer_at) as days_to_deliver,
        case
            when orders.delivered_to_customer_at is null or orders.estimated_delivery_at is null then null
            else cast(orders.delivered_to_customer_at as date) > cast(orders.estimated_delivery_at as date)
        end as is_delivered_late,
        coalesce(items.n_items, 0) as n_items,
        coalesce(items.n_products, 0) as n_products,
        coalesce(items.n_sellers, 0) as n_sellers,
        coalesce(items.item_revenue, 0) as item_revenue,
        coalesce(items.freight_revenue, 0) as freight_revenue,
        coalesce(items.item_revenue, 0) + coalesce(items.freight_revenue, 0) as gross_order_value,
        payments.payment_total,
        payments.n_payment_records,
        payments.n_payment_types,
        payments.max_installments,
        payments.primary_payment_type,
        payments.payment_total
        - (coalesce(items.item_revenue, 0) + coalesce(items.freight_revenue, 0)) as payment_minus_order_value,
        reviews.review_id,
        reviews.review_score
    from orders
    left join customers
        on orders.customer_id = customers.customer_id
    left join items
        on orders.order_id = items.order_id
    left join payments
        on orders.order_id = payments.order_id
    left join reviews
        on orders.order_id = reviews.order_id

)

select
    *,
    case
        when is_valid_order then row_number() over (
            partition by customer_unique_id, is_valid_order
            order by purchased_at, order_id
        )
    end as customer_valid_order_number
from joined
