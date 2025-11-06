

module mac_cell #(
  parameter int ACC_STAGES = 1,         // extra valid pipeline after MAC
  parameter int MAC_LAT    = 1          // latency of sim_fp_mac / DW_fp_mac
)(
  input  logic         clk,
  input  logic         rst_n,

  input  logic         mode_fp8,       // 0:E4M3, 1:E5M2
  input  logic         out_bf16_en,    // 1: drive BF16, else FP8

  // Systolic handshakes
  input  logic         valid_in_a,
  input  logic         valid_in_b,
  output logic         ready_in_a,
  output logic         ready_in_b,

  input  logic  [7:0]  a_in,
  input  logic  [7:0]  b_in,
  output logic  [7:0]  a_out,
  output logic  [7:0]  b_out,
  output logic         valid_out_a,
  output logic         valid_out_b,

  // Accum control
  input  logic         acc_clear,
  input  logic         acc_en,

  // Outputs
  output logic [7:0]   c_out_fp8,
  output logic [15:0]  c_out_bf16,
  output logic         c_valid
);

  // ----------------------------------------------------------------
  // Always-ready
  // ----------------------------------------------------------------
  always_comb begin
    ready_in_a = 1'b1;
    ready_in_b = 1'b1;
  end

  // ----------------------------------------------------------------
  // 1-cycle flopped pass-through
  // ----------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      a_out       <= '0;
      b_out       <= '0;
      valid_out_a <= 1'b0;
      valid_out_b <= 1'b0;
    end else begin
      a_out       <= a_in;
      b_out       <= b_in;
      valid_out_a <= valid_in_a;
      valid_out_b <= valid_in_b;
    end
  end

  // ----------------------------------------------------------------
  // Unpack FP8 -> FP32 (instantiate both formats, select by mode)
  // ----------------------------------------------------------------
  logic [31:0] a32_e4m3, b32_e4m3;
  logic [31:0] a32_e5m2, b32_e5m2;
  logic [31:0] a32, b32;

  // E4M3
  Float8_unpack #(.E(4), .M(3)) u_up_a_e4 (.fp8_in(a_in), .f32_out(a32_e4m3));
  Float8_unpack #(.E(4), .M(3)) u_up_b_e4 (.fp8_in(b_in), .f32_out(b32_e4m3));
  // E5M2
  Float8_unpack #(.E(5), .M(2)) u_up_a_e5 (.fp8_in(a_in), .f32_out(a32_e5m2));
  Float8_unpack #(.E(5), .M(2)) u_up_b_e5 (.fp8_in(b_in), .f32_out(b32_e5m2));

  // runtime select
  always_comb begin
    a32 = mode_fp8 ? a32_e5m2 : a32_e4m3;
    b32 = mode_fp8 ? b32_e5m2 : b32_e4m3;
  end

  // Fire pulse
  logic fire_in;
  logic mac_out_pulse;
  logic [ACC_STAGES-1:0] v_post;
  assign fire_in = valid_in_a & valid_in_b & acc_en;

  // MAC latency pipe
  logic [MAC_LAT:0] v_mac;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) v_mac <= '0;
    else begin
      v_mac[0] <= fire_in;
      for (int i=1;i<=MAC_LAT;i++) v_mac[i] <= v_mac[i-1];
    end
  end
  assign mac_out_pulse = (MAC_LAT==0) ? fire_in : v_mac[MAC_LAT];

  // Post-MAC pipeline (ACC_STAGES)
  generate
    if (ACC_STAGES==0) begin
      assign c_valid = mac_out_pulse;
    end else begin : g_post
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) v_post <= '0;
        else begin
          v_post[0] <= mac_out_pulse;
          for (int j=1;j<ACC_STAGES;j++) v_post[j] <= v_post[j-1];
        end
      end
      assign c_valid = v_post[ACC_STAGES-1];
    end
  endgenerate

  // ----------------------------------------------------------------
  // Accumulator register (feeds MAC .c), MAC generates new sum
  // ----------------------------------------------------------------
  logic [31:0] acc_q, mac_z;
  logic [7:0]  mac_status; // ignored for now

`ifdef USE_DW
  DW_fp_mac #(
    .sig_width(23), .exp_width(8), .ieee_compliance(1)
  ) u_mac (
    .a     (a32),
    .b     (b32),
    .c     (acc_q),
    .rnd   (3'b000),    // RNE
    .z     (mac_z),
    .status(mac_status)
  );
`else
  sim_fp_mac #(
    .sig_width(23), .exp_width(8), .ieee_compliance(1),
    .LATENCY(MAC_LAT)
  ) u_mac (
    .a     (a32),
    .b     (b32),
    .c     (acc_q),
    .rnd   (3'b000),
    .z     (mac_z),
    .status(mac_status)
  );
`endif

 // Accumulator state update
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      acc_q <= 32'h0000_0000;
    end else if (acc_clear) begin
      acc_q <= 32'h0000_0000;
    end else if (mac_out_pulse) begin
      // capture MAC result exactly when it emerges
      acc_q <= mac_z;
    end
  end

  // ----------------------------------------------------------------
  // Pack outputs at c_valid edge
  // ----------------------------------------------------------------
  // TODO: replace stubs with real packers (instantiate both FP8 formats and BF16, then mux)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      c_out_fp8  <= 8'h00;
      c_out_bf16 <= 16'h0000;
    end else if (c_valid) begin
      // BF16 stub: take top 16 bits of IEEE754 f32
      c_out_bf16 <= acc_q[31:16];  // <- use acc_q, not mac_z
      c_out_fp8  <= 8'h01;
    end
  end

endmodule


