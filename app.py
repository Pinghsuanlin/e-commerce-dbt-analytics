"""Streamlit dashboard over the dbt marts in the local DuckDB file.

Run from the project root after `make build`:
    streamlit run dashboard/app.py

Reads only from the marts and data_quality schemas, read-only. Set
OLIST_DUCKDB_PATH to point at a different file (for example data/ci.duckdb).
"""

from __future__ import annotations

import os
from pathlib import Path

import duckdb
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import streamlit as st

DB_PATH = Path(os.environ.get("OLIST_DUCKDB_PATH", "data/olist.duckdb"))

st.set_page_config(page_title="Olist weekly performance", layout="wide")


@st.cache_data(show_spinner=False)
def query(sql: str) -> pd.DataFrame:
    # Read-only so the dashboard never holds a write lock on the file.
    with duckdb.connect(str(DB_PATH), read_only=True) as con:
        return con.execute(sql).df()


def require_database() -> None:
    if not DB_PATH.exists():
        st.error(
            f"No DuckDB file at `{DB_PATH}`. Run `make load` (or `make sample load-sample`) "
            "and then `make build` first."
        )
        st.stop()
    try:
        query("select 1 from marts.mart_product_performance_weekly limit 1")
    except duckdb.Error as error:
        st.error(f"The marts are not built yet ({error}). Run `make build`.")
        st.stop()


def is_synthetic() -> bool:
    # make_sample_data.py names every city "synthetic city NN".
    flagged = query(
        "select count(*) as n from marts.dim_customers where customer_city like 'synthetic city%'"
    )
    return int(flagged["n"].iloc[0]) > 0


require_database()

st.title("Olist weekly category performance")
st.caption(
    "Built on dbt marts. Valid orders only (canceled and unavailable excluded). "
    "Weeks are complete ISO weeks inside the analysis window."
)
if is_synthetic():
    st.warning("This database looks like the SYNTHETIC sample. Numbers are meaningless.")

categories = query(
    """
    select product_category, sum(units_sold) as units
    from marts.mart_product_performance_weekly
    group by product_category
    order by units desc
    """
)

with st.sidebar:
    st.header("Filters")
    default_categories = categories["product_category"].head(5).tolist()
    selected = st.multiselect("Categories", categories["product_category"].tolist(), default=default_categories)
    metric = st.radio("Metric", ["units", "revenue"], horizontal=True)

if not selected:
    st.sidebar.info("No category picked; showing the five largest.")
    selected = default_categories

tab_weekly, tab_gaps, tab_retention, tab_quality = st.tabs(
    ["Weekly performance", "Availability gaps (proxy)", "Retention cohorts", "Data quality"]
)

category_list = ", ".join("'" + c.replace("'", "''") + "'" for c in selected)
weekly = query(
    f"""
    select *
    from marts.mart_demand_adjusted_weekly
    where product_category in ({category_list})
    order by week_start
    """
)

# ---------------------------------------------------------------- weekly tab
with tab_weekly:
    raw_col = "units_sold" if metric == "units" else "item_revenue"
    adj_col = "seasonally_adjusted_units" if metric == "units" else "seasonally_adjusted_revenue"

    totals = weekly.groupby("week_start", as_index=False)[[raw_col, adj_col]].sum()
    fig = go.Figure()
    fig.add_trace(go.Scatter(x=totals["week_start"], y=totals[raw_col], name="Actual", mode="lines"))
    fig.add_trace(
        go.Scatter(x=totals["week_start"], y=totals[adj_col], name="Seasonally adjusted", mode="lines",
                   line={"dash": "dot"})
    )
    fig.update_layout(
        title=f"Selected categories, weekly {metric}: actual vs seasonally adjusted",
        xaxis_title="Week starting",
        yaxis_title=metric.capitalize() + (" (BRL)" if metric == "revenue" else ""),
        legend={"orientation": "h"},
    )
    st.plotly_chart(fig, use_container_width=True)

    by_category = px.line(
        weekly, x="week_start", y=adj_col, color="product_category",
        title=f"Seasonally adjusted {metric} by category",
        labels={"week_start": "Week starting", adj_col: f"Adjusted {metric}"},
    )
    st.plotly_chart(by_category, use_container_width=True)

    index = query(
        "select distinct iso_week, seasonality_index from marts.mart_demand_adjusted_weekly order by iso_week"
    )
    st.plotly_chart(
        px.bar(index, x="iso_week", y="seasonality_index",
               title="Week-of-year seasonality index (platform level, 1.0 = trend)",
               labels={"iso_week": "ISO week", "seasonality_index": "Index"}),
        use_container_width=True,
    )
    st.caption(
        "The index divides out the usual week-of-year pattern after removing growth. "
        "With about 20 months of data most weeks are observed once or twice, so read it as indicative."
    )

    summary = (
        weekly.groupby("product_category", as_index=False)
        .agg(units=("units_sold", "sum"), revenue=("item_revenue", "sum"),
             avg_review=("avg_review_score", "mean"))
        .assign(avg_price=lambda d: d["revenue"] / d["units"].where(d["units"] > 0))
        .sort_values("revenue", ascending=False)
    )
    st.dataframe(summary, use_container_width=True, hide_index=True)

