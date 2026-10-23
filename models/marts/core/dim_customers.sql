-- Grain: one row per customer_unique_id (a person, not Olist's per-order customer_id).
-- Holds the single definition of "first order" and "repeat purchase" that the
-- retention mart aggregates:
--   first order      = earliest valid order
--   repeat purchase  = a later valid order placed at least repeat_min_gap_days
--                      after the first (so same-day split baskets do not count)
with orders as (

    select * from {{ ref('fct_orders') }}

),

customers as (

    select * from {{ ref('stg_olist__customers') }}

),

geolocation as (

    select * from {{ ref('stg_olist__geolocation') }}

),

latest_address as (

    select
        orders.customer_unique_id,
        customers.customer_zip_code_prefix,
        customers.customer_city,
        customers.customer_state
    from orders
    inner join customers
        on orders.customer_id = customers.customer_id
    qualify row_number() over (
        partition by orders.customer_unique_id
        order by orders.purchased_at desc, orders.order_id desc
    ) = 1

),

order_summary as (

    select
        customer_unique_id,
        count(*) as n_orders_all_statuses,
        count(*) filter (where is_valid_order) as n_valid_orders,
        min(purchase_date) filter (where is_valid_order) as first_order_date,
        max(purchase_date) filter (where is_valid_order) as last_order_date,
        sum(gross_order_value) filter (where is_valid_order) as lifetime_gross_order_value,
        avg(review_score) filter (where is_valid_order) as avg_review_score
    from orders
    group by customer_unique_id

),

second_orders as (

    select
        summary.customer_unique_id,
        min(orders.purchase_date) as second_order_date
    from order_summary as summary
    inner join orders
        on summary.customer_unique_id = orders.customer_unique_id
    where orders.is_valid_order
        and date_diff('day', summary.first_order_date, orders.purchase_date) >= {{ var('repeat_min_gap_days') }}
    group by summary.customer_unique_id

)

select
    summary.customer_unique_id,
    latest_address.customer_zip_code_prefix,
    latest_address.customer_city,
    latest_address.customer_state,
    geolocation.latitude as customer_latitude,
    geolocation.longitude as customer_longitude,
    summary.n_orders_all_statuses,
    summary.n_valid_orders,
    summary.first_order_date,
    summary.last_order_date,
    cast(date_trunc('month', summary.first_order_date) as date) as cohort_month,
    second_orders.second_order_date,
    date_diff('day', summary.first_order_date, second_orders.second_order_date) as days_to_repeat_purchase,
    second_orders.second_order_date is not null as has_repeat_purchase,
    coalesce(summary.lifetime_gross_order_value, 0) as lifetime_gross_order_value,
    summary.avg_review_score
from order_summary as summary
left join latest_address
    on summary.customer_unique_id = latest_address.customer_unique_id
left join geolocation
    on latest_address.customer_zip_code_prefix = geolocation.zip_code_prefix
left join second_orders
    on summary.customer_unique_id = second_orders.customer_unique_id
