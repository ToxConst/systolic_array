
module mac_cell_tb;

  // Clock and reset
  logic clk;
  logic rst_n;

  // Inputs
  logic        mode_fp8, clear_accum, mac_valid, valid_in;
  logic        out_bf16_en;
  logic [7:0]  a_raw, b_raw;

  // Outputs
  logic [7:0]  a_out;
  logic [15:0] mac_packed_bf;

  // Instantiate the DUT
  mac_cell dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .mode_fp8      (mode_fp8),
    .out_bf16_en   (out_bf16_en),
    .a_raw         (a_raw),
    .b_raw         (b_raw),
    .a_out         (a_out),
    .clear_accum   (clear_accum),
    .mac_packed_bf (mac_packed_bf),
    .mac_valid     (mac_valid),
    .valid_in      (valid_in)
  );

  initial begin
    $monitor("Time: %0t | mode_fp8: %b | out_bf16_en: %b | a_raw: %h | b_raw: %h || a_out: %h | mac_packed_bf: %h",
              $time, mode_fp8, out_bf16_en, a_raw, b_raw, a_out, mac_packed_bf);
  end

  // Clock generation
  initial begin
    clk = 0;
    rst_n = 0;

    @(posedge clk);
    @(negedge clk);
    rst_n = 1;

    // Test sequence
    mode_fp8 = 0; // E4M3
    out_bf16_en = 1;
    a_raw = 8'h3C; // Example FP8 value
    b_raw = 8'h42; // Example FP8 value
    valid_in = 1;

    @(posedge clk);
    valid_in = 0;

    fork
      begin : mac_val
        @(posedge mac_valid);
        $display("MAC operation completed in E4M3 mode.");
        disable timeout;
      end

      begin : timeout
        repeat(10) @(posedge clk);
        $display("mac_valid didnt go high");
        $stop();
      end
    join


    @(posedge clk)
    clear_accum = 1;

    @(posedge clk);
    clear_accum = 0;
    mode_fp8 = 1; // E5M2
    a_raw = 8'h41; // Example FP8 value
    b_raw = 8'h3E; // Example FP8 value
    valid_in = 1;

    @(posedge clk);
    valid_in= 0;

    fork
      begin : mac_val2
        @(posedge mac_valid);
        $display("MAC operation completed in E5M2 mode.");
        disable timeout2;
      end

      begin : timeout2
        repeat(10) @(posedge clk);
        $display("mac_valid didnt go high");
        $stop();
      end
    join

    $stop();

  end

  always #10 clk = ~clk; // 50MHz clock
endmodule

