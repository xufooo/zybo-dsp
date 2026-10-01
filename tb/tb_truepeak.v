// SPDX-License-Identifier: GPL-2.0-only


`timescale 1ns/1ps

module tb_truepeak;
    localparam SAMPLE_W = 24;
    localparam LOOK     = 96;
    localparam N        = 400;
    localparam PERIOD   = 120;

    localparam integer FULL     = 1 << 23;
    localparam integer THR      = 29491;
    localparam integer THR_ABS  = THR << 8;
    localparam real    JUMP_MAX = 0.05;

    reg clk = 0;
    always #5 clk = ~clk;

    reg                resetn = 0;
    reg  [SAMPLE_W-1:0] din = 0;
    reg                 sv = 0;
    reg                 bypass = 0;
    reg  [17:0]         thr = THR;
    reg  [17:0]         k_att = 18'd1310;
    reg  [17:0]         k_rel = 18'd8;

    wire                     out_valid;
    wire signed [SAMPLE_W-1:0] dout;
    wire signed [16:0]       gain_lg;
    wire                     overrun;
    wire [15:0]              gain_q15 = dut.gain_applied;

    truepeak_limiter #(.SAMPLE_W(SAMPLE_W), .LOOK(LOOK)) dut (
        .clk(clk), .resetn(resetn), .sample_valid(sv), .sample_in(din),
        .thr(thr), .k_att(k_att), .k_rel(k_rel), .bypass(bypass),
        .out_valid(out_valid), .sample_out(dout), .gain_lg(gain_lg), .overrun(overrun)
    );

    reg [SAMPLE_W-1:0] inq  [0:2*N];
    reg [SAMPLE_W-1:0] outq [0:2*N];
    reg [15:0]         gq   [0:2*N];
    integer nq = 0;
    integer nw = 0;

    always @(posedge clk) if (resetn && out_valid) begin
        outq[nq] = dout; gq[nq] = gain_q15; nq = nq + 1;
    end

    task feed(input [SAMPLE_W-1:0] v);
        begin
            @(negedge clk); din = v; sv = 1'b1;
            @(negedge clk); sv = 1'b0;
            inq[nw] = v; nw = nw + 1;
            repeat (PERIOD - 2) @(negedge clk);
        end
    endtask

    integer i, bad, njump, maxjump, pk, base;
    integer errors = 0;
    reg [SAMPLE_W-1:0] want;

    initial begin
        resetn = 0; repeat (10) @(negedge clk); resetn = 1; repeat (10) @(negedge clk);
        $display("=== truepeak_limiter check (LOOK=%0d, thr=0.9FS) ===", LOOK);

        bypass = 0; base = 0;
        for (i = 0; i < N; i = i + 1)
            feed(((((i * 24'h001357) ^ 24'h00A5A5) & 24'h7FFFF)) - 24'h40000 + 24'h1);

        repeat (PERIOD * (LOOK + 4)) @(negedge clk);
        bad = 0;
        for (i = LOOK; i < N; i = i + 1)
            if (outq[i] !== inq[i-LOOK]) begin
                if (bad < 3) $display("  FAIL[1] out[%0d]=%0d, want in[%0d]=%0d",
                                      i, $signed(outq[i]), i-LOOK, $signed(inq[i-LOOK]));
                bad = bad + 1;
            end
        if (bad == 0) $display("  OK   [1]: %0d samples below threshold bit-exact transparent (= input delayed %0d cycles)", N-LOOK, LOOK);
        else begin $display("  FAIL [1]: %0d samples not transparent", bad); errors = errors + 1; end

        nq = 0;
        for (i = 0; i < N; i = i + 1) begin
            if (i % 40 < 3) feed(24'sh7FFFF0);
            else            feed(sat24($rtoi(0.98 * FULL * $sin(6.2831853 * 1000.0 * i * PERIOD / 1.0e8))));
        end
        repeat (PERIOD * (LOOK + 4)) @(negedge clk);

        pk = 0;
        for (i = 0; i < N; i = i + 1) begin
            if ($signed(outq[i]) > pk)                pk = $signed(outq[i]);
            else if (-$signed(outq[i]) > pk)          pk = -$signed(outq[i]);
        end
        if (pk <= THR_ABS + THR_ABS / 10)
            $display("  OK   [2]: ceiling holds (output peak %0d <= threshold %0d + 10%%)", pk, THR_ABS);
        else begin
            $display("  FAIL [2]: ceiling broken (output peak %0d, threshold %0d)", pk, THR_ABS);
            errors = errors + 1;
        end

        njump = 0; maxjump = 0;
        for (i = 1; i < N; i = i + 1) begin
            bad = (gq[i] > gq[i-1]) ? (gq[i] - gq[i-1]) : (gq[i-1] - gq[i]);
            if (bad > maxjump) maxjump = bad;
            if (bad * 100 > 32768 * 5) njump = njump + 1;
        end
        if (njump == 0)
            $display("  OK   [3]: gain jumps >5%% count = 0 (max jump %0d/32768 = %0d%%)",
                     maxjump, maxjump * 100 / 32768);
        else begin
            $display("  FAIL [3]: %0d gain jumps >5%% (max %0d/32768)", njump, maxjump);
            errors = errors + 1;
        end

        nq = 0; nw = 0; bypass = 1;
        bypass = 1;
        for (i = 0; i < N; i = i + 1)
            feed((((i * 24'h003B1D) ^ 24'h005A5A) & 24'hFFFFFF));
        repeat (PERIOD * (LOOK + 4)) @(negedge clk);
        bad = 0;
        for (i = LOOK; i < N; i = i + 1)
            if (outq[i] !== inq[i-LOOK]) bad = bad + 1;
        if (bad == 0) $display("  OK   [4]: bypass bit-exact straight-through (= input delayed %0d cycles)", LOOK);
        else begin $display("  FAIL [4]: bypass has %0d mismatched samples", bad); errors = errors + 1; end

        if (overrun) begin
            $display("  FAIL [5]: overrun set (input outruns processing, widen test spacing)");
            errors = errors + 1;
        end else
            $display("  OK   [5]: no overrun (%0d-cycle spacing > LOOK+2=%0d)", PERIOD, LOOK+2);

        if (errors == 0) $display("\n=== ALL TESTS PASSED ===");
        else             $display("\n=== %0d ERRORS ===", errors);
        $finish;
    end

    function [SAMPLE_W-1:0] sat24(input integer v);
        begin
            if (v > FULL - 1)      sat24 = FULL - 1;
            else if (v < -FULL)    sat24 = -FULL;
            else                   sat24 = v[SAMPLE_W-1:0];
        end
    endfunction

    initial begin
        #40000000;
        $display("TIMEOUT (nw=%0d nq=%0d)", nw, nq);
        $finish;
    end
endmodule
