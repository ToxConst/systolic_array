package fp8_params_pkg;
  typedef enum logic [1:0] { FP8_E4M3=2'd0, FP8_E5M2=2'd1 } fp8_mode_e;

  function automatic int bias_of(fp8_mode_e m);
    return (m==FP8_E4M3) ? 7 : 16;      
  endfunction

  function automatic int e_bits_of(fp8_mode_e m);
    return (m==FP8_E4M3) ? 4 : 5;
  endfunction

  function automatic int m_bits_of(fp8_mode_e m);
    return (m==FP8_E4M3) ? 3 : 2;
  endfunction
endpackage