// SPDX-License-Identifier: GPL-2.0-only


module fir_bank_long #(
    parameter SAMPLE_W = 24,
    parameter COEF_W   = 18,
    parameter SHIFT    = 15,
    parameter ACC_W    = 56,
    parameter NCH      = 2,
    parameter BLK_TAPS = 4096,
    parameter BLKS     = 2,
    parameter MACS     = 16
) (
    input  wire                       clk,
    input  wire                       resetn,
    input  wire                       cwr,
    input  wire [15:0]                caddr,
    input  wire signed [COEF_W-1:0]   cdat,
    input  wire                       start,
    input  wire                       ch,
    input  wire [15:0]                ntaps,
    input  wire signed [SAMPLE_W-1:0] x_in,
    output wire                       done,
    output wire signed [SAMPLE_W-1:0] y_out
);
    localparam TOT       = BLK_TAPS * BLKS;
    localparam PER_CH_AW = $clog2(TOT);
    localparam BLK_AW    = $clog2(BLK_TAPS);
    localparam DLEN_RAW  = (BLKS - 1) * BLK_TAPS;
    localparam DLEN      = (DLEN_RAW <= 1) ? 1 : (1 << $clog2(DLEN_RAW));
    localparam DLW       = (DLEN <= 1) ? 1 : $clog2(DLEN);
    localparam SUM_W     = SAMPLE_W + ((BLKS <= 1) ? 1 : $clog2(BLKS));
    localparam signed [SUM_W-1:0] SUM_MAX = (1 <<< (SAMPLE_W-1)) - 1;
    localparam signed [SUM_W-1:0] SUM_MIN = -(1 <<< (SAMPLE_W-1));

    (* ram_style = "block" *) reg [SAMPLE_W-1:0] dly [0:NCH*DLEN-1];
    reg [DLW-1:0]      dp  [0:NCH-1];
    integer di;
    initial begin
        for (di = 0; di < NCH*DLEN; di = di + 1) dly[di] = {SAMPLE_W{1'b0}};
    end

    wire signed [SAMPLE_W-1:0] bx [0:BLKS-1];
    assign bx[0] = x_in;

    genvar b;
    generate
    for (b = 1; b < BLKS; b = b + 1) begin : g_dly

        wire           active_b = (ntaps > (b*BLK_TAPS));

        wire [DLW-1:0] rd_b     = dp[ch] + (start ? 1'b1 : 1'b0) - (b*BLK_TAPS);
        reg  [SAMPLE_W-1:0] dly_q;
        always @(posedge clk) dly_q <= dly[ch*DLEN + rd_b];
        assign bx[b] = active_b ? dly_q : {SAMPLE_W{1'b0}};
    end
    endgenerate

    always @(posedge clk) begin
        if (!resetn) begin
            for (di = 0; di < NCH; di = di + 1) dp[di] <= 0;
        end else if (start) begin
            dly[ch*DLEN + dp[ch]] <= x_in;
            dp[ch] <= dp[ch] + 1'b1;
        end
    end

    wire [15:0] blk_sel  = (caddr >> BLK_AW) & (BLKS - 1);
    wire [15:0] loc_addr = (caddr >> PER_CH_AW) * BLK_TAPS + (caddr & (BLK_TAPS - 1));

    wire                       c_done [0:BLKS-1];
    wire signed [SAMPLE_W-1:0] c_y    [0:BLKS-1];
    generate
    for (b = 0; b < BLKS; b = b + 1) begin : g_core
        wire wr_b = cwr && (blk_sel == b);
        wire [15:0] off_b = b * BLK_TAPS;
        wire [15:0] nt_b  = (ntaps <= off_b) ? 16'd0
                          : ((ntaps - off_b) > BLK_TAPS) ? BLK_TAPS[15:0] : (ntaps - off_b);
        fir_bank #(
            .SAMPLE_W(SAMPLE_W), .COEF_W(COEF_W), .SHIFT(SHIFT), .ACC_W(ACC_W),
            .TAPS(BLK_TAPS), .MACS(MACS), .NCH(NCH)
        ) u_core (
            .clk(clk), .resetn(resetn),
            .cwr(wr_b), .caddr(loc_addr), .cdat(cdat),
            .start(start), .ch(ch), .ntaps(nt_b), .x_in(bx[b]),
            .done(c_done[b]), .y_out(c_y[b])
        );
    end
    endgenerate

    reg signed [SUM_W-1:0] sum_r;
    integer si;
    always @* begin
        sum_r = {SUM_W{1'b0}};
        for (si = 0; si < BLKS; si = si + 1)
            sum_r = sum_r + {{(SUM_W-SAMPLE_W){c_y[si][SAMPLE_W-1]}}, c_y[si]};
    end
    assign y_out = (sum_r > SUM_MAX) ? SUM_MAX[SAMPLE_W-1:0] :
                   (sum_r < SUM_MIN) ? SUM_MIN[SAMPLE_W-1:0] : sum_r[SAMPLE_W-1:0];

    reg done_r;
    integer dj;
    always @* begin
        done_r = 1'b1;
        for (dj = 0; dj < BLKS; dj = dj + 1) done_r = done_r & c_done[dj];
    end
    assign done = done_r;
endmodule
