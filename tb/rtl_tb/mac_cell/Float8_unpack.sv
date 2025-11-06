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

    int p, i;
    logic [23:0] sig24;
    logic [22:0] frac23;

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
                p = -1;
                for (i = M-1; i >= 0; i--) begin
                if (mantissa[i]) begin
                    p = i;
                    break;
                end
                end

                sig24        = 24'(mantissa) << (23 - p); ;
                mantissa_f32 = sig24[22:0];

                // 3) exponent = ((1 - BIAS - M) + p) + 127  ==  1 - M + DELTA + p
                exponent_f32 = (1 - M + DELTA + p);  // cast to 8-bit

                form_fp32 = 1;
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


