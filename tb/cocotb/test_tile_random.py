# Random numeric driver (placeholder for RTL cocotb integration)
import os, numpy as np, json
from systolic_array.tb.rtl_tb.e4m3.quant import *

SEEDS = int(os.environ.get("SEEDS", "100"))

def run():
    rng = np.random.default_rng(1234)
    all_ulps = []
    for s in range(SEEDS):
        A = rng.standard_normal((8,8), dtype=np.float32)
        B = rng.standard_normal((8,8), dtype=np.float32)
        qA = float32_to_fp8(A, E4M3)
        qB = float32_to_fp8(B, E4M3)
        A32 = fp8_to_float32(qA, E4M3).astype(np.float32)
        B32 = fp8_to_float32(qB, E4M3).astype(np.float32)
        ref = A32 @ B32
        test = ref.copy()  # replace with RTL comparison
        ulp = ulp_error(ref.astype(np.float32), test.astype(np.float32))
        all_ulps.extend(ulp.flatten().tolist())

    os.makedirs("reports", exist_ok=True)
    with open("reports/ulp_log.json", "w") as f:
        json.dump({"ulp_values": all_ulps}, f)
    print(f"Wrote {len(all_ulps)} ULP samples to reports/ulp_log.json")

if __name__ == "__main__":
    run()
