"""Generate a small SYNTHETIC dataset with the same files and columns as Olist.

THIS IS NOT OLIST DATA. Every id, price, date and review is randomly generated
from a fixed seed. It exists so CI (and anyone without a Kaggle account) can run
`dbt build` end to end. Results computed on it mean nothing.

The generator deliberately plants the quirks the dbt project handles, so the
tests and data quality checks have something to catch:
  - repeat customers (several customer_id values per customer_unique_id),
    including same-day split baskets
  - canceled and unavailable orders, some with no item lines
  - split payments (voucher + card) and two orders whose payments do not match
  - duplicate review rows and orders with two distinct reviews
  - a product with no category and a category with no English translation
  - zip prefixes without leading zeros, duplicate geolocation rows, missing zips
  - a UTF-8 byte-order mark on the translation file header
  - three products that sell most weeks, two of them with a planted run of
    zero-sale weeks (to exercise the availability-gap proxy)

Usage:
    python scripts/make_sample_data.py --out data/sample_synthetic --seed 42
"""

from __future__ import annotations

import argparse
from datetime import date, datetime, timedelta
from pathlib import Path

import numpy as np
import pandas as pd

TIMESTAMP_FORMAT = "%Y-%m-%d %H:%M:%S"

# Portuguese name -> English name (None = deliberately untranslated)
CATEGORIES: dict[str, str | None] = {
    "beleza_saude": "health_beauty",
    "cama_mesa_banho": "bed_bath_table",
    "esporte_lazer": "sports_leisure",
    "informatica_acessorios": "computers_accessories",
    "moveis_decoracao": "furniture_decor",
    "utilidades_domesticas": "housewares",
    "relogios_presentes": "watches_gifts",
    "brinquedos": "toys",
    "telefonia": "telephony",
    "categoria_sintetica_sem_traducao": None,
}

STATES = ["SP", "RJ", "MG", "RS", "PR", "SC", "BA", "DF", "GO", "PE"]

REGULAR_PRODUCTS = 3
BACKGROUND_PRODUCTS = 57
N_SELLERS = 15
BACKGROUND_ORDERS = 380
SPLIT_BASKETS = 6


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", default="data/sample_synthetic", help="Output folder for the CSV files.")
    parser.add_argument("--seed", type=int, default=42, help="Random seed (output is deterministic).")
    return parser.parse_args()


class Generator:
    def __init__(self, seed: int) -> None:
        self.rng = np.random.default_rng(seed)
        self.orders: list[dict] = []
        self.items: list[dict] = []
        self.customers: list[dict] = []
        self.persons: list[dict] = []

    # ------------------------------------------------------------------ ids
    def new_id(self) -> str:
        """32-character hex id, like Olist's, drawn from the seeded generator."""
        return "".join(self.rng.choice(list("0123456789abcdef"), size=32))

    def ts(self, value: datetime | None) -> str | None:
        return value.strftime(TIMESTAMP_FORMAT) if value else None

    # ------------------------------------------------------------- catalogue
    def build_catalogue(self) -> None:
        categories = list(CATEGORIES)
        self.products = []
        for index in range(REGULAR_PRODUCTS + BACKGROUND_PRODUCTS):
            if index == REGULAR_PRODUCTS + 5:
                category = None  # product with no category
            elif index in (REGULAR_PRODUCTS + 6, REGULAR_PRODUCTS + 7):
                category = "categoria_sintetica_sem_traducao"
            elif index < REGULAR_PRODUCTS:
                category = categories[index]
            else:
                category = categories[int(self.rng.integers(0, len(categories) - 1))]
            self.products.append(
                {
                    "product_id": self.new_id(),
                    "product_category_name": category,
                    "product_name_lenght": int(self.rng.integers(10, 70)),
                    "product_description_lenght": int(self.rng.integers(50, 2000)),
                    "product_photos_qty": int(self.rng.integers(1, 6)),
                    "product_weight_g": int(self.rng.integers(100, 15000)),
                    "product_length_cm": int(self.rng.integers(10, 80)),
                    "product_height_cm": int(self.rng.integers(2, 60)),
                    "product_width_cm": int(self.rng.integers(8, 60)),
                    "_base_price": float(self.rng.uniform(15, 400)),
                }
            )
        self.sellers = []
        for _ in range(N_SELLERS):
            state = STATES[int(self.rng.integers(0, len(STATES)))]
            self.sellers.append(
                {
                    "seller_id": self.new_id(),
                    "seller_zip_code_prefix": str(int(self.rng.integers(1000, 99999))),
                    "seller_city": f"synthetic city {int(self.rng.integers(1, 40)):02d}",
                    "seller_state": state,
                }
            )
        for product in self.products:
            product["_seller"] = self.sellers[int(self.rng.integers(0, N_SELLERS))]["seller_id"]

    # -------------------------------------------------------------- persons
    def pick_person(self) -> dict:
        """Mostly new people; about one order in six goes to an existing person."""
        if self.persons and self.rng.random() < 0.17:
            return self.persons[int(self.rng.integers(0, len(self.persons)))]
        state = STATES[int(self.rng.integers(0, len(STATES)))]
        person = {
            "customer_unique_id": self.new_id(),
            # Some prefixes below 10000, written without the leading zero.
            "zip": str(int(self.rng.integers(1000, 99999))),
            "city": f"synthetic city {int(self.rng.integers(1, 40)):02d}",
            "state": state,
        }
        self.persons.append(person)
        return person

    # --------------------------------------------------------------- orders
    def add_order(self, purchased_at: datetime, product_indexes: list[int], person: dict | None = None,
                  status: str | None = None) -> dict:
        person = person or self.pick_person()
        customer_id = self.new_id()
        self.customers.append(
            {
                "customer_id": customer_id,
                "customer_unique_id": person["customer_unique_id"],
                "customer_zip_code_prefix": person["zip"],
                "customer_city": person["city"],
                "customer_state": person["state"],
            }
        )
        if status is None:
            status = str(self.rng.choice(
                ["delivered", "shipped", "canceled", "invoiced", "processing"],
                p=[0.93, 0.03, 0.02, 0.01, 0.01],
            ))
        approved = purchased_at + timedelta(hours=float(self.rng.uniform(0.2, 48)))
        carrier = approved + timedelta(days=float(self.rng.uniform(1, 5)))
        delivered = carrier + timedelta(days=float(self.rng.uniform(2, 20)))
        estimated = datetime.combine(
            (purchased_at + timedelta(days=int(self.rng.integers(15, 35)))).date(), datetime.min.time()
        )
        order = {
            "order_id": self.new_id(),
            "customer_id": customer_id,
            "order_status": status,
            "order_purchase_timestamp": self.ts(purchased_at),
            "order_approved_at": self.ts(approved) if status != "created" else None,
            "order_delivered_carrier_date": self.ts(carrier) if status in ("delivered", "shipped") else None,
            "order_delivered_customer_date": self.ts(delivered) if status == "delivered" else None,
            "order_estimated_delivery_date": self.ts(estimated),
            "_purchased_at": purchased_at,
            "_delivered": delivered if status == "delivered" else None,
        }
        self.orders.append(order)
        if status != "unavailable":
            for item_number, product_index in enumerate(product_indexes, start=1):
                product = self.products[product_index]
                self.items.append(
                    {
                        "order_id": order["order_id"],
                        "order_item_id": item_number,
                        "product_id": product["product_id"],
                        "seller_id": product["_seller"],
                        "shipping_limit_date": self.ts(purchased_at + timedelta(days=6)),
                        "price": round(product["_base_price"] * float(self.rng.uniform(0.9, 1.1)), 2),
                        "freight_value": round(float(self.rng.uniform(5, 40)), 2),
                    }
                )
        return order

    def random_time(self, day: date) -> datetime:
        return datetime.combine(day, datetime.min.time()) + timedelta(seconds=int(self.rng.integers(0, 86_399)))

    def build_orders(self) -> None:
        weeks = pd.date_range("2017-01-02", "2018-08-20", freq="7D")
        planted_gaps = {0: range(30, 36), 1: range(60, 64)}  # product index -> week indexes with no sales
        for week_index, week in enumerate(weeks):
            for product_index in range(REGULAR_PRODUCTS):
                if week_index in planted_gaps.get(product_index, ()):
                    continue
                if self.rng.random() < 0.8:
                    day = (week + pd.Timedelta(days=int(self.rng.integers(0, 7)))).date()
                    self.add_order(self.random_time(day), [product_index], status="delivered")

        start, end = date(2016, 10, 3), date(2018, 9, 20)
        span_days = (end - start).days
        for _ in range(BACKGROUND_ORDERS):
            day = start + timedelta(days=int(self.rng.integers(0, span_days)))
            # Mild seasonal bump in late November and December.
            if day.month in (11, 12) and self.rng.random() < 0.3:
                day = date(day.year, 11, 24) + timedelta(days=int(self.rng.integers(0, 30)))
            n_items = int(self.rng.choice([1, 1, 1, 2, 3]))
            product_indexes = list(
                self.rng.integers(REGULAR_PRODUCTS, REGULAR_PRODUCTS + BACKGROUND_PRODUCTS, size=n_items)
            )
            self.add_order(self.random_time(day), [int(i) for i in product_indexes])

        # Unavailable orders with no item lines.
        for _ in range(4):
            day = start + timedelta(days=int(self.rng.integers(0, span_days)))
            self.add_order(self.random_time(day), [], status="unavailable")

        # Same-day split baskets: the same person orders twice on one day.
        for order in list(self.orders[:: max(1, len(self.orders) // SPLIT_BASKETS)])[:SPLIT_BASKETS]:
            person_id = next(c for c in self.customers if c["customer_id"] == order["customer_id"])
            person = next(p for p in self.persons if p["customer_unique_id"] == person_id["customer_unique_id"])
            later = order["_purchased_at"] + timedelta(minutes=int(self.rng.integers(5, 120)))
            if later.date() == order["_purchased_at"].date():
                self.add_order(later, [int(self.rng.integers(REGULAR_PRODUCTS, REGULAR_PRODUCTS + 10))],
                               person=person, status="delivered")

    # ------------------------------------------------------------- payments
    def build_payments(self) -> list[dict]:
        totals: dict[str, float] = {}
        for item in self.items:
            totals[item["order_id"]] = totals.get(item["order_id"], 0.0) + item["price"] + item["freight_value"]
        payments = []
        mismatches_left = 2
        for order in self.orders:
            total = round(totals.get(order["order_id"], float(self.rng.uniform(20, 200))), 2)
            if mismatches_left and order["order_status"] == "delivered" and order["order_id"] in totals:
                total = round(total + 5.0, 2)  # planted payment mismatch
                mismatches_left -= 1
            if self.rng.random() < 0.1 and total > 30:
                voucher = round(float(self.rng.uniform(5, total / 2)), 2)
                parts = [("voucher", voucher, 1), ("credit_card", round(total - voucher, 2), int(self.rng.integers(1, 6)))]
            else:
                method = str(self.rng.choice(["credit_card", "boleto", "debit_card"], p=[0.75, 0.2, 0.05]))
                installments = int(self.rng.integers(1, 11)) if method == "credit_card" else 1
                parts = [(method, total, installments)]
            for sequential, (method, value, installments) in enumerate(parts, start=1):
                payments.append(
                    {
                        "order_id": order["order_id"],
                        "payment_sequential": sequential,
                        "payment_type": method,
                        "payment_installments": installments,
                        "payment_value": f"{value:.2f}",
                    }
                )
        return payments

    # -------------------------------------------------------------- reviews
    def build_reviews(self) -> list[dict]:
        reviews = []
        comments = [None, None, "Chegou rapido, recomendo", "Produto bom, mas a entrega atrasou",
                    "Nao recebi o produto\nAguardando resposta"]
        for order in self.orders:
            if order["order_status"] == "unavailable" or self.rng.random() > 0.9:
                continue
            base = order["_delivered"] or (order["_purchased_at"] + timedelta(days=20))
            created = datetime.combine((base + timedelta(days=1)).date(), datetime.min.time())
            answered = created + timedelta(hours=float(self.rng.uniform(1, 72)))
            reviews.append(
                {
                    "review_id": self.new_id(),
                    "order_id": order["order_id"],
                    "review_score": int(self.rng.choice([1, 2, 3, 4, 5], p=[0.1, 0.04, 0.08, 0.2, 0.58])),
                    "review_comment_title": None,
                    "review_comment_message": comments[int(self.rng.integers(0, len(comments)))],
                    "review_creation_date": self.ts(created),
                    "review_answer_timestamp": self.ts(answered),
                }
            )
        # Exact duplicate rows.
        reviews.extend(dict(review) for review in reviews[:3])
        # Orders with a second, later review.
        for review in reviews[10:12]:
            later = dict(review)
            later["review_id"] = self.new_id()
            later["review_score"] = 5
            answered = datetime.strptime(review["review_answer_timestamp"], TIMESTAMP_FORMAT) + timedelta(days=3)
            later["review_answer_timestamp"] = self.ts(answered)
            reviews.append(later)
        return reviews

    # ----------------------------------------------------------- geolocation
    def build_geolocation(self) -> list[dict]:
        zips = {(c["customer_zip_code_prefix"], c["customer_city"], c["customer_state"]) for c in self.customers}
        zips |= {(s["seller_zip_code_prefix"], s["seller_city"], s["seller_state"]) for s in self.sellers}
        rows = []
        for zip_prefix, city, state in sorted(zips):
            if self.rng.random() < 0.05:
                continue  # zip missing from the geolocation table
            lat, lng = float(self.rng.uniform(-30, -5)), float(self.rng.uniform(-55, -35))
            for _ in range(int(self.rng.integers(1, 4))):  # duplicate rows per prefix
                rows.append(
                    {
                        "geolocation_zip_code_prefix": zip_prefix,
                        "geolocation_lat": round(lat + float(self.rng.normal(0, 0.01)), 6),
                        "geolocation_lng": round(lng + float(self.rng.normal(0, 0.01)), 6),
                        "geolocation_city": city,
                        "geolocation_state": state,
                    }
                )
        return rows


def public(rows: list[dict]) -> pd.DataFrame:
    """Drop helper fields (prefixed with _) before writing."""
    frame = pd.DataFrame(rows)
    return frame[[c for c in frame.columns if not c.startswith("_")]]


def main() -> None:
    args = parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    gen = Generator(args.seed)
    gen.build_catalogue()
    gen.build_orders()

    files = {
        "olist_orders_dataset.csv": public(gen.orders),
        "olist_order_items_dataset.csv": public(gen.items),
        "olist_products_dataset.csv": public(gen.products),
        "olist_customers_dataset.csv": public(gen.customers),
        "olist_sellers_dataset.csv": public(gen.sellers),
        "olist_order_payments_dataset.csv": public(gen.build_payments()),
        "olist_order_reviews_dataset.csv": public(gen.build_reviews()),
        "olist_geolocation_dataset.csv": public(gen.build_geolocation()),
    }
    for name, frame in files.items():
        frame.to_csv(out / name, index=False)

    translation = pd.DataFrame(
        [{"product_category_name": pt, "product_category_name_english": en}
         for pt, en in CATEGORIES.items() if en is not None]
    )
    # Write a UTF-8 byte-order mark (some exports of this file carry one) so the loader's header cleanup is exercised.
    translation.to_csv(out / "product_category_name_translation.csv", index=False, encoding="utf-8-sig")

    (out / "SYNTHETIC_DATA_README.txt").write_text(
        "SYNTHETIC DATA. Generated by scripts/make_sample_data.py "
        f"(seed {args.seed}). Not Olist data; numbers computed on it are meaningless.\n"
        "It only matches the Olist file names and columns so the dbt project can run in CI.\n"
    )

    print(f"Wrote synthetic sample to {out}/ (seed {args.seed})")
    for name, frame in files.items():
        print(f"  {name:<40} {len(frame):>6,} rows")
    print(f"  {'product_category_name_translation.csv':<40} {len(translation):>6,} rows")


if __name__ == "__main__":
    main()
