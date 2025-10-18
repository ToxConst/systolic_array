import numpy as np
from ml_dtypes import bfloat16

# --- BF16 helpers ---
def float32_to_bf16(x: np.ndarray) -> np.ndarray:
    if x.dtype != np.float32:
        x = x.astype(np.float32, copy=False)

    bits = x.view(np.uint32)
    low16 = bits & np.uint32(0xFFFF)
    kept_lsb = (bits >> np.uint32(16)) & np.uint32(1)

    # Round-to-nearest-even mask (boolean per element)
    round_up = (low16 > np.uint32(0x8000)) | ((low16 == np.uint32(0x8000)) & (kept_lsb == np.uint32(1)))

    # Add carry into bit 16 where needed
    bits = bits + (round_up.astype(np.uint32) << np.uint32(16))

    # Take upper 16 bits as bf16
    return (bits >> np.uint32(16)).astype(np.uint16)


def bf16_to_float32(bf: np.ndarray) -> np.ndarray:
    return (bf.astype(np.uint32) << 16).view(np.float32)


# --- FP8 helpers (E4M3 and E5M2) ---
# class FP8Format:
#     def __init__(self, exp_bits, man_bits, exp_bias):
#         self.e = exp_bits
#         self.m = man_bits
#         self.bias = exp_bias
#         self.max_exp = (1 << exp_bits) - 1

# E4M3 = FP8Format(4,3, exp_bias=7)
# E5M2 = FP8Format(5,2, exp_bias=15)

def float32_to_fp8e4m3(x: np.ndarray) -> np.ndarray:
    if x.dtype != np.float32:
        x = x.astype(np.float32, copy=False)

    s  = np.signbit(x).astype(np.uint8)   # 0 or 1
    ax = np.abs(x)

    is_nan  = np.isnan(ax)
    is_inf  = np.isinf(ax)
    is_zero = (ax == 0.0)

    out = np.zeros(ax.shape, dtype=np.uint8)

    # Specials
    out = np.where(is_nan,  (s << 7) | (0xF << 3) | 0x1, out)  # qNaN payload=1
    out = np.where(is_inf,  (s << 7) | (0xF << 3),        out) # ±Inf
    out = np.where(is_zero, (s << 7) | 0x00,              out) # ±0

    bias, m, max_e = 7, 3, 0xF
    max_finite_e = max_e - 1  # 14
    min_normal = np.exp2(1 - bias)  # 2^-6

    norm = ~(is_nan | is_inf | is_zero)
    # (for now) require normal magnitude:
    norm = norm & (ax >= min_normal)

    if np.any(norm):
        axn = ax[norm]
        sn  = s[norm]

        mant, exp = np.frexp(axn)               # mant ∈ [0.5,1)
        z = mant * (2**(m+1))                   # include hidden bit
        mi = np.floor(z).astype(np.int32)
        frac = z - mi
        rnd = (frac > 0.5) | ((frac == 0.5) & ((mi & 1) == 1))
        mi = mi + rnd.astype(np.int32)

        # handle hidden-bit carry
        overflow = (mi >> (m+1)) & 1
        mi = mi - (overflow << (m+1))
        exp = exp + overflow

        e_field = exp - 1 + bias

        # clip to max finite if needed
        too_big  = e_field > max_finite_e
        e_final  = np.where(too_big, max_finite_e, e_field)
        m_final  = np.where(too_big, (1<<m)-1, (mi & ((1<<m) - 1))).astype(np.uint8)

        out[norm] = ((sn << 7)
                    | (e_final.astype(np.uint8) << m)
                    | m_final)

    sub = ~(is_nan | is_inf | is_zero) & (ax < min_normal)

    if np.any(sub):
        axs = ax[sub]
        ss  = s[sub]

        # scale into subnormal mantissa space: value = (mant/2) * 2^(1-bias)
        # => mant_sub_real = axs / 2^(1-bias) * 2^m
        z = axs / np.exp2(1 - bias) * (2**m)
        mi  = np.floor(z).astype(np.int32)
        frac= z - mi
        rnd = (frac > 0.5) | ((frac == 0.5) & ((mi & 1) == 1))
        mi  = mi + rnd.astype(np.int32)
        mi  = np.clip(mi, 0, (1<<m)-1)

        out[sub] = ((ss << 7) | mi.astype(np.uint8))

    return out

def fp8_to_float32(x: np.ndarray) -> np.ndarray:
  return 0



def matmul_oracle(A32, B32):
    return A32 @ B32

def ulp_error(ref32, test32):
    ref_bits = ref32.view(np.uint32)
    test_bits = test32.view(np.uint32)
    def to_magnitude(u):
        return np.where(u & 0x80000000, 0x80000000 - (u & 0x7fffffff), u | 0x80000000)
    return np.abs(to_magnitude(ref_bits) - to_magnitude(test_bits)).astype(np.uint32)


if __name__ == "__main__":
    #test BF16 <-> F32 conversion
    # xs = np.array([420.75], np.float32)
    # bf = float32_to_bf16(xs); back = bf16_to_float32(bf)
    # print([hex(int(v)) for v in bf], back)

    #FP8 <-> F32
    # xs = np.array([1.0, 2.0, 3.0, 0.25, 16.0], dtype=np.float32)
    # print([hex(int(b)) for b in float32_to_fp8e4m3(xs)])

    # xs = np.array([0.0, -0.0, 1.0, 2.0, 3.0, 0.25, 1e-4, np.inf, -np.inf, np.nan], dtype=np.float32)
    # b  = float32_to_fp8e4m3(xs)
    # print([hex(int(v)) for v in b])

    # xs = np.array([0.0, -0.0, 1.0, 2.0, 3.0, 0.25, 1e-4, 1e3, 1e6, np.inf, -np.inf, np.nan],
    #           dtype=np.float32)


    xs = np.array([
    # Zeros & signs
    0.0, -0.0,

    # Simple normals
    0.25, -0.25, 1.0, -1.0, 2.0, 3.0,

    # Around the min-normal (2**-6 = 0.015625)
    0.015625,         # exactly min-normal
    0.016,            # slight above (still normal)
    0.015,            # slight below (subnormal or rounds to 0)
    -0.015,           # negative subnormal-ish
    0.002, 0.0005,    # deeper subnormals (often → 0 after rounding)

    # Tie-to-even midpoints near 1.0 and 2.0
    1.0625,           # midway between 1.0 and 1.125 → should round to 1.0 (even)
    2.125,            # midway between 2.0 and 2.25  → should round to 2.0 (even)

    # Near the max finite (~ (2 - 2^-3) * 2^7 = 240)
    239.5, 240.0, 241.0,   # last safe, boundary, should saturate
    -300.0, 300.0,         # big magnitudes → saturate to 0xF7/0x77

    # Specials (your packer should map these)
    np.inf, -np.inf, np.nan
], dtype=np.float32)

    b  = float32_to_fp8e4m3(xs)
    print([hex(int(v)) for v in b])


