-- A customer who repeats within 30 days has also repeated within 90 and 180,
-- so for every cohort: 30-day rate <= 90-day rate <= 180-day rate.
select cohort_month, repeat_rate_30d, repeat_rate_90d, repeat_rate_180d
from {{ ref('mart_customer_retention') }}
where (repeat_rate_30d is not null and repeat_rate_90d is not null and repeat_rate_30d > repeat_rate_90d)
   or (repeat_rate_90d is not null and repeat_rate_180d is not null and repeat_rate_90d > repeat_rate_180d)
