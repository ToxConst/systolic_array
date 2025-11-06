
// //A flows west to east, accumulated result goes out (a*b + c)
// module mac_cell (
//   input  logic         clk,
//   input  logic         rst_n,

//   input  logic         mode_fp8,       // 0:E4M3, 1:E5M2
//   input  logic         out_bf16_en,    // 1: drive BF16, else FP8

//   input logic clear_accum,

//   input logic [7:0] a_raw, b_raw,
//   output logic [7:0] a_out,
//   output logic [15:0] mac_packed_bf
//   output logic mac_valid
// );

//   logic [31:0] mac_z, c_in, a_fp32_e4, a_fp32_e5, b_fp32_e4, b_fp32_e5, a_float32, b_float32;
//   logic [7:0] mac_status, a_in, b_in;

//   logic [15:0] mac_packed;

//   always_ff@(posedge or negedge rst_n) begin
//     if(!rst_n) begin
//       a_in <= 0;
//       b_in <= 0;
//     end
//     else begin
//       a_in  <= a_raw;
//       b_in <= b_raw;
//       mac_valid <= 0;

//     end

//   end

//   always_ff@(posedge clk or negedge rst_n) begin
//     if(!rst_n) begin
//       mac_packed_bf <= 0;
//       mac_valid <= 0;
//       a_out <= 0;
//     end
//     else begin
//       mac_packed_bf <= mac_packed
//       mac_valid <= 1;
//       a_out <= a_raw;
//     end
//   end

//   //Mac feedback loop
//   always_ff@(posedge clk or negedge rst_n)
//     if(!rst_n) begin
//       c_in <= 0;

//     else if (clear_accum | mac_valid)
//       c_in <= 0;

//     else
//       c_in <= mac_z;
//   end


//   //E4M3 path
//   Float8_unpack #(.E(4), .M(3)) u_unpack_a_e4 (.fp8_in(a_raw), .f32_out(a_fp32_e4));
//   Float8_unpack #(.E(4), .M(3)) u_unpack_b_e4 (.fp8_in(b_raw), .f32_out(b_fp32_e4));

//   //E5M2 Path
//   Float8_unpack #(.E(5), .M(2)) u_unpack_a_e5 (.fp8_in(a_raw), .f32_out(a_fp32_e5));
//   Float8_unpack #(.E(5), .M(2)) u_unpack_b_e5 (.fp8_in(b_raw), .f32_out(b_fp32_e5));

//   //pack accum
//   bf16_pack output_packer(.f32_i(mac_z), .bf16_o(mac_packed));


//   //get unpacked input values
//   assign a_float32 = mac_valid ? 0 : mode_fp8 ? a_fp32_e5 : a_fp32_e4;
//   assign b_float32 = mac_valid ? 0 : mode_fp8 ? b_fp32_e5 : b_fp32_e4;

// ////////////////Uncomment to use designware//////////////////////////////////////////

//   //`define USE_DW

// ////////////////Uncomment to use designware//////////////////////////////////////////

//   //Feed mac
//   `ifdef USE_DW
//   DW_fp_mac #(
//     .sig_width(23), .exp_width(8), .ieee_compliance(1)
//   ) u_mac (
//     .a   (a_float32),
//     .b   (b_float32),
//     .c   (c_in),
//     .rnd (3'b000),        // RNE
//     .z   (mac_z),         //output
//     .status(mac_status)
//   );
// `else
//   sim_fp_mac #(
//     .sig_width(23), .exp_width(8), .ieee_compliance(1),
//     .LATENCY(0)
//   ) u_mac (
//     .a   (a_float32),
//     .b   (b_float32),
//     .c   (c_in),
//     .rnd (3'b000),
//     .z   (mac_z),          //output
//     .status(mac_status)
//   );
// `endif

// endmodule


