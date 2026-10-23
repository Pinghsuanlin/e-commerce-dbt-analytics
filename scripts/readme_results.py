"""Compute the numbers for the Results table in README.md from the built marts.

Usage (from the project root, after `make build`):
    .venv/bin/python scripts/readme_results.py > readme_results.txt
"""

import json
import sys
from pathlib import Path

import duckdb

DB_PATH = sys.argv[1] if len(sys.argv) > 1 else "data/olist.duckdb"
con = duckdb.connect(DB_PATH, read_only=True)


def table(name: str) -> str:
    """Return the schema-qualified name of a model, whatever schema dbt put it in."""
    row = con.execute(
        "select table_schema from information_schema.tables where table_name = ? limit 1", [name]
    ).fetchone()
    if row is None:
        raise SystemExit(f"Table {name} not found. Did `make build` finish?")
    return f'"{row[0]}"."{name}"'


def show(title: str, sql: str) -> None:
    print(f"\n## {title}")
    print(con.sql(sql))


show(
    "Orders, valid orders, customers (people)",
    f"""
    select
        (select count(*) from {table('fct_orders')}) as orders,
        (select count(*) from {table('fct_orders')} where is_valid_order) as valid_orders,
        (select count(*) from {table('dim_customers')}) as customers
    """,
)

show(
    "Item revenue and freight (valid orders), purchase date range",
    f"""
    select
        round(sum(item_revenue), 2) as item_revenue,
        round(sum(freight_revenue), 2) as freight_revenue,
        min(purchase_date) as first_purchase,
        max(purchase_date) as last_purchase
    from {table('fct_orders')}
    where is_valid_order
    """,
)

show(
    "Top 5 categories by item revenue (analysis window) and average unit price",
    f"""
    select
        product_category,
        round(sum(item_revenue), 2) as item_revenue,
        sum(units_sold) as units,
        round(sum(item_revenue) / nullif(sum(units_sold), 0), 2) as avg_unit_price
    from {table('mart_product_performance_weekly')}
    group by 1
    order by item_revenue desc
    limit 5
    """,
)

show(
    "Top 5 ISO weeks by seasonality index (platform level)",
    f"""
    select distinct iso_week, round(seasonality_index, 2) as seasonality_index
    from {table('mart_demand_adjusted_weekly')}
    order by seasonality_index desc
    limit 5
    """,
)

show(
    "Regular-selling products scored for gaps, and flagged gaps",
    f"""
    select
        (select count(*) from {table('dim_products')} where is_regular_seller) as regular_sellers,
        (select count(*) from {table('mart_product_availability_gaps')}) as flagged_gaps,
        (select count(distinct product_id) from {table('mart_product_availability_gaps')}) as products_with_a_gap,
        (select count(*) from {table('mart_demand_adjusted_weekly')} where has_availability_gap_flag) as category_weeks_flagged
    """,
)

show(
    "Top 5 categories by flagged gap weeks",
    f"""
    select product_category, sum(gap_weeks) as gap_weeks, count(*) as gaps
    from {table('mart_product_availability_gaps')}
    group by 1
    order by gap_weeks desc
    limit 5
    """,
)

show(
    "Repeat purchase rate at 30 / 90 / 180 days (complete cohorts, pooled), and median cohort",
    f"""
    select
        round(100.0 * sum(case when is_complete_30d then repeaters_30d end)
              / sum(case when is_complete_30d then cohort_size end), 2) as pct_30d,
        round(100.0 * sum(case when is_complete_90d then repeaters_90d end)
              / sum(case when is_complete_90d then cohort_size end), 2) as pct_90d,
        round(100.0 * sum(case when is_complete_180d then repeaters_180d end)
              / sum(case when is_complete_180d then cohort_size end), 2) as pct_180d,
        round(100.0 * median(case when is_complete_90d and cohort_size >= 100 then repeat_rate_90d end), 2)
            as median_cohort_pct_90d
    from {table('mart_customer_retention')}
    """,
)

show(
    "Data quality checks, largest first",
    f"""
    select check_name, severity, n_failing, n_checked, round(100 * pct_failing, 2) as pct_failing
    from {table('dq_summary')}
    order by n_failing desc
    """,
)

results = Path("target/run_results.json")
if results.exists():
    statuses = [r["status"] for r in json.loads(results.read_text())["results"]]
    counts = {s: statuses.count(s) for s in sorted(set(statuses))}
    print("\n## dbt build statuses (last run)")
    print(counts)
