
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


// // A flows west->east; single-shot: accept one pair in IDLE, hold result in MAC until consumed.
module mac_cell (
  input  logic         clk,
  input  logic         rst_n,

  input  logic         mode_fp8,         // 0:E4M3, 1:E5M2
  input  logic         out_bf16_en,      // (unused here; BF16 boundary)

  // Data
  input  logic  [7:0]  a_raw,
  input  logic  [7:0]  b_raw,
  output logic  [7:0]  a_out,

  // Handshakes
  input  logic         valid_in,         // upstream has (a_raw,b_raw)
  input  logic         output_ready,     // downstream can consume our result
  output logic         input_ready_take, // we can accept one pair now
  output logic         mac_valid,        // result valid for downstream
  output logic         done,             // same as mac_valid (level)

  // Output data
  output logic [15:0]  mac_packed_bf
);

  // ======== Datapath internals ========
  logic [31:0] a_fp32_e4, a_fp32_e5, b_fp32_e4, b_fp32_e5;
  logic [31:0] a_float32, b_float32;
  logic [31:0] mac_z;                // combinational a*b + c
  logic [31:0] z_reg;                // latched final result (FP32)
  logic [31:0] c_reg;                // accumulator (single-shot => 0)
  logic [15:0] bf16_comb;            // BF16 of z_reg (combinational)
  logic [7:0]  mac_status;           // unused

  // "hold" gates MAC inputs (zeroes them) while in IDLE/MAC as commanded by the FSM
  logic        hold, take;            // take=1 when we accept new input pair
  logic [31:0] a_mac, b_mac, c_mac;

  // ======== Unpack FP8 -> FP32 & select format ========
  Float8_unpack #(.E(4), .M(3)) u_unpack_a_e4 (.fp8_in(a_raw), .f32_out(a_fp32_e4));
  Float8_unpack #(.E(4), .M(3)) u_unpack_b_e4 (.fp8_in(b_raw), .f32_out(b_fp32_e4));
  Float8_unpack #(.E(5), .M(2)) u_unpack_a_e5 (.fp8_in(a_raw), .f32_out(a_fp32_e5));
  Float8_unpack #(.E(5), .M(2)) u_unpack_b_e5 (.fp8_in(b_raw), .f32_out(b_fp32_e5));

  assign a_float32 = mode_fp8 ? a_fp32_e5 : a_fp32_e4;
  assign b_float32 = mode_fp8 ? b_fp32_e5 : b_fp32_e4;

  // Gate MAC inputs with hold (when hold=1, MAC sees zeros and does no work)
  assign {a_mac, b_mac, c_mac} = hold ? {32'h0, 32'h0, 32'h0} : {a_float32, b_float32, c_reg};       // single-shot keeps c_reg at 0 anyway

  // ======== FP MAC core (combinational) ========
`ifdef USE_DW
  DW_fp_mac #(.sig_width(23), .exp_width(8), .ieee_compliance(1)) u_mac (
    .a(a_mac), .b(b_mac), .c(c_mac), .rnd(3'b000), .z(mac_z), .status(mac_status)
  );
`else
  sim_fp_mac #(.sig_width(23), .exp_width(8), .ieee_compliance(1), .LATENCY(0)) u_mac (
    .a(a_mac), .b(b_mac), .c(c_mac), .rnd(3'b000), .z(mac_z), .status(mac_status)
  );
`endif

  // Pack the *latched* result to present a stable BF16 in MAC state
  bf16_pack u_pack (.f32_i(z_reg), .bf16_o(bf16_comb));

  // ======== FSM control ========
  typedef enum logic [0:0] { IDLE=1'b0, MAC=1'b1 } state_t;
  state_t state, next_state;

  // State flop
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      state <= IDLE;
    else
      state <= next_state;
  end

  // Next-state & control outputs
  always_comb begin
    // defaults
    next_state        = state;
    input_ready_take  = 1'b0;
    mac_valid         = 1'b0;
    done              = 1'b0;
    hold              = 1'b0;
    take              = 1'b0;

    case (state)
      IDLE: begin
        input_ready_take = 1'b1;     // we can accept one pair now
        take = 1'b1;
        if (valid_in)               // accept this one pair
          next_state = MAC;         // then move to holding state
      end

      MAC: begin
        done       = 1'b1;
        hold       = 1'b1;          // gate MAC inputs while holding
        if (output_ready)           // downstream consumed our result
          next_state = IDLE;        // re-arm for the next pair
          mac_valid  = 1'b1;          // present held result
      end
    endcase
  end

  // ======== Datapath registers ========
  // Latch result on accept; keep c_reg at zero for single-shot; register outputs
  // "take" happens when we are in IDLE and upstream presents valid_in


  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      z_reg         <= 32'h0;
      c_reg         <= 32'h0;
      a_out         <= 8'h00;
      mac_packed_bf <= 16'h0000;
    end else begin
      a_out         <= a_raw;          // systolic pass-through (1-cycle)
      mac_packed_bf <= bf16_comb;      // register BF16 boundary

      if (take)
        z_reg <= mac_z;                // capture a*b (+c) once

      // single-shot: keep accumulator at zero; (for K>1, update c_reg on 'take')
      c_reg <= 32'h0;
    end
  end

  // // synopsys translate_off
  // // Simple sanity: outputs shouldn’t be X after reset
  // always @(posedge clk) if (rst_n) begin
  //   if ($isunknown({mac_valid, input_ready_take, mac_packed_bf, a_out}))
  //     $error("mac_cell: X detected on outputs at t=%0t", $time);
  // end
  // // synopsys translate_on

endmodule
