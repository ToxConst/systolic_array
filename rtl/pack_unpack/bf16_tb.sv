module bf16_tb();
  // DUTs
  logic [31:0] f32_i;
  logic [15:0] bf16_o;


  logic [15:0] bf16_i;
  logic [31:0] f32_o;


  bf16_unpack dut_unpack(.bf16_i(bf16_i), .f32_o(f32_o));
  bf16_pack   dut_pack(.f32_i(f32_i), .bf16_o(bf16_o));

    initial begin
        // Test vector 1
        f32_i = 32'h40490FDB; // pi in float32
        #10;
        $display("Input float32: %h, Packed bf16: %h", f32_i, bf16_o);

        // Unpack back to float32
        bf16_i = bf16_o;
        #10;
        $display("Unpacked bf16: %h, Resulting float32: %h", bf16_i, f32_o);

        // Test vector 2
        f32_i = 32'hC0490FDB; // -pi in float32
        #10;
        $display("Input float32: %h, Packed bf16: %h", f32_i, bf16_o);

        // Unpack back to float32
        bf16_i = bf16_o;
        #10;
        $display("Unpacked bf16: %h, Resulting float32: %h", bf16_i, f32_o);

        // Test vector 3
        /*# Subnormals & underflow behavior
            0x00007FFF  -> 0x0000 -> 0x00000000   # < tie, rounds down to +0
            0x00008000  -> 0x0000 -> 0x00000000   # exact tie, kept LSB=0 → +0
            0x00008001  -> 0x0001 -> 0x00010000   # just over tie → smallest +subnormal bf16
            0x80008001  -> 0x8001 -> 0x80010000   # smallest -subnormal bf16*/

        f32_i = 32'h00007FFF;
        #10;
        $display("Input float32: %h, Packed bf16: %h", f32_i, bf16_o);

        bf16_i = bf16_o;
        #10;
        $display("Unpacked bf16: %h, Resulting float32: %h", bf16_i, f32_o);

        f32_i = 32'h00008000;
        #10;
        $display("Input float32: %h, Packed bf16: %h", f32_i, bf16_o);

        bf16_i = bf16_o;
        #10;
        $display("Unpacked bf16: %h, Resulting float32: %h", bf16_i, f32_o);

        f32_i = 32'h00008001;
        #10;
        $display("Input float32: %h, Packed bf16: %h", f32_i, bf16_o);


        bf16_i = bf16_o;
        #10;
        $display("Unpacked bf16: %h, Resulting float32: %h", bf16_i, f32_o);

        f32_i = 32'h80008001;
        #10;
        $display("Input float32: %h, Packed bf16: %h", f32_i, bf16_o);
        
        bf16_i = bf16_o;
        #10;
        $display("Unpacked bf16: %h, Resulting float32: %h", bf16_i, f32_o);

        //Test vector 4
        /*Max finite vs overflow to +Inf
            0x7F7F7FFF  -> 0x7F7F -> 0x7F7F0000   # stays max finite
            0x7F7F8000  -> 0x7F80 -> 0x7F800000   # tie w/ LSB=1 → rounds to +Inf
            0xFF7F8000  -> 0xFF80 -> 0xFF800000   # negative side → -Inf*/
        f32_i = 32'h7F7F7FFF;
        #10;
        $display("Input float32: %h, Packed bf16: %h", f32_i, bf16_o);

        bf16_i = bf16_o;
        #10;
        $display("Unpacked bf16: %h, Resulting float32: %h", bf16_i, f32_o);

        f32_i = 32'h7F7F8000;
        #10;
        $display("Input float32: %h, Packed bf16: %h", f32_i, bf16_o);

        bf16_i = bf16_o;
        #10;
        $display("Unpacked bf16: %h, Resulting float32: %h", bf16_i, f32_o);

        f32_i = 32'hFF7F8000;
        #10;
        $display("Input float32: %h, Packed bf16: %h", f32_i, bf16_o);

        bf16_i = bf16_o;
        #10;
        $display("Unpacked bf16: %h, Resulting float32: %h", bf16_i, f32_o);

        $stop();
    end

endmodule
