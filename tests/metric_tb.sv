module metric_tb;
  logic signed [19:0] prior, history, result;
  logic signed [15:0] diag;
  logic signed [2:0] symbol;
  MCU #(.WORD_LENGTH(20),.WORD_LENGTH_R(16)) dut(
    .PED(prior),.history(history),.rii(diag),.si(symbol),.new_PED(result)
  );
  initial begin
    for (int h=-7;h<=7;h++) begin
      for (int s=-3;s<=3;s+=2) begin
        int residual, expected;
        history=h; prior=11; diag=2; symbol=s;
        residual=h-2*s;
        expected=11+(residual<0?-residual:residual);
        #1;
        if (result!==expected) $fatal(1,"h=%0d s=%0d expected %0d got %0d",h,s,expected,result);
      end
    end
    $display("PASS: 60 signed MCU metric updates");
    $finish;
  end
endmodule
