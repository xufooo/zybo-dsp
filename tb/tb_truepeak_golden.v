// SPDX-License-Identifier: GPL-2.0-only


`timescale 1ns/1ps

module tb_truepeak_golden;
    localparam SAMPLE_W = 24;
    localparam LOOK     = 96;
    localparam N        = 600;
    localparam PERIOD   = 120;

    reg clk = 0;
    always #5 clk = ~clk;

    reg                 resetn = 0;
    reg  [SAMPLE_W-1:0] din = 0;
    reg                 sv = 0;
    reg  [17:0]         thr   = 18'd29491;
    reg  [17:0]         k_att = 18'd1310;
    reg  [17:0]         k_rel = 18'd8;

    wire                       out_valid;
    wire signed [SAMPLE_W-1:0] dout;
    wire                       overrun;

    truepeak_limiter #(.SAMPLE_W(SAMPLE_W), .LOOK(LOOK)) dut (
        .clk(clk), .resetn(resetn), .sample_valid(sv), .sample_in(din),
        .thr(thr), .k_att(k_att), .k_rel(k_rel), .bypass(1'b0),
        .out_valid(out_valid), .sample_out(dout), .gain_lg(), .overrun(overrun)
    );

    reg [SAMPLE_W-1:0] gin  [0:N-1];
    reg [SAMPLE_W-1:0] gout [0:N-1];
    reg [15:0]         ggn  [0:N-1];
    reg [SAMPLE_W-1:0] rout [0:N-1];
    reg [15:0]         rgn  [0:N-1];

    integer nq = 0, i, badout, badgain;

    always @(posedge clk) if (resetn && out_valid) begin
        rout[nq] = dout; rgn[nq] = dut.gain_applied; nq = nq + 1;
    end

    initial begin
        $readmemh("tp_gold_in.hex",   gin);
        $readmemh("tp_gold_out.hex",  gout);
        $readmemh("tp_gold_gain.hex", ggn);

        resetn = 0; repeat (10) @(negedge clk); resetn = 1; repeat (10) @(negedge clk);
        $display("=== truepeak_limiter bit-exact check vs fixed-point model (%0d samples) ===", N);

        for (i = 0; i < N; i = i + 1) begin
            @(negedge clk); din = gin[i]; sv = 1'b1;
            @(negedge clk); sv = 1'b0;
            repeat (PERIOD - 2) @(negedge clk);
        end
        repeat (PERIOD * 4) @(negedge clk);

        if (nq < N) begin
            $display("  FAIL: only produced %0d samples (want %0d)", nq, N);
            $display("\n=== 1 ERRORS ===");
            $finish;
        end

        badout = 0; badgain = 0;
        for (i = 0; i < N; i = i + 1) begin
            if (rout[i] !== gout[i]) begin
                if (badout < 3)
                    $display("  FAIL output #%0d: RTL %0d, model %0d", i, $signed(rout[i]), $signed(gout[i]));
                badout = badout + 1;
            end
            if (rgn[i] !== ggn[i]) begin
                if (badgain < 3)
                    $display("  FAIL gain #%0d: RTL %0d, model %0d", i, rgn[i], ggn[i]);
                badgain = badgain + 1;
            end
        end

        if (badout == 0)
            $display("  OK   [1]: output of %0d samples bit-exact vs model", N);
        else
            $display("  FAIL [1]: %0d/%0d outputs mismatch model", badout, N);

        if (badgain == 0)
            $display("  OK   [2]: gain of %0d samples bit-exact vs model (listening trajectory matches)", N);
        else
            $display("  FAIL [2]: %0d/%0d gains mismatch model", badgain, N);

        if (overrun) begin
            $display("  FAIL [3]: overrun set");
            $display("\n=== 1 ERRORS ===");
        end else if (badout == 0 && badgain == 0) begin
            $display("  OK   [3]: no overrun");
            $display("\n=== ALL TESTS PASSED ===");
        end else
            $display("\n=== 2 ERRORS ===");
        $finish;
    end

    initial begin
        #40000000;
        $display("TIMEOUT (nq=%0d)", nq);
        $finish;
    end
endmodule
