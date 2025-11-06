
module mac_cell_tb;

  // Clock/Reset
  logic clk = 0;
  logic rst_n = 0;
  always #5 clk = ~clk;  // 100 MHz

  // DUT IO
  logic         mode_fp8;
  logic         out_bf16_en;
  logic         valid_in_a, valid_in_b;
  logic         ready_in_a, ready_in_b;
  logic  [7:0]  a_in, b_in;
  logic  [7:0]  a_out, b_out;
  logic         valid_out_a, valid_out_b;
  logic         acc_clear, acc_en;
  logic  [7:0]  c_out_fp8;
  logic [15:0]  c_out_bf16;
  logic         c_valid;

    // --- add near top of TB ---
  logic [31:0] a_f32, b_f32;
  logic [7:0]  a_fp8, b_fp8;

  Float8_pack #(.E(4), .M(3)) tb_pack_a (.f32_i(a_f32), .fp8_o(a_fp8), .sat_o());
  Float8_pack #(.E(4), .M(3)) tb_pack_b (.f32_i(b_f32), .fp8_o(b_fp8), .sat_o());

  // DUT
  mac_cell #(.ACC_STAGES(1)) dut (
    .clk, .rst_n,
    .mode_fp8, .out_bf16_en,
    .valid_in_a, .valid_in_b,
    .ready_in_a, .ready_in_b,
    .a_in, .b_in,
    .a_out, .b_out,
    .valid_out_a, .valid_out_b,
    .acc_clear, .acc_en,
    .c_out_fp8, .c_out_bf16, .c_valid
  );

  // Simple monitors
  initial begin
    $display("[TB] Start");
    mode_fp8      = 1'b0;  // E4M3
    out_bf16_en   = 1'b1;
    valid_in_a    = 1'b0;
    valid_in_b    = 1'b0;
    a_in = '0; b_in = '0;
    acc_clear = 1'b0;
    acc_en    = 1'b0;

    $monitor("%0t %s%s%s",
      $time,
      (valid_out_a ? $sformatf(" A=%02h", a_out) : ""),
      (valid_out_b ? $sformatf(" B=%02h", b_out) : ""),
      (c_valid     ? $sformatf(" C:fp8=%02h bf16=%04h", c_out_fp8, c_out_bf16) : "")
    );


    // Reset
    repeat (2) @(posedge clk);
    rst_n = 0;
    repeat (5) @(posedge clk);
    rst_n = 1;
    repeat (2) @(posedge clk);

    a_f32 = 32'h3F800000; // 1.0f
    b_f32 = 32'h40000000; // 2.0f

    @(posedge clk);
    a_in = a_fp8; b_in = b_fp8;
    valid_in_a = 1; valid_in_b = 1; acc_en = 1;

    @(posedge clk);
    valid_in_a = 0; valid_in_b = 0; acc_en = 0;

    // Fire 2: + 1.0 * 1.0 => 3.0 total (if no acc_clear)
    repeat (3) @(posedge clk);
    a_f32 = 32'h3F800000; // 1.0f
    b_f32 = 32'h3F800000; // 1.0f

    @(posedge clk);
    a_in = a_fp8; b_in = b_fp8;
    valid_in_a = 1; valid_in_b = 1; acc_en = 1;

    @(posedge clk);
    valid_in_a = 0; valid_in_b = 0; acc_en = 0;

    // Expect: pass-through valids one cycle after inputs; c_valid after ACC_STAGES
    repeat (10) @(posedge clk);
    $display("[TB] Done");
    $stop();
  end

endmodule

