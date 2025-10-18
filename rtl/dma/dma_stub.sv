module dma_stub #(
  parameter N = 8,
  parameter BYTES = 8
)(
  input  logic clk, rst_n,
  output logic mem_req,
  input  logic mem_gnt,
  output logic [31:0] mem_addr,
  input  logic [63:0] mem_rdata,
  output logic [63:0] mem_wdata,
  output logic mem_we,
  output logic a_valid,
  input  logic a_ready,
  output logic [N*8-1:0] a_row,
  output logic b_valid,
  input  logic b_ready,
  output logic [N*8-1:0] b_col,
  input  logic c_valid,
  output logic c_ready,
  input  logic [N*16-1:0] c_row
);
  assign mem_req = 1'b0;
  assign mem_addr = '0;
  assign mem_wdata = '0;
  assign mem_we = 1'b0;
  assign a_valid = 1'b0;
  assign a_row = '0;
  assign b_valid = 1'b0;
  assign b_col = '0;
  assign c_ready = 1'b1;
endmodule
