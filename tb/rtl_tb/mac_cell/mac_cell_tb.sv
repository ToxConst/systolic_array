module mac_cell_tb;


  int unsigned SEED = 32'hC0FFEE01;
  localparam int TRIALS = 1000;
  int timeouts;

  function automatic [7:0] rand8();
    SEED = $urandom(SEED);
    return SEED[7:0];
  endfunction

  function automatic bit rand1();
    SEED = $urandom(SEED);
    return SEED[0];
  endfunction

  // Optional: inject interesting corner cases every so often
  function automatic [7:0] corner8(int i, bit e5m2);
    // A tiny pool: {+0, -0, tiny subnormal, 1.0, max normal, Inf, NaN}
    case (i % 7)
      0:   return 8'h00;                   // +0
      1:   return 8'h80;                   // -0
      2:   return e5m2 ? 8'h01 : 8'h01;    // smallest subnormal (works for both)
      3:   return e5m2 ? 8'h3C : 8'h38;    // ~1.0 encodings differ by format
      4:   return e5m2 ? 8'h7B : 8'h77;    // near max normal
      5:   return e5m2 ? 8'h7C : 8'h78;    // +Inf
      default: return e5m2 ? 8'h7F : 8'h7F;// NaN
    endcase
  endfunction

  bit e5m2;

  byte a_rand;
  byte b_rand;
  byte a_val;
  byte b_val;
  int cycles;
  int t;
  // Clock and reset
  logic clk;
  logic rst_n;

  // Inputs (to DUT)
  logic        mode_fp8;
  logic        out_bf16_en;
  logic        output_ready;

  // Outputs (from DUT)
  logic        input_ready_take;
  logic        mac_valid;
  logic        done, a_valid_in, mac_valid_in, a_valid_out;
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

    .a_valid_in       (a_valid_in),
    .mac_valid_in     (mac_valid_in),
    .output_ready     (output_ready),
    .input_ready_take (input_ready_take),
    .mac_valid        (mac_valid),
    .done             (done),
    .a_valid_out      (a_valid_out)
  );

  initial begin
    $monitor("Time:%0t | mode:%0b | a:%02h b:%02h || a_out:%02h | C_bf16:%04h | in_rdy:%0b | a_in_vld:%0b | mac_valid_in:%0b | mac_valid:%0b | out_rdy:%0b | done:%0b",
             $time, mode_fp8, a_raw, b_raw, a_out, mac_packed_bf,
             input_ready_take, a_valid_in, mac_valid_in,  mac_valid, output_ready, done);
  end

  // Clock
  always #10 clk = ~clk; // 50 MHz

  // Stimulus
  initial begin
    timeouts = 0;
    // ---- init ----
    clk            = 0;
    rst_n          = 0;
    mode_fp8       = 0;
    out_bf16_en    = 1;
    a_raw          = 8'h00;
    b_raw          = 8'h00;
    a_valid_in     = 0;
    mac_valid_in   = 0;
    output_ready   = 0;

    // Release reset
    @(posedge clk);
    @(negedge clk);
    rst_n = 1;

    // // ---------------- E4M3 single-shot ----------------
    // mode_fp8 = 0;          // E4M3
    // a_raw    = 8'h3C;
    // b_raw    = 8'h42;

    // // Wait until PE can accept
    // @(posedge clk);
    // wait (input_ready_take == 1'b1);

    // // Pulse valid_in for exactly one cycle to submit the operands
    // a_valid_in = 1'b1;
    // mac_valid_in = 1'b1;
    // @(posedge clk);
    // a_valid_in = 1'b0;
    // mac_valid_in = 1'b0;

    // // Wait for mac_valid (result available & held)
    // fork
    //   begin : mac_val
    //     @(posedge mac_valid);
    //     $display("%0t: MAC operation completed in E4M3 mode.", $time);
    //     disable timeout;
    //   end
    //   begin : timeout
    //     repeat (10) @(posedge clk);
    //     $error("%0t: TIMEOUT waiting for mac_valid (E4M3).", $time);
    //   end
    // join_any
    // disable fork;

    // // Consume the result: pulse output_ready for one cycle
    // output_ready = 1'b1;
    // @(posedge clk);
    // output_ready = 1'b0;

    // // ---------------- E5M2 single-shot ----------------
    // mode_fp8 = 1;          // E5M2
    // a_raw    = 8'h42;
    // b_raw    = 8'h3C;

    // // Wait until PE can accept
    // @(posedge clk);
    // wait (input_ready_take == 1'b1);

    // // Submit operands
    // a_valid_in = 1'b1;
    // mac_valid_in = 1'b1;
    // @(posedge clk);
    // a_valid_in = 1'b0;
    // mac_valid_in = 1'b0;

    // // Wait for mac_valid (result available & held)
    // fork
    //   begin : mac_val2
    //     @(posedge mac_valid);
    //     $display("%0t: MAC operation completed in E5M2 mode.", $time);
    //     disable timeout2;
    //   end
    //   begin : timeout2
    //     repeat (10) @(posedge clk);
    //     $error("%0t: TIMEOUT waiting for mac_valid (E5M2).", $time);
    //   end
    // join_any
    // disable fork;

    // // Consume the result
    // output_ready = 1'b1;
    // @(posedge clk);
    // output_ready = 1'b0;

    // $display("[TB] Done");


    //Looped attempt
    for (t = 0; t < TRIALS; t++) begin
      // Randomize mode and operands (bias in some corners)
      mode_fp8 = rand1();  // 0:E4M3, 1:E5M2
      e5m2 = mode_fp8;

      a_rand = rand8();
      b_rand = rand8();
      a_val  = (t % 13 == 0) ? corner8(t, e5m2) : a_rand;
      b_val  = (t % 17 == 0) ? corner8(t+5, e5m2) : b_rand;

      // Drive operands
      a_raw = a_val;
      b_raw = b_val;

      // Wait until DUT is ready to take a pair
      @(posedge clk);
      wait (input_ready_take == 1'b1);

      // Pulse both valids for exactly one cycle
      a_valid_in    = 1'b1;
      mac_valid_in  = 1'b1;
      @(posedge clk);
      a_valid_in    = 1'b0;
      mac_valid_in  = 1'b0;

      // Wait for result valid with a cycle timeout
      cycles = 0;
      while (!mac_valid && cycles < 100) begin
        @(posedge clk);
        cycles++;
      end

      if (!mac_valid) begin
        $error("%0t [TRIAL %0d]: TIMEOUT waiting for mac_valid (mode=%0d a=%02h b=%02h)",
              $time, t, mode_fp8, a_val, b_val);
        timeouts++;
      end else begin
        // Optional random backpressure before consuming
        repeat ($urandom_range(0,3)) @(posedge clk);

        // Consume result (1-cycle pulse)
        output_ready = 1'b1;
        @(posedge clk);
        output_ready = 1'b0;

        // Log occasionally
        if ((t % 100) == 0)
          $display("%0t [TRIAL %0d]: mode=%0d a=%02h b=%02h -> consumed result",
                  $time, t, mode_fp8, a_val, b_val);
      end
  end

  $display("[TB] Completed %0d trials, timeouts=%0d", TRIALS, timeouts);
  if (timeouts == 0) $display("[TB] PASS (no timeouts).");
  $stop();
  end

endmodule