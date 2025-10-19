module bf16_unpack (
  input  logic [15:0] bf16_i,   // bfloat16 bits
  output logic [31:0] f32_o     // IEEE-754 float32 bits
);
    assign f32_o = {bf16_i, 16'b0}; // Append 16 zero bits to the LSBs
endmodule