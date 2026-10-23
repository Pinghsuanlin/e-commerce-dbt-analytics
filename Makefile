# Run everything from the project root.
# BIN points at the virtualenv; CI calls `make <target> BIN=` to use the system Python.
VENV       ?= .venv
BIN        ?= $(VENV)/bin/
PYTHON     ?= python3
DB         ?= data/olist.duckdb
RAW_DIR    ?= data/raw
SAMPLE_DIR ?= data/sample_synthetic

export DBT_PROFILES_DIR := .
export OLIST_DUCKDB_PATH := $(DB)

.PHONY: help setup profile sample load load-sample deps build test docs docs-serve dashboard lint ci clean

help:
	@echo "setup        create .venv, install requirements, copy profile, install dbt packages"
	@echo "sample       generate the SYNTHETIC sample CSVs into $(SAMPLE_DIR)"
	@echo "load         load the real Olist CSVs from $(RAW_DIR) into $(DB)"
	@echo "load-sample  load the synthetic sample into $(DB)"
	@echo "build        dbt build (run models + tests)"
	@echo "test         dbt test only"
	@echo "docs         dbt docs generate; docs-serve to browse"
	@echo "dashboard    streamlit app on the built marts"
	@echo "lint         sqlfluff lint of models and tests"
	@echo "ci           sample + load-sample + build into data/ci.duckdb (what CI runs)"

setup:
	$(PYTHON) -m venv $(VENV)
	$(VENV)/bin/pip install --upgrade pip
	$(VENV)/bin/pip install -r requirements.txt
	$(MAKE) profile deps

profile:
	@test -f profiles.yml || cp profiles.yml.example profiles.yml

sample:
	$(BIN)python scripts/make_sample_data.py --out $(SAMPLE_DIR)

load:
	$(BIN)python scripts/load_raw.py --data-dir $(RAW_DIR) --db $(DB)

load-sample:
	$(BIN)python scripts/load_raw.py --data-dir $(SAMPLE_DIR) --db $(DB)

deps: profile
	$(BIN)dbt deps

build: deps
	$(BIN)dbt build

test:
	$(BIN)dbt test

docs:
	$(BIN)dbt docs generate

docs-serve: docs
	$(BIN)dbt docs serve

dashboard:
	$(BIN)streamlit run dashboard/app.py

lint:
	$(BIN)sqlfluff lint models tests

ci:
	$(MAKE) sample load-sample build docs DB=data/ci.duckdb

clean:
	$(BIN)dbt clean
	rm -f data/ci.duckdb data/ci.duckdb.wal
