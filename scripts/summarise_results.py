"""Print a quick summary of every mart and data-quality table after `make build`.

Usage (from the project root):
    .venv/bin/python scripts/summarise_results.py > results_summary.txt

The output is used to fill in the Results table in README.md.
"""

import sys

import duckdb

DB_PATH = sys.argv[1] if len(sys.argv) > 1 else "data/olist.duckdb"

con = duckdb.connect(DB_PATH, read_only=True)
tables = con.sql(
    """
    select table_schema, table_name
    from information_schema.tables
    where table_schema like '%marts%' or table_schema like '%data_quality%'
    order by 1, 2
    """
).fetchall()

if not tables:
    print(f"No mart tables found in {DB_PATH}. Did `make build` finish?")
    sys.exit(1)

for schema, table in tables:
    full = f'"{schema}"."{table}"'
    n_rows = con.sql(f"select count(*) from {full}").fetchone()[0]
    print(f"\n=== {schema}.{table} ({n_rows:,} rows)")
    print(con.sql(f"select * from {full} limit 15"))
