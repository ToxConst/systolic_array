# Simple Makefile scaffold (adjust tool commands for your env)
PYTHON ?= python3

.PHONY: smoke rand plots

smoke:
	$(PYTHON) -m pytest -q tb/cocotb/test_tile_basic.py

rand:
	SEEDS=100 $(PYTHON) tb/cocotb/test_tile_random.py

plots:
	$(PYTHON) tb/models/plots.py --in reports/ulp_log.json --out reports/plots
