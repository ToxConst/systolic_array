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


def fp8e4m3_to_float32(b: np.ndarray) -> np.ndarray:
    b = b.astype(np.uint8, copy=False)

    s = (b >> 7) & 0x1          # sign
    e = (b >> 3) & 0xF          # 4-bit exponent
    m =  b       & 0x7          # 3-bit mantissa

    is_spc = (e == 0xF)         # exp=1111 => Inf/NaN
    is_sub = (e == 0)           # exp=0000 => subnormal/zero

    # mantissa as float32: add hidden 1 only for normals
    mant = m.astype(np.float32) / (2**3)
    mant = np.where(is_sub, mant / 2.0, mant + 1.0)

    # exponent (int): normals use e-bias, subs use 1-bias
    exp  = np.where(is_sub, 1 - 7, e.astype(np.int32) - 7)

    # compose
    x = mant * np.exp2(exp.astype(np.float32))

    # specials
    x = np.where(is_spc & (m == 0), np.inf, x)   # ±Inf
    x = np.where(is_spc & (m != 0), np.nan, x)   # NaN

    # apply sign
    x = np.where(s == 1, -x, x)
    return x.astype(np.float32)

def float32_to_fp8e5m2(x: np.ndarray) -> np.ndarray:
    if x.dtype != np.float32:
        x = x.astype(np.float32, copy=False)

    s  = np.signbit(x).astype(np.uint8)
    ax = np.abs(x)

    is_nan  = np.isnan(ax)
    is_inf  = np.isinf(ax)
    is_zero = (ax == 0.0)

    out = np.zeros(ax.shape, dtype=np.uint8)

    # Specials
    out = np.where(is_nan,  (s<<7) | (0x1F<<2) | 0x1, out)  # qNaN payload=1
    out = np.where(is_inf,  (s<<7) | (0x1F<<2),       out)  # ±Inf
    out = np.where(is_zero, (s<<7) | 0x00,            out)  # ±0

    # ---- Normals (ax >= min_normal) ----
    bias, m, max_e = 15, 2, 0x1F
    max_finite_e = max_e - 1                   # 30
    min_normal   = np.exp2(1 - bias)           # 2^-14

    norm = ~(is_nan | is_inf | is_zero) & (ax >= min_normal)
    if np.any(norm):
        axn = ax[norm]; sn = s[norm]

        mant, exp = np.frexp(axn)              # mant in [0.5,1)
        z   = mant * (2**(m+1))                # include hidden bit → * 4
        mi  = np.floor(z).astype(np.int32)
        frac= z - mi
        rnd = (frac > 0.5) | ((frac == 0.5) & ((mi & 1) == 1))
        mi  = mi + rnd.astype(np.int32)

        # hidden-bit carry into exponent
        overflow = (mi >> (m+1)) & 1
        mi  = mi - (overflow << (m+1))
        exp = exp + overflow

        e_field = exp - 1 + bias

        # saturate to max finite when too big
        too_big = e_field > max_finite_e
        e_final = np.where(too_big, max_finite_e, e_field)
        m_final = np.where(too_big, (1<<m)-1, (mi & ((1<<m)-1))).astype(np.uint8)

        out[norm] = ((sn << 7)
                     | (e_final.astype(np.uint8) << m)
                     | m_final)

    sub = ~(is_nan | is_inf | is_zero) & (ax < min_normal)
    if np.any(sub):
        axs = ax[sub]; ss = s[sub]

        # Scale real value into subnormal mantissa space (no hidden 1)
        # mant_sub_real = ax / 2^(1-bias) * 2^m
        z   = axs / np.exp2(1 - bias) * (2**m)
        mi  = np.floor(z).astype(np.int32)
        frac= z - mi
        rnd = (frac > 0.5) | ((frac == 0.5) & ((mi & 1) == 1))
        mi  = mi + rnd.astype(np.int32)
        mi  = np.clip(mi, 0, (1<<m)-1)

        out[sub] = ((ss << 7) | mi.astype(np.uint8))

    return out

def fp8e5m2_to_float32(b: np.ndarray, bias: int = 15) -> np.ndarray:
    b = b.astype(np.uint8, copy=False)
    s = (b >> 7) & 1
    e = (b >> 2) & 0x1F
    m = (b     ) & 0x03

    is_spc = (e == 0x1F)
    is_sub = (e == 0)

    mant = m.astype(np.float32) / 4.0
    mant = np.where(is_sub, mant, mant + 1.0)

    exp  = np.where(is_sub, 1 - bias, e.astype(np.int32) - bias)

    x = mant * np.exp2(exp.astype(np.float32))
    x = np.where(is_spc & (m == 0), np.inf, x)
    x = np.where(is_spc & (m != 0), np.nan, x)
    x = np.where(s == 1, -x, x)
    return x.astype(np.float32)



def matmul_oracle(A32: np.ndarray, B32: np.ndarray) -> np.ndarray:
    """Float32 golden matmul."""
    return (A32.astype(np.float32) @ B32.astype(np.float32)).astype(np.float32)

def ulp_error(ref32, test32, mask_finite=True):
    ref32 = ref32.astype(np.float32, copy=False)
    test32 = test32.astype(np.float32, copy=False)
    if mask_finite:
        finite = np.isfinite(ref32) & np.isfinite(test32)
        if not finite.any():
            return np.zeros(0, dtype=np.uint32)
        ref32, test32 = ref32[finite], test32[finite]

    ua = ref32.view(np.uint32)
    ub = test32.view(np.uint32)

    # inline "to_mag"
    ua_m = np.where(ua & 0x80000000, 0x80000000 - (ua & 0x7FFFFFFF), ua | 0x80000000)
    ub_m = np.where(ub & 0x80000000, 0x80000000 - (ub & 0x7FFFFFFF), ub | 0x80000000)

    return np.abs(ua_m - ub_m).astype(np.uint32)



# if __name__ == "__main__":
#     rng = np.random.default_rng(0)
#     xs = (rng.standard_normal(20)*50).astype(np.float32)

#     packed = float32_to_fp8e4m3(xs)
#     back   = fp8e4m3_to_float32(packed)

#     print("xs[:5]    ", xs[:5])
#     print("packed[:5]", [hex(int(b)) for b in packed[:5]])
#     print("back[:5]  ", back[:5])





