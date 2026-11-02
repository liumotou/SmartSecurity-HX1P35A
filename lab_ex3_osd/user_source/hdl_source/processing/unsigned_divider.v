`timescale 1ns/1ps
module unsigned_divider #(parameter WIDTH=48)(input wire I_clk,I_rst_n,I_start,
 input wire[WIDTH-1:0] I_numerator,I_denominator,output reg O_busy,O_done,output reg[WIDTH-1:0] O_quotient);
reg[WIDTH-1:0] denominator;reg[WIDTH:0] remainder;reg[6:0] count;
wire[WIDTH:0] shifted={remainder[WIDTH-1:0],O_quotient[WIDTH-1]};
wire subtract=shifted>={1'b0,denominator};
always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin O_busy<=0;O_done<=0;O_quotient<=0;denominator<=0;remainder<=0;count<=0;end
 else begin O_done<=0;
  if(I_start&&!O_busy)begin
   denominator<=I_denominator;O_quotient<=I_numerator;remainder<=0;count<=0;O_busy<=1;
   if(I_denominator==0)begin O_quotient<=0;O_busy<=0;O_done<=1;end
  end else if(O_busy)begin
   remainder<=subtract?shifted-{1'b0,denominator}:shifted;
   O_quotient<={O_quotient[WIDTH-2:0],subtract};
   if(count==WIDTH-1)begin O_busy<=0;O_done<=1;end else count<=count+1'b1;
  end
 end
end
endmodule