# ------------------------------------------------------------------ gaps tab
with tab_gaps:
    st.markdown(
        "**This is a proxy.** Olist has no inventory data. A flag means a product that sells regularly "
        "went quiet for longer than chance would explain. It could be a stock-out, a paused listing, "
        "a price change or demand moving to a substitute."
    )
    flagged = weekly[weekly["has_availability_gap_flag"]]
    st.plotly_chart(
        px.bar(weekly, x="week_start", y="n_products_in_gap", color="product_category",
               title="Regular-selling products in a flagged gap, by week",
               labels={"week_start": "Week starting", "n_products_in_gap": "Products in gap"}),
        use_container_width=True,
    )
    col1, col2 = st.columns(2)
    col1.metric("Category-weeks with a flag", f"{len(flagged):,}")
    col2.metric("Expected units in gap weeks (proxy)", f"{flagged['expected_units_in_gap_proxy'].sum():,.0f}")

    gaps = query(
        f"""
        select product_id, product_category, gap_start_week, gap_end_week, gap_weeks,
               round(weekly_sell_probability, 2) as weekly_sell_probability,
               round(prob_zero_run_by_chance, 4) as prob_zero_run_by_chance,
               round(expected_units_in_gap_proxy, 1) as expected_units_in_gap_proxy
        from marts.mart_product_availability_gaps
        where product_category in ({category_list})
        order by prob_zero_run_by_chance, gap_weeks desc
        """
    )
    st.dataframe(gaps, use_container_width=True, hide_index=True)

# ------------------------------------------------------------- retention tab
with tab_retention:
    retention = query("select * from marts.mart_customer_retention order by cohort_month")
    rate_cols = [c for c in retention.columns if c.startswith("repeat_rate_") and c.endswith("d")]
    heat = retention.set_index(retention["cohort_month"].astype(str))[rate_cols] * 100
    heat.columns = [c.replace("repeat_rate_", "") for c in rate_cols]
    fig = px.imshow(
        heat, text_auto=".1f", aspect="auto", color_continuous_scale="Blues",
        labels={"x": "Window", "y": "First-order cohort", "color": "Repeat rate (%)"},
        title="Repeat purchase rate by first-order cohort (%)",
    )
    st.plotly_chart(fig, use_container_width=True)
    st.caption(
        "Customers are people (customer_unique_id). Blank cells are cohorts that have not had the full "
        "window yet (right-censored), so they are left out rather than shown as artificially low."
    )
    st.dataframe(retention, use_container_width=True, hide_index=True)

# ---------------------------------------------------------------- quality tab
with tab_quality:
    dq = query("select * from data_quality.dq_summary order by severity, n_failing desc")
    st.dataframe(
        dq.assign(pct_failing=lambda d: (d["pct_failing"] * 100).round(2)),
        use_container_width=True, hide_index=True,
    )
    st.caption("error = should never happen; warn = known source quirk; info = expected, sized for context.")
