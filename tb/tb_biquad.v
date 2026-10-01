// SPDX-License-Identifier: GPL-2.0-only


`timescale 1ns/1ps

module tb_biquad;
    localparam SAMPLE_W = 24;
    localparam COEF_W   = 18;
    localparam SHIFT    = 15;

    localparam integer PEAK = 4194304;
    localparam integer QONE = 1 << SHIFT;

    localparam signed [COEF_W-1:0] LP_B0 =    128;
    localparam signed [COEF_W-1:0] LP_B1 =    257;
    localparam signed [COEF_W-1:0] LP_B2 =    128;
    localparam signed [COEF_W-1:0] LP_A1 = -59485;
    localparam signed [COEF_W-1:0] LP_A2 =  27230;

    reg clk = 0;
    always #5 clk = ~clk;

    reg reset = 1, clear = 0, sample_valid = 0;
    reg signed [SAMPLE_W-1:0] sample_in = 0;
    reg signed [COEF_W-1:0] b0 = 0, b1 = 0, b2 = 0, a1 = 0, a2 = 0;

    wire out_valid;
    wire signed [SAMPLE_W-1:0] sample_out;

    biquad_filter #(.SAMPLE_W(SAMPLE_W), .COEF_W(COEF_W), .SHIFT(SHIFT)) dut (
        .clk(clk), .reset(reset), .clear(clear),
        .sample_valid(sample_valid), .sample_in(sample_in),
        .b0(b0), .b1(b1), .b2(b2), .a1(a1), .a2(a2),
        .out_valid(out_valid), .sample_out(sample_out)
    );

    reg signed [SAMPLE_W-1:0] outq [0:8191];
    integer qn = 0;
    always @(posedge clk) begin
        if (out_valid) begin
            outq[qn] = sample_out;
            qn = qn + 1;
        end
    end

    integer errors = 0;
    integer i;
    integer got;

    task push(input signed [SAMPLE_W-1:0] s);
        begin
            @(negedge clk);
            sample_in = s; sample_valid = 1'b1;
            @(negedge clk);
            sample_valid = 1'b0;
            repeat (8) @(negedge clk);
        end
    endtask

    task do_clear;
        begin
            clear = 1'b1;
            repeat (4) @(negedge clk);
            clear = 1'b0;
            repeat (2) @(negedge clk);
        end
    endtask

    task chk(input integer g, input integer expect, input integer tol,
             input [255:0] name);
        begin
            if ((g > expect - tol) && (g < expect + tol)) begin
                $display("  OK   %0s: got=%0d (expect %0d +/- %0d)", name, g, expect, tol);
            end else begin
                $display("  FAIL %0s: got=%0d (expect %0d +/- %0d)", name, g, expect, tol);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        reset = 1'b1;
        repeat (5) @(negedge clk);
        reset = 1'b0;
        repeat (2) @(negedge clk);

        $display("=== Test 1: unity gain (b0=1.0) ===");
        b0 = QONE; b1 = 0; b2 = 0; a1 = 0; a2 = 0;
        do_clear;
        qn = 0;
        push(PEAK);
        for (i = 0; i < 6; i = i + 1) push(0);
        repeat (10) @(negedge clk);
        if (qn < 7) begin
            $display("  FAIL too few output samples (qn=%0d)", qn);
            errors = errors + 1;
        end else begin
            chk(outq[0], PEAK, 2, "impulse y[0]");
            for (i = 1; i < 6; i = i + 1) chk(outq[i], 0, 2, "impulse tail");
        end

        $display("=== Test 2: LPF DC gain (expect 1.0) ===");
        b0 = LP_B0; b1 = LP_B1; b2 = LP_B2; a1 = LP_A1; a2 = LP_A2;
        do_clear;
        qn = 0;
        for (i = 0; i < 400; i = i + 1) push(PEAK);
        repeat (10) @(negedge clk);
        got = outq[qn-1];
        chk(got, PEAK, 42000, "DC steady-state");

        $display("=== Test 3: LPF Nyquist gain (expect ~0) ===");
        do_clear;
        qn = 0;
        for (i = 0; i < 400; i = i + 1) begin
            if (i % 2 == 0) push(PEAK); else push(-PEAK);
        end
        repeat (10) @(negedge clk);
        got = outq[qn-1];
        if (got < 0) got = -got;
        if (got < 41943) begin
            $display("  OK   Nyquist attenuation: |out|=%0d (< 1%% FS)", got);
        end else begin
            $display("  FAIL Nyquist attenuation: |out|=%0d (filter or sign problem)", got);
            errors = errors + 1;
        end

        if (errors == 0) $display("\n=== ALL TESTS PASSED ===");
        else             $display("\n=== %0d ERRORS ===", errors);
        $finish;
    end

    initial begin
        #5000000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
