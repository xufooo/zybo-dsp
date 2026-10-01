// SPDX-License-Identifier: GPL-2.0-only


`timescale 1ns/1ps

module tb_limiter;
    localparam SAMPLE_W = 24;
    localparam PARAM_W  = 18;
    localparam SHIFT    = 15;
    localparam N        = 200;

    reg clk = 0;
    always #5 clk = ~clk;

    reg                    resetn = 0;
    reg                    sample_valid = 0;
    reg  signed [SAMPLE_W-1:0] sample_in = 0;
    reg  [PARAM_W-1:0]     thr = 18'd29491;
    reg  [PARAM_W-1:0]     k_att = 18'd26214;
    reg  [PARAM_W-1:0]     k_rel = 18'd32784;
    reg                    bypass = 1;
    wire                   out_valid;
    wire signed [SAMPLE_W-1:0] sample_out;

    limiter #(.SAMPLE_W(SAMPLE_W), .PARAM_W(PARAM_W), .SHIFT(SHIFT)) dut (
        .clk(clk), .resetn(resetn), .sample_valid(sample_valid),
        .sample_in(sample_in), .thr(thr), .k_att(k_att), .k_rel(k_rel),
        .bypass(bypass), .out_valid(out_valid), .sample_out(sample_out)
    );

    reg signed [SAMPLE_W-1:0] vin  [0:4*N];
    reg signed [SAMPLE_W-1:0] vout [0:4*N];
    integer nin = 0, nout = 0;

    always @(posedge clk) if (resetn && sample_valid) begin
        vin[nin] = sample_in; nin = nin + 1;
    end
    always @(posedge clk) if (resetn && out_valid) begin
        vout[nout] = sample_out; nout = nout + 1;
    end

    integer nmon = 0;
    always @(posedge clk) if (resetn && sample_valid && nmon < 8) begin
        $display("    [v] in=%0d in[23]=%b ax_comb=%0d gain=%0d v0=%b",
                 sample_in, sample_in[23], dut.ax_comb, dut.gain, dut.v0);
        nmon = nmon + 1;
    end

    integer i, k, errors = 0;
    integer amp;
    task feed(input integer n, input integer amplitude);
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(negedge clk);
                sample_valid = 1'b1;

                sample_in = ((i % 2) == 0) ? amplitude : -amplitude;
                @(negedge clk);
                sample_valid = 1'b0;
                repeat (5) @(negedge clk);
            end
        end
    endtask

    integer base_in, base_out, bad, j, jmax;
    integer sh_sel;
    task chk(input integer tag, input integer expect_scale_num, input integer expect_scale_den,
             input integer tol);
        integer sh, jj, bb, best, best_sh;
        begin

            best = 1 << 30; best_sh = 0;
            for (sh = 1; sh <= 6; sh = sh + 1) begin
                bb = 0; jmax = nout - base_out;
                if (jmax > N) jmax = N;
                for (jj = sh; jj < jmax; jj = jj + 1)
                    if ($signed(vout[base_out + jj]) > $signed((vin[base_in + jj - sh] * expect_scale_num) / expect_scale_den) + tol ||
                        $signed(vout[base_out + jj]) < $signed((vin[base_in + jj - sh] * expect_scale_num) / expect_scale_den) - tol)
                        bb = bb + 1;
                if (bb < best) begin best = bb; best_sh = sh; end
            end
            sh_sel = best_sh;
            bad = best;
            if (bad == 0) $display("  OK   [%0d]: %0d samples as expected (delay %0d valids, ratio %0d/%0d)",
                                   tag, jmax - best_sh, best_sh, expect_scale_num, expect_scale_den);
            else begin
                $display("  FAIL [%0d]: %0d samples mismatch (best delay %0d)", tag, bad, best_sh);
                for (k = 0; k < 5; k = k + 1)
                    $display("        j=%0d: in=%0d out=%0d", best_sh + k,
                             vin[base_in + k], vout[base_out + best_sh + k]);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        resetn = 0;
        repeat (10) @(negedge clk);
        resetn = 1;
        repeat (5) @(negedge clk);

        bypass = 1;
        base_in = nin; base_out = nout;
        feed(N, 1000000);
        chk(1, 1, 1, 0);

        $display("  [dbg] thr=%0d thr_abs=%0d (want %0d)  GAIN_ONE=%0d",
                 thr, dut.thr_abs, thr * (1 << (SAMPLE_W-1-SHIFT)), dut.GAIN_ONE);

        bypass = 0;
        thr = 18'd29491;
        repeat (20) @(negedge clk);
        base_in = nin; base_out = nout;
        feed(N, 100000);
        $display("  [dbg] end of phase 2: gain=%0d ax0=%0d thr_abs=%0d",
                 dut.gain, dut.ax0, dut.thr_abs);
        chk(2, 1, 1, 0);

        thr = 18'd3277;
        repeat (20) @(negedge clk);
        base_in = nin; base_out = nout;
        feed(N, 1000000);

        begin : lim_level
            integer jj, bb, lo, hi;
            bb = 0;
            lo = 838860 / 3;
            hi = 838860 * 3;
            for (jj = 30; jj < nout - base_out && jj < N; jj = jj + 1) begin
                if ($signed(vout[base_out + jj]) > hi || $signed(vout[base_out + jj]) < -hi) bb = bb + 1;
                if (vout[base_out + jj] != 0 && $signed(vout[base_out + jj]) < lo &&
                    $signed(vout[base_out + jj]) > -lo) bb = bb + 1;
            end
            if (bb == 0) $display("  OK   [3]: output level stably clamped near threshold (%0d~%0d)", lo, hi);
            else begin
                $display("  FAIL [3]: %0d samples not settled near threshold (last out=%0d, threshold 838860)",
                         bb, vout[nout-1]);
                errors = errors + 1;
            end
        end

        if (errors == 0) $display("\n=== ALL TESTS PASSED ===");
        else             $display("\n=== %0d ERRORS ===", errors);
        $finish;
    end

    initial begin
        #2000000;
        $display("TIMEOUT (nin=%0d nout=%0d)", nin, nout);
        $finish;
    end
endmodule
