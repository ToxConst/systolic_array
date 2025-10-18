module systolic_tile #(
  parameter N = 8,
  parameter IN_W = 8,
  parameter ACC_W = 32
)(
  input  logic             clk,
  input  logic             rst_n,
  input  logic             a_valid,
  output logic             a_ready,
  input  logic [N*8-1:0]   a_row,
  input  logic             b_valid,
  output logic             b_ready,
  input  logic [N*8-1:0]   b_col,
  output logic             c_valid,
  input  logic             c_ready,
  output logic [N*16-1:0]  c_row
);
  assign a_ready = 1'b1;
  assign b_ready = 1'b1;
  assign c_valid = 1'b0;
  assign c_row   = '0;
endmodule
