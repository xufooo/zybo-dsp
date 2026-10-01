// SPDX-License-Identifier: GPL-2.0-only


module biquad_filter #(
    parameter SAMPLE_W = 24,
    parameter COEF_W   = 18,
    parameter SHIFT    = 15,
    parameter ACC_W    = 56
) (
    input  wire                         clk,
    input  wire                         reset,
    input  wire                         clear,
    input  wire                         sample_valid,
    input  wire signed [SAMPLE_W-1:0]   sample_in,
    input  wire signed [COEF_W-1:0]     b0,
    input  wire signed [COEF_W-1:0]     b1,
    input  wire signed [COEF_W-1:0]     b2,
    input  wire signed [COEF_W-1:0]     a1,
    input  wire signed [COEF_W-1:0]     a2,
    output reg                          out_valid,
    output reg  signed [SAMPLE_W-1:0]   sample_out
);

    reg signed [SAMPLE_W-1:0] x1, x2;
    reg signed [SAMPLE_W-1:0] y1, y2;
    reg signed [SAMPLE_W-1:0] x_in_d, x1_d;

    reg signed [ACC_W-1:0] p0, p1, p2, p3, p4;
    reg signed [ACC_W-1:0] s01, s23, p4_d;
    reg signed [ACC_W-1:0] acc;
    reg signed [ACC_W-1:0] scaled_r;

    wire signed [ACC_W-1:0] scaled;
    wire signed [SAMPLE_W-1:0] y_clip;

    reg [3:0] valid_pipe;

    assign scaled = scaled_r;

    saturator #(.IN_W(ACC_W), .OUT_W(SAMPLE_W)) u_sat (
        .in_sample(scaled),
        .out_sample(y_clip)
    );

    always @(posedge clk) begin
        if (reset || clear) begin
            x1 <= 0; x2 <= 0; y1 <= 0; y2 <= 0;
            x_in_d <= 0; x1_d <= 0;
            p0 <= 0; p1 <= 0; p2 <= 0; p3 <= 0; p4 <= 0;
            s01 <= 0; s23 <= 0; p4_d <= 0;
            acc <= 0; scaled_r <= 0;
            sample_out <= 0;
            out_valid  <= 1'b0;
            valid_pipe <= 0;
        end else begin

            valid_pipe <= {valid_pipe[2:0], sample_valid};
            out_valid  <= valid_pipe[3];

            if (sample_valid) begin
                p0 <= sample_in * b0;
                p1 <= x1 * b1;
                p2 <= x2 * b2;
                p3 <= y1 * a1;
                p4 <= y2 * a2;
                x_in_d <= sample_in;
                x1_d <= x1;
            end

            s01  <= p0 + p1;
            s23  <= p2 - p3;
            p4_d <= p4;

            acc <= s01 + s23 - p4_d;

            scaled_r <= acc >>> SHIFT;

            if (valid_pipe[3]) begin
                sample_out <= y_clip;
                x2 <= x1_d;
                x1 <= x_in_d;
                y2 <= y1;
                y1 <= y_clip;
            end
        end
    end

endmodule
