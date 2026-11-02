`timescale 1ns/1ps
module zone_bounds #(parameter WIDTH=1280,HEIGHT=720)(
 input wire[1:0] I_zone,
 output reg[10:0] O_left,O_right,output reg[9:0] O_top,O_bottom);
localparam CENTER_LEFT=(WIDTH/4/32)*32;
localparam CENTER_TOP=((HEIGHT/4+31)/32)*32;
localparam CENTER_BOTTOM=(HEIGHT*4/5/32)*32-1;
always @*begin
 O_left=0;O_right=WIDTH-1;O_top=0;O_bottom=HEIGHT-1;
 case(I_zone)
  1:begin O_left=CENTER_LEFT;O_right=WIDTH-CENTER_LEFT-1;O_top=CENTER_TOP;O_bottom=CENTER_BOTTOM;end
  2:O_right=(WIDTH/2/32)*32-1;
  3:O_left=(WIDTH/2/32)*32;
  default:;
 endcase
end
endmodule
