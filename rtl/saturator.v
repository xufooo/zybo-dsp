// SPDX-License-Identifier: GPL-2.0-only


module saturator #(
    parameter IN_W  = 56,
    parameter OUT_W = 24
) (
    input  wire signed [IN_W-1:0] in_sample,
    output reg   signed [OUT_W-1:0] out_sample
);

    localparam signed [IN_W-1:0] MAX_VAL = {{(IN_W-OUT_W+1){1'b0}}, {(OUT_W-1){1'b1}}};
    localparam signed [IN_W-1:0] MIN_VAL = {{(IN_W-OUT_W+1){1'b1}}, {(OUT_W-1){1'b0}}};

    always @(*) begin
        if (in_sample > MAX_VAL)
            out_sample = {1'b0, {(OUT_W-1){1'b1}}};
        else if (in_sample < MIN_VAL)
            out_sample = {1'b1, {(OUT_W-1){1'b0}}};
        else
            out_sample = in_sample[OUT_W-1:0];
    end
endmodule
