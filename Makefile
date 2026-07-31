PYTHON ?= python3
RUNNER := $(PYTHON) scripts/bq_runner.py
NOTEBOOK_PYTHON ?= python3
NOTEBOOK_VENV_PYTHON := .venv/bin/python
NOTEBOOK_JUPYTER := .venv/bin/jupyter
DASHBOARD_DIR := dashboard/site
MEMO_PYTHON ?= python3

.PHONY: auth doctor setup dry-run build qa extract all notebook-setup notebook ab-notebook notebooks notebook-html analysis dashboard-setup dashboard-data dashboard-build dashboard-test dashboard-dev dashboard memo

auth:
	$(RUNNER) auth

doctor:
	$(RUNNER) doctor

setup:
	$(RUNNER) setup

dry-run:
	$(RUNNER) dry-run

build:
	$(RUNNER) build

qa:
	$(RUNNER) qa

extract:
	$(RUNNER) extract

all:
	$(RUNNER) all

notebook-setup:
	$(NOTEBOOK_PYTHON) -m venv .venv
	$(NOTEBOOK_VENV_PYTHON) -m pip install --upgrade pip
	$(NOTEBOOK_VENV_PYTHON) -m pip install -r requirements.txt

notebook:
	@test -x $(NOTEBOOK_VENV_PYTHON) || (echo "Run 'make notebook-setup NOTEBOOK_PYTHON=/path/to/python3' first."; exit 1)
	$(NOTEBOOK_VENV_PYTHON) scripts/build_analysis_notebook.py

ab-notebook:
	@test -x $(NOTEBOOK_VENV_PYTHON) || (echo "Run 'make notebook-setup NOTEBOOK_PYTHON=/path/to/python3' first."; exit 1)
	$(NOTEBOOK_VENV_PYTHON) scripts/build_ab_test_notebook.py

notebooks: notebook ab-notebook

notebook-html: notebooks
	mkdir -p data/interim/notebook_previews
	$(NOTEBOOK_JUPYTER) nbconvert --to html notebooks/01_funnel_and_sensitivity.ipynb notebooks/02_ab_test_design_and_simulation.ipynb --output-dir data/interim/notebook_previews

analysis: all
	@test -x $(NOTEBOOK_VENV_PYTHON) || (echo "Run 'make notebook-setup NOTEBOOK_PYTHON=/path/to/python3' first."; exit 1)
	$(NOTEBOOK_VENV_PYTHON) scripts/build_analysis_notebook.py
	$(NOTEBOOK_VENV_PYTHON) scripts/build_ab_test_notebook.py

dashboard-setup:
	npm --prefix $(DASHBOARD_DIR) ci

dashboard-data:
	$(PYTHON) scripts/build_dashboard_data.py

dashboard-build: dashboard-data
	npm --prefix $(DASHBOARD_DIR) run build

dashboard-test: dashboard-data
	npm --prefix $(DASHBOARD_DIR) test
	npm --prefix $(DASHBOARD_DIR) run lint

dashboard-dev: dashboard-data
	npm --prefix $(DASHBOARD_DIR) run dev

dashboard: dashboard-test

memo:
	$(MEMO_PYTHON) scripts/build_decision_memo_pdf.py
