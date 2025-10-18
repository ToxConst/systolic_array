# TESTPLAN — FP8/BF16 Systolic Tile

## Features
- Formats: FP8 E4M3, FP8 E5M2, BF16
- Rounding: nearest-even (default), stochastic (opt)
- Saturation/clip + NaN/Inf propagation
- 8×8 MAC dataflow with pipeline
- DMA double-buffer overlap (load/compute/store)

## Assertions (SVAs)
- No data drop/dup across tile boundaries
- Denorm/Inf/NaN rules match spec for each format
- Saturation only when overflow detected
- Back-pressure respected; no deadlock

## Stimuli
- Directed: identity, zero, max/min ranges, denorms, NaN/Inf lanes
- Random: uniform, normal, log-uniform, adversarial (overflow-prone)
- Sizes: exact 8×8, boundary tiles, partial tiles (masked)

## Coverage
- Code: ≥95% line/branch
- Functional: ≥92% (format × rounding × edge-class × boundary-mask)
- Numeric: ULP histogram targets per op (median, 95p, 99p)

## Metrics
- ULP heatmaps vs NumPy oracle
- Throughput/utilization vs DMA overlap (synthetic)
- Seeds: ≥2000 with zero escapes; all failing seeds triaged
