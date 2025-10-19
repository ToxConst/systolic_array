# FP8/BF16 Systolic Tile — Starter Repo

**Goal:** Build and verify an 8×8 systolic MAC tile with FP8 (E4M3/E5M2) and BF16 fronts, including rounding/saturation, a double-buffered DMA stub, and a NumPy oracle. Verification uses cocotb with constrained-random stimuli, ULP histograms, and coverage.

## Layout
- `rtl/include/fp_formats_pkg.sv` - FP8/BF16 pack/unpack types and helpers.
- `rtl/tile/systolic_tile.sv` - 8×8 dataflow tile (streaming interfaces).
- `rtl/tile/saturate_round.sv` - rounding/saturation unit (stochastic optional).
- `rtl/dma/dma_stub.sv` - simple tile loader/drainer with double-buffering.
- `tb/cocotb/test_tile_basic.py` - smoke + directed tests.
- `tb/cocotb/test_tile_random.py` - constrained-random with seeds.
- `tb/models/quant.py` - FP8/BF16 encode/decode + NumPy oracle.
- `tb/models/plots.py` - ULP histograms & heatmaps.
- `scripts/Makefile` - common targets (`make smoke`, `make rand`, `make plots`).
- `TESTPLAN.md` - feature → test/coverage mapping.
- `reports/` - auto-generated plots and logs.

## Milestones
1. Encode/decode & rounding (Day 1–2)
2. Tile dataflow (Day 3–4)
3. DMA overlap (Day 5)
4. Directed tests + SVAs (Day 6)
5. Random + coverage (Day 7–8)
6. Plots + sign-off (Day 9–10)
