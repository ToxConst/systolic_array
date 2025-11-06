// Systolic PE with three streams: A-east (FP8), B-south (FP8), C-south (FP32/BF16)
module mac_cell #(
  parameter int MAC_LAT     = 1,   // latency of the MAC core (matches sim DW)
  parameter int ACC_STAGES  = 1,   // extra output pipe after MAC (>=1)
  parameter bit PIPE_AB_1CYC= 1    // 1: register A/B pass-through by one cycle
) (
  input  logic        clk,
  input  logic        rst_n,

  // Control
  input  logic        mode_fp8,       // 0:E4M3, 1:E5M2
  input  logic        out_bf16_en,    // 1: also produce BF16
  input  logic        clr_acc,        // top row or new window: inject psum=0 for next MAC

  // A stream (west -> east), FP8
  input  logic        valid_in_a,
  output logic        ready_in_a,
  input  logic [7:0]  a_in,
  output logic        valid_out_a,
  input  logic        ready_out_a,
  output logic [7:0]  a_out,

  // B stream (north -> south), FP8
  input  logic        valid_in_b,
  output logic        ready_in_b,
  input  logic [7:0]  b_in,
  output logic        valid_out_b,
  input  logic        ready_out_b,
  output logic [7:0]  b_out,

  // C stream (north -> south), FP32/BF16 partial sums/results
  input  logic        valid_in_c,          // psum from north (0/ignored when clr_acc=1)
  output logic        ready_in_c,
  input  logic [31:0] c_in_fp32,

  output logic        valid_out_c,
  input  logic        ready_out_c,
  output logic [31:0] acc_fp32,            // psum/result southbound
  output logic [15:0] acc_bf16,            // optional BF16 (gated by out_bf16_en)

  // Status for the C stream (aligned with valid_out_c)
  output logic [7:0]  mac_status_o
);
  // Local parameters
  localparam int L = (ACC_STAGES < 1) ? 1 : ACC_STAGES;

  logic        v_a_q, v_b_q;
  logic [7:0]  d_a_q, d_b_q;

  // Handshake & do_mac for this cycle (accept only when we have all three)
  // If clr_acc=1, allow MAC even if valid_in_c=0 (top row injects zero)
  logic all_inputs_valid = valid_in_a & valid_in_b & (valid_in_c | clr_acc);

  // ----------------------------
  // 1) FP8 -> FP32 unpack
  // ----------------------------
  logic [31:0] a_fp32_e4, b_fp32_e4;
  logic [31:0] a_fp32_e5, b_fp32_e5;
  logic [31:0] a_fp32,    b_fp32;


  logic [31:0] acc_pipe [0:L];   // [0] feeds MAC.c, [1] captures mac_z, ... [L] -> output
  logic        vld_pipe [0:L];
  logic [7:0]  stat_pipe[0:L];

  logic [15:0] bf16_packed;

  Float8_unpack #(.E(4), .M(3)) u_unpack_a_e4 (.fp8_in(a_in), .f32_out(a_fp32_e4));
  Float8_unpack #(.E(4), .M(3)) u_unpack_b_e4 (.fp8_in(b_in), .f32_out(b_fp32_e4));
  Float8_unpack #(.E(5), .M(2)) u_unpack_a_e5 (.fp8_in(a_in), .f32_out(a_fp32_e5));
  Float8_unpack #(.E(5), .M(2)) u_unpack_b_e5 (.fp8_in(b_in), .f32_out(b_fp32_e5));

  always_comb begin
    unique case (mode_fp8)
      1'b0: begin a_fp32 = a_fp32_e4; b_fp32 = b_fp32_e4; end // E4M3
      1'b1: begin a_fp32 = a_fp32_e5; b_fp32 = b_fp32_e5; end // E5M2
      default: begin a_fp32 = 32'h7FC0_0000; b_fp32 = 32'h7FC0_0000; end // qNaN
    endcase
  end

  // ----------------------------
  // 2) A/B pass-through lanes
  // ----------------------------
  generate if (PIPE_AB_1CYC) begin : g_ab_pipe
    // simple 1-deep elastic buffer per lane

    assign ready_in_a = ~v_a_q | ready_out_a;
    assign ready_in_b = ~v_b_q | ready_out_b;

    always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        v_a_q <= 1'b0; d_a_q <= '0;
        v_b_q <= 1'b0; d_b_q <= '0;
      end else begin
        // A lane
        if (ready_in_a && valid_in_a) begin
          v_a_q <= 1'b1;
          d_a_q <= a_in;
        end else if (ready_out_a && v_a_q) begin
          v_a_q <= 1'b0;
        end
        // B lane
        if (ready_in_b && valid_in_b) begin
          v_b_q <= 1'b1;
          d_b_q <= b_in;
        end else if (ready_out_b && v_b_q) begin
          v_b_q <= 1'b0;
        end
      end
    end

    assign valid_out_a = v_a_q;
    assign a_out       = d_a_q;
    assign valid_out_b = v_b_q;
    assign b_out       = d_b_q;

  end else begin : g_ab_wire
    // direct wire-through (no backpressure supported)
    assign ready_in_a  = ready_out_a; // usually 1'b1 in wire mode
    assign ready_in_b  = ready_out_b;
    assign valid_out_a = valid_in_a;
    assign valid_out_b = valid_in_b;
    assign a_out       = a_in;
    assign b_out       = b_in;
  end
  endgenerate

  // ----------------------------
  // 3) Accumulator pipeline (C stream)
  //    In array mode: z comes from the north (c_in_fp32), or 0 when clr_acc=1
  // ----------------------------

  // Ready on C-in: 1 if we will consume it (either it's valid, or clr_acc lets us ignore it)
  // For now we don’t implement deeper buffering on C; ready follows downstream readiness loosely.
  assign ready_in_c = 1'b1; // simple model; upgrade to elastic if needed

  // Head of pipe
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      acc_pipe[0] <= 32'd0;
      vld_pipe[0] <= 1'b0;
      stat_pipe[0]<= 8'd0;
    end else begin
      vld_pipe[0] <= all_inputs_valid;
      // z source: c_in or zero on clear
      acc_pipe[0] <= (clr_acc) ? 32'd0 : c_in_fp32;
      stat_pipe[0]<= 8'd0;
    end
  end

  // The FP MAC
  logic [31:0] mac_z;
  logic [7:0]  mac_status;

