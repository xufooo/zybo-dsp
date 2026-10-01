// SPDX-License-Identifier: GPL-2.0-only


module tb_engine_delay;

    localparam SLOT_HDR = 192;
    localparam HOLD     = 400;

    localparam SAMPLE_W = 24;
    localparam COEF_W   = 18;
    localparam SHIFT    = 15;
    localparam NB       = 6;
    localparam HEADROOM = 0;

    reg clk = 0;
    always #5 clk = ~clk;

    reg         resetn = 0;
    reg         dsp_bypass = 1;
    reg  [3:0]  nbands = 0;
    reg  [15:0] cidx = 0;
    reg         cwr = 0;
    reg  [31:0] cdat = 0;
    reg  [15:0] slot_addr = 0;
    reg  [31:0] slot_data = 0;
    reg         slot_we = 0;
    reg         bank_sel = 0;
    reg         commit = 0;
    wire [31:0] status, cap0, cap1, cap2, cap3, rd;
    reg         lim_bypass = 1;
    reg         lim_tp = 0;
    reg  [17:0] lim_thr = 18'd3277;
    reg  [17:0] lim_att = 18'd29491;
    reg  [17:0] lim_rel = 18'd32784;
    reg         headroom = 0;

    reg  [SAMPLE_W-1:0] in_data = 0;
    reg                 in_stb = 0;
    wire                in_ack, out_stb;
    wire [SAMPLE_W-1:0] out_data;
    reg                 out_ack = 0;

    dsp_engine #(.SAMPLE_W(SAMPLE_W), .COEF_W(COEF_W), .SHIFT(SHIFT),
                 .NB(NB), .HEADROOM(HEADROOM)) u_dut (
        .clk(clk), .resetn(resetn),
        .in_stb(in_stb), .in_data(in_data), .in_ack(in_ack),
        .out_stb(out_stb), .out_data(out_data), .out_ack(out_ack),
        .dsp_bypass(dsp_bypass), .nbands(nbands),
        .cidx(cidx), .cwr(cwr), .cdat(cdat), .cdat_rd(rd),
        .slot_addr(slot_addr), .slot_data(slot_data), .slot_we(slot_we),
        .bank_sel(bank_sel), .commit(commit),
        .status(status), .cap0(cap0), .cap1(cap1), .cap2(cap2), .cap3(cap3),
        .lim_bypass(lim_bypass), .lim_thr(lim_thr), .lim_att(lim_att), .lim_rel(lim_rel),
        .lim_tp(lim_tp), .headroom(headroom)
    );

    integer fail = 0;
    integer si;

    task put_coef(input integer idx, input integer val);
        begin
            @(negedge clk); cidx = idx[15:0]; cwr = 1; cdat = val[31:0];
            @(negedge clk); cwr = 0;
        end
    endtask
    task put_slot(input integer widx, input [31:0] val);
        begin
            @(negedge clk); slot_addr = widx[15:0]; slot_data = val; slot_we = 1;
            @(negedge clk); slot_we = 0;
        end
    endtask
    task do_commit;
        begin
            @(negedge clk); commit = 1;
            @(negedge clk); commit = 0;
            while (status[0]) @(negedge clk);
            repeat (8) @(negedge clk);
        end
    endtask

    task load_delay(input integer len, input integer flags);
        begin

            bank_sel = ~u_dut.active_bank;
            put_coef(0, len);
            put_slot(0*8 + 0, {8'd0, 8'd1, flags[7:0], 8'd4});
            put_slot(0*8 + 1, 32'd0);
            put_slot(0*8 + 2, 32'd0);
            put_slot(0*8 + 3, 32'd0);
            put_slot(0*8 + 4, 32'h0000FFFF);
            put_slot(0*8 + 5, 32'd1);
            put_slot(0*8 + 6, 32'd0);
            put_slot(0*8 + 7, 32'd0);
            put_slot(SLOT_HDR, 32'd1);
            do_commit;
        end
    endtask

    task load_pair_flagsr(input integer lenA, input integer offA,
                          input integer lenB, input integer offB);
        begin
            bank_sel = ~u_dut.active_bank;
            put_coef(0, lenA);
            put_coef(1, lenB);
            put_slot(0*8 + 0, {8'd0, 8'd1, 8'd0, 8'd4});
            put_slot(0*8 + 1, 32'd0);
            put_slot(0*8 + 2, offA);
            put_slot(0*8 + 3, 32'd0);
            put_slot(0*8 + 4, 32'h0000FFFF);
            put_slot(0*8 + 5, 32'd1);
            put_slot(0*8 + 6, 32'd0);
            put_slot(0*8 + 7, 32'd0);
            put_slot(1*8 + 0, {8'd0, 8'd1, 8'd4, 8'd4});
            put_slot(1*8 + 1, 32'd1);
            put_slot(1*8 + 2, offB);
            put_slot(1*8 + 3, 32'd1);
            put_slot(1*8 + 4, 32'h0000FFFF);
            put_slot(1*8 + 5, 32'd2);
            put_slot(1*8 + 6, 32'd0);
            put_slot(1*8 + 7, 32'd0);
            put_slot(SLOT_HDR, 32'd2);
            do_commit;
        end
    endtask

    task load_six_then_flagsr(input integer len, input integer off);
        begin
            bank_sel = ~u_dut.active_bank;
            put_coef(0, len);
            for (si = 0; si < 6; si = si + 1) begin
                put_slot(si*8 + 0, {8'd0, 8'd1, 8'd0, 8'd8});
                put_slot(si*8 + 1, 32'd0);
                put_slot(si*8 + 2, si*3);
                put_slot(si*8 + 3, si);
                put_slot(si*8 + 4, 32'h0000FFFF);
                put_slot(si*8 + 5, si + 1);
                put_slot(si*8 + 6, 32'd0);
                put_slot(si*8 + 7, 32'd0);
            end
            put_slot(6*8 + 0, {8'd0, 8'd1, 8'd4, 8'd4});
            put_slot(6*8 + 1, 32'd0);
            put_slot(6*8 + 2, off);
            put_slot(6*8 + 3, 32'd6);
            put_slot(6*8 + 4, 32'h0000FFFF);
            put_slot(6*8 + 5, 32'd7);
            put_slot(6*8 + 6, 32'd0);
            put_slot(6*8 + 7, 32'd0);
            put_slot(SLOT_HDR, 32'd7);
            do_commit;
        end
    endtask

    task put_delay_slot(input integer s, input integer cfb, input integer off,
                        input integer inbus, input integer outbus);
        begin
            put_slot(s*8 + 0, {8'd0, 8'd1, 8'd0, 8'd4});
            put_slot(s*8 + 1, cfb);
            put_slot(s*8 + 2, off);
            put_slot(s*8 + 3, inbus);
            put_slot(s*8 + 4, 32'h0000FFFF);
            put_slot(s*8 + 5, outbus);
            put_slot(s*8 + 6, 32'd0);
            put_slot(s*8 + 7, 32'd0);
        end
    endtask

    task load_two_delays(input integer lenA, input integer offA,
                         input integer lenB, input integer offB, input integer bFirst);
        begin
            bank_sel = ~u_dut.active_bank;
            put_coef(0, lenA);
            put_coef(1, lenB);
            if (bFirst) begin
                put_delay_slot(0, 1, offB, 0, 2);
                put_delay_slot(1, 0, offA, 0, 1);
            end else begin
                put_delay_slot(0, 0, offA, 0, 1);
                put_delay_slot(1, 1, offB, 0, 2);
            end
            put_slot(SLOT_HDR, 32'd2);
            do_commit;
        end
    endtask

    localparam MAXV = 2048;
    reg [SAMPLE_W-1:0] cap [0:MAXV-1];
    reg [SAMPLE_W-1:0] fed [0:MAXV-1];
    integer nc = 0;

    reg [SAMPLE_W-1:0] cur = 0;
    reg       parity = 0;
    reg       feed_r = 0;
    integer   fidx = 0;
    always @(negedge clk) if (resetn && in_stb) in_data <= cur;

    initial begin
        out_ack = 0;
        forever begin

            repeat (HOLD) @(negedge clk);
            out_ack = 1;
            @(negedge clk);
            out_ack = 0;
        end
    end
    always @(posedge clk) if (resetn && out_ack && nc < MAXV) begin
        fed[nc] = cur;
        cap[nc] = out_data;
        nc = nc + 1;
        parity <= ~parity;
        if (parity) fidx <= fidx + 1;
        cur <= parity ? (feed_r ? (24'sd3000 + (fidx % 5000)) : 24'sd0)
                      : (24'sd100 + (fidx % (feed_r ? 5000 : 500)));
    end

    task wait_acks(input integer n);
        integer target;
        begin
            target = nc + n;
            while (nc < target) @(posedge clk);
        end
    endtask

    function integer measure_delay(input integer maxd);
        integer d, i, m, best;
        begin
            best = -1;
            for (d = 0; d <= maxd; d = d + 1) begin
                m = 0;
                for (i = nc - 24; i < nc; i = i + 1)
                    if (i >= d && $signed(cap[i]) === $signed(fed[i - d])) m = m + 1;
                if (m == 24) begin
                    if (best >= 0) best = -2;
                    else best = d;
                end
            end
            measure_delay = best;
        end
    endfunction

    function integer measure_delay_ch(input integer ch, input integer maxd);
        integer d, i, m, best;
        begin
            best = -1;
            for (d = 1; d <= maxd; d = d + 2) begin
                m = 0;
                for (i = nc - 24; i < nc; i = i + 1)
                    if ((i % 2 == ch) && (i >= d) &&
                        ($signed(cap[i]) === $signed(fed[i - d]))) m = m + 1;
                if (m == 12) begin
                    if (best >= 0) best = -2;
                    else best = d;
                end
            end
            measure_delay_ch = best;
        end
    endfunction

    function integer nonzero_ch(input integer ch, input integer n);
        integer i, c;
        begin
            c = 0;
            for (i = nc - n; i < nc; i = i + 1)
                if ((i >= 0) && (i % 2 == ch) && (cap[i] !== 24'd0)) c = c + 1;
            nonzero_ch = c;
        end
    endfunction

    function integer peak_ch(input integer ch, input integer n);
        integer i, p, v;
        begin
            p = 0;
            for (i = nc - n; i < nc; i = i + 1)
                if ((i >= 0) && (i % 2 == ch)) begin
                    v = $signed(cap[i]);
                    if (v < 0) v = -v;
                    if (v > p) p = v;
                end
            peak_ch = p;
        end
    endfunction

    integer d2, d4, d8, dL, dR, bad;
    integer dTwoA, dTwoB;
    integer nL, nR;
    integer pL, pR;

    task phase(input integer len, input integer flags, input integer acks);
        begin
            load_delay(len, flags);
            nc = 0;
            parity = 0; fidx = 0; cur = 24'sd1000;
            wait_acks(acks);
        end
    endtask

    initial begin
        $display("== tb_engine_delay ==");
        in_stb = 1;
        repeat (8) @(negedge clk);
        resetn = 1;
        while (u_dut.clr_busy) @(negedge clk);
        repeat (8) @(negedge clk);
        dsp_bypass = 0; lim_bypass = 1; lim_tp = 0; headroom = 0;

        $display("-- criteria 1/2/3: L=2 / 4 / 8 (unit = that channel's samples, the stream sees 2L)--");
        phase(2, 0, 200);  d2 = measure_delay(24);
        phase(4, 0, 200);  d4 = measure_delay(24);
        phase(8, 0, 200);  d8 = measure_delay(28);
        if (d2 < 0 || d4 < 0 || d8 < 0) begin
            $display("  FAIL some phase has no unique matching delay (%0d/%0d/%0d) — the ring was written wrong, or the two channels share one ring",
                     d2, d4, d8);
            fail = fail + 1;
        end else if (d2 - 4 == d4 - 8 && d4 - 8 == d8 - 16 && d2 - 4 >= 0 && d2 - 4 <= 6)
            $display("  OK   [1..3]: L=2/4/8 measure %0d/%0d/%0d on the stream = 2L + %0d (the same fixed offset => convention is right)",
                     d2, d4, d8, d2 - 4);
        else begin
            $display("  FAIL L=2/4/8 measure %0d/%0d/%0d, which does not satisfy d = 2L + constant", d2, d4, d8);
            fail = fail + 1;
        end

        $display("-- criterion 4: L = 240 (5 ms, not a power of 2, close to the 256 ring depth)--");
        phase(240, 0, 900);
        dL = measure_delay(600);
        if (dL == 2*240 + 1) $display("  OK   [4]: at L=240 the stream measures %0d = 2L + 1 (the 5 ms delay holds)", dL);
        else begin
            $display("  FAIL criterion 4: at L=240 measured %0d, want %0d", dL, 2*240 + 1);
            fail = fail + 1;
        end

        $display("-- criterion 5: flags bit2 = delay the right channel only (the left should measure baseline 1)--");
        phase(96, 4, 400);
        dR = measure_delay(256);
        if (dR == 1) $display("  OK   [5]: the left passes through (measures baseline 1), the right is delayed => the flag works");
        else begin
            $display("  FAIL criterion 5: the left channel measured %0d (want 1; 193 means the flag did not take effect)", dR);
            fail = fail + 1;
        end

        $display("-- criterion 5b: flags bit2 + L=576 (the real on-board value)--");
        phase(576, 4, 800);
        dL = measure_delay(1400);
        if (dL == 1) $display("  OK   [5b]: at L=576 the left channel still passes through (baseline 1)");
        else begin
            $display("  FAIL criterion 5b: at L=576 the left channel measured %0d (want 1)", dL);
            fail = fail + 1;
        end

        $display("-- criterion 8: two delay slots in one frame (lengths 4/10, in-ring offsets 0/4) must not interfere --");
        load_two_delays(4, 0, 10, 4, 0);
        nc = 0; parity = 0; fidx = 0; cur = 24'sd1000;
        wait_acks(400);
        dTwoB = measure_delay(80);
        load_two_delays(4, 0, 10, 4, 1);
        nc = 0; parity = 0; fidx = 0; cur = 24'sd1000;
        wait_acks(400);
        dTwoA = measure_delay(80);
        if (dTwoB == 2*10+1 && dTwoA == 2*4+1)
            $display("  OK   [8]: both delay slots hold (last slot B => %0d, last slot A => %0d)", dTwoB, dTwoA);
        else begin
            $display("  FAIL criterion 8: the two delay slots measured %0d on the B branch (want %0d) and %0d on the A branch (want %0d)"+
                     " — this is exactly what a shared write pointer looks like", dTwoB, 2*10+1, dTwoA, 2*4+1);
            fail = fail + 1;
        end

        $display("-- criterion 9: flags bit2 at slot1 (inA=1/outB=2), both channels' stimuli non-zero --");
        feed_r = 1;
        load_pair_flagsr(4, 0, 576, 8);
        nc = 0; parity = 0; fidx = 0; cur = 24'sd1000;
        wait_acks(2000);
        dL = measure_delay_ch(1, 1400);
        dR = measure_delay_ch(0, 1400);
        nL = nonzero_ch(1, 400);
        nR = nonzero_ch(0, 400);
        feed_r = 0;
        $display("     odd-index channel: delay %0d (want 9), non-zero outputs %0d/200", dL, nL);
        $display("     even-index channel: delay %0d (want 1161), non-zero outputs %0d/200", dR, nR);
        if (nL < 100 || nR < 100) begin
            $display("  FAIL criterion 9: one channel's output is nearly empty (%0d / %0d) => the delayed channel is silent",
                     nL, nR);
            fail = fail + 1;
        end else if ((dL == 9 && dR == 1161) || (dL == 1161 && dR == 9))
            $display("  OK   [9]: both channels have output, delay = %0d / %0d (= 2*4+1 and 2*580+1)", dL, dR);
        else begin
            $display("  FAIL criterion 9: measured %0d / %0d, want {9, 1161}", dL, dR);
            fail = fail + 1;
        end

        $display("-- criterion 10: 6 front-end slots + a flags bit2 delay at slot6 (inA=6/outB=7, the real plan shape)--");
        feed_r = 1;
        load_six_then_flagsr(576, 0);
        nc = 0; parity = 0; fidx = 0; cur = 24'sd1000;
        wait_acks(2000);
        dL = measure_delay_ch(1, 1400);
        dR = measure_delay_ch(0, 1400);
        nL = nonzero_ch(1, 400);
        nR = nonzero_ch(0, 400);
        feed_r = 0;
        $display("     odd-index channel: delay %0d (want 1 = pass-through), non-zero outputs %0d/200", dL, nL);
        $display("     even-index channel: delay %0d (want 1153 = 2*576+1), non-zero outputs %0d/200", dR, nR);
        if (nL < 100 || nR < 100) begin
            $display("  FAIL criterion 10: one channel's output is nearly empty (%0d / %0d) => under the real plan shape one ear is silent",
                     nL, nR);
            fail = fail + 1;
        end else if ((dL == 1 && dR == 1153) || (dL == 1153 && dR == 1))
            $display("  OK   [10]: under the real shape both channels have output, delay = %0d / %0d (pass-through / 2*576+1)",
                     dL, dR);
        else begin
            $display("  FAIL criterion 10: measured %0d / %0d, want {1, 1153}", dL, dR);
            fail = fail + 1;
        end

        $display("-- criterion 10b: same shape + in-chain headroom on + true-peak limiter enabled (the real on-board configuration)--");
        headroom = 1; lim_bypass = 0; lim_tp = 1;
        feed_r = 1;
        load_six_then_flagsr(576, 0);
        nc = 0; parity = 0; fidx = 0; cur = 24'sd1000;
        wait_acks(2000);
        nL = nonzero_ch(1, 400);
        nR = nonzero_ch(0, 400);
        pL = peak_ch(1, 400);
        pR = peak_ch(0, 400);
        feed_r = 0;
        headroom = 0; lim_bypass = 1; lim_tp = 0;
        $display("     odd-index channel: non-zero %0d/200, peak %0d", nL, pL);
        $display("     even-index channel: non-zero %0d/200, peak %0d", nR, pR);
        if (nL < 100 || nR < 100) begin
            $display("  FAIL criterion 10b: one channel's output is empty (non-zero %0d / %0d) => headroom+limiter+delay killed one ear",
                     nL, nR);
            fail = fail + 1;
        end else if (pL * 8 < pR || pR * 8 < pL) begin
            $display("  FAIL criterion 10b: the two channel peaks differ by more than 8x (%0d vs %0d)", pL, pR);
            fail = fail + 1;
        end else
            $display("  OK   [10b]: both channels have output (peaks %0d / %0d)", pL, pR);

        if (cap1[4] === 1'b1) $display("  OK   [6]: CAP1 bit4 = 1 (this bitstream reports that it has DELAY)");
        else begin $display("  FAIL CAP1 bit4 = 0, software would think there is no DELAY"); fail = fail + 1; end

        if (cap2[23:16] === 8'd13) $display("  OK   [7]: CAP2 reports DELAY log2 = 13 (8192 words/channel ~= 170.7 ms)");
        else begin $display("  FAIL CAP2 DELAY log2 = %0d, want 13", cap2[23:16]); fail = fail + 1; end

        if (cap3[23:16] === 8'd24) $display("  OK   [9]: CAP3[23:16] = 24 (24 independent delay slot pointers per channel)");
        else begin $display("  FAIL CAP3[23:16] = %0d, want 24", cap3[23:16]); fail = fail + 1; end

        if (fail == 0) $display("== tb_engine_delay: ALL PASSED ==");
        else           $display("== tb_engine_delay: %0d FAILED ==", fail);
        $finish;
    end
endmodule
