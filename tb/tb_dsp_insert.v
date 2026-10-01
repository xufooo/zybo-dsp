// SPDX-License-Identifier: GPL-2.0-only


`timescale 1ns/1ps

module tb_dsp_insert;
    localparam SAMPLE_W = 24;
    localparam COEF_W   = 18;
    localparam SHIFT    = 15;
    localparam NB       = 6;
    localparam N        = 300;

    localparam integer QONE  = 1 << SHIFT;
    localparam integer QHALF = 1 << (SHIFT-1);
    localparam integer QTWO  = 1 << (SHIFT+1);

    reg clk = 0;
    always #5 clk = ~clk;

    reg                     resetn = 0;
    reg                     dsp_bypass = 1;
    reg  [3:0]              nbands = 0;
    reg  [5:0]              cidx = 0;
    reg                     cwr = 0;
    reg  [31:0]             cdat = 0;
    wire [31:0]             cdat_rd;

    reg                     lim_bypass = 1;
    reg  [17:0]             lim_thr  = 18'd29491;
    reg  [17:0]             lim_att  = 18'd32440;
    reg  [17:0]             lim_rel  = 18'd32784;

    wire                     in_ack;
    wire                     out_stb;
    wire [SAMPLE_W-1:0]      out_data;
    reg                      out_ack = 0;

    reg  [SAMPLE_W-1:0]      in_data = 0;
    reg                      in_stb  = 0;
    integer                  rdptr = 0;

    reg                      imp_mode = 0;
    reg                      imp_pending = 0;

    dsp_insert #(.SAMPLE_W(SAMPLE_W), .COEF_W(COEF_W), .SHIFT(SHIFT), .NB(NB)) dut (
        .clk(clk), .resetn(resetn),
        .in_stb(in_stb), .in_data(in_data), .in_ack(in_ack),
        .out_stb(out_stb), .out_data(out_data), .out_ack(out_ack),
        .dsp_bypass(dsp_bypass), .nbands(nbands),
        .cidx(cidx), .cwr(cwr), .cdat(cdat), .cdat_rd(cdat_rd),
        .lim_bypass(lim_bypass), .lim_thr(lim_thr), .lim_att(lim_att), .lim_rel(lim_rel)
    );

    reg [SAMPLE_W-1:0] acc [0:8*N+1024];
    reg [SAMPLE_W-1:0] lat [0:8*N+1024];
    integer na = 0, nl = 0;

    always @(posedge clk) if (resetn && in_stb && in_ack) begin
        acc[na] = in_data; na = na + 1;
    end
    always @(posedge clk) if (resetn && out_ack) begin
        lat[nl] = out_data; nl = nl + 1;
    end

    always @(posedge clk) begin
        if (resetn) begin
            if (rdptr < 6*N + 512) begin
                in_stb  <= 1'b1;
                if (imp_mode)
                    in_data <= imp_pending ? 24'sh3FFFFE : 24'sd0;
                else
                    in_data <= ({8'b0, (rdptr * 24'h001357) ^ 24'h00A5A5}) & 24'hFFFFFE;
            end else begin
                in_stb  <= 1'b0;
            end
            if (in_stb && in_ack) begin
                rdptr <= rdptr + 1;
                if (imp_mode && imp_pending) imp_pending <= 1'b0;
            end
        end
    end

    integer gap2;
    initial begin
        forever begin
            gap2 = 50 + ({$random} % 20);
            repeat (gap2) @(negedge clk);
            out_ack = 1'b1;
            @(negedge clk);
            out_ack = 1'b0;
        end
    end

    task put_coef(input [5:0] idx, input integer val);
        begin
            @(negedge clk); cidx = idx; cdat = val; cwr = 1'b1;
            @(negedge clk); cwr = 1'b0;
            @(negedge clk);
        end
    endtask

    task put_band(input integer band, input integer v0, input integer v1,
                  input integer v2, input integer v3, input integer v4);
        begin
            put_coef(band*5 + 0, v0);
            put_coef(band*5 + 1, v1);
            put_coef(band*5 + 2, v2);
            put_coef(band*5 + 3, v3);
            put_coef(band*5 + 4, v4);
        end
    endtask

    integer k, errors = 0;
    integer a_end = 0, b_end = 0;
    integer b0b = 0, b0a = 0, c0b = 0, c0a = 0, d0b = 0, d0a = 0;
    integer c_end = 0, d_end_a = 0;
    integer e0b = 0, e0a = 0, e_end_a = 0;
    integer f0b = 0, f0a = 0;

    task chk_phase(input integer base, input integer ref, input integer shift,
                   input integer j0, input integer jmax, input integer tol,
                   input integer tag);
        integer j, bad, exp;
        begin
            bad = 0;
            for (j = j0; j < jmax; j = j + 1) begin
                exp = acc[ref + j + shift];
                if (lat[base + j] > exp + tol || lat[base + j] < exp - tol) begin
                    if (bad < 3)
                        $display("  FAIL [%0d] j=%0d: expected %0d, got %0d",
                                 tag, j, exp, lat[base + j]);
                    bad = bad + 1;
                end
            end
            if (bad == 0)
                $display("  OK   [%0d]: %0d samples match (tolerance +/-%0d)", tag, jmax - j0, tol);
            else
                errors = errors + 1;
        end
    endtask

    initial begin

        for (k = 0; k < 8; k = k + 1) dut.mem[k] = {SAMPLE_W{1'b0}};

        resetn = 0;
        repeat (5) @(negedge clk);
        resetn = 1;

        wait (na >= N);
        @(posedge clk);
        a_end = nl;

        put_band(0, QONE, 0, 0, 0, 0);
        nbands = 1;
        dsp_bypass = 0;
        repeat (40) @(negedge clk);
        b0b = nl; b0a = na;
        wait (na >= 2*N);
        repeat (200) @(negedge clk);
        b_end = nl;

        put_band(0, QHALF, 0, 0, 0, 0);
        put_band(1, QTWO,  0, 0, 0, 0);
        nbands = 2;
        repeat (40) @(negedge clk);
        c0b = nl; c0a = na;

        wait (na >= 3*N);
        repeat (200) @(negedge clk);
        c_end = nl;
        nbands = 1;
        repeat (40) @(negedge clk);
        d0b = nl; d0a = na;
        wait (na >= 4*N);
        @(posedge clk); d_end_a = na;
        repeat (200) @(negedge clk);

        lim_thr    = 18'd3277;
        lim_att    = 18'd29491;
        lim_rel    = 18'd32784;
        lim_bypass = 0;
        repeat (40) @(negedge clk);
        e0b = nl; e0a = na;
        wait (na >= 4*N + 100);
        @(posedge clk); e_end_a = na;
        repeat (200) @(negedge clk);

        resetn = 0;
        repeat (5) @(negedge clk);
        resetn = 1;
        dsp_bypass = 0;
        nbands = 1;
        lim_bypass = 1;
        put_band(0, 33822, -64275, 31008, -64275, 32061);
        imp_mode = 1;
        repeat (400) @(negedge clk);
        f0b = nl; f0a = na;
        imp_pending = 1;
        repeat (4) @(negedge clk);
        wait (na >= f0a + 80);
        repeat (400) @(negedge clk);

        $display("=== dsp_insert check (NB=%0d, Q%0d.%0d) ===", NB, COEF_W-SHIFT, SHIFT);
        $display("  upstream consumed %0d, downstream acks %0d", na, nl);

        if (a_end < 20) begin
            $display("  FAIL phase A recorded too few acks (%0d)", a_end);
            errors = errors + 1;
        end else
            chk_phase(0, 0, 0, 0, a_end, 0, 0);

        chk_phase(b0b, b0a, -1, 1, b_end - b0b - 1, 0, 1);

        chk_phase(c0b, c0a, -1, 2, c_end - c0b - 1, 0, 2);

        begin : gate_check
            integer j, bad, jmax;
            bad = 0;
            jmax = nl - d0b - 1;
            if (jmax > d_end_a - d0a) jmax = d_end_a - d0a;
            if (jmax > 200) jmax = 200;
            for (j = 2; j < jmax; j = j + 1)
                if (lat[d0b + j] != (acc[d0a + j - 1] >> 1)) bad = bad + 1;
            if (bad == 0)
                $display("  OK   [3]: section-count gating correct (nbands=1 -> band1 bypassed, out = in x0.5)");
            else begin
                $display("  FAIL [3]: with nbands=1 output is not x0.5 (%0d mismatching samples)", bad);
                errors = errors + 1;
            end
        end

        begin : lim_check
            integer j, jmax, peak_in, peak_out;
            peak_in = 0; peak_out = 0;
            jmax = nl - e0b - 1;
            if (jmax > e_end_a - e0a) jmax = e_end_a - e0a;
            if (jmax > 400) jmax = 400;
            for (j = 2; j < jmax; j = j + 1) begin
                if (acc[e0a + j - 1] > peak_in)  peak_in  = acc[e0a + j - 1];
                if (lat[e0b + j]     > peak_out) peak_out = lat[e0b + j];
            end
            if (peak_out < peak_in / 2) begin
                $display("  OK   [4]: limiter engaged (input peak %0d -> output peak %0d)",
                         peak_in, peak_out);

                if (peak_out > 24'sh7FFFFF * 3 / 4) begin
                    $display("  FAIL [4]: output near full scale, looks like hard clipping not limiting");
                    errors = errors + 1;
                end
            end else begin
                $display("  FAIL [4]: limiter did not hold (input peak %0d, output peak %0d)",
                         peak_in, peak_out);
                errors = errors + 1;
            end
        end

        begin : xtalk_check
            integer j, jmax, k0, bad, ring;
            bad = 0; ring = 0; k0 = -1;
            jmax = nl - f0b - 1;
            if (jmax > 300) jmax = 300;
            for (j = 1; j < jmax; j = j + 1)
                if (k0 < 0 && lat[f0b + j] != 0) k0 = j;
            if (k0 < 0) begin
                $display("  FAIL [5]: no impulse response seen (resonant filter not connected?)");
                errors = errors + 1;
            end else begin

                for (j = k0; j < jmax; j = j + 1) begin
                    if (((j - k0) % 2) == 1) begin
                        if (lat[f0b + j] != 0) begin
                            if (bad < 3)
                                $display("  FAIL [5] other-channel leak: slot %0d = %0d",
                                         j, lat[f0b + j]);
                            bad = bad + 1;
                        end
                    end else if (lat[f0b + j] != 0) ring = ring + 1;
                end
                if (bad == 0 && ring > 5)
                    $display("  OK   [5]: crosstalk is 0 (own-channel tail %0d slots, other channel all 0)", ring);
                else if (bad == 0) begin
                    $display("  FAIL [5]: own channel barely rings (%0d) — filter may be inactive", ring);
                    errors = errors + 1;
                end
                else
                    errors = errors + 1;
            end
        end

        if (errors == 0) $display("\n=== ALL TESTS PASSED ===");
        else             $display("\n=== %0d ERRORS ===", errors);
        $finish;
    end

    initial begin
        #4000000;
        $display("TIMEOUT (na=%0d nl=%0d)", na, nl);
        $finish;
    end
endmodule
