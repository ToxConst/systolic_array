`default_nettype none

module mac_cell #(
 parameter int ACC_STAGES = 2,
); (
  input  logic         clk, rst_n,
  input  logic         mode_fp8,       // 0: E4M3, 1: E5M2
  input  logic         out_bf16_en,     // 1: convert to BF16 on output
  input  logic         valid_in_a, valid_in_b,
  input  logic  [7:0]  a_in, b_in,      // FP8 inputs
  output logic         ready_in_a, ready_in_b,
  output logic  [7:0]  a_out, b_out,    // FP8 outputs for next cell
  output logic         valid_out_a, valid_out_b,
  output logic [15:0]  acc_bf16,        // packed output if out_bf16_en=1
  output logic [31:0]  acc_fp32,        // full precision accumulator output
  output logic         valid_out_c      // output valid
);

  // FP8 -> FP32 unpack
  logic [31:0] a_fp32_e4, b_fp32_e4;
  logic [31:0] a_fp32_e5, b_fp32_e5;
  logic [31:0] a_fp32,    b_fp32;

  // E4M3 path
  Float8_unpack #(.E(4), .M(3)) u_unpack_a_e4 (.fp8_in(a_in), .f32_out(a_fp32_e4));
  Float8_unpack #(.E(4), .M(3)) u_unpack_b_e4 (.fp8_in(b_in), .f32_out(b_fp32_e4));

  // E5M2 path
  Float8_unpack #(.E(5), .M(2)) u_unpack_a_e5 (.fp8_in(a_in), .f32_out(a_fp32_e5));
  Float8_unpack #(.E(5), .M(2)) u_unpack_b_e5 (.fp8_in(b_in), .f32_out(b_fp32_e5));

  // Runtime select
  always_comb begin
    unique case (mode_fp8)
      1'b0: begin a_fp32 = a_fp32_e4; b_fp32 = b_fp32_e4; end // E4M3
      1'b1: begin a_fp32 = a_fp32_e5; b_fp32 = b_fp32_e5; end // E5M2
      default: begin a_fp32 = 32'h7fc00000; b_fp32 = 32'h7fc00000; end // NaN fall-back
    endcase
  end



  //  Forwarding (systolic)

  // Simple 1-cycle pass-through; retime later if needed.
  assign a_out      = a_in;
  assign b_out      = b_in;
  assign valid_out_a = valid_in_a;
  assign valid_out_b = valid_in_b;

  // For now, always ready (no back-pressure). If you add FIFOs, gate these.
  assign ready_in_a = 1'b1;
  assign ready_in_b = 1'b1;


  //  Accumulator pipeline
  logic [31:0] acc_pipe   [0:ACC_STAGES];
  logic        vld_pipe   [0:ACC_STAGES];

  // init head of pipe
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      acc_pipe[0] <= 32'd0;
      vld_pipe[0] <= 1'b0;
    end else begin
      // valid when both inputs present (you can refine this condition)
      vld_pipe[0] <= valid_in_a & valid_in_b;
      // hold previous z by default; DW_fp_mac output will replace acc_pipe[1]
      acc_pipe[0] <= acc_pipe[ACC_STAGES]; // feedback last stage by default
    end
  end


  // 4) DW_fp_mac
  logic [31:0] mac_z;
  logic [7:0]  mac_status; // optional flags

// `define USE_DW  // uncomment when DW libs are available

`ifdef USE_DW
  DW_fp_mac #(
    .sig_width(23), .exp_width(8), .ieee_compliance(1), .arch_type(0)
  ) u_mac (
    .a(a_fp32), .b(b_fp32), .c(acc_pipe[0]),
    .rnd(3'b000), .z(mac_z), .status(mac_status)
  );
`else
  sim_fp_mac #(
    .sig_width(23), .exp_width(8), .ieee_compliance(1), .arch_type(0),
    .LATENCY(1)    // match pipeline
  ) u_mac (
    .a(a_fp32), .b(b_fp32), .c(acc_pipe[0]),
    .rnd(3'b000), .z(mac_z), .status(mac_status)
  );
`endif

  // 5) Register the pipeline
  // Stage 1 takes mac_z as the new value; then shift through ACC_STAGES
  genvar gi;
  generate
    for (gi = 1; gi <= ACC_STAGES; gi++) begin : g_acc
      always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
          acc_pipe[gi] <= 32'd0;
          vld_pipe[gi] <= 1'b0;
        end else begin
          acc_pipe[gi] <= (gi == 1) ? mac_z : acc_pipe[gi-1];
          vld_pipe[gi] <= (gi == 1) ? vld_pipe[0] : vld_pipe[gi-1];
        end
      end
    end
  endgenerate

  assign acc_fp32   = acc_pipe[ACC_STAGES];
  assign valid_out_c= vld_pipe[ACC_STAGES];

  //BF16 packer
  logic [15:0] bf16_packed;
  bf16_pack u_bf16_pack (
    .fp32_i (acc_fp32),
    .bf16_o (bf16_packed)
  );

  assign acc_bf16 = out_bf16_en ? bf16_packed : 16'd0;

endmodule

`default_nettype wire
