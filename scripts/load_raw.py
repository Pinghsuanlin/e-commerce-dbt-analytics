"""Load the Olist CSVs into the `raw` schema of a local DuckDB file.

Every column is loaded as VARCHAR. Typing happens once, in the dbt staging
models, so a malformed value fails the dbt build with a clear error instead of
being silently guessed here.

Usage:
    python scripts/load_raw.py --data-dir data/raw --db data/olist.duckdb
    python scripts/load_raw.py --data-dir data/sample_synthetic --db data/ci.duckdb
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

import duckdb

# raw table name -> Olist file name
TABLES: dict[str, str] = {
    "orders": "olist_orders_dataset.csv",
    "order_items": "olist_order_items_dataset.csv",
    "products": "olist_products_dataset.csv",
    "product_category_name_translation": "product_category_name_translation.csv",
    "customers": "olist_customers_dataset.csv",
    "sellers": "olist_sellers_dataset.csv",
    "order_payments": "olist_order_payments_dataset.csv",
    "order_reviews": "olist_order_reviews_dataset.csv",
    "geolocation": "olist_geolocation_dataset.csv",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--data-dir", default="data/raw", help="Folder containing the Olist CSV files.")
    parser.add_argument(
        "--db",
        default=os.environ.get("OLIST_DUCKDB_PATH", "data/olist.duckdb"),
        help="DuckDB file to write (default: $OLIST_DUCKDB_PATH or data/olist.duckdb).",
    )
    return parser.parse_args()


def sql_literal(value: str) -> str:
    """Quote a string as a SQL literal."""
    return "'" + value.replace("'", "''") + "'"


def load_with_duckdb(con: duckdb.DuckDBPyConnection, table: str, path: Path) -> None:
    con.execute(
        f"""
        create or replace table raw.{table} as
        select *
        from read_csv(
            {sql_literal(str(path))},
            header = true,
            all_varchar = true,
            quote = '"',
            escape = '"'
        )
        """
    )


def load_with_pandas(con: duckdb.DuckDBPyConnection, table: str, path: Path) -> None:
    """Fallback for files the DuckDB sniffer rejects (for example multi-line review text)."""
    import pandas as pd

    frame = pd.read_csv(path, dtype=str, keep_default_na=False, encoding="utf-8-sig")
    frame = frame.replace({"": None})
    con.register("frame_to_load", frame)
    con.execute(f"create or replace table raw.{table} as select * from frame_to_load")
    con.unregister("frame_to_load")


def clean_column_names(con: duckdb.DuckDBPyConnection, table: str) -> None:
    """Strip byte-order marks and stray whitespace from header names."""
    columns = con.execute(
        "select column_name from information_schema.columns where table_schema = 'raw' and table_name = ?",
        [table],
    ).fetchall()
    for (name,) in columns:
        clean = name.replace("﻿", "").strip()
        if clean != name:
            con.execute(f'alter table raw.{table} rename column "{name}" to "{clean}"')


def main() -> int:
    args = parse_args()
    data_dir = Path(args.data_dir)
    db_path = Path(args.db)

    missing = [name for name in TABLES.values() if not (data_dir / name).exists()]
    if missing:
        print(f"Missing files in {data_dir}:", file=sys.stderr)
        for name in missing:
            print(f"  - {name}", file=sys.stderr)
        print("See data/README.md for download steps, or run `make sample` for synthetic data.", file=sys.stderr)
        return 1

    db_path.parent.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(str(db_path))
    con.execute("create schema if not exists raw")

    for table, file_name in TABLES.items():
        path = data_dir / file_name
        try:
            load_with_duckdb(con, table, path)
            method = "duckdb"
        except duckdb.Error as error:
            print(f"  duckdb reader failed for {file_name} ({error.__class__.__name__}); retrying with pandas")
            load_with_pandas(con, table, path)
            method = "pandas"
        clean_column_names(con, table)
        (n_rows,) = con.execute(f"select count(*) from raw.{table}").fetchone()
        print(f"raw.{table:<36} {n_rows:>10,} rows  ({method})")

    con.close()
    print(f"Loaded {len(TABLES)} tables into {db_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
