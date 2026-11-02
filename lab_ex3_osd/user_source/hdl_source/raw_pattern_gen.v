/*****************************************************************
 * raw_pattern_gen.v
 *
 * Built-in diagnostic video source for the camera->ISP->DDR->HDMI chain.
 * Emulates the uial2axis AXI4-Stream output (4 x RAW10 pixels per 40-bit
 * beat, 320 beats per line, 720 lines per frame) with a static BGGR Bayer
 * pattern: 4 vertical bands (white / red / green / blue, 320 px each).
 *
 * Purpose: when the live camera picture is unstable, switch to this
 * source.  If the on-screen bars are stable, the ISP/DDR/HDMI path is
 * healthy and the fault is in the camera or MIPI link; if the bars still
 * flicker or swap colors, the fault is downstream of the mux.
 *
 * Beat pacing: 1 valid beat every 3 clocks (~20 Mbeats/s at 60 MHz),
 * 600-clock line gap, 3000-clock frame gap -> ~53 fps, close to the real
 * camera so the DDR/FIFO watermark behaviour is representative.
 *****************************************************************/

module raw_pattern_gen (
    input  wire        I_clk,
    input  wire        I_rst_n,
    output reg         O_tvalid,
    output reg  [39:0] O_tdata,
    output reg         O_tlast,
    output reg         O_tuser
);

    localparam BEATS_PER_LINE = 10'd320;
    localparam LINE_GAP       = 10'd600;
    localparam FRAME_GAP      = 12'd3000;
    localparam LAST_LINE      = 10'd719;

    reg [1:0]  S_state;          // 0=frame gap, 1=line data, 2=line gap
    reg [1:0]  S_gap_cnt;
    reg [9:0]  S_beat_cnt;
    reg [9:0]  S_line_cnt;
    reg [9:0]  S_line_gap_cnt;
    reg [11:0] S_frame_gap_cnt;

    wire S_v_odd = S_line_cnt[0];

    // RAW10 value for sub-pixel `sub` (0..3) of beat `beat`.
    // BGGR: even line = B G B G ..., odd line = G R G R ...
    function [9:0] pixel_val;
        input [1:0] sub;
        input       v_odd;
        input [9:0] beat;
        reg is_r, is_g, is_b;
        begin
            is_b = (!v_odd) && (sub[0] == 1'b0);
            is_g = v_odd ^ sub[0];
            is_r = v_odd && (sub[0] == 1'b1);
            case ((beat < 10'd80) ? 2'd0 : (beat < 10'd160) ? 2'd1 :
                  (beat < 10'd240) ? 2'd2 : 2'd3) // 4 x 80 beats
                2'd0:    pixel_val = 10'h3ff;                     // white
                2'd1:    pixel_val = is_r ? 10'h3ff : 10'h000;    // red
                2'd2:    pixel_val = is_g ? 10'h3ff : 10'h000;    // green
                default: pixel_val = is_b ? 10'h3ff : 10'h000;    // blue
            endcase
        end
    endfunction

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_state         <= 2'd0;
            S_gap_cnt       <= 2'd0;
            S_beat_cnt      <= 10'd0;
            S_line_cnt      <= 10'd0;
            S_line_gap_cnt  <= 10'd0;
            S_frame_gap_cnt <= 12'd0;
            O_tvalid        <= 1'b0;
            O_tlast         <= 1'b0;
            O_tuser         <= 1'b0;
            O_tdata         <= 40'd0;
        end
        else begin
            O_tvalid <= 1'b0;
            O_tlast  <= 1'b0;
            O_tuser  <= 1'b0;
            case (S_state)
                2'd0: begin     // frame gap
                    if(S_frame_gap_cnt == FRAME_GAP-1) begin
                        S_frame_gap_cnt <= 12'd0;
                        S_line_cnt      <= 10'd0;
                        S_beat_cnt      <= 10'd0;
                        S_gap_cnt       <= 2'd0;
                        S_state         <= 2'd1;
                    end
                    else
                        S_frame_gap_cnt <= S_frame_gap_cnt + 12'd1;
                end
                2'd1: begin     // emit one beat every 3 clocks
                    if(S_gap_cnt != 2'd0) begin
                        S_gap_cnt <= S_gap_cnt - 2'd1;
                    end
                    else begin
                        S_gap_cnt <= 2'd2;
                        O_tvalid  <= 1'b1;
                        O_tuser   <= (S_line_cnt == 10'd0) && (S_beat_cnt == 10'd0);
                        O_tlast   <= (S_beat_cnt == BEATS_PER_LINE-1);
                        O_tdata   <= {pixel_val(2'd3, S_v_odd, S_beat_cnt),
                                      pixel_val(2'd2, S_v_odd, S_beat_cnt),
                                      pixel_val(2'd1, S_v_odd, S_beat_cnt),
                                      pixel_val(2'd0, S_v_odd, S_beat_cnt)};
                        if(S_beat_cnt == BEATS_PER_LINE-1) begin
                            S_beat_cnt     <= 10'd0;
                            S_line_gap_cnt <= 10'd0;
                            S_state        <= 2'd2;
                        end
                        else
                            S_beat_cnt <= S_beat_cnt + 10'd1;
                    end
                end
                2'd2: begin     // line gap
                    if(S_line_gap_cnt == LINE_GAP-1) begin
                        if(S_line_cnt == LAST_LINE) begin
                            S_frame_gap_cnt <= 12'd0;
                            S_state         <= 2'd0;
                        end
                        else begin
                            S_line_cnt <= S_line_cnt + 10'd1;
                            S_beat_cnt <= 10'd0;
                            S_gap_cnt  <= 2'd0;
                            S_state    <= 2'd1;
                        end
                    end
                    else
                        S_line_gap_cnt <= S_line_gap_cnt + 10'd1;
                end
                default: S_state <= 2'd0;
            endcase
        end
    end

endmodule
