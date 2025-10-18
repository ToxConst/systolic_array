package fp_formats_pkg;
  typedef enum logic [1:0] {FP8_E4M3=2'b00, FP8_E5M2=2'b01, BF16=2'b10} fp_mode_e;

  typedef struct packed {
    logic        sign;
    logic [4:0]  exp;
    logic [1:0]  man;
  } fp8_e5m2_t;

  typedef struct packed {
    logic        sign;
    logic [3:0]  exp;
    logic [2:0]  man;
  } fp8_e4m3_t;

  typedef struct packed {
    logic        sign;
    logic [7:0]  exp;
    logic [6:0]  man;
  } bf16_t;

endpackage : fp_formats_pkg
