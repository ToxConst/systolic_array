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

with open("C:\\Users\\adity\\Proj\\MACproj\\systolic_array\\tb\\rtl_tb\\e4m3\\fp32_fp8e4m3_vectors.txt", "w") as f:
    for a, b in zip(f32_hex(xs), u8_hex(fp8)):
        f.write(f"{a} {b}\n")

with open("C:\\Users\\adity\\Proj\\MACproj\\systolic_array\\tb\\rtl_tb\\e4m3\\fp32_fp8e5m2_vectors.txt", "w") as f:
    for a, b in zip(f32_hex(xs), u8_hex(fp8_2)):
        f.write(f"{a} {b}\n")

print("Wrote", len(xs), "vectors to fp32_fp8e4m3_vectors.txt")
print("Wrote", len(xs), "vectors to fp32_fp8e5m2_vectors.txt")