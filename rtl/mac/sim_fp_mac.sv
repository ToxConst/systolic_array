// ---------------------------------------------
// Simulation-only FP MAC (DW_fp_mac drop-in)
//   z = a * b + c  (IEEE-ish via shortreal)
// Rounding/status are ignored for now.
// ---------------------------------------------
`default_nettype none
module sim_fp_mac #(
  parameter int sig_width = 23,   // kept for interface parity
  parameter int exp_width = 8,
  parameter bit ieee_compliance = 1,
  parameter int arch_type = 0,
  parameter int LATENCY = 1       // pipeline stages on z
)(
  input  logic [31:0] a, b, c,    // IEEE-754 single in bit form
  input  logic [2:0]  rnd,        // ignored in sim model
  output logic [31:0] z,          // IEEE-754 single in bit form
  output logic [7:0]  status      // all zeros for now
);
  // convert to shortreal, do the math, convert back
  shortreal ar, br, cr, zr;

  always_comb begin
    ar = $bitstoshortreal(a);
    br = $bitstoshortreal(b);
    cr = $bitstoshortreal(c);
    zr = (ar * br) + cr;          // do compute in 32-bit float
  end

  // Optional pipeline on output to mimic DW latency
  logic [31:0] z_pipe [0:LATENCY];
  integer i;

  always_comb z_pipe[0] = $shortrealtobits(zr);

  always_ff @(posedge $global_clock) begin
    for (i = 1; i <= LATENCY; i++) begin
      z_pipe[i] <= z_pipe[i-1];
    end
  end

  assign z      = z_pipe[LATENCY];
  assign status = 8'b0;
endmodule
`default_nettype wire
