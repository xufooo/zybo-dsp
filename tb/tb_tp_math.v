// SPDX-License-Identifier: GPL-2.0-only


`timescale 1ns/1ps

module tb_tp_math;
    reg  [23:0] mag;
    wire signed [16:0] lg;
    reg  signed [16:0] xq;
    wire [15:0] gn;

    tp_log2 u_log (.mag(mag), .log2q(lg));
    tp_exp2 u_exp (.x_q5_11(xq), .gain_q15(gn));

    integer errors = 0, i, got, want, tol;
    real    r;

    initial begin
        $display("=== tp_log2 / tp_exp2 check ===");

        tol = 12;
        for (i = 0; i < 4000; i = i + 1) begin
            if      (i == 0) mag = 24'd0;
            else if (i == 1) mag = 24'd1;
            else if (i == 2) mag = 24'hFFFFFF;
            else if (i == 3) mag = 24'h800000;
            else if (i < 40)  mag = (24'd1 << (i - 4));
            else              mag = (i * 24'h00A3D7 + 24'd17) & 24'hFFFFFF;
            #1;
            if (mag == 24'd0) begin
                if (lg !== 17'sd0) begin
                    $display("  FAIL mag=0 should output 0, got %0d", lg);
                    errors = errors + 1;
                end
            end else begin
                r = $ln(mag + 0.0) / $ln(2.0) * 2048.0;
                want = $rtoi(r + 0.5);
                got  = lg;
                if (got > want + tol || got < want - tol) begin
                    if (errors < 5)
                        $display("  FAIL mag=%0d log2=%0d, want %0d (tolerance +/-%0d)", mag, got, want, tol);
                    errors = errors + 1;
                end
            end
        end
        if (errors == 0) $display("  OK   [1]: all 4000 tp_log2 samples within +/-%0d LSB", tol);

        begin : exp_sweep
            integer e0, g2, w2;
            e0 = errors; tol = 70;
            for (i = -24*2048; i <= 0; i = i + 97) begin
                xq = i[16:0];
                #1;
                r = $pow(2.0, i / 2048.0) * 32768.0;
                w2 = $rtoi(r + 0.5);
                g2 = gn;
                if (g2 > w2 + tol || g2 < w2 - tol) begin
                    if (errors - e0 < 5)
                        $display("  FAIL x=%0d gain=%0d, want %0d (tolerance +/-%0d)", i, g2, w2, tol);
                    errors = errors + 1;
                end
            end
            if (errors == e0) $display("  OK   [2]: all tp_exp2 samples within +/-%0d LSB", tol);

            xq = 17'sd0; #1;
            if (gn !== 16'd32768) begin
                $display("  FAIL x=0 should be exactly 32768 (1.0), got %0d", gn);
                errors = errors + 1;
            end else
                $display("  OK   [3]: x=0 -> gain exactly 1.0 (%0d)", gn);

            xq = 17'sd2048; #1;
            if (gn !== 16'd32768) begin
                $display("  FAIL x=+1.0 should clamp to 32768, got %0d", gn);
                errors = errors + 1;
            end else
                $display("  OK   [4]: x>0 clamps to 1.0 (compress only, never boost)");
        end

        if (errors == 0) $display("\n=== ALL TESTS PASSED ===");
        else             $display("\n=== %0d ERRORS ===", errors);
        $finish;
    end
endmodule
