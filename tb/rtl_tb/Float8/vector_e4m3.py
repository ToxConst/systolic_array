
import sys, numpy as np

# (Tiny safety) If quant.py needs ml_dtypes for unrelated bf16 code
try:
    import quant
except Exception as e:
    if "ml_dtypes" in str(e):
        import types
        ml = types.ModuleType("ml_dtypes")
        class bfloat16: pass
        ml.bfloat16 = bfloat16
        sys.modules["ml_dtypes"] = ml
        import quant
    else:
        raise
# --- helpers ---
def u32_hex_from_f32_array(xf32: np.ndarray):
    return [f"{int(v):08X}" for v in xf32.astype(np.float32).view(np.uint32)]

def canonical_nan_e4(b: int) -> int:
    # keep sign, set exp=1111, mant=001
    return ((b & 0x80) | 0x78 | 0x01)

def canonical_nan_e5(b: int) -> int:
    # keep sign, set exp=11111, mant=01
    return ((b & 0x80) | 0x7C | 0x01)

def is_nan_e4(b: int) -> bool:
    return (b & 0x78) == 0x78 and (b & 0x07) != 0

def is_nan_e5(b: int) -> bool:
    return (b & 0x7C) == 0x7C and (b & 0x03) != 0

def f32_hex(x):
    return [f"{int(v):08X}" for v in x.astype(np.float32).view(np.uint32)]
def u8_hex(x):
    return [f"{int(v):02X}" for v in x.astype(np.uint8)]

# inputs
vals = [
    0.0, -0.0, 1.0, -1.0, 0.5, -0.5, 2.0, -2.0,
    float("inf"), float("-inf"), np.float32("nan"),
    2**-10, 2**-8, 2**-7, 2**-6, 2**-5, 2**-4,  # around min-normal
    100.0, 200.0, 448.0, 480.0, 512.0, 1024.0,  # large / overflow-y
    -353.2, 139.2, -76.8, 33.6, 12.5, -6.25, 3.125, -1.5625, 0.78125,
    0.390625, 0.00374861, 0.23489, 0.0000246182, 1.9986
]

vals += [i/16 for i in range(-32, 33)]

rng = np.random.default_rng(123)
vals += list((rng.standard_normal(64) * 50).astype(np.float32))

xs = np.array(vals, dtype=np.float32)

fp8 = quant.float32_to_fp8e4m3(xs)
fp8_2 = quant.float32_to_fp8e5m2(xs)


# Sweep all 0..255 bytes
fp8_bytes = np.arange(256, dtype=np.uint8)

# Unpack with your gold
fp32_from_e4 = quant.fp8e4m3_to_float32(fp8_bytes)
fp32_from_e5 = quant.fp8e5m2_to_float32(fp8_bytes)


# Write E4M3 byte->f32
with open("C:\\Users\\adity\\Proj\\MACproj\\systolic_array\\tb\\rtl_tb\\Float8\\E4M3_float32.txt", "w") as f:
    for b, f32hex in zip(fp8_bytes, u32_hex_from_f32_array(fp32_from_e4)):
        f.write(f"{int(b):02X} {f32hex}\n")

# Write E5M2 byte->f32
with open("C:\\Users\\adity\\Proj\\MACproj\\systolic_array\\tb\\rtl_tb\\Float8\\E5M2_float32.txt", "w") as f:
    for b, f32hex in zip(fp8_bytes, u32_hex_from_f32_array(fp32_from_e5)):
        f.write(f"{int(b):02X} {f32hex}\n")


with open("C:\\Users\\adity\\Proj\\MACproj\\systolic_array\\tb\\rtl_tb\\Float8\\float32_E4M3.txt", "w") as f:
    for a, b in zip(f32_hex(xs), u8_hex(fp8)):
        f.write(f"{a} {b}\n")

with open("C:\\Users\\adity\\Proj\\MACproj\\systolic_array\\tb\\rtl_tb\\Float8\\float32_E5M2.txt", "w") as f:
    for a, b in zip(f32_hex(xs), u8_hex(fp8_2)):
        f.write(f"{a} {b}\n")

