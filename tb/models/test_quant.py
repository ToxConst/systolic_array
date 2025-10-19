import numpy as np
from ml_dtypes import bfloat16

# === import your functions (adjust the import if they live elsewhere) ===
from quant import (
    float32_to_bf16, bf16_to_float32,
    float32_to_fp8e4m3, fp8e4m3_to_float32,
    float32_to_fp8e5m2, fp8e5m2_to_float32
)

# --- ULP helper on float32 (monotonic-mapped) ---
def ulp_error(a32: np.ndarray, b32: np.ndarray) -> np.ndarray:
    ua = a32.view(np.uint32)
    ub = b32.view(np.uint32)
    def to_mag(u):
        # map sign-magnitude to monotonic order:
        # negative numbers get reversed; positives get the sign bit set
        return np.where(u & 0x80000000, 0x80000000 - (u & 0x7FFFFFFF), u | 0x80000000)
    return np.abs(to_mag(ua) - to_mag(ub)).astype(np.uint32)

def summarize(name, x, x_back):
    # exclude NaNs from numeric stats
    finite = np.isfinite(x) & np.isfinite(x_back)
    dx = np.abs(x_back[finite] - x[finite])
    rel = dx / (np.abs(x[finite]) + 1e-30)
    ulp = ulp_error(x[finite].astype(np.float32), x_back[finite].astype(np.float32))

    def p(v, q): return float(np.percentile(v, q)) if v.size else float('nan')
    print(f"\n[{name}]  N={finite.sum()}/{x.size} finite")
    print(f"  abs err  median={p(dx,50):.6g}  95p={p(dx,95):.6g}  max={dx.max():.6g}")
    print(f"  rel err  median={p(rel,50):.6g}  95p={p(rel,95):.6g}")
    print(f"  ULPs     median={p(ulp,50):.0f}  95p={p(ulp,95):.0f}  max={ulp.max() if ulp.size else 0:.0f}")

def check_specials(pack_fn, unpack_fn, pos_inf_byte, nan_byte_mask_bits: int):
    xs = np.array([0.0, -0.0, np.inf, -np.inf, np.nan], dtype=np.float32)
    b = pack_fn(xs)
    back = unpack_fn(b)
    print("  specials bytes:", [hex(int(v)) for v in b])
    print("  back:", back)
    # sanity: +inf code matches, NaN has mant!=0
    assert int(b[2]) == pos_inf_byte
    assert (int(b[4]) & nan_byte_mask_bits) != 0  # any nonzero mantissa

def main():
    rng = np.random.default_rng(42)

    # Two distributions: “normal-ish” and wide-range log-ish
    xs1 = (rng.standard_normal(10000) * 50).astype(np.float32)
    # wide range incl. tiny/huge
    mags = np.exp(rng.uniform(-20, 20, 10000)).astype(np.float32)  # e^U ≈ 10^±(8.7)
    signs = rng.choice([-1.0, 1.0], size=10000).astype(np.float32)
    xs2 = (mags * signs).astype(np.float32)

    # --- BF16 ---
    bf = float32_to_bf16(xs1); xs1_b = bf16_to_float32(bf)
    summarize("BF16  (normal dist)", xs1, xs1_b)
    bf = float32_to_bf16(xs2); xs2_b = bf16_to_float32(bf)
    summarize("BF16  (wide dist)", xs2, xs2_b)

    # --- FP8 E4M3 ---
    b8 = float32_to_fp8e4m3(xs1); xs1_8 = fp8e4m3_to_float32(b8)
    summarize("FP8 E4M3 (normal dist)", xs1, xs1_8)
    b8 = float32_to_fp8e4m3(xs2); xs2_8 = fp8e4m3_to_float32(b8)
    summarize("FP8 E4M3 (wide dist)", xs2, xs2_8)
    print("E4M3 specials check:")
    check_specials(float32_to_fp8e4m3, fp8e4m3_to_float32, pos_inf_byte=0x78, nan_byte_mask_bits=0x07)

    # --- FP8 E5M2 ---
    b5 = float32_to_fp8e5m2(xs1); xs1_5 = fp8e5m2_to_float32(b5)
    summarize("FP8 E5M2 (normal dist)", xs1, xs1_5)
    b5 = float32_to_fp8e5m2(xs2); xs2_5 = fp8e5m2_to_float32(b5)
    summarize("FP8 E5M2 (wide dist)", xs2, xs2_5)
    print("E5M2 specials check:")
    check_specials(float32_to_fp8e5m2, fp8e5m2_to_float32, pos_inf_byte=0x7C, nan_byte_mask_bits=0x03)

    # Quick tie probes (sanity)
    ties = np.array([1.0625, 2.125], dtype=np.float32)  # midpoints between grid points in E4M3
    tb = float32_to_fp8e4m3(ties)
    print("E4M3 tie bytes (expect 1.0→0x38, 2.0→0x40):", [hex(int(v)) for v in tb])

if __name__ == "__main__":
    main()
