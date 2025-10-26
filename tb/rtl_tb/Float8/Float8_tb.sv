module Float8_tb();
logic [31:0] f32_in;
logic [7:0] f8_out;
logic sat_o;

logic [7:0] exp_f8;

int f, mismatches;

Float8_pack #(.E(5), .M(2)) f8_pack_inst(
  .f32_i(f32_in),
  .fp8_o (f8_out),
  .sat_o (sat_o)
);

//Currently testing : FP32 to FP8 E5M2 conversion
initial begin
    f = $fopen("C:\\Users\\adity\\Proj\\MACproj\\systolic_array\\tb\\rtl_tb\\e4m3\\fp32_fp8e5m2_vectors.txt", "r");
    if (f == 0) begin
        $display("Failed to open input vector file");
        $stop();
    end
    while (!$feof(f)) begin
        $fscanf(f, "%h %h\n", f32_in, exp_f8);
        #5;
        if (f8_out !== exp_f8) begin
            $display("Mismatch: f32_in=%h, got f8_out=%h, expected=%h", f32_in, f8_out, exp_f8);
            mismatches = mismatches + 1;
        end
    end

    $fclose(f);
    if (mismatches == 0) begin
        $display("All tests passed!");
    end else begin
        $display("Total mismatches: %0d", mismatches);
    end
    $stop();

end

endmodule