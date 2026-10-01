// SPDX-License-Identifier: GPL-2.0-only


`timescale 1ns / 1ps

module tb_fir_bank;
    localparam SAMPLE_W = 24;
    localparam COEF_W   = 18;
    localparam SHIFT    = 15;
    localparam ACC_W    = 56;
    localparam TAPS     = 64;
    localparam MACS8    = 8;
    localparam MACS16   = 16;
    localparam NCH      = 2;
    localparam DEPTH8   = TAPS/MACS8;
    localparam DEPTH16  = TAPS/MACS16;

    reg clk = 0;
    always #5 clk = ~clk;

    reg         resetn = 0;
    reg         cwr = 0;
    reg  [15:0] caddr = 0;
    reg  signed [COEF_W-1:0] cdat = 0;
    reg         start = 0;
    reg         ch = 0;
    reg  [15:0] ntaps = TAPS;
    reg  signed [SAMPLE_W-1:0] x_in = 0;
    wire        done8, done16;
    wire signed [SAMPLE_W-1:0] y8, y16;

    fir_bank #(
        .SAMPLE_W(SAMPLE_W), .COEF_W(COEF_W), .SHIFT(SHIFT), .ACC_W(ACC_W),
        .TAPS(TAPS), .MACS(MACS8), .NCH(NCH)
    ) dut8 (
        .clk(clk), .resetn(resetn),
        .cwr(cwr), .caddr(caddr), .cdat(cdat),
        .start(start), .ch(ch), .ntaps(ntaps), .x_in(x_in),
        .done(done8), .y_out(y8)
    );

    fir_bank #(
        .SAMPLE_W(SAMPLE_W), .COEF_W(COEF_W), .SHIFT(SHIFT), .ACC_W(ACC_W),
        .TAPS(TAPS), .MACS(MACS16), .NCH(NCH)
    ) dut16 (
        .clk(clk), .resetn(resetn),
        .cwr(cwr), .caddr(caddr), .cdat(cdat),
        .start(start), .ch(ch), .ntaps(ntaps), .x_in(x_in),
        .done(done16), .y_out(y16)
    );

    reg signed [COEF_W-1:0]   hch [0:NCH-1][0:TAPS-1];
    reg signed [SAMPLE_W-1:0] rh  [0:NCH-1][0:TAPS-1];
    integer i, c;

    task ref_step(input integer cc, input signed [SAMPLE_W-1:0] xn,
                  output signed [SAMPLE_W-1:0] yn);
        integer k2;
        reg signed [ACC_W-1:0] a;
        begin
            for (k2 = TAPS-1; k2 > 0; k2 = k2 - 1) rh[cc][k2] = rh[cc][k2-1];
            rh[cc][0] = xn;
            a = 0;
            for (k2 = 0; k2 < TAPS; k2 = k2 + 1)
                a = a + hch[cc][k2] * rh[cc][k2];
            yn = a >>> SHIFT;
            if ((a >>> SHIFT) >= 8388608 || (a >>> SHIFT) < -8388608) begin
                $display("  !! reference model saturated (acc>>>15 = %0d) -- premise of criterion 6 broken", a >>> SHIFT);
            end
        end
    endtask

    integer cyc8, cyc16;
    task run_one(input integer cc, input signed [SAMPLE_W-1:0] xn,
                 output signed [SAMPLE_W-1:0] o8, output signed [SAMPLE_W-1:0] o16);
        reg seen8, seen16;
        begin
            @(negedge clk);
            ch = cc[0]; x_in = xn; start = 1;
            cyc8 = 0; cyc16 = 0; seen8 = 0; seen16 = 0;
            @(negedge clk);
            start = 0;
            while (!(seen8 && seen16)) begin
                @(negedge clk);
                if (!seen8)  begin cyc8  = cyc8  + 1; if (done8)  seen8  = 1; end
                if (!seen16) begin cyc16 = cyc16 + 1; if (done16) seen16 = 1; end
                if (cyc8 > TAPS + 20 || cyc16 > TAPS + 20) begin
                    $display("  !! timeout: done never comes (ch=%0d seen8=%0d seen16=%0d)", cc, seen8, seen16);
                    $finish;
                end
            end
            o8  = y8;
            o16 = y16;
        end
    endtask

    integer fails = 0;
    task check(input cond, input [255:0] what);
        begin
            if (cond) $display("  OK   %0s", what);
            else begin $display("  FAIL %0s", what); fails = fails + 1; end
        end
    endtask

    integer n, mismatch0, mismatch1, mismatch16_0, mismatch16_1, mm_diff;
    reg signed [SAMPLE_W-1:0] yd8, yd16, y_ref;
    integer maxcyc8, maxcyc16;

    initial begin
        $display("\n== tb_fir_bank: parallel-split FIR core (TAPS=%0d, MACS=%0d and %0d, NCH=%0d) ==",
                 TAPS, MACS8, MACS16, NCH);
        for (c = 0; c < NCH; c = c + 1)
            for (i = 0; i < TAPS; i = i + 1) begin
                rh[c][i] = 0;

                hch[c][i] = (c == 0) ? ((i % 8) - 4) * 40 : (((i % 5) - 2) * 100);
            end

        resetn = 0;
        repeat (4) @(negedge clk);
        resetn = 1;
        repeat (2) @(negedge clk);

        for (c = 0; c < NCH; c = c + 1)
            for (i = 0; i < TAPS; i = i + 1) begin
                @(negedge clk);
                cwr = 1; caddr = c*TAPS + i; cdat = hch[c][i];
            end
        @(negedge clk); cwr = 0;

        $display("\n1. impulse response = coef sequence (x = 1.0), compare MACS=%0d and %0d each once", MACS8, MACS16);
        begin : imp_chk
            integer k3; reg signed [SAMPLE_W-1:0] imp;
            reg signed [ACC_W-1:0] pref;

            imp = 4194304;
            mismatch0 = 0; mismatch16_0 = 0; mm_diff = 0;
            for (n = 0; n < TAPS; n = n + 1) begin
                run_one(0, (n == 0) ? imp : 0, yd8, yd16);
                pref  = ((n == 0) ? hch[0][0] : hch[0][n]) * imp;
                y_ref = pref >>> SHIFT;
                if (yd8 !== y_ref) begin
                    mismatch0 = mismatch0 + 1;
                    if (mismatch0 <= 3) $display("     ch0/M8  k=%0d: dut=%0d ref=%0d", n, yd8, y_ref);
                end
                if (yd16 !== y_ref) begin
                    mismatch16_0 = mismatch16_0 + 1;
                    if (mismatch16_0 <= 3) $display("     ch0/M16 k=%0d: dut=%0d ref=%0d", n, yd16, y_ref);
                end
                if (yd8 !== yd16) begin
                    mm_diff = mm_diff + 1;
                    if (mm_diff <= 3) $display("     ch0 width mismatch k=%0d: M8=%0d M16=%0d", n, yd8, yd16);
                end
            end
            check(mismatch0 == 0,     "ch0 impulse response bit-exact vs coef sequence (64 points, MACS=8)");
            check(mismatch16_0 == 0,  "ch0 impulse response bit-exact vs coef sequence (64 points, MACS=16)");

            mismatch1 = 0; mismatch16_1 = 0;
            for (n = 0; n < TAPS; n = n + 1) begin
                run_one(1, (n == 0) ? imp : 0, yd8, yd16);
                pref  = ((n == 0) ? hch[1][0] : hch[1][n]) * imp;
                y_ref = pref >>> SHIFT;
                if (yd8 !== y_ref) begin
                    mismatch1 = mismatch1 + 1;
                    if (mismatch1 <= 3) $display("     ch1/M8  k=%0d: dut=%0d ref=%0d", n, yd8, y_ref);
                end
                if (yd16 !== y_ref) begin
                    mismatch16_1 = mismatch16_1 + 1;
                    if (mismatch16_1 <= 3) $display("     ch1/M16 k=%0d: dut=%0d ref=%0d", n, yd16, y_ref);
                end
                if (yd8 !== yd16) begin
                    mm_diff = mm_diff + 1;
                    if (mm_diff <= 3) $display("     ch1 width mismatch k=%0d: M8=%0d M16=%0d", n, yd8, yd16);
                end
            end
            check(mismatch1 == 0,    "ch1 impulse response bit-exact vs coef sequence (64 points, MACS=8)");
            check(mismatch16_1 == 0, "ch1 impulse response bit-exact vs coef sequence (64 points, MACS=16)");

            check(hch[0][0] !== hch[1][0], "two-channel coefs differ (channel-isolation premise holds)");
        end

        $display("\n4. pseudo-random signal x 3*TAPS samples, both widths bit-exact vs reference convolver");
        begin : rnd_chk
            integer m, n0, bad8, bad16, bad_diff;
            reg signed [SAMPLE_W-1:0] xn;
            bad8 = 0; bad16 = 0; bad_diff = 0; maxcyc8 = 0; maxcyc16 = 0;
            for (n0 = 0; n0 < 3*TAPS; n0 = n0 + 1) begin
                for (m = 0; m < NCH; m = m + 1) begin

                    xn = ((n0*7919 + m*104729) % 65536) - 32768;
                    run_one(m, xn, yd8, yd16);
                    if (cyc8  > maxcyc8)  maxcyc8  = cyc8;
                    if (cyc16 > maxcyc16) maxcyc16 = cyc16;
                    ref_step(m, xn, y_ref);
                    if (yd8 !== y_ref) begin
                        bad8 = bad8 + 1;
                        if (bad8 <= 3) $display("     M8  n=%0d ch=%0d: dut=%0d ref=%0d", n0, m, yd8, y_ref);
                    end
                    if (yd16 !== y_ref) begin
                        bad16 = bad16 + 1;
                        if (bad16 <= 3) $display("     M16 n=%0d ch=%0d: dut=%0d ref=%0d", n0, m, yd16, y_ref);
                    end
                    if (yd8 !== yd16) begin
                        bad_diff = bad_diff + 1;
                        if (bad_diff <= 3) $display("     width mismatch n=%0d ch=%0d: M8=%0d M16=%0d", n0, m, yd8, yd16);
                    end
                end
            end
            check(bad8 == 0, "MACS=8: all 3x64 samples x 2 channels bit-exact (incl. ring wrap)");
            check(bad16 == 0, "MACS=16: all 3x64 samples x 2 channels bit-exact (incl. ring wrap)");

            check(bad_diff == 0, "MACS=8 and MACS=16 outputs bit-exact (summation order irrelevant, no overflow)");
        end

        $display("\n5. throughput (cycle budget)");
        $display("     MACS=8 : one 64-tap convolution takes at most %0d cycles (TAPS/MACS = %0d)", maxcyc8,  DEPTH8);
        $display("     MACS=16: one 64-tap convolution takes at most %0d cycles (TAPS/MACS = %0d)", maxcyc16, DEPTH16);
        check(maxcyc8  <= DEPTH8  + 9, "MACS=8  cycles ~= TAPS/MACS + constant (4096 taps => 512+a few cycles/channel)");
        check(maxcyc16 <= DEPTH16 + 9, "MACS=16 cycles ~= TAPS/MACS + constant (4096 taps => 256+a few cycles/channel)");

        check(maxcyc8 >= maxcyc16, "MACS=16 not slower than MACS=8 (one more merge level, but half the blocks)");

        if (fails == 0) $display("\n== tb_fir_bank ALL PASSED ==\n");
        else            $display("\n== tb_fir_bank: %0d FAILED ==\n", fails);
        $finish;
    end

    initial begin
        #4000000;
        $display("!! simulation timeout");
        $finish;
    end
endmodule
