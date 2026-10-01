// SPDX-License-Identifier: GPL-2.0-only


`default_nettype none

module truepeak_limiter #(
    parameter SAMPLE_W = 24,
    parameter SHIFT    = 15,
    parameter LOOK     = 96,
    parameter AW       = 7
) (
    input  wire                       clk,
    input  wire                       resetn,
    input  wire                       sample_valid,
    input  wire signed [SAMPLE_W-1:0] sample_in,
    input  wire [17:0]                thr,
    input  wire [17:0]                k_att,
    input  wire [17:0]                k_rel,
    input  wire                       bypass,
    output reg                        out_valid,
    output reg  signed [SAMPLE_W-1:0] sample_out,
    output wire signed [16:0]         gain_lg,
    output reg  [15:0]                gain_applied,
    output reg                        overrun
);

    localparam THR_SHIFT = SAMPLE_W - 1 - SHIFT;
    localparam [7:0] LOOK8 = LOOK;

    wire [SAMPLE_W:0] thr_abs = {1'b0, thr} << THR_SHIFT;
    wire [23:0]       thr_abs24 = thr_abs[23:0];

    function [SAMPLE_W-1:0] abs24(input signed [SAMPLE_W-1:0] v);
        begin
            abs24 = v[SAMPLE_W-1] ? (~v + 1'b1) : v;
        end
    endfunction

    wire signed [16:0] thr_lg;
    tp_log2 u_log_thr (.mag(thr_abs24), .log2q(thr_lg));

    reg  signed [SAMPLE_W-1:0] dl [0:(1<<AW)-1];
    reg  [AW-1:0]              wptr;
    reg  [AW-1:0]              raddr;

    wire signed [SAMPLE_W-1:0] drd = dl[raddr];

    wire [AW-1:0] dly_addr = wptr - LOOK8[AW-1:0];

    integer di;
    initial begin
        for (di = 0; di < (1<<AW); di = di + 1) dl[di] = {SAMPLE_W{1'b0}};
        wptr = {AW{1'b0}};
    end

    localparam [2:0] S_IDLE = 3'd0, S_SCAN = 3'd1,
                     S_C1 = 3'd2,
                     S_C2 = 3'd3,
                     S_C3 = 3'd4,
                     S_C4 = 3'd5,
                     S_C5 = 3'd6,
                     S_C6 = 3'd7;

    reg  [2:0]                state;

    wire                      we = resetn && (state == S_IDLE) && sample_valid;
    always @(posedge clk) begin
        if (we) dl[wptr] <= sample_in;
    end

    reg  [7:0]                scnt;
    reg  [SAMPLE_W-1:0]       maxabs;
    reg  [SAMPLE_W-1:0]       maxabs_r;
    reg  signed [SAMPLE_W-1:0] dly_hold;
    reg  signed [16:0]        g_lg;
    reg  signed [16:0]        peak_r, tgt_r, diff_r;
    reg  signed [17:0]        ksel_r;
    reg  [15:0]               gain_r;

    wire signed [16:0] peak_c;
    tp_log2 u_log_peak (.mag(maxabs), .log2q(peak_c));

    wire signed [16:0] tgt_c = (maxabs_r <= thr_abs24) ? 17'sd0 : (thr_lg - peak_r);

    wire signed [34:0] dmul_c   = diff_r * ksel_r;
    wire signed [16:0] g_next_c = g_lg + (dmul_c >>> 15);

    wire [15:0] gain_c;
    tp_exp2 u_exp (.x_q5_11(g_lg), .gain_q15(gain_c));

    wire signed [SAMPLE_W+16-1:0] ymul_c = dly_hold * $signed({1'b0, gain_r});
    wire signed [SAMPLE_W-1:0]    y_sat;
    saturator #(.IN_W(SAMPLE_W + 16 - SHIFT), .OUT_W(SAMPLE_W)) u_sat (
        .in_sample (ymul_c >>> SHIFT),
        .out_sample(y_sat)
    );

    assign gain_lg = g_lg;

    always @(posedge clk) begin
        if (!resetn) begin
            state      <= S_IDLE;
            wptr       <= {AW{1'b0}};
            raddr      <= {AW{1'b0}};
            scnt       <= 8'd0;
            maxabs     <= {SAMPLE_W{1'b0}};
            maxabs_r   <= {SAMPLE_W{1'b0}};
            dly_hold   <= {SAMPLE_W{1'b0}};
            g_lg       <= 17'sd0;
            peak_r     <= 17'sd0;
            tgt_r      <= 17'sd0;
            diff_r     <= 17'sd0;
            ksel_r     <= 18'sd0;
            gain_r     <= 16'd32768;
            gain_applied <= 16'd32768;
            out_valid  <= 1'b0;
            sample_out <= {SAMPLE_W{1'b0}};
            overrun    <= 1'b0;
        end else begin
            out_valid <= 1'b0;

            if (sample_valid && (state != S_IDLE)) overrun <= 1'b1;

            case (state)
                S_IDLE: if (sample_valid) begin
                    dly_hold <= dl[dly_addr];
                    maxabs   <= abs24(sample_in);
                    raddr    <= wptr + 1'b1;
                    scnt     <= 8'd0;
                    wptr     <= wptr + 1'b1;
                    state    <= S_SCAN;
                end

                S_SCAN: begin
                    if (abs24(drd) > maxabs) maxabs <= abs24(drd);
                    raddr <= raddr + 1'b1;
                    if (scnt == LOOK8 - 8'd2) state <= S_C1;
                    else                      scnt  <= scnt + 8'd1;
                end

                S_C1: begin peak_r <= peak_c; maxabs_r <= maxabs;          state <= S_C2; end
                S_C2: begin tgt_r  <= tgt_c;                               state <= S_C3; end
                S_C3: begin
                    diff_r <= tgt_r - g_lg;
                    ksel_r <= (tgt_r < g_lg) ? $signed({1'b0, k_att}) : $signed({1'b0, k_rel});
                    state  <= S_C4;
                end
                S_C4: begin g_lg   <= g_next_c;                            state <= S_C5; end
                S_C5: begin gain_r <= gain_c;                              state <= S_C6; end
                S_C6: begin
                    gain_applied <= gain_r;
                    sample_out   <= bypass ? dly_hold : y_sat;
                    out_valid    <= 1'b1;
                    state        <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
