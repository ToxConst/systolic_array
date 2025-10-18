import numpy as np, json
from tb.models.quant import float32_to_bf16, bf16_to_float32, E4M3, E5M2, float32_to_fp8, fp8_to_float32

def test_encode_decode_roundtrip():
    x = np.random.randn(1024).astype(np.float32) * 3.0
    for fmt in (E4M3, E5M2):
        q = float32_to_fp8(x, fmt)
        xr = fp8_to_float32(q, fmt)
        assert np.isfinite(xr).all()

    bf = float32_to_bf16(x)
    xr = bf16_to_float32(bf)
    assert np.all(np.isfinite(xr))

def test_ulps_logging(tmp_path):
    x = (np.random.randn(4096)*2).astype(np.float32)
    bf = float32_to_bf16(x)
    xr = bf16_to_float32(bf)
    ulps = np.abs(x.view(np.uint32) - xr.view(np.uint32)).tolist()
    out = tmp_path / "ulp_log.json"
    with open(out, "w") as f:
        json.dump({"ulp_values": ulps}, f)
