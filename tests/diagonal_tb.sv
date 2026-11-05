// Noiseless identity-channel regression; +archive checks the preserved historical failure.
module diagonal_tb;
  logic clk=0, rst=0, flagChannelorData=0, i_valid=0;
  logic [95:0] InData;
  wire o_valid;
  wire [11:0] OutData;
  localparam logic [11:0] expected = 12'h792;
  mimo_detector dut(.*);
  always #5 clk=~clk;
  int coeff[24], got=0;
  initial begin
    // Row-major packed upper triangle of I6, then three padding fields.
    foreach(coeff[i]) coeff[i]=0;
    coeff[0]=4096; coeff[6]=4096; coeff[11]=4096;
    coeff[15]=4096; coeff[18]=4096; coeff[20]=4096;
    @(negedge clk);rst=1;@(negedge clk);rst=0;
    for(int beat=0;beat<4;beat++) begin
      for(int j=0;j<6;j++) InData[(5-j)*16+:16]=coeff[6*beat+j];
      i_valid=1;@(negedge clk);
    end
    // z = [3,-1,+1,-3,+3,-1], Q6.10 words; use the same vector each cycle.
    flagChannelorData=1;
    InData={16'd3072,-16'sd1024,16'd1024,-16'sd3072,16'd3072,-16'sd1024};
    repeat(150) begin
      @(negedge clk);
      if(o_valid) got++;
    end
    if(got==0) $fatal(1,"No output-valid indication");
    $display("TOP DIAGONAL: expected=%03h observed=%03h valid_cycles=%0d",expected,OutData,got);
    if ($test$plusargs("archive")) begin
      if (OutData !== 12'h781 || got != 129) $fatal(1,"Archival behavior changed");
    end else if (OutData !== expected || got != 144) begin
      $fatal(1,"Detector decision or output-valid mismatch");
    end
    $finish;
  end
endmodule
