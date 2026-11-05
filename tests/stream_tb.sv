// Compare every output, including cycles that must be invalid. The independent
// oracle supplies the expected decision for each accepted input transaction.
module stream_tb;
  localparam int LATENCY = 6;
  bit clk, rst, i_valid, flagChannelorData;
  logic [95:0] InData;
  wire [11:0] OutData;
  wire o_valid;
  mimo_detector dut(.*);
  always #5 clk = ~clk;
  bit valid_pipe[0:LATENCY];
  logic [11:0] expected_pipe[0:LATENCY];
  string filename;
  integer fd, parsed, reset_in, valid_in, flag_in, expect_valid, cycle, checked;
  logic [95:0] bits_in;
  logic [11:0] word_in;

  initial begin
    if (!$value$plusargs("vectors=%s",filename)) $fatal(1,"Specify +vectors=<file>");
    fd=$fopen(filename,"r");
    if (fd == 0) $fatal(1,"Cannot open stimulus file %s",filename);
    while (!$feof(fd)) begin
      parsed=$fscanf(fd,"%d %d %d %h %d %h",reset_in,valid_in,flag_in,bits_in,expect_valid,word_in);
      if (parsed!=6) begin
        if (!$feof(fd)) $fatal(1,"Malformed stimulus at cycle %0d",cycle);
        break;
      end
      @(negedge clk);
      rst=reset_in[0]; i_valid=valid_in[0]; flagChannelorData=flag_in[0]; InData=bits_in;
      @(posedge clk); #1;
      if (rst) begin
        foreach(valid_pipe[k]) valid_pipe[k]=0;
      end else begin
        for (int k=LATENCY;k>0;k--) begin
          valid_pipe[k]=valid_pipe[k-1];
          expected_pipe[k]=expected_pipe[k-1];
        end
        valid_pipe[0]=expect_valid[0];
        expected_pipe[0]=word_in;
      end
      if (o_valid!==valid_pipe[LATENCY])
        $fatal(1,"cycle %0d: expected o_valid=%b observed %b",cycle,valid_pipe[LATENCY],o_valid);
      if (o_valid) begin
        if (OutData!==expected_pipe[LATENCY])
          $fatal(1,"cycle %0d: expected %03h observed %03h",cycle,expected_pipe[LATENCY],OutData);
        checked++;
      end
      cycle++;
    end
    if (checked<4096) $fatal(1,"Incomplete regression");
    $display("PASS: %0d output words and all %0d valid/invalid cycles matched",checked,cycle);
    $finish;
  end
endmodule
