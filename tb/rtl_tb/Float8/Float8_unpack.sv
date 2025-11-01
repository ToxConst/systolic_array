module Float8_unpack #(parameter E = 4, parameter M = 3, parameter BIAS = (1 << (E-1)) - 1) (
    input logic [7:0] fp8_in,
    output logic [31:0] f32_out
);

    localparam DELTA = 127 - BIAS;

    // Extract sign, exponent, and mantissa from the 8-bit float
    logic sign;
    logic [E-1:0] exponent;
    logic [M-1:0] mantissa;

    logic form_fp32;

    assign sign = fp8_in[7];
    assign exponent = fp8_in[6:M];
    assign mantissa = fp8_in[M-1:0];

    // Intermediate variables
    logic [22:0] mantissa_f32;
    logic [7:0] exponent_f32;

    logic [31:0] pos;

    always_comb begin
        form_fp32 = 0;
        if(exponent == '1) begin
            if(mantissa == 0)
                f32_out = {sign, {8{1'b1}}, {23{1'b0}} }; //Infinite
            else
                f32_out = {sign, {8{1'b1}}, 23'h400000 }; //NaN
        end
        else if(exponent == 0) begin
            if(mantissa == 0)
                f32_out = {sign, 31'b0};                    //+-0
            else begin
                form_fp32 = 0;
                unique case (mantissa)
                    3'd1: pos = 32'h3A80_0000; // 2^-9
                    3'd2: pos = 32'h3B00_0000; // 2^-8
                    3'd3: pos = 32'h3B40_0000; // 3*2^-9
                    3'd4: pos = 32'h3B80_0000; // 2^-7
                    3'd5: pos = 32'h3BA0_0000; // 5*2^-9
                    3'd6: pos = 32'h3BC0_0000; // 6*2^-9
                    3'd7: pos = 32'h3BE0_0000; // 7*2^-9
                    default: pos = 32'h0000_0000;
                endcase
                // apply sign (pos is +value with sign=0; copy sign into bit31)
                f32_out = {sign, pos[30:0]};
            end
        end
        else begin
            form_fp32 = 1;
            mantissa_f32 = (mantissa << (23 - M));
            exponent_f32 = exponent + DELTA;
        end

        if(form_fp32)
            f32_out  = {sign, exponent_f32, mantissa_f32};

    end

endmodule


