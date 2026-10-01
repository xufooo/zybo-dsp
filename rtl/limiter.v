// SPDX-License-Identifier: GPL-2.0-only


`default_nettype none

module limiter #(
    parameter SAMPLE_W = 24,
    parameter PARAM_W  = 18,
    parameter SHIFT    = 15
) (
    input  wire                        clk,
    input  wire                        resetn,
    input  wire                        sample_valid,
    input  wire signed [SAMPLE_W-1:0]  sample_in,
    input  wire [PARAM_W-1:0]          thr,
    input  wire [PARAM_W-1:0]          k_att,
    input  wire [PARAM_W-1:0]          k_rel,
    input  wire                        bypass,
    output reg                         out_valid,
    output reg  signed [SAMPLE_W-1:0]  sample_out
);

    localparam [PARAM_W-1:0] GAIN_ONE = 18'd1 << SHIFT;
    localparam THR_SHIFT = SAMPLE_W - 1 - SHIFT;
    wire [SAMPLE_W:0] thr_abs = {1'b0, thr} << THR_SHIFT;

    reg v0, v1, v2, v3, v4;

    reg signed [SAMPLE_W-1:0] x0;
    reg [SAMPLE_W:0]          ax0;
    reg                       byp0;

    reg [SAMPLE_W+PARAM_W:0]  lvl1;
    reg signed [SAMPLE_W-1:0] x1;
    reg                       byp1;

    reg [2*PARAM_W-1:0]       mul2;
    reg signed [SAMPLE_W-1:0] x2;
    reg                       byp2;

    reg [PARAM_W-1:0]         gain;
    reg signed [SAMPLE_W-1:0] x3;
    reg                       byp3;

    reg signed [SAMPLE_W-1:0] x4;

    wire [SAMPLE_W-1:0] mag24 = sample_in[SAMPLE_W-1] ? (~sample_in + 1'b1) : sample_in;
    wire [SAMPLE_W:0]   ax_comb = {1'b0, mag24};

    wire [SAMPLE_W:0]   lvl_q = lvl1 >> SHIFT;
    wire [PARAM_W-1:0]  k_now = (lvl_q > thr_abs) ? k_att : k_rel;

    wire [PARAM_W-1:0] gain_q   = mul2 >> SHIFT;
    wire [PARAM_W-1:0] gain_nxt = (gain_q > GAIN_ONE) ? GAIN_ONE : gain_q;

    wire signed [SAMPLE_W+PARAM_W-1:0] prod   = x4 * $signed({1'b0, gain});
    wire signed [SAMPLE_W+PARAM_W-1-SHIFT:0] scaled = prod >>> SHIFT;
    wire signed [SAMPLE_W-1:0] y_clip;

    saturator #(.IN_W(SAMPLE_W + PARAM_W - SHIFT), .OUT_W(SAMPLE_W)) u_sat (
        .in_sample(scaled),
        .out_sample(y_clip)
    );

    always @(posedge clk) begin
        if (!resetn) begin
            v0 <= 0; v1 <= 0; v2 <= 0; v3 <= 0; v4 <= 0;
            x0 <= 0; ax0 <= 0; byp0 <= 1'b1;
            lvl1 <= 0; x1 <= 0; byp1 <= 1'b1;
            mul2 <= 0; x2 <= 0; byp2 <= 1'b1;
            gain <= GAIN_ONE; x3 <= 0; byp3 <= 1'b1;
            x4 <= 0;
            out_valid <= 1'b0; sample_out <= 0;
        end else begin
            v0 <= sample_valid;
            v1 <= v0; v2 <= v1; v3 <= v2; v4 <= v3;
            out_valid <= v4;

            if (sample_valid) begin
                x0   <= sample_in;
                ax0  <= ax_comb;
                byp0 <= bypass;
            end

            if (v0) begin
                lvl1 <= ax0 * gain;
                x1   <= x0;
                byp1 <= byp0;
            end

            if (v1) begin
                mul2 <= gain * k_now;
                x2   <= x1;
                byp2 <= byp1;
            end

            if (v2) begin
                gain <= byp2 ? GAIN_ONE : gain_nxt;
                x3   <= x2;
                byp3 <= byp2;
            end

            if (v3) begin
                x4 <= x3;
                sample_out <= byp3 ? x3 : y_clip;
            end
        end
    end

endmodule

`default_nettype wire
