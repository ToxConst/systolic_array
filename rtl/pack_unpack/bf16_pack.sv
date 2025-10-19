module bf16_pack (
  input  logic [31:0] f32_i,   // IEEE-754 float32 bits
  output logic [15:0] bf16_o   // bfloat16 bits
);
    // lower 16 bits we drop, and the kept LSB (bit 16)
    logic [15:0] low16;
    logic        kept_lsb;
    logic        round_up;
    logic [31:0] rounded;

    always_comb begin
        low16    = f32_i[15:0];
        kept_lsb = f32_i[16];

        // Round-to-nearest-even: up if >0x8000, or ==0x8000 and kept_lsb==1
        round_up = (low16 > 16'h8000) || ((low16 == 16'h8000) && kept_lsb);

        // Add carry into bit16, then take the upper half
        rounded = f32_i + {15'b0, round_up, 16'b0};
        bf16_o  = rounded[31:16];
    end
endmodule