-- Grain: one row per data quality check.
-- dbt tests answer "did anything break?" with pass/fail. This table answers
-- "how big is each known quirk?" so the numbers can be monitored and shown in
-- the dashboard. Severity: error = should never happen, warn = known source
-- quirk to watch, info = expected property of the data, sized for context.
with raw_review_pairs as (

    select review_id, order_id, count(*) as n_copies
    from {{ source('olist', 'order_reviews') }}
    group by review_id, order_id

),

checks as (

    {{ dq_check(
        'orders_without_items', 'fct_orders', ref('fct_orders'),
        'n_items = 0', 'info',
        'Orders with no item lines (mostly canceled or unavailable). They carry zero revenue.'
    ) }}

    union all

    {{ dq_check(
        'valid_orders_without_items', 'fct_orders', ref('fct_orders'),
        'n_items = 0', 'warn',
        'Valid orders with no item lines. Revenue for these orders is understated.',
        'is_valid_order'
    ) }}

    union all

    {{ dq_check(
        'payment_mismatch', 'fct_orders', ref('fct_orders'),
        'abs(payment_minus_order_value) > ' ~ var('payment_tolerance'), 'warn',
        'Valid orders where payments differ from item price plus freight by more than the tolerance (vouchers, instalment interest or source errors).',
        'is_valid_order and n_items > 0 and payment_total is not null'
    ) }}

    union all

    {{ dq_check(
        'orders_without_payment', 'fct_orders', ref('fct_orders'),
        'payment_total is null', 'warn',
        'Orders with no payment record.'
    ) }}

    union all

    {{ dq_check(
        'orders_without_review', 'fct_orders', ref('fct_orders'),
        'review_score is null', 'info',
        'Orders with no customer review. Review-score metrics exclude them.'
    ) }}

    union all

    {{ dq_check(
        'orders_with_multiple_reviews', 'int_order_reviews', ref('int_order_reviews'),
        'n_reviews_for_order > 1', 'info',
        'Orders with more than one distinct review. The latest answered review is used.'
    ) }}

    union all

    {{ dq_check(
        'duplicate_review_rows', 'source olist.order_reviews', 'raw_review_pairs',
        'n_copies > 1', 'info',
        'Review and order pairs that appear more than once in the raw file. Deduplicated in staging.'
    ) }}

    union all

    {{ dq_check(
        'delivered_before_purchase', 'fct_orders', ref('fct_orders'),
        'delivered_to_customer_at < purchased_at', 'error',
        'Orders delivered before they were placed. Should never happen.'
    ) }}

    union all

    {{ dq_check(
        'delivered_status_missing_date', 'fct_orders', ref('fct_orders'),
        'delivered_to_customer_at is null', 'warn',
        'Orders with status delivered but no delivery timestamp. Delivery-time metrics exclude them.',
        "order_status = 'delivered'"
    ) }}

    union all

    {{ dq_check(
        'products_missing_category', 'dim_products', ref('dim_products'),
        'not has_category', 'info',
        'Products with no category. Reported under the category label unknown.'
    ) }}

    union all

    {{ dq_check(
        'categories_missing_translation', 'dim_products', ref('dim_products'),
        'not has_english_category', 'info',
        'Products whose category has no English translation. The Portuguese name is used.',
        'has_category'
    ) }}

    union all

    {{ dq_check(
        'customers_without_geolocation', 'dim_customers', ref('dim_customers'),
        'customer_latitude is null', 'info',
        'Customers whose zip prefix is missing from the geolocation table.'
    ) }}

    union all

    {{ dq_check(
        'zero_price_items', 'stg_olist__order_items', ref('stg_olist__order_items'),
        'item_price = 0', 'warn',
        'Item lines with a price of zero.'
    ) }}

)

select
    check_name,
    model_name,
    severity,
    description,
    n_failing,
    n_checked,
    {{ safe_divide('n_failing', 'n_checked') }} as pct_failing,
    current_timestamp as checked_at
from checks
