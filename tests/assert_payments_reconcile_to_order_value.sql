-- Payments are reconciled against order value but do not define it: vouchers,
-- instalment interest and source errors make them noisy. This is a warning,
-- not an error, and dq_summary sizes the mismatch so it can be monitored.
{{ config(severity = 'warn') }}
select order_id, gross_order_value, payment_total, payment_minus_order_value
from {{ ref('fct_orders') }}
where is_valid_order
  and n_items > 0
  and payment_total is not null
  and abs(payment_minus_order_value) > {{ var('payment_tolerance') }}
