// Defaults: E4M3  (E=4, M=3, bias=7).  For E5M2: E=5, M=2 (bias=15).

module Float8_pack #(parameter E = 4, parameter M = 3, parameter BIAS = (1 << (E-1)) - 1) (  // IEEE-style bias = 2^(E-1)-1
  input  logic [31:0] f32_i,       // IEEE-754 float32 bits
  output logic [7:0] fp8_o,      // packed byte 
  output logic          sat_o      // 1 when saturated to max finite
);

  // ========= Derived constants =========
  localparam int KEEP_NORM  = M + 1;          // hidden + mant
  localparam int MAX_E      = (1 << E) - 1;   // all-ones exp (specials)
  localparam int MAX_FIN_E  = MAX_E - 1;      // max finite exponent field
  localparam int REM_W      = 23 - M;         // remainder bits under KEEP_NORM

  // ========= FP32 fields =========
  logic        s;
  logic [7:0]  e32;
  logic [22:0] m32;

  assign s   = f32_i[31];
  assign e32 = f32_i[30:23];
  assign m32 = f32_i[22:0];

  // ========= Normalized significand & unbiased exponent =========
  logic [23:0]       signif;   // {hidden, m32}
  logic signed [9:0] exp_unb;  // FP32 unbiased exponent

  // ========= Classification =========
  logic is_special, is_zero, is_nan;
  assign is_special = (e32 == 8'hFF);
  assign is_zero    = (e32 == 8'h00) && (m32 == 23'd0);
  assign is_nan     = is_special && (m32 != 23'd0);

  // ========= Outputs being built =========
  logic [E-1:0] exp_f;
  logic [M-1:0] man_f;
  logic         sat;

  // ========= Normal rounding (RNE) =========
  // Take top KEEP_NORM bits = {hidden, mant[M-1:0]} from signif[23:0]
  logic [KEEP_NORM-1:0] keep;           // width M+1
  logic [REM_W-1:0]     rem;            // width 23-M
  logic                  round_up;
  logic [KEEP_NORM:0]    keep_plus;     // +1 carry room
  logic                  carry_norm;

  // ========= Subnormal rounding (RNE) =========
  int                    SHIFT_SUB;
  logic [31:0]           sig_ext, shifted;
  logic [M:0]            keep_sub;      // M bits + guard
  logic                  sticky, guard, lsb, tie_up;
  logic [M+1:0]          keep_sub_ext;  // extra carry room

  // ========= Exponent working var (wider for math) =========
  logic signed [9:0]     e8_pre;        // biased target exponent
  logic signed [9:0]     e_tmp;

  logic rem_gt_half, rem_eq_half;

  always_comb begin
    if (e32 == 8'h00) begin
      signif  = {1'b0, m32};                   // subnormals/zero
      exp_unb = -10'sd126;
    end else begin
      signif  = {1'b1, m32};                   // normals
      exp_unb = $signed({1'b0, e32}) - 127;
    end
    // defaults
    exp_f = '0; man_f = '0; sat = 1'b0;

    if (is_special) begin
      // Inf / NaN
      exp_f = {E{1'b1}};                      // all ones
      man_f = is_nan ? {{(M-1){1'b0}}, 1'b1}  // qNaN: frac != 0 (use ...001)
                     : {M{1'b0}};             // Inf
    end
    else if (is_zero) begin
      exp_f = '0; man_f = '0;
    end
    else begin
      // Finite non-zero
      e8_pre = exp_unb + BIAS;

      if (e8_pre > 0) begin
        // ========== NORMAL PATH ==========
        // Top (M+1) bits: [23:23-M]
        keep = signif[23 -: (M+1)];
        // Remainder under that: [23-M-1 : 0], width = 23-M
        rem  = signif[23-(M+1) -: (23 - M)];

        // RNE (tie to even) on the remainder
        rem_gt_half = (REM_W>0) ? ( rem[REM_W-1] && (|rem[REM_W-2:0]) ) : 1'b0;
        rem_eq_half = (REM_W>0) ? ( rem[REM_W-1] && ~(|rem[REM_W-2:0]) ) : 1'b0;
        round_up    = rem_gt_half | (rem_eq_half & keep[0]);

        keep_plus   = {1'b0, keep} + {{KEEP_NORM{1'b0}}, round_up};
        carry_norm  = keep_plus[KEEP_NORM];

        // exponent math in wide int to avoid wrap
        e_tmp = e8_pre + (carry_norm ? 10'sd1 : 10'sd0);

        // Saturate finite overflow
        if (e_tmp >= MAX_E) begin
          exp_f = MAX_FIN_E[E-1:0];
          man_f = {M{1'b1}};
          sat   = 1'b1;
        end else begin
          exp_f = e_tmp[E-1:0];
          man_f = keep_plus[M-1:0];   // drop hidden bit → keep M bits
        end
      end
      else begin
        // ========== SUBNORMAL / UNDERFLOW PATH ==========
        // Bring M mantissa bits + 1 guard down to [M:0] from bit-23 anchor:
        // SHIFT_SUB = (23 - M) - e8_pre
        SHIFT_SUB = (23 - M) - e8_pre;
        if (SHIFT_SUB < 0)  SHIFT_SUB = 0;
        if (SHIFT_SUB > 31) SHIFT_SUB = 31;

        sig_ext = {8'b0, signif};
        shifted = sig_ext >> SHIFT_SUB;

        // keep_sub = {mant[M-1:0], guard}
        keep_sub = shifted[M:0];

        // sticky = OR of all dropped bits below guard
        sticky = (SHIFT_SUB == 0) ? 1'b0
               : ((sig_ext & ((32'h1 << SHIFT_SUB) - 1)) != 0);

        guard  = keep_sub[0];
        lsb    = (M>=1) ? keep_sub[1] : 1'b0;

        // RNE (tie to even)
        tie_up       = guard && (sticky || lsb);

        // Add with a headroom bit to detect true carry-out
        keep_sub_ext = {1'b0, keep_sub};                // [M+1:0]
        keep_sub_ext = keep_sub_ext + {{(M+1){1'b0}}, tie_up};

        // If carry into the headroom bit, clamp to max subnormal; else drop guard
        if (keep_sub_ext[M+1]) begin
          man_f = {M{1'b1}};
        end else begin
          man_f = keep_sub_ext[M:1];                    // drop guard, keep M
        end

        exp_f = '0;                                     // subnormal exponent
      end
    end
  end

  assign sat_o = sat;
  assign fp8_o = {s, exp_f, man_f};

endmodule
