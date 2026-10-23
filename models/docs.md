{% docs __overview__ %}
# Olist dbt analytics

A tested, documented metrics layer on the public Olist Brazilian E-Commerce dataset,
built with dbt and DuckDB so it runs on a laptop.

Layers:

- **staging**: one model per raw table. Renamed, typed, deduplicated. Nothing else.
- **intermediate**: reusable building blocks (item-level enrichment, weekly sales,
  the week spine, seasonality index, availability-gap proxy).
- **marts**: what analysts and the dashboard query. `fct_orders`, `dim_products`,
  `dim_customers`, weekly product performance, the demand-adjusted view, gap
  drill-down, and customer retention cohorts.
- **data_quality**: `dq_summary`, one row per known data quirk with its size.

Business rules (excluded statuses, analysis window, tolerances, gap thresholds,
retention windows) are dbt vars in `dbt_project.yml`.

Data: Olist, CC BY-NC-SA 4.0. Not redistributed with this project.
{% enddocs %}

{% docs valid_order %}
True when the order status is not in the `excluded_order_statuses` var
(default: canceled, unavailable). Only valid orders count towards revenue,
units, product metrics and retention.
{% enddocs %}

{% docs week_start %}
Monday of the ISO week (Monday to Sunday) the order was purchased in, from the
`week_start` macro. Every weekly model uses this same macro.
{% enddocs %}

{% docs item_revenue %}
Sum of item prices (BRL), excluding freight. Each item line is one unit.
{% enddocs %}

{% docs gross_order_value %}
Item revenue plus freight (BRL). The single definition of order value in this
project. Payments are reconciled against it but do not define it.
{% enddocs %}

{% docs seasonality_index %}
Platform-level week-of-year index, averaging 1.0. Built as the ratio of weekly
units to a fitted log-linear growth trend, averaged by ISO week, smoothed with a
centred 3-week moving average and rescaled. Above 1 means that week of the year
normally sells more than trend. With about 20 months of data most ISO weeks are
observed once or twice, so treat it as indicative.
{% enddocs %}

{% docs availability_gap_proxy %}
PROXY for a stock-out or listing pause. Olist publishes no inventory data, so
this is inferred: for a product that sells regularly, a run of zero-sale weeks is
flagged when it lasts at least `gap_min_run_weeks` and the chance of that run
happening by luck, (1 - p) ^ run_length where p is the share of weeks the product
sells, is below `gap_probability_threshold`. A flag can also mean a price change,
a paused seller, or demand moving to a substitute.
{% enddocs %}

{% docs regular_seller %}
A product with at least `regular_min_active_weeks` weeks containing a sale inside
the analysis window, that sold in at least `regular_min_sell_probability` of the
weeks between its first and last sale. Only regular sellers are scored for
availability gaps; sporadic products have no stable baseline to compare against,
and for them a long silence is normal.
{% enddocs %}

{% docs cohort_month %}
Month of the customer's first valid order, keyed on customer_unique_id (the
person). Olist's customer_id changes with every order, so using it would make
every customer look new.
{% enddocs %}

{% docs repeat_purchase %}
A valid order placed at least `repeat_min_gap_days` days after the customer's
first valid order. The gap stops same-day split baskets counting as loyalty.
{% enddocs %}
