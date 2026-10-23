# Data

This project does not ship any data. The real dataset is downloaded by you; the
CI sample is generated on the fly.

## Real data: Olist Brazilian E-Commerce

- Source: Kaggle, [olistbr/brazilian-ecommerce](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)
- Publisher: Olist
- Licence: [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/)
  (attribution, non-commercial, share-alike). Do not commit the files to a public repo.
- Content: about 100k orders placed in Brazil between 2016 and 2018, as 9 CSV files.

### Download

Option A, Kaggle CLI (needs a Kaggle account and `~/.kaggle/kaggle.json`):

```bash
pip install kaggle
kaggle datasets download -d olistbr/brazilian-ecommerce -p data/raw --unzip
```

Option B, by hand: download the zip from the Kaggle page and unzip it into `data/raw/`.

You should end up with:

```
data/raw/
  olist_customers_dataset.csv
  olist_geolocation_dataset.csv
  olist_order_items_dataset.csv
  olist_order_payments_dataset.csv
  olist_order_reviews_dataset.csv
  olist_orders_dataset.csv
  olist_products_dataset.csv
  olist_sellers_dataset.csv
  product_category_name_translation.csv
```

Then load it into DuckDB:

```bash
make load          # writes data/olist.duckdb, schema raw
```

## Synthetic sample (CI and quick demos)

```bash
make sample        # writes data/sample_synthetic/ (SYNTHETIC, fixed seed)
make load-sample   # loads it into data/olist.duckdb
```

The sample has the same file names and columns as Olist but every value is
randomly generated. It plants the source quirks the models handle (duplicate
reviews, split payments, missing translations, repeat customers, planted
zero-sale runs). Numbers computed on it mean nothing. A
`SYNTHETIC_DATA_README.txt` is written next to the files as a reminder.

Both `data/raw/` and `data/sample_synthetic/` are git-ignored, as are `*.duckdb` files.
