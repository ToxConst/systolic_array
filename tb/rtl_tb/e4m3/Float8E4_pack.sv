// rtl/pack/fp8_e4m3_pack.sv
// Format: 1 | 4 | 3  (sign | exponent | mantissa), bias = 7
module fp8_e4m3_pack (
  input  logic [31:0] f32_i,   // IEEE-754 float32 bits
  output logic [7:0]  fp8_o,   // packed E4M3 byte
  output logic        sat_o    // 1 when clipped to max finite (0x77/0xF7)
);

  // ---- Extract FP32 fields ----
  logic        signBit;
  logic [7:0]  exponent32;
  logic [22:0] mantissa32;

  assign signBit   = f32_i[31];
  assign exponent32 = f32_i[30:23];
  assign mantissa32 = f32_i[22:0];

  // ---- Classify specials/zero ----
  logic is_spc, is_zero;
  assign is_spc  = (exponent32 == 8'hFF);                 // Inf/NaN
  assign is_zero = (exponent32 == 8'h00) && (mantissa32 == 0);   // ±0

  // ---- Build normalized significand and unbiased exponent ----
  // Normals: sig24 = 1.mmmm..., exp_unb = exponent32-127
  // Subnormals/zero: sig24 = 0.mmmm..., exp_unb = 1-127
  logic  [23:0]       sig24;
  logic signed [9:0]  exp_unb;
  always_comb begin
    if (exponent32 == 8'h00) begin
      sig24   = {1'b0, mantissa32};
      exp_unb = 10'(1 - 127);
    end else begin
      sig24   = {1'b1, mantissa32};
      exp_unb = 10'($signed({1'b0, exponent32}) - 127);
    end
  end

  // ---- Constants for E4M3 ----
  localparam int BIAS       = 7;
  localparam int M          = 3;            // mantissa bits
  localparam int MAX_E      = 4'hF;         // exp field all ones = specials
  localparam int MAX_FIN_E  = MAX_E - 1;    // 14
  localparam int KEEP_NORM  = M + 1;        // keep hidden+mant = 4 bits
  localparam int SHIFT_NORM = 24 - KEEP_NORM; // 24→4 = 20

  // ---- Pre-rebias exponent ----
  logic signed [9:0] e8_pre;   // can be negative
  assign e8_pre = exp_unb + BIAS;

  // ---- Outputs we’ll build ----
  logic [3:0] e_field;
  logic [2:0] m_field;
  logic       sat;

  always_comb begin
    // defaults
    e_field = 4'd0;
    m_field = 3'd0;
    sat     = 1'b0;

    if (is_spc) begin
      // Inf / NaN (map all NaNs to qNaN with mant=001)
      logic is_nan = (mantissa32 != 0);
      e_field = 4'hF;
      m_field = is_nan ? 3'b001 : 3'b000;

    end else if (is_zero) begin
      // ±0
      e_field = 4'h0;
      m_field = 3'b000;

    end else begin
      // Finite non-zero
      if (e8_pre > 0) begin
        // ========== NORMAL PATH ==========
        // Keep top 4 bits of 1.xxx… (hidden+3 mant), round remaining 20 bits (RNE)
        logic [KEEP_NORM-1:0] keep;    // 4 bits (1 + 3)
        logic [SHIFT_NORM-1:0] rem;    // 20 bits remainder
        logic                  round_up;
        logic [KEEP_NORM:0]    keep_plus; // for carry detection
        logic                  carry;

        keep      = sig24[23 -: KEEP_NORM];   // top 4 bits of sig24
        rem       = sig24[0 +: SHIFT_NORM];   // lower 20 bits
        // RNE: up if rem > half, or rem==half and LSB(keep)==1
        logic [SHIFT_NORM-1:0] half = 1 << (SHIFT_NORM-1);
        round_up = (rem > half) || ((rem == half) && keep[0]);

        keep_plus = {1'b0, keep} + {{KEEP_NORM{1'b0}}, round_up};
        carry     = keep_plus[KEEP_NORM];     // overflow into hidden bit

        // If carry, shift mant right and bump exponent
        if (carry) begin
          keep_plus = keep_plus >> 1;         // becomes 1.000
          e_field   = e8_pre[3:0] + 4'd1;
        end else begin
          e_field   = e8_pre[3:0];
        end

        // Saturate to max finite if exponent would hit specials or beyond
        if (e_field >= 4'hF) begin
          e_field = 4'hE;     // 1110
          m_field = 3'b111;   // max mant
          sat     = 1'b1;
        end else begin
          // Drop hidden 1 → take the lower 3 bits
          m_field = keep_plus[M-1:0];         // 3 LSBs of (hidden+mant)
        end

      end else begin
        // ========== SUBNORMAL / UNDERFLOW PATH ==========
        // Exp field = 0, no hidden 1. Scale signif into 3-bit mant with RNE.
        // Effective right-shift to land M bits in place:
        //   SHIFT_SUB = (24 - M) + (1 - e8_pre)
        int                SHIFT_SUB;
        logic [31:0]       sig_ext, shifted;
        logic [M:0]        keep_sub;   // M bits + guard
        logic              sticky, guard, lsb, tie_up;
        logic [M:0]        keep_sub_inc;

        SHIFT_SUB = (24 - M) + (1 - e8_pre);
        if (SHIFT_SUB < 0)  SHIFT_SUB = 0;
        if (SHIFT_SUB > 31) SHIFT_SUB = 31;

        sig_ext = {8'b0, sig24};
        shifted = sig_ext >> SHIFT_SUB;

        // Keep M bits + guard
        keep_sub = shifted[M:0];

        // Sticky = any dropped bits below those
        sticky = (SHIFT_SUB == 0) ? 1'b0
                 : ((sig_ext & ((32'h1 << SHIFT_SUB) - 1)) != 0);

        guard = keep_sub[0];
        lsb   = (M>=1) ? keep_sub[1] : 1'b0;

        // RNE for subs: round up if guard && (sticky || lsb)  (tie-to-even)
        tie_up      = guard && (sticky || lsb);
        keep_sub_inc= keep_sub + {{M{1'b0}}, tie_up};

        // Clamp to max subnormal (keep behavior consistent with your Python)
        if (keep_sub_inc[M]) begin
          m_field = {M{1'b1}};     // 3'b111
        end else begin
          m_field = keep_sub_inc[M-1:0];
        end
        e_field = 4'h0;            // subnormal exponent
      end
    end
  end

  assign sat_o = sat;
  assign fp8_o = {signBit, e_field, m_field};

endmodule

