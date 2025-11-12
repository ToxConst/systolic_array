// A flows west->east; single-shot: accept one pair in IDLE, hold result in MAC until consumed.
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
  input  logic         a_valid_in,
  input  logic         mac_valid_in,

  input  logic         output_ready,     // downstream can consume our result
  output logic         input_ready_take, // we can accept one pair now
  output logic         mac_valid,        // result valid for downstream
  output logic         a_valid_out,
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
  logic        valid_in, a_valid_in_gated, mac_valid_in_gated, clear_valids;        // handshake

  // "hold" gates MAC inputs (zeroes them) while in IDLE/MAC as commanded by the FSM
  logic        hold, take;            // take=1 when we accept new input pair
  logic [31:0] a_mac, b_mac, c_mac;


  //MAC FSM
  typedef enum reg{ IDLE, MAC} state_t;
  state_t state, next_state;

  //Handshake FSM
  typedef enum reg { WAIT, AHA } state_2;
  state_2 state2, nextState2;

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

  //Valid register
  always_ff @(posedge clk)
    if(clear_valids) begin
      a_valid_in_gated <= 0;
      mac_valid_in_gated <= 0;
      a_valid_out <= 0;
    end

    else begin
      a_valid_in_gated <= a_valid_in;
      mac_valid_in_gated <= mac_valid_in;
    end


  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      z_reg         <= 32'h0;
     // c_reg         <= 32'h0;
      a_out         <= 8'h00;
      mac_packed_bf <= 16'h0000;
      a_valid_out   <= 0;
    end else begin
      a_valid_out <= 1;
      a_out         <= a_raw;          // systolic pass-through (1-cycle)
      mac_packed_bf <= bf16_comb;      // register BF16 boundary

      if (take)
        z_reg <= mac_z;                // capture a*b (+c) once

      // // single-shot: keep accumulator at zero; (for K>1, update c_reg on 'take')
      // c_reg <= 32'h0;
    end
  end



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
        if (valid_in)  begin             // accept this one pair
          // clear_valids = 1;
          next_state = MAC;                               // then move to holding state
        end
      end

      MAC: begin
        done       = 1'b1;
        hold       = 1'b1;          // gate MAC inputs while holding
        mac_valid  = 1'b1;          // present held result
        if (output_ready) begin           // downstream consumed our result
          next_state = IDLE;        // re-arm for the next pair
        end
      end
    endcase
  end

  // ======== Datapath registers ========
  // Latch result on accept; keep c_reg at zero for single-shot; register outputs
  // "take" happens when we are in IDLE and upstream presents valid_in


  //HANDSHAKE FSM
  always_ff @(posedge clk, negedge rst_n)
    if(!rst_n)
      state2 <= WAIT;
    else
      state2 <= nextState2;

  always_comb begin
    clear_valids = 0;
    valid_in = 0;
    nextState2 = state2;

    case (state2)
      WAIT :
        if(mac_valid_in_gated  &  a_valid_in_gated) begin
          valid_in = 1;
          clear_valids = 1;
          nextState2 = AHA;
        end
      AHA :
        nextState2 = WAIT;
    endcase
  end

endmodule