// A flows west to east; accumulated result z = a*b + c (feedback via c_in)
// Single-shot mode: take exactly one MAC when valid_in=1, then hold until clear_accum.
module mac_cell (
  input  logic         clk,
  input  logic         rst_n,

  input  logic         mode_fp8,        // 0:E4M3, 1:E5M2
  input  logic         out_bf16_en,     // (unused here; BF16 boundary)
  input  logic         clear_accum,     // sync clear/start-over
  input  logic         valid_in,        // NEW: present a/b this cycle for ONE MAC

  input  logic [7:0]   a_raw,
  input  logic [7:0]   b_raw,
  output logic [7:0]   a_out,
  output logic [15:0]  mac_packed_bf,
  output logic         mac_valid,       // NEW: high when final result held (ready)
  output logic         done             // NEW: latched after one MAC
);

  // ---------- Internals ----------
  logic [31:0] a_fp32_e4, a_fp32_e5;
  logic [31:0] b_fp32_e4, b_fp32_e5;
  logic [31:0] a_float32, b_float32;

  logic [31:0] mac_z;       // combinational MAC result (f32 bits)
  logic [31:0] c_in;        // accumulator feedback (registered)
  logic [7:0]  mac_status;  // unused for now
  logic [15:0] mac_packed;  // combinational BF16 pack

  // ---------- Format select ----------
  // Unpack FP8 -> FP32
  Float8_unpack #(.E(4), .M(3)) u_unpack_a_e4 (.fp8_in(a_raw), .f32_out(a_fp32_e4));
  Float8_unpack #(.E(4), .M(3)) u_unpack_b_e4 (.fp8_in(b_raw), .f32_out(b_fp32_e4));
  Float8_unpack #(.E(5), .M(2)) u_unpack_a_e5 (.fp8_in(a_raw), .f32_out(a_fp32_e5));
  Float8_unpack #(.E(5), .M(2)) u_unpack_b_e5 (.fp8_in(b_raw), .f32_out(b_fp32_e5));

  assign a_float32 = mode_fp8 ? a_fp32_e5 : a_fp32_e4;
  assign b_float32 = mode_fp8 ? b_fp32_e5 : b_fp32_e4;

  // ---------- FP MAC core (combinational) ----------
`ifdef USE_DW
  DW_fp_mac #(
    .sig_width(23), .exp_width(8), .ieee_compliance(1)
  ) u_mac (
    .a      (a_float32),
    .b      (b_float32),
    .c      (c_in),
    .rnd    (3'b000),     // RNE
    .z      (mac_z),
    .status (mac_status)
  );
`else
  sim_fp_mac #(
    .sig_width(23), .exp_width(8), .ieee_compliance(1),
    .LATENCY(0)
  ) u_mac (
    .a      (a_float32),
    .b      (b_float32),
    .c      (c_in),
    .rnd    (3'b000),
    .z      (mac_z),
    .status (mac_status)
  );
`endif

  // ---------- One-shot control ----------
  // done: latches on first valid_in; clears on reset/clear_accum
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)           done <= 1'b0;
    else if (clear_accum) done <= 1'b0;
    else if (valid_in)    done <= 1'b1;     // take exactly one MAC
  end

  // mac_valid is high while result is held (same as done)
  always_ff @(posedge clk)
    mac_valid <= done;

  // ---------- Feedback / registered boundary ----------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      c_in          <= '0;
      a_out         <= '0;
      mac_packed_bf <= '0;
    end else if (clear_accum) begin
      c_in          <= '0;                 // restart accumulation
      a_out         <= a_raw;              // systolic pass-through
      mac_packed_bf <= mac_packed;         // register boundary output
    end else begin
      a_out         <= a_raw;
      mac_packed_bf <= mac_packed;
      // Update accumulator only on the one accepted MAC
      if (valid_in && !done)
        c_in <= mac_z;                     // capture z = a*b + c_in
      else
        c_in <= c_in;                      // hold thereafter
    end
  end

  // ---------- Pack FP32 -> BF16 (combinational) ----------
  bf16_pack u_output_packer (
    .f32_i  (mac_z),
    .bf16_o (mac_packed)
  );

endmodule
