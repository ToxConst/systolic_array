// ---------------------------------------------
// Simulation-only FP MAC (DW_fp_mac drop-in)
//   z = a * b + c (IEEE-ish via shortreal)
// Rounding/status ignored; combinational like DW.
// ---------------------------------------------
module sim_fp_mac #(
  parameter int sig_width = 23,   // kept for interface parity
  parameter int exp_width = 8,
  parameter bit ieee_compliance = 1,
  parameter int LATENCY = 0       // not used here; keep for parity
)(
  input  logic [31:0] a, b, c,    // IEEE-754 single in bit form
  input  logic [2:0]  rnd,        // ignored in sim model
  output logic [31:0] z,          // IEEE-754 single in bit form
  output logic [7:0]  status      // all zeros for now
);
  shortreal ar, br, cr, zr;

  // Simple sanity checks for sim (no sim-time cost if disabled)
  // synopsys translate_off
  always @* begin
    if ($isunknown(a) || $isunknown(b) || $isunknown(c)) begin
      $warning("sim_fp_mac: X/Z detected on inputs");
    end
  end
  // synopsys translate_on

  always_comb begin
    ar = $bitstoshortreal(a);
    br = $bitstoshortreal(b);
    cr = $bitstoshortreal(c);
    zr = (ar * br) + cr;
    z  = $shortrealtobits(zr);
  end

  assign status = '0; // no exception modeling (yet)
endmodule
