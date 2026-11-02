`timescale 1ns/1ps
module pixel_pipeline #(parameter WIDTH=1280,HEIGHT=720,H_TOTAL=1650)(
 input wire I_clk,I_rst_n,input wire[23:0] I_rgb,input wire I_de,I_hs,I_vs,I_sof,I_eol,
 input wire[10:0] I_x,input wire[9:0] I_y,input wire[31:0] I_frame_id,input wire I_frame_valid,
 input wire[2:0] I_mode,input wire[1:0] I_level,input wire I_motion,
 output wire[23:0] O_rgb,output wire O_de,O_hs,O_vs,O_sof,O_eol,
 output wire[10:0] O_x,output wire[9:0] O_y,output wire[31:0] O_frame_id,output wire O_frame_valid,
 output wire[10:0] O_query_x,output wire[9:0] O_query_y);
wire[82:0] sobel_packet;wire[7:0] edge_value;
sobel_stream #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.H_TOTAL(H_TOTAL)) sobel(.I_clk(I_clk),.I_rst_n(I_rst_n),
 .I_rgb(I_rgb),.I_de(I_de),.I_hs(I_hs),.I_vs(I_vs),.I_sof(I_sof),.I_eol(I_eol),.I_x(I_x),.I_y(I_y),
 .I_frame_id(I_frame_id),.I_frame_valid(I_frame_valid),.O_rgb(sobel_packet[23:0]),.O_de(sobel_packet[28]),
 .O_hs(sobel_packet[27]),.O_vs(sobel_packet[26]),.O_sof(sobel_packet[25]),.O_eol(sobel_packet[24]),
 .O_x(sobel_packet[49:39]),.O_y(sobel_packet[38:29]),.O_frame_id(sobel_packet[81:50]),
 .O_frame_valid(sobel_packet[82]),.O_edge(edge_value));
assign O_query_x=sobel_packet[49:39];assign O_query_y=sobel_packet[38:29];
wire[15:0] sum=sobel_packet[23:16]*16'd77+sobel_packet[15:8]*16'd150+sobel_packet[7:0]*16'd29;
wire[7:0] threshold=I_level==0?96:I_level==2?160:128;
wire[7:0] edge_threshold=I_level==0?48:I_level==2?112:80;
// Piecewise-linear tone curve for color display: shadows x2.5, highlights compressed to <=223.
function[7:0] lift;input[7:0] v;begin
 if(v<64)lift=(v<<1)+(v>>1);
 else if(v<128)lift=8'd160+((v-8'd64)>>1);
 else if(v<192)lift=8'd192+((v-8'd128)>>2);
 else lift=8'd208+((v-8'd192)>>2);
end endfunction
wire[23:0] lifted={lift(sobel_packet[23:16]),lift(sobel_packet[15:8]),lift(sobel_packet[7:0])};
reg[82:0] result;
assign {O_frame_valid,O_frame_id,O_x,O_y,O_de,O_hs,O_vs,O_sof,O_eol,O_rgb}=result;
always @(posedge I_clk or negedge I_rst_n) begin
 if(!I_rst_n)result<=0;
 else begin
  result<=sobel_packet;
  case(I_mode)
   1:result[23:0]<={sum[15:8],sum[15:8],sum[15:8]};
   2:result[23:0]<=sum[15:8]>=threshold?24'hffffff:24'h000000;
   3:result[23:0]<={edge_value,edge_value,edge_value};
   4:result[23:0]<=edge_value>=edge_threshold?24'h00ff80:lifted;
   default:result[23:0]<=lifted;
  endcase
 end
end
endmodule
