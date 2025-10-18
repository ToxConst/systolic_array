module saturate_round #(
  parameter ACC_W = 32
)(
  input  logic          clk,
  input  logic          rst_n,
  input  logic  [1:0]   mode,   // 0:E4M3 1:E5M2 2:BF16
  input  logic          use_stochastic,
  input  logic [ACC_W-1:0] acc_in,
  input  logic [15:0]   rand_bits, // for stochastic rounding if enabled
  output logic [15:0]   q_out,     // 16b to cover BF16; FP8 uses low byte
  output logic          sat
);
  assign q_out = '0;
  assign sat   = 1'b0;
endmodule