`ifdef USE_DW
  DW_fp_mac #(
    .sig_width(23), .exp_width(8), .ieee_compliance(1)
  ) u_mac (
    .a   (a_fp32),
    .b   (b_fp32),
    .c   (acc_pipe[0]),
    .rnd (3'b000),        // RNE
    .z   (mac_z),
    .status(mac_status)
  );
`else
  sim_fp_mac #(
    .sig_width(23), .exp_width(8), .ieee_compliance(1),
    .LATENCY(MAC_LAT)
  ) u_mac (
    .a   (a_fp32),
    .b   (b_fp32),
    .c   (acc_pipe[0]),
    .rnd (3'b000),
    .z   (mac_z),
    .status(mac_status)
  );
`endif

  // Register MAC output + shift pipeline
  genvar gi;
  generate
    for (gi = 1; gi <= L; gi++) begin : g_acc
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          acc_pipe[gi] <= 32'd0;
          vld_pipe[gi] <= 1'b0;
          stat_pipe[gi]<= 8'd0;
        end else begin
          acc_pipe[gi] <= (gi == 1) ? mac_z        : acc_pipe[gi-1];
          vld_pipe[gi] <= (gi == 1) ? vld_pipe[0]  : vld_pipe[gi-1];
          stat_pipe[gi]<= (gi == 1) ? mac_status   : stat_pipe[gi-1];
        end
      end
    end
  endgenerate

  // Tail -> C southbound
  // (You can add an elastic buffer here if you want backpressure via ready_out_c)
  assign acc_fp32     = acc_pipe[L];
  assign mac_status_o = stat_pipe[L];

  // Optional BF16 pack

  bf16_pack u_bf16_pack (.fp32_i(acc_fp32), .bf16_o(bf16_packed));
  assign acc_bf16 = out_bf16_en ? bf16_packed : 16'd0;

  // Valid management for C
  // If you need true backpressure, insert a 1-deep skid: here we assume ready_out_c==1.
  assign valid_out_c = vld_pipe[L] & ready_out_c;

endmodule


