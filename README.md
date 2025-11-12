# FP8/BF16 Systolic MAC Tile

An educational, verification‑driven SystemVerilog project that implements an FP8 systolic MAC tile (E4M3 & E5M2), optional BF16 output, and a self‑checking test/analysis stack (cocotb + Python oracles).

---

## Features

* **FP8 front‑end:** E4M3 and E5M2 formats (pack/unpack), subnormals, ±Inf, qNaN.
* **PE (processing element):** FP8×FP8 → FP32 MAC, optional BF16/FP8 output.
* **Output‑stationary tile:** A streams east, B streams south, each PE accumulates locally and emits C with ready/valid.
* **Rounding:** IEEE‑754 **round‑to‑nearest, ties‑to‑even** for BF16 packing.
* **Verification:** cocotb testbenches, constrained‑random stimulus, numeric scoreboard vs Python model, ULP histograms.

---

## Repository layout

```
rtl/
  include/
    fp_formats_pkg.sv       # (optional) common FP params/types
  pack_unpack/
    Float8_pack.sv          # FP32 → FP8 (E4M3/E5M2)
    Float8_unpack.sv        # FP8  → FP32 (E4M3/E5M2)
    bf16_pack.sv            # FP32 → BF16 (RNE)
    bf16_unpack.sv          # BF16 → FP32 (if used)
  pe/
    mac_cell.sv             # Single PE; A east, B local; FP32 MAC core
  tile/
    systolic_tile.sv        # R×C mesh wrapper (A east / B south / C local)
    saturate_round_bf16.sv  # FP32→BF16 rounding & overflow/NaN handling
  dma/
    dma_stub.sv             # Simple double‑buffered feeder (optional)

tb/
  rtl_tb/
    Float8_tb.sv            # Unit tests for FP8 pack/unpack
    bf16_tb.sv              # Unit tests for BF16 pack/unpack
    mac_cell_tb.sv          # PE handshake + numeric checks
  cocotb/
    test_tile_basic.py      # Smoke tests: 2×2 tile, K=1
    test_tile_random.py     # Randomized tests: sizes, stalls, specials
  models/
    quant.py                # FP8/BF16 encode/decode + numpy oracle
    plots.py                # ULP histograms, heatmaps

scripts/
  Makefile                  # Convenience targets: sim, rand, plots

README.md
TESTPLAN.md                 # Feature→test→coverage mapping
LICENSE (MIT)
```
---

## How it works (high‑level)

### Dataflow

* **A (west→east)** and **B (north→south)** propagate with ready/valid.
* Each PE multiplies the FP8 operands, accumulates in **FP32** (output‑stationary), and presents a **C** result locally.
* The tile exposes `c_valid[r][c]/c_ready[r][c]` per PE so you can collect or throttle results independently.

### Numeric handling

* **FP8:** E4M3 and E5M2; supports ±0, subnormals, ±Inf, and qNaN. NaNs are kept quiet on pack.
* **Accumulation:** Internal accumulator uses IEEE‑754 single precision (FP32). For K>1 workloads, partial sums stay in FP32 until drain.
* **BF16 output:** FP32→BF16 uses **RNE (ties‑to‑even)**; max‑finite overflow saturates to ±Inf; NaN payloads become qNaN.

## Interfaces (PE & Tile)

### mac_cell (single‑shot today)

* **Control:** `mode_fp8` (0:E4M3, 1:E5M2), `out_bf16_en` (reserved)
* **Inputs:** `a_raw[7:0]`, `b_raw[7:0]`, `a_valid_in`, `mac_valid_in`
* **Outputs:** `a_out[7:0]`, `a_valid_out`, `mac_packed_bf[15:0]`, `mac_downstream[7:0]`
* **Handshake:** `input_ready_take` (accept when high), `mac_valid`/`output_ready`


## Test & verification

* **Unit tests:** FP8/BF16 pack/unpack SV testbenches (directed vectors + specials).
* **PE tests:** Randomized handshake runs (stalls, single‑shot), numeric scoreboard (BF16 bit‑exact under RNE).
* **Tile tests:** cocotb smoke (2×2) and randomized (sizes, stalls, specials, mixed modes).
* **Coverage:** Code ≥95% and functional ≥92% targets, covering: modes, specials, stalls, K lengths, edge PEs, NaN/Inf propagation.

---

## Roadmap

* [ ] **Enable multi‑K accumulation** in `mac_cell` (uncomment/add `c_reg`, gate `take`).
* [ ] **Add B pass‑through** to `mac_cell` (b_out/b_valid_out) to push the south fabric inside the PE.
* [ ] **Tile controller** with `K_len` and end‑of‑wavefront signaling (`done`).
* [ ] **FP8 output option** (select BF16 or FP8 per PE/row).
* [ ] **DMA stub integration** for streaming matrices from SRAM/AXI‑Lite.
* [ ] **Cocotb coverage hooks** and UVM‑lite style scoreboard.

---

## Getting help / contributing

Issues and PRs welcome. If you spot a corner case (NaN payloads, subnormal edge, saturation), please attach a minimal waveform or Python repro.

---

## License

[MIT](LICENSE)
