// SPDX-License-Identifier: GPL-2.0-only


`default_nettype none

module dsp_insert #(
    parameter SAMPLE_W = 24,
    parameter COEF_W   = 18,
    parameter SHIFT    = 15,
    parameter NB       = 6,
    parameter NCH      = 2
) (
    input  wire                     clk,
    input  wire                     resetn,

    input  wire                     in_stb,
    input  wire [SAMPLE_W-1:0]      in_data,
    output wire                     in_ack,

    output wire                     out_stb,
    output wire [SAMPLE_W-1:0]      out_data,
    input  wire                     out_ack,

    input  wire                     dsp_bypass,
    input  wire [3:0]               nbands,
    input  wire [5:0]               cidx,
    input  wire                     cwr,
    input  wire [31:0]              cdat,
    output reg  [31:0]              cdat_rd,

    input  wire                     lim_bypass,
    input  wire [17:0]              lim_thr,
    input  wire [17:0]              lim_att,
    input  wire [17:0]              lim_rel
);

    wire use_dsp = ~dsp_bypass;

    assign in_ack = out_ack;

    reg signed [COEF_W-1:0] cf_b0 [0:NB-1];
    reg signed [COEF_W-1:0] cf_b1 [0:NB-1];
    reg signed [COEF_W-1:0] cf_b2 [0:NB-1];
    reg signed [COEF_W-1:0] cf_a1 [0:NB-1];
    reg signed [COEF_W-1:0] cf_a2 [0:NB-1];

    wire [2:0] wband = cidx / 5;
    wire [2:0] wk    = cidx % 5;

    integer bi;
    always @(posedge clk) begin
        if (!resetn) begin
            for (bi = 0; bi < NB; bi = bi + 1) begin
                cf_b0[bi] <= 0; cf_b1[bi] <= 0; cf_b2[bi] <= 0;
                cf_a1[bi] <= 0; cf_a2[bi] <= 0;
            end
        end else if (cwr) begin
            case (wk)
                3'd0: cf_b0[wband] <= cdat[COEF_W-1:0];
                3'd1: cf_b1[wband] <= cdat[COEF_W-1:0];
                3'd2: cf_b2[wband] <= cdat[COEF_W-1:0];
                3'd3: cf_a1[wband] <= cdat[COEF_W-1:0];
                3'd4: cf_a2[wband] <= cdat[COEF_W-1:0];
                default: ;
            endcase
        end
    end

    reg signed [COEF_W-1:0] coef_sel;
    always @* begin
        case (wk)
            3'd0: coef_sel = cf_b0[wband];
            3'd1: coef_sel = cf_b1[wband];
            3'd2: coef_sel = cf_b2[wband];
            3'd3: coef_sel = cf_a1[wband];
            default: coef_sel = cf_a2[wband];
        endcase
    end
    always @* cdat_rd = {{(32-COEF_W){coef_sel[COEF_W-1]}}, coef_sel};

    wire acc = use_dsp & out_ack & in_stb;
    reg  ch_par;
    always @(posedge clk) begin
        if (!resetn)                ch_par <= 1'b0;
        else if (acc)               ch_par <= ~ch_par;
    end

    localparam NSIG = NCH * (NB + 1);
    wire [SAMPLE_W-1:0] ch_data  [0:NSIG-1];
    wire                ch_valid [0:NSIG-1];
    wire                ch_out_v [0:NCH-1];
    wire [SAMPLE_W-1:0] ch_out_d [0:NCH-1];

    genvar c, gi;
    generate
        for (c = 0; c < NCH; c = c + 1) begin : g_ch
            assign ch_data[c*(NB+1)]  = in_data;
            assign ch_valid[c*(NB+1)] = acc & (ch_par == c[0]);
            for (gi = 0; gi < NB; gi = gi + 1) begin : g_band
                wire                bq_valid;
                wire [SAMPLE_W-1:0] bq_data;
                wire en = use_dsp & (gi < nbands);

                biquad_filter #(
                    .SAMPLE_W (SAMPLE_W),
                    .COEF_W   (COEF_W),
                    .SHIFT    (SHIFT)
                ) u_bq (
                    .clk          (clk),
                    .reset        (~resetn),
                    .clear        (1'b0),
                    .sample_valid (ch_valid[c*(NB+1)+gi]),
                    .sample_in    (ch_data[c*(NB+1)+gi]),
                    .b0           (cf_b0[gi]),
                    .b1           (cf_b1[gi]),
                    .b2           (cf_b2[gi]),
                    .a1           (cf_a1[gi]),
                    .a2           (cf_a2[gi]),
                    .out_valid    (bq_valid),
                    .sample_out   (bq_data)
                );

                assign ch_valid[c*(NB+1)+gi+1] = en ? bq_valid : ch_valid[c*(NB+1)+gi];
                assign ch_data[c*(NB+1)+gi+1]  = en ? bq_data  : ch_data[c*(NB+1)+gi];
            end
            assign ch_out_v[c] = ch_valid[c*(NB+1)+NB];
            assign ch_out_d[c] = ch_data[c*(NB+1)+NB];
        end
    endgenerate

    wire                merge_v = ch_out_v[0] | ch_out_v[1];
    wire [SAMPLE_W-1:0] merge_d = ch_out_v[0] ? ch_out_d[0] : ch_out_d[1];

    wire                    lim_valid;
    wire [SAMPLE_W-1:0]     lim_data;

    limiter #(
        .SAMPLE_W (SAMPLE_W),
        .PARAM_W  (18),
        .SHIFT    (SHIFT)
    ) u_lim (
        .clk          (clk),
        .resetn       (resetn),
        .sample_valid (merge_v),
        .sample_in    (merge_d),
        .thr          (lim_thr),
        .k_att        (lim_att),
        .k_rel        (lim_rel),
        .bypass       (lim_bypass),
        .out_valid    (lim_valid),
        .sample_out   (lim_data)
    );

    localparam AW    = 3;
    localparam DEPTH = 1 << AW;

    reg [SAMPLE_W-1:0] mem [0:DEPTH-1];
    reg [AW:0]         cnt;
    reg [AW-1:0]       wr, rd;
    reg                use_dsp_d;
    reg [3:0]          nbands_d;

    wire push = use_dsp & lim_valid;
    wire pop  = use_dsp & out_ack & (cnt != 0);

    wire mode_chg = (use_dsp != use_dsp_d) || (nbands != nbands_d);

    always @(posedge clk) begin
        use_dsp_d <= use_dsp;
        nbands_d  <= nbands;
        if (!resetn || mode_chg) begin
            wr  <= {AW{1'b0}};
            rd  <= {AW{1'b0}};
            cnt <= {(AW+1){1'b0}};
        end else if (use_dsp) begin
            if (push) begin
                mem[wr] <= lim_data;
                wr      <= wr + 1'b1;
            end
            if (pop)
                rd <= rd + 1'b1;
            if (push && !pop)
                cnt <= cnt + 1'b1;
            else if (!push && pop)
                cnt <= cnt - 1'b1;
        end
    end

    assign out_stb  = use_dsp ? (in_stb | (cnt != 0)) : in_stb;
    assign out_data = use_dsp ? mem[rd]              : in_data;

endmodule

`default_nettype wire
