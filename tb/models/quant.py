import numpy as np

# --- BF16 helpers ---
def float32_to_bf16(x: np.ndarray) -> np.ndarray:
    x = x.astype(np.float32, copy=False)
    ui = x.view(np.uint32)
    # RN-E: add 0x8000 before truncation when lower 16 bits > midpoint (ties to even)
    lsb = (ui >> 16) & 1
    round_bias = ((ui & 0xFFFF) > 0x8000) | (((ui & 0xFFFF) == 0x8000) & lsb)
    ui = ui + (round_bias.astype(np.uint32) << 16)
    bf16 = (ui >> 16).astype(np.uint16)
    return bf16

def bf16_to_float32(bf: np.ndarray) -> np.ndarray:
    ui = (bf.astype(np.uint32) << 16)
    return ui.view(np.float32)

# --- FP8 helpers (E4M3 and E5M2) ---
class FP8Format:
    def __init__(self, exp_bits, man_bits, exp_bias):
        self.e = exp_bits
        self.m = man_bits
        self.bias = exp_bias
        self.max_exp = (1 << exp_bits) - 1

E4M3 = FP8Format(4,3, exp_bias=7)
E5M2 = FP8Format(5,2, exp_bias=15)

def float32_to_fp8(x: np.ndarray, fmt: FP8Format, mode="rn", clip=True):
    """Convert float32 to FP8; mode in {"rn","rz"}; simple saturation when clip=True."""
    x = x.astype(np.float32, copy=False)
    s = np.signbit(x).astype(np.uint8)
    ax = np.abs(x)

    # Special cases
    is_nan = np.isnan(ax)
    is_inf = np.isinf(ax)
    ax = np.nan_to_num(ax, nan=0.0, posinf=np.finfo(np.float32).max, neginf=np.finfo(np.float32).max)

    mant, exp = np.frexp(ax)  # ax = mant * 2**exp, mant in [0.5,1)
    mant = mant * 2**(fmt.m + 1)  # include hidden bit
    mant_i = np.floor(mant).astype(np.int32)
    frac = mant - mant_i

    if mode == "rn":
        mant_i += (frac > 0.5) | ((frac == 0.5) & (mant_i & 1))

    overflow = mant_i >> (fmt.m + 1)
    mant_i = mant_i - (overflow << (fmt.m + 1))
    exp = exp + overflow

    e_unbiased = exp - 1 + fmt.bias
    if clip:
        e_unbiased = np.clip(e_unbiased, 0, fmt.max_exp)

    mant_fp = (mant_i & ((1 << (fmt.m + 1)) - 1)) & ((1 << fmt.m) - 1)  # drop hidden
    out = (s << 7) | (e_unbiased.astype(np.uint8) << fmt.m) | mant_fp.astype(np.uint8)

    out = np.where(is_nan, (s << 7) | (fmt.max_exp << fmt.m) | (1), out)  # qNaN
    out = np.where(is_inf, (s << 7) | (fmt.max_exp << fmt.m), out)        # Inf
    return out.astype(np.uint8)

def fp8_to_float32(b: np.ndarray, fmt: FP8Format) -> np.ndarray:
    b = b.astype(np.uint8, copy=False)
    s = (b >> 7) & 1
    e = (b >> fmt.m) & ((1 << fmt.e) - 1)
    m = b & ((1 << fmt.m) - 1)

    is_sub = e == 0
    is_inf = e == ((1 << fmt.e) - 1)

    mant = m.astype(np.float32) / (2**fmt.m)
    mant = np.where(is_sub, mant / 2.0, mant + 1.0)
    exp = np.where(is_sub, 1 - fmt.bias, e.astype(np.int32) - fmt.bias)

    x = mant * np.exp2(exp.astype(np.float32))
    x = np.where(is_inf & (m == 0), np.inf, x)
    x = np.where(is_inf & (m != 0), np.nan, x)
    x = np.where(s == 1, -x, x)
    return x.astype(np.float32)

def matmul_oracle(A32, B32):
    return A32 @ B32

def ulp_error(ref32, test32):
    ref_bits = ref32.view(np.uint32)
    test_bits = test32.view(np.uint32)
    def to_magnitude(u):
        return np.where(u & 0x80000000, 0x80000000 - (u & 0x7fffffff), u | 0x80000000)
    return np.abs(to_magnitude(ref_bits) - to_magnitude(test_bits)).astype(np.uint32)

def test_bf16_matches_numpy():
    x = np.linspace(-1e5, 1e5, 10000).astype(np.float32)
    ours_bf = float32_to_bf16(x)
    ours = bf16_to_float32(ours_bf)
    ref = np.asarray(x, dtype=np.bfloat16).astype(np.float32)
    assert np.array_equal(ours.view(np.uint32), ref.view(np.uint32))

test_bf16_matches_numpy()
