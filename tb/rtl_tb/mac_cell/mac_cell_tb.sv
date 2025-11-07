
module mac_cell_tb;

  // Clock and reset
  logic clk;
  logic rst_n;

  // Inputs (to DUT)
  logic        mode_fp8;
  logic        out_bf16_en;
  logic        valid_in;
  logic        output_ready;

  // Outputs (from DUT)
  logic        input_ready_take;
  logic        mac_valid;
  logic        done;
  logic [7:0]  a_out;
  logic [15:0] mac_packed_bf;

  // Data
  logic [7:0]  a_raw, b_raw;

  // DUT
  mac_cell dut (
    .clk              (clk),
    .rst_n            (rst_n),

    .mode_fp8         (mode_fp8),
    .out_bf16_en      (out_bf16_en),

    .a_raw            (a_raw),
    .b_raw            (b_raw),
    .a_out            (a_out),
    .mac_packed_bf    (mac_packed_bf),

    .valid_in         (valid_in),
    .output_ready     (output_ready),
    .input_ready_take (input_ready_take),
    .mac_valid        (mac_valid),
    .done             (done)
  );

  initial begin
    $monitor("Time:%0t | mode:%0b | a:%02h b:%02h || a_out:%02h | C_bf16:%04h | in_rdy:%0b | v_in:%0b | mac_valid:%0b | out_rdy:%0b | done:%0b",
             $time, mode_fp8, a_raw, b_raw, a_out, mac_packed_bf,
             input_ready_take, valid_in, mac_valid, output_ready, done);
  end

  // Clock
  always #10 clk = ~clk; // 50 MHz

  // Stimulus
  initial begin
    // ---- init ----
    clk            = 0;
    rst_n          = 0;
    mode_fp8       = 0;
    out_bf16_en    = 1;
    a_raw          = 8'h00;
    b_raw          = 8'h00;
    valid_in       = 0;
    output_ready   = 0;

    // Release reset
    @(posedge clk);
    @(negedge clk);
    rst_n = 1;

    // ---------------- E4M3 single-shot ----------------
    mode_fp8 = 0;          // E4M3
    a_raw    = 8'h3C;
    b_raw    = 8'h42;

    // Wait until PE can accept
    @(posedge clk);
    wait (input_ready_take == 1'b1);

    // Pulse valid_in for exactly one cycle to submit the operands
    valid_in = 1'b1;
    @(posedge clk);
    valid_in = 1'b0;

    // Wait for mac_valid (result available & held)
    fork
      begin : mac_val
        @(posedge mac_valid);
        $display("%0t: MAC operation completed in E4M3 mode.", $time);
        disable timeout;
      end
      begin : timeout
        repeat (10) @(posedge clk);
        $error("%0t: TIMEOUT waiting for mac_valid (E4M3).", $time);
      end
    join_any
    disable fork;

    // Consume the result: pulse output_ready for one cycle
    output_ready = 1'b1;
    @(posedge clk);
    output_ready = 1'b0;

    // ---------------- E5M2 single-shot ----------------
    mode_fp8 = 1;          // E5M2
    a_raw    = 8'h42;
    b_raw    = 8'h3C;

    // Wait until PE can accept
    @(posedge clk);
    wait (input_ready_take == 1'b1);

    // Submit operands
    valid_in = 1'b1;
    @(posedge clk);
    valid_in = 1'b0;

    // Wait for mac_valid (result available & held)
    fork
      begin : mac_val2
        @(posedge mac_valid);
        $display("%0t: MAC operation completed in E5M2 mode.", $time);
        disable timeout2;
      end
      begin : timeout2
        repeat (10) @(posedge clk);
        $error("%0t: TIMEOUT waiting for mac_valid (E5M2).", $time);
      end
    join_any
    disable fork;

    // Consume the result
    output_ready = 1'b1;
    @(posedge clk);
    output_ready = 1'b0;

    $display("[TB] Done");
    $stop();
  end

endmodule


