// SPDX-License-Identifier: GPL-2.0-only


`timescale 1ns / 1ps

module fir_bank #(
    parameter SAMPLE_W = 24,
    parameter COEF_W   = 18,
    parameter SHIFT    = 15,
    parameter ACC_W    = 56,
    parameter TAPS     = 4096,
    parameter MACS     = 16,
    parameter NCH      = 2
)(
    input  wire                       clk,
    input  wire                       resetn,

    input  wire                       cwr,
    input  wire [15:0]                caddr,
    input  wire signed [COEF_W-1:0]   cdat,

    input  wire                       start,
    input  wire                       ch,
    input  wire [15:0]                ntaps,
    input  wire signed [SAMPLE_W-1:0] x_in,
    output reg                        done,
    output reg  signed [SAMPLE_W-1:0] y_out
);
    localparam DEPTH  = TAPS / MACS;
    localparam ADW    = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    localparam CNT_W  = (DEPTH <= 2) ? 2 : $clog2(DEPTH + 4);
    localparam PW     = (TAPS  <= 1) ? 1 : $clog2(TAPS);
    localparam PROD_W = SAMPLE_W + COEF_W;

    localparam LOGM   = (MACS <= 1) ? 1 : $clog2(MACS);
    localparam SUMP_W = PROD_W + LOGM;

    localparam [1:0] F_IDLE = 2'd0, F_RUN = 2'd1, F_SUM = 2'd2;

    reg  [1:0]        fstate;
    reg  [CNT_W-1:0]  jcnt;
    reg  [CNT_W-1:0]  nblk;
    reg               ch_r;
    reg  [LOGM-1:0]   rot_r;
    reg  [PW-1:0]     wp [0:NCH-1];
    reg  [ADW-1:0]    radr [0:MACS-1];

    integer k, binit;

    wire lane_en = (fstate == F_RUN) && (jcnt >= 3) && ((jcnt - 3) < nblk);
    wire run_fin = (fstate == F_RUN) && (jcnt == (nblk + 3));

    reg  signed [PROD_W-1:0] prod_r [0:MACS-1];
    reg  signed [COEF_W-1:0] c_rot_r [0:MACS-1];
    reg  signed [SAMPLE_W-1:0] h_r_d [0:MACS-1];

    reg  signed [ACC_W-1:0] acc_lane [0:MACS-1];

    reg  signed [ACC_W-1:0] mreg [0:LOGM][0:MACS-1];
    reg  [3:0]  scnt;
    wire signed [COEF_W-1:0] cbank_w [0:MACS-1];
    wire signed [COEF_W-1:0] c_rot   [0:MACS-1];

    genvar l;
    generate
    for (l = 0; l < MACS; l = l + 1) begin : g_rot
        assign c_rot[l] = cbank_w[rot_r - l[LOGM-1:0]];
    end
    endgenerate

    genvar b;
    generate
    for (b = 0; b < MACS; b = b + 1) begin : g_bank
        reg [COEF_W-1:0]   cmem [0:NCH*DEPTH-1];
        reg [SAMPLE_W-1:0] hmem [0:NCH*DEPTH-1];
        reg signed [COEF_W-1:0]   c_r;
        reg signed [SAMPLE_W-1:0] h_r;

        integer ii;
        initial begin
            for (ii = 0; ii < NCH*DEPTH; ii = ii + 1) begin
                cmem[ii] = {COEF_W{1'b0}};
                hmem[ii] = {SAMPLE_W{1'b0}};
            end
        end

        always @(posedge clk) begin
            if (cwr && ((caddr % MACS) == b[15:0]))
                cmem[caddr / MACS] <= cdat;
        end

        always @(posedge clk) begin
            if (start && ((wp[ch] % MACS) == b[PW-1:0]))
                hmem[ch * DEPTH + (wp[ch] / MACS)] <= x_in;
        end

        always @(posedge clk) begin
            c_r <= cmem[ch_r * DEPTH + jcnt[ADW-1:0]];
            h_r <= hmem[ch_r * DEPTH + radr[b]];
        end

        assign cbank_w[b] = c_r;

        always @(posedge clk) begin
            c_rot_r[b] <= c_rot[b];
            h_r_d[b]   <= h_r;
            prod_r[b]  <= h_r_d[b] * c_rot_r[b];

            if (!resetn)      acc_lane[b] <= {ACC_W{1'b0}};
            else if (start)   acc_lane[b] <= {ACC_W{1'b0}};
            else if (lane_en)
                acc_lane[b] <= acc_lane[b] + {{(ACC_W-PROD_W){prod_r[b][PROD_W-1]}}, prod_r[b]};
        end
    end
    endgenerate

    genvar rl;
    generate
    for (rl = 1; rl < LOGM; rl = rl + 1) begin : g_mrg
        integer mi;
        always @(posedge clk) begin
            if (!resetn) begin
                for (mi = 0; mi < (MACS >> rl); mi = mi + 1)
                    mreg[rl][mi] <= {ACC_W{1'b0}};
            end else if ((fstate == F_SUM) && (scnt == (rl[3:0] - 4'd1))) begin
                for (mi = 0; mi < (MACS >> rl); mi = mi + 1)
                    mreg[rl][mi] <= ((rl == 1) ? acc_lane[2*mi]   : mreg[rl-1][2*mi])
                                  + ((rl == 1) ? acc_lane[2*mi+1] : mreg[rl-1][2*mi+1]);
            end
        end
    end
    endgenerate

    wire signed [ACC_W-1:0] mrg_a = (LOGM == 1) ? acc_lane[0] : mreg[LOGM-1][0];
    wire signed [ACC_W-1:0] mrg_b = (LOGM == 1) ? acc_lane[1] : mreg[LOGM-1][1];
    wire signed [ACC_W-1:0] tot   = mrg_a + mrg_b;

    wire signed [ACC_W-1:0] acc_sh  = tot >>> SHIFT;

    wire signed [SAMPLE_W-1:0] y_sat;
    saturator #(.IN_W(ACC_W), .OUT_W(SAMPLE_W)) u_sat (
        .in_sample (acc_sh),
        .out_sample(y_sat)
    );

    always @(posedge clk) begin
        if (!resetn) begin
            fstate <= F_IDLE; jcnt <= 0; nblk <= 0; ch_r <= 0; scnt <= 0;
            done <= 1'b0; y_out <= 0;
            for (k = 0; k < NCH; k = k + 1) wp[k] <= 0;
            for (binit = 0; binit < MACS; binit = binit + 1) radr[binit] <= 0;

        end else begin
            done <= 1'b0;

            if ((fstate == F_RUN) && (jcnt < nblk)) begin
                for (binit = 0; binit < MACS; binit = binit + 1)
                    radr[binit] <= (radr[binit] == 0) ? DEPTH[ADW-1:0] - 1'b1 : radr[binit] - 1'b1;
            end

            case (fstate)
                F_IDLE: begin
                    if (start) begin
                        ch_r <= ch;
                        nblk <= ((ntaps == 0) || (ntaps > TAPS)) ? DEPTH[CNT_W-1:0]
                                                                 : (ntaps / MACS);

                        for (binit = 0; binit < MACS; binit = binit + 1)
                            radr[binit] <= ((wp[ch] - binit[PW-1:0]) & (TAPS[PW-1:0] - 1'b1)) >> LOGM;
                        rot_r  <= wp[ch][LOGM-1:0];
                        scnt   <= 4'd0;
                        jcnt   <= 0;
                        wp[ch] <= (wp[ch] + 1'b1) & (TAPS[PW-1:0] - 1'b1);
                        fstate <= F_RUN;
                    end
                end

                F_RUN: begin
                    jcnt <= jcnt + 1'b1;
                    if (run_fin) begin
                        scnt   <= 4'd0;
                        fstate <= F_SUM;
                    end
                end

                F_SUM: begin
                    if (scnt == (LOGM[3:0] - 4'd1)) begin
                        y_out  <= y_sat;
                        done   <= 1'b1;
                        fstate <= F_IDLE;
                    end else begin
                        scnt <= scnt + 1'b1;
                    end
                end

                default: fstate <= F_IDLE;
            endcase
        end
    end
endmodule
