// SPDX-License-Identifier: GPL-2.0-only


`timescale 1ns/1ps

module tb_dsp_engine;
    localparam SAMPLE_W = 24;
    localparam COEF_W   = 18;
    localparam SHIFT    = 15;
    localparam NB       = 6;
    localparam NP       = 400;

    localparam MAXA     = 12000;

    localparam integer QONE  = 1 << SHIFT;
    localparam integer QHALF = 1 << (SHIFT-1);
    localparam integer QTWO  = 1 << (SHIFT+1);

    reg clk = 0;
    always #5 clk = ~clk;

    reg         resetn = 0;
    reg         dsp_bypass = 1;

    localparam NSEC = 48;

    reg  [3:0]  nbands = 0;
    reg  [3:0]  nbands_ref = 0;
    reg  [15:0] cidx = 0;

    reg  [15:0] slot_addr = 0;
    reg  [31:0] slot_data = 0;
    reg         slot_we = 0;
    wire [31:0] new_status, new_cap0, new_cap1, new_cap2, new_cap3;

    reg         bank_sel = 0;
    reg         commit   = 0;

    reg         chp [0:MAXA-1];
    integer     nch = 0;
    reg         cwr = 0;
    reg  [31:0] cdat = 0;
    wire [31:0] ref_rd, new_rd;
    reg         lim_bypass = 1;
    reg         lim_tp = 0;
    reg  [17:0] lim_thr = 18'd3277;
    reg  [17:0] lim_att = 18'd29491;
    reg  [17:0] lim_rel = 18'd32784;

    reg  [SAMPLE_W-1:0] in_data = 0;
    reg                 in_stb  = 0;
    wire                ref_in_ack, new_in_ack;
    wire                ref_out_stb, new_out_stb;
    wire [SAMPLE_W-1:0] ref_out_data, new_out_data;
    reg                 out_ack = 0;

    dsp_insert #(.SAMPLE_W(SAMPLE_W), .COEF_W(COEF_W), .SHIFT(SHIFT),
                 .NB(NB), .NCH(2)) u_ref (
        .clk(clk), .resetn(resetn),
        .in_stb(in_stb), .in_data(in_data), .in_ack(ref_in_ack),
        .out_stb(ref_out_stb), .out_data(ref_out_data), .out_ack(out_ack),
        .dsp_bypass(dsp_bypass), .nbands(nbands_ref),
        .cidx(cidx[5:0]), .cwr(cwr), .cdat(cdat), .cdat_rd(ref_rd),
        .lim_bypass(lim_bypass), .lim_thr(lim_thr), .lim_att(lim_att), .lim_rel(lim_rel)
    );

    dsp_engine #(.SAMPLE_W(SAMPLE_W), .COEF_W(COEF_W), .SHIFT(SHIFT),
                 .NB(NB), .NCH(2)) u_new (
        .clk(clk), .resetn(resetn),
        .in_stb(in_stb), .in_data(in_data), .in_ack(new_in_ack),
        .out_stb(new_out_stb), .out_data(new_out_data), .out_ack(out_ack),
        .dsp_bypass(dsp_bypass), .nbands(nbands),
        .cidx(cidx), .cwr(cwr), .cdat(cdat), .cdat_rd(new_rd),
        .slot_addr(slot_addr), .slot_data(slot_data), .slot_we(slot_we),
        .bank_sel(bank_sel), .commit(commit),
        .status(new_status), .cap0(new_cap0), .cap1(new_cap1),
        .cap2(new_cap2), .cap3(new_cap3),
        .lim_bypass(lim_bypass), .lim_thr(lim_thr), .lim_att(lim_att), .lim_rel(lim_rel),
        .lim_tp(lim_tp),

        .headroom(1'b0)
    );

    reg [SAMPLE_W-1:0] lat_ref [0:MAXA-1];
    reg [SAMPLE_W-1:0] lat_new [0:MAXA-1];
    reg [SAMPLE_W-1:0] up      [0:MAXA-1];
    integer nl = 0, nu = 0;

    always @(posedge clk) if (resetn && out_ack) begin
        lat_ref[nl] = ref_out_data;
        lat_new[nl] = new_out_data;
        nl = nl + 1;
    end
    always @(posedge clk) if (resetn && out_ack && in_stb) begin
        up[nu] = in_data;
        nu = nu + 1;
    end
    always @(posedge clk) if (resetn && out_ack) begin
        chp[nch] = u_new.ch_par;
        nch = nch + 1;
    end

    reg [SAMPLE_W-1:0] lin_ref [0:MAXA-1], lin_new [0:MAXA-1];
    reg [17:0]         lgn_ref [0:MAXA-1], lgn_new [0:MAXA-1];
    integer nlr = 0, nln = 0;

    always @(posedge clk) if (resetn && u_ref.u_lim.sample_valid) begin
        lin_ref[nlr] = u_ref.u_lim.sample_in;
        lgn_ref[nlr] = u_ref.u_lim.gain;
        nlr = nlr + 1;
    end
    always @(posedge clk) if (resetn && u_new.u_lim.sample_valid) begin
        lin_new[nln] = u_new.u_lim.sample_in;
        lgn_new[nln] = u_new.u_lim.gain;
        nln = nln + 1;
    end

    integer rdptr = 0;
    always @(posedge clk) begin
        if (resetn) begin
            if (rdptr < MAXA) begin
                in_stb  <= 1'b1;
                in_data <= ({8'b0, (rdptr * 24'h001357) ^ 24'h00A5A5}) & 24'hFFFFFE;
            end else begin
                in_stb  <= 1'b0;
            end
            if (in_stb && out_ack) rdptr <= rdptr + 1;
        end
    end

    integer gap;
    reg     fflush_acks = 0;
    initial begin
        forever begin
            gap = 160 + ({$random} % 80);
            repeat (gap) @(negedge clk);
            if (!fflush_acks) begin
                out_ack = 1'b1;
                @(negedge clk);
                out_ack = 1'b0;
            end
        end
    end

    task put_coef(input [5:0] idx, input integer val);
        begin
            @(negedge clk); cidx = idx; cdat = val[31:0]; cwr = 1'b1;
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

    task put_slot(input integer widx, input [31:0] val);
        begin
            @(negedge clk); slot_addr = widx[15:0]; slot_data = val; slot_we = 1'b1;
            @(negedge clk); slot_we = 1'b0;
            @(negedge clk);
        end
    endtask

    task put_desc(input integer slot, input integer op, input integer flags, input integer n,
                  input integer cfb, input integer stb, input integer ina, input integer outb);
        begin
            put_slot(slot*8 + 0, {8'd0, n[7:0], flags[7:0], op[7:0]});
            put_slot(slot*8 + 1, cfb[15:0]);
            put_slot(slot*8 + 2, stb[15:0]);
            put_slot(slot*8 + 3, ina[15:0]);
            put_slot(slot*8 + 4, 16'hFFFF);
            put_slot(slot*8 + 5, outb[15:0]);
            put_slot(slot*8 + 6, 32'd0);
            put_slot(slot*8 + 7, 32'd0);
        end
    endtask

    integer errors = 0;

    task put_coef_b(input integer bank, input integer idx, input integer val);
        begin
            bank_sel = bank[0];
            @(negedge clk); cidx = idx[15:0]; cdat = val[31:0]; cwr = 1'b1;
            @(negedge clk); cwr = 1'b0;
            @(negedge clk);
        end
    endtask

    task put_slot_b(input integer bank, input integer widx, input [31:0] val);
        begin
            bank_sel = bank[0];
            @(negedge clk); slot_addr = widx[15:0]; slot_data = val; slot_we = 1'b1;
            @(negedge clk); slot_we = 1'b0;
            @(negedge clk);
        end
    endtask

    task do_commit(output integer treq);
        begin
            @(negedge clk); commit = 1'b1;
            @(negedge clk); commit = 1'b0;
            treq = nl;
        end
    endtask

    task chk_commit_switch(input integer i0, input integer i1, input integer treq, input integer tag);
        integer i, t, badp, badq, expv;
        begin
            t = -1;
            for (i = i0+1; i < i1; i = i + 1) begin
                expv = $signed(up[i-1]) >>> 1;
                if ((t < 0) && (lat_new[i] === expv[23:0]) && (expv[23:0] !== up[i-1]))
                    t = i;
            end
            if (t < 0) begin
                $display("  FAIL [%0d]: no switch point found (COMMIT did not take effect?)", tag);

                for (i = i0+1; i < i0+9 && i < i1; i = i + 1)
                    $display("    dbg i=%0d up=%h lat=%h half=%h", i, up[i-1], lat_new[i], ($signed(up[i-1])>>>1));
                errors = errors + 1;
            end else begin
                badp = 0; badq = 0;
                for (i = i0+1; i < t; i = i + 1)
                    if (lat_new[i] !== up[i-1]) badp = badp + 1;
                for (i = t; i < i1; i = i + 1) begin
                    expv = $signed(up[i-1]) >>> 1;
                    if (lat_new[i] !== expv[23:0]) badq = badq + 1;
                end
                if (chp[t-1] !== 1'b0) begin
                    $display("  FAIL [%0d]: bank swap not at a frame boundary (channel of slot #%0d = %0d, want 0=L)",
                             tag, t-1, chp[t-1]);
                    errors = errors + 1;
                end else if ((t-1 < treq) || (t-1 > treq + 2)) begin
                    $display("  FAIL [%0d]: activation point #%0d too far from request point #%0d (must be within 2 acks)",
                             tag, t-1, treq);
                    errors = errors + 1;
                end else if ((badp !== 0) || (badq !== 0)) begin
                    $display("  FAIL [%0d]: not clean around the switch (%0d mismatches before / %0d after)",
                             tag, badp, badq);
                    errors = errors + 1;
                end else
                    $display("  OK   [%0d]: COMMIT took effect atomically at the frame boundary (L slot #%0d); all %0d samples around it exact (in -> in/2)",
                             tag, t-1, i1 - i0);
            end
        end
    endtask

    task chk_half(input integer i0, input integer i1, input integer tag);
        integer i, bad, shown, expv;
        begin
            bad = 0; shown = 0;
            for (i = i0; i < i1; i = i + 1) begin
                expv = $signed(up[i-1]) >>> 1;
                if (lat_new[i] !== expv[23:0]) begin
                    if (shown < 3) begin
                        $display("     ack #%0d: want (upstream x0.5) %0d got %0d",
                                 i, expv, $signed(lat_new[i]));
                        shown = shown + 1;
                    end
                    bad = bad + 1;
                end
            end
            if (bad == 0)
                $display("  OK   [%0d]: %0d acks = upstream delayed one slot then x0.5 (bus wiring and the x0.5 section are both right)",
                         tag, i1 - i0);
            else begin
                $display("  FAIL [%0d]: %0d/%0d acks do not match x0.5", tag, bad, i1 - i0);
                errors = errors + 1;
            end
        end
    endtask

    task enter_dsp2(input integer slots, input integer refbands);
        begin
            nbands     = slots[3:0];
            nbands_ref = refbands[3:0];
            repeat (10) @(negedge clk);
            dsp_bypass = 1'b0;
            repeat (200) @(negedge clk);
        end
    endtask

    task run_window(output integer a0, output integer a1);
        begin
            a0 = nl;
            wait (nl >= a0 + NP);
            a1 = nl;
            repeat (2) @(negedge clk);
        end
    endtask

    task chk_eq(input integer i0, input integer i1, input integer tag);
        integer i, bad, shown;
        begin
            bad = 0; shown = 0;
            for (i = i0; i < i1; i = i + 1) begin
                if (lat_ref[i] !== lat_new[i]) begin
                    if (shown < 3) begin
                        $display("     ack #%0d: in=%0d ref=%0d new=%0d",
                                 i, $signed(up[i-1]), $signed(lat_ref[i]), $signed(lat_new[i]));
                        shown = shown + 1;
                    end
                    bad = bad + 1;
                end
            end
            if (bad == 0)
                $display("  OK   [%0d]: out_data of %0d acks is bit-exact with dsp_insert",
                         tag, i1 - i0);
            else begin
                $display("  FAIL [%0d]: %0d/%0d acks differ", tag, bad, i1 - i0);
                errors = errors + 1;
            end
        end
    endtask

    task chk_passthru(input integer i0, input integer i1, input integer tag);
        integer i, bad, shown;
        begin
            bad = 0; shown = 0;
            for (i = i0; i < i1; i = i + 1) begin
                if (lat_new[i] !== up[i-1]) begin
                    if (shown < 3) begin
                        $display("     ack #%0d: want (previous upstream sample) %0d got %0d",
                                 i, $signed(up[i-1]), $signed(lat_new[i]));
                        shown = shown + 1;
                    end
                    bad = bad + 1;
                end
            end
            if (bad == 0)
                $display("  OK   [%0d]: %0d acks equal the upstream delayed by one slot (the cascade really is unity gain)",
                         tag, i1 - i0);
            else begin
                $display("  FAIL [%0d]: %0d/%0d acks do not equal the upstream delayed by one slot",
                         tag, bad, i1 - i0);
                errors = errors + 1;
            end
        end
    endtask

    task chk_changed(input integer i0, input integer i1, input integer tag);
        integer i, diff, nz;
        begin
            diff = 0; nz = 0;
            for (i = i0; i < i1; i = i + 1) begin
                if (lat_new[i] !== up[i-1]) diff = diff + 1;
                if (lat_new[i] !== {SAMPLE_W{1'b0}}) nz = nz + 1;
            end
            if (nz == 0) begin

                $display("  FAIL [%0d]: output is **all zero** (coefficients never got in? this comparison is meaningless)", tag);
                errors = errors + 1;
            end else if (diff > (i1 - i0) / 4)
                $display("  OK   [%0d]: the filter changed %0d/%0d of the output (really computing, not bypassing)",
                         tag, diff, i1 - i0);
            else begin
                $display("  FAIL [%0d]: only %0d/%0d samples changed, looks inactive",
                         tag, diff, i1 - i0);
                errors = errors + 1;
            end
        end
    endtask

    task chk_bypass(input integer i0, input integer i1, input integer tag);
        integer i, bad, shown;
        begin
            bad = 0; shown = 0;
            for (i = i0; i < i1; i = i + 1) begin
                if (lat_new[i] !== up[i]) begin
                    if (shown < 3) begin
                        $display("     ack #%0d: want (upstream this cycle) %0d got %0d",
                                 i, $signed(up[i]), $signed(lat_new[i]));
                        shown = shown + 1;
                    end
                    bad = bad + 1;
                end
            end
            if (bad == 0)
                $display("  OK   [%0d]: %0d acks are combinational pass-through", tag, i1 - i0);
            else begin
                $display("  FAIL [%0d]: %0d/%0d acks are not combinational pass-through", tag, bad, i1 - i0);
                errors = errors + 1;
            end
        end
    endtask

    task chk_peak(input integer i0, input integer i1, input integer tag);
        integer i, pin, pout, v;
        begin
            pin = 0; pout = 0;
            for (i = i0; i < i1; i = i + 1) begin
                v = $signed(up[i-1]);      if (v < 0) v = -v;
                if (v > pin) pin = v;
                v = $signed(lat_new[i]);   if (v < 0) v = -v;
                if (v > pout) pout = v;
            end

            if (pout == 0) begin
                $display("  FAIL [%0d]: limiter output is all zero (coefficients or the path are broken, this criterion is meaningless)", tag);
                errors = errors + 1;
            end else if (pout < pin - pin / 5)
                $display("  OK   [%0d]: limiter engaged (input peak %0d -> output peak %0d, pushed to %0d%%)",
                         tag, pin, pout, (pout * 100) / pin);
            else begin
                $display("  FAIL [%0d]: limiter did not clamp (input peak %0d, output peak %0d)",
                         tag, pin, pout);
                errors = errors + 1;
            end
        end
    endtask

    task do_reset;
        begin
            dsp_bypass = 1'b1;
            nbands     = 4'd0;
            nbands_ref = 4'd0;
            lim_bypass = 1'b1;
            repeat (50) @(negedge clk);
            resetn = 0;
            repeat (10) @(negedge clk);
            resetn = 1;

            while (u_new.clr_busy) @(negedge clk);
            repeat (16) @(negedge clk);
        end
    endtask

    task enter_dsp(input integer nb);
        begin
            nbands     = nb[3:0];
            nbands_ref = nb[3:0];
            repeat (10) @(negedge clk);
            dsp_bypass = 1'b0;
            repeat (200) @(negedge clk);
        end
    endtask

    integer p0, p1, k, t_req;

    reg  [31:0] rd_new_g, rd_ref_g;
    integer     lim_wm = 0;

    integer     clip_before, clip_after, clip_expect;

    initial begin

        for (k = 0; k < 8; k = k + 1) begin
            u_ref.mem[k] = {SAMPLE_W{1'b0}};
            u_new.mem[k] = {SAMPLE_W{1'b0}};
        end

        resetn = 0;
        repeat (10) @(negedge clk);
        resetn = 1;

        while (u_new.clr_busy) @(negedge clk);
        repeat (16) @(negedge clk);

        $display("=== dsp_engine vs dsp_insert bit-exact equivalence check (NB=%0d, Q%0d.%0d) ===",
                 NB, COEF_W-SHIFT, SHIFT);

        p0 = nl;
        wait (nl >= p0 + NP);
        p1 = nl; repeat (2) @(negedge clk);
        $display("phase A: bypass (dsp_bypass=1, nbands=0)");
        chk_eq(p0, p1, 0);
        chk_bypass(p0, p1, 0);

        do_reset;
        put_band(0, QONE, 0, 0, 0, 0);
        enter_dsp(1);
        p0 = nl;
        wait (nl >= p0 + NP);
        p1 = nl; repeat (2) @(negedge clk);
        $display("phase B: single-section unity gain (band0 b0=1.0)");
        chk_eq(p0, p1, 1);
        chk_passthru(p0+1, p1, 1);

        do_reset;
        put_band(0, QHALF, 0, 0, 0, 0);
        put_band(1, QTWO,  0, 0, 0, 0);
        enter_dsp(2);
        p0 = nl;
        wait (nl >= p0 + NP);
        p1 = nl; repeat (2) @(negedge clk);
        $display("phase C: two-section cascade (x0.5 then x2.0, the cascade must still be 1.0)");
        chk_eq(p0, p1, 2);
        chk_passthru(p0+1, p1, 2);

        do_reset;
        put_band(0, 33822, -64275, 31008, -64275, 32061);
        enter_dsp(1);
        p0 = nl;
        wait (nl >= p0 + NP);
        p1 = nl; repeat (2) @(negedge clk);
        $display("phase D0: single-section real EQ (1kHz Q3 +12dB, after reset)");
        chk_eq(p0, p1, 10);
        chk_changed(p0+1, p1, 10);

        do_reset;
        put_band(0, 33822, -64275, 31008, -64275, 32061);
        put_band(1, 30123, -50750, 24808, -50750, 22163);
        enter_dsp(2);
        p0 = nl;
        wait (nl >= p0 + NP);
        p1 = nl; repeat (2) @(negedge clk);
        $display("phase D1: two-section real EQ (after reset)");
        chk_eq(p0, p1, 11);
        chk_changed(p0+1, p1, 11);

        do_reset;
        put_band(0, 32897, -65275, 32380, -65275, 32509);
        put_band(1, 32572, -64452, 31902, -64452, 31706);
        put_band(2, 33822, -64275, 31008, -64275, 32061);
        put_band(3, 30123, -50750, 24808, -50750, 22163);
        put_band(4, 39019, -24736, 10453, -24736, 16704);
        put_band(5, 23004,  16546, 10088,  16546,   324);
        enter_dsp(6);
        p0 = nl;
        wait (nl >= p0 + NP);
        p1 = nl; repeat (2) @(negedge clk);
        $display("phase D: six-section real EQ (limiter bypassed)");
        chk_eq(p0, p1, 3);
        chk_changed(p0+1, p1, 3);

        do_reset;
        lim_bypass = 1'b0;
        put_band(0, 32897, -65275, 32380, -65275, 32509);
        put_band(1, 32572, -64452, 31902, -64452, 31706);
        put_band(2, 33822, -64275, 31008, -64275, 32061);
        put_band(3, 30123, -50750, 24808, -50750, 22163);
        put_band(4, 39019, -24736, 10453, -24736, 16704);
        put_band(5, 23004,  16546, 10088,  16546,   324);
        enter_dsp(6);
        p0 = nl;
        wait (nl >= p0 + NP);
        p1 = nl; repeat (2) @(negedge clk);
        $display("phase E: six-section real EQ + limiter (threshold 0.1FS)");
        chk_eq(p0, p1, 4);
        chk_changed(p0+1, p1, 4);
        chk_peak(p0+1, p1, 4);

        do_reset;
        p0 = nl;
        wait (nl >= p0 + NP);
        p1 = nl; repeat (2) @(negedge clk);
        $display("phase F: back to bypass (no residual state fed back in)");
        chk_eq(p0, p1, 5);
        chk_bypass(p0, p1, 5);

        do_reset;
        lim_bypass = 1'b0;
        put_band(0, 33822, -64275, 31008, -64275, 32061);
        enter_dsp(0);
        p0 = nl;
        wait (nl >= p0 + NP);
        p1 = nl; repeat (2) @(negedge clk);
        $display("phase G: DSP enabled but nbands=0 (all sections bypassed, limiter active)");
        chk_eq(p0, p1, 13);
        chk_changed(p0+1, p1, 13);

        repeat (400) @(negedge clk);

        rd_new_g = new_rd; rd_ref_g = ref_rd;

        do_reset;
        put_band(0, 32897, -65275, 32380, -65275, 32509);
        put_band(1, 32572, -64452, 31902, -64452, 31706);
        put_band(2, 33822, -64275, 31008, -64275, 32061);
        put_band(3, 30123, -50750, 24808, -50750, 22163);
        put_band(4, 39019, -24736, 10453, -24736, 16704);
        put_band(5, 23004,  16546, 10088,  16546,   324);
        put_desc(0, 1, 0, 6, 0, 0, 0, 1);
        enter_dsp2(1, 6);
        run_window(p0, p1);
        $display("phase H1: 6-section chain in one slot (n=6) vs the legacy 6-section cascade");
        chk_eq(p0, p1, 20);

        do_reset;
        put_coef(0,  QHALF);
        put_coef(25, QONE);
        put_coef(5,  QONE);
        put_coef(10, QHALF);
        put_coef(15, QONE);
        put_coef(20, QONE);
        put_desc(0, 1, 0, 1, 25, 0, 0, 5);
        put_desc(1, 0, 0, 0,  0, 0, 0, 0);
        put_desc(2, 1, 0, 1,  5, 1, 5, 3);
        put_desc(3, 1, 0, 1, 10, 4, 3, 1);
        put_desc(4, 1, 0, 2, 15, 2, 1, 6);
        enter_dsp2(5, 1);
        run_window(p0, p1);
        $display("phase H2: arbitrary chain order (NOP hole / non-monotonic buses / an n=2 slot)");
        chk_eq(p0, p1, 21);
        chk_half(p0+1, p1, 21);

        if (new_status[15:8] !== 8'd4 || new_status[23:16] !== 8'd5) begin
            $display("  FAIL [22]: STATUS execution counts wrong (slots %0d, sections %0d, want 4 / 5)",
                     new_status[15:8], new_status[23:16]);
            errors = errors + 1;
        end else
            $display("  OK   [22]: STATUS execution counts correct (4 slots / 5 sections)");

        do_reset;
        put_coef(0,  QONE);
        put_coef(25, QONE);
        put_coef(5,  QONE);
        put_coef(10, QHALF);
        put_coef(15, QONE);
        put_coef(20, QONE);
        put_desc(0, 1, 0, 1, 25, 0, 0, 5);
        put_desc(1, 0, 0, 0,  0, 0, 0, 0);
        put_desc(2, 1, 0, 1,  5, 1, 5, 3);
        put_desc(3, 1, 1, 1, 10, 4, 3, 1);
        put_desc(4, 1, 0, 2, 15, 2, 1, 6);
        enter_dsp2(5, 1);
        run_window(p0, p1);
        $display("phase H3: bypass flag (bypass on slot3, the x0.5 must not take effect)");
        chk_eq(p0, p1, 23);

        do_reset;
        bank_sel = 1'b0;
        put_band(0, 33822, -64275, 31008, -64275, 32061);
        bank_sel = 1'b1;
        put_band(0, 33822, -64275, 31008, -64275, 32061);
        bank_sel = 1'b0;
        enter_dsp(1);
        p0 = nl;
        wait (nl >= p0 + 120);
        do_commit(t_req);
        wait (nl >= t_req + 150);
        p1 = nl; repeat (2) @(negedge clk);
        $display("phase I1: COMMIT transparency (same coefficients in both banks, a swap must not disturb any sample)");
        chk_eq(p0, p1, 30);

        lim_wm = nlr;
        do_reset;
        put_coef_b(0, 0, QONE);
        put_coef_b(1, 0, QHALF);
        bank_sel = 1'b0;
        enter_dsp(1);
        p0 = nl;
        wait (nl >= p0 + 120);
        do_commit(t_req);
        wait (nl >= t_req + 200);
        p1 = nl; repeat (2) @(negedge clk);
        $display("phase I2: COMMIT takes effect atomically at the frame boundary (in -> in/2)");
        chk_commit_switch(p0, p1, t_req, 31);

        do_reset;
        put_coef(0, QTWO);
        put_desc(0, 1, 0, 1, 0, 0, 0, 1);
        put_desc(1, 8, 0, 1, 0, 8, 1, 2);
        enter_dsp2(2, 1);

        p0 = nl;
        wait (nl >= p0 + 5);
        p0 = nl;

        repeat (2) @(negedge clk);
        clip_before = u_new.st_x1[8] + u_new.st_x1[NSEC+8];
        wait (nl >= p0 + NP);
        p1 = nl; repeat (2) @(negedge clk);
        $display("phase J: SAT slot (clip detection / counting)");
        chk_eq(p0, p1, 40);
        clip_after  = u_new.st_x1[8] + u_new.st_x1[NSEC+8];
        clip_expect = 0;

        for (k = p0+1; k <= p1; k = k + 1)
            if (($signed(up[k-1]) >= 4194304) || ($signed(up[k-1]) <= -4194304))
                clip_expect = clip_expect + 1;

        if ((clip_after - clip_before) !== clip_expect &&
            (clip_after - clip_before) !== clip_expect + 1) begin
            $display("  FAIL [41]: SAT clip count wrong (hardware %0d, want %0d or %0d)",
                     clip_after - clip_before, clip_expect, clip_expect + 1);
            errors = errors + 1;
        end else
            $display("  OK   [41]: SAT clip count correct (%0d samples reached the rail, want %0d)",
                     clip_after - clip_before, clip_expect);

        do_reset;
        put_coef(0, QONE);
        enter_dsp(1);
        fflush_acks = 1;
        repeat (20) @(negedge clk);
        do_commit(t_req);
        repeat (300) @(negedge clk);
        fflush_acks = 0;
        begin : commit_idle
            integer waited;
            waited = 0;

            while ((u_new.commit_pend != 1'b0) && (waited < 12000)) begin
                @(negedge clk); waited = waited + 1;
            end
            if (u_new.commit_pend == 1'b0)
                $display("  OK   [50]: with no audio, COMMIT took effect via the fallback (waited %0d cycles)", waited);
            else begin
                $display("  FAIL [50]: with no audio, COMMIT never takes effect (commit_pend stays asserted)");
                errors = errors + 1;
            end
        end
        do_reset;

        if (new_cap0 !== 32'h5A44_0001) begin
            $display("  FAIL [24]: CAP0 magic/version wrong (%08x)", new_cap0);
            errors = errors + 1;

        end else if (new_cap1 !== 32'h0000_1F7B) begin
            $display("  FAIL [24]: CAP1 opcode bitmap wrong (%08x)", new_cap1);
            errors = errors + 1;
        end else if (new_cap2[7:0] !== 8'd24) begin
            $display("  FAIL [24]: CAP2 NSLOT wrong (%0d)", new_cap2[7:0]);
            errors = errors + 1;
        end else
            $display("  OK   [24]: CAP0..CAP2 correct (magic 5A44 / ver 1 / bitmap 1F7B = NOP+BIQUAD+MIX2+DELAY+SAT+true-peak limiter selectable+in-chain headroom+DYN+FIR+POLY+joint-stereo frame pass / NSLOT 24)");

        $display("  recorded: %0d acks, %0d upstream fetches", nl, nu);
        if (u_new.overrun) begin
            $display("  FAIL [6]: dsp_engine reported an overrun (the FSM cannot keep up, samples get dropped)");
            errors = errors + 1;
        end else
            $display("  OK   [6]: no overrun (44 cycles/sample << the ack gap)");

        if (u_new.overrun_cnt !== 8'd0) begin
            $display("  FAIL [25]: dropped-sample counter = %0d, simulation must not drop samples", u_new.overrun_cnt);
            errors = errors + 1;
        end else
            $display("  OK   [25]: dropped-sample counter is 0 (on board, read STATUS[31:24] for the same thing)");
        if (new_status[31:24] !== 8'd0) begin
            $display("  FAIL [26]: STATUS high byte (dropped-sample count) should be 0, got %0d", new_status[31:24]);
            errors = errors + 1;
        end else
            $display("  OK   [26]: STATUS[31:24] carries the dropped-sample counter and it is 0");
        if (rd_ref_g !== rd_new_g) begin
            $display("  FAIL [7]: cdat_rd readback differs on the legacy path (ref=%0d new=%0d)",
                     $signed(rd_ref_g), $signed(rd_new_g));
            errors = errors + 1;
        end else
            $display("  OK   [7]: cdat_rd readback agrees on the legacy path (%0d); at the end the two read back through different banks, as expected",
                     $signed(rd_new_g));

        begin : lim_seq
            integer i, bad_in, bad_g, first_in, first_g, engaged;
            bad_in = 0; bad_g = 0; first_in = -1; first_g = -1;
            if (lim_wm > nlr) lim_wm = nlr;
            if (lim_wm > nln) lim_wm = nln;
            for (i = 0; i < lim_wm; i = i + 1) begin
                if (lin_ref[i] !== lin_new[i]) begin
                    if (first_in < 0) begin
                        first_in = i;
                        $display("     first limiter input divergence #%0d: ref=%0d new=%0d",
                                 i, $signed(lin_ref[i]), $signed(lin_new[i]));
                    end
                    bad_in = bad_in + 1;
                end
                if (lgn_ref[i] !== lgn_new[i]) begin
                    if (first_g < 0) begin
                        first_g = i;
                        $display("     first limiter gain divergence #%0d: ref=%0d new=%0d",
                                 i, lgn_ref[i], lgn_new[i]);
                    end
                    bad_g = bad_g + 1;
                end
            end
            if (bad_in == 0)
                $display("  OK   [8]: limiter input sequences agree (first %0d pulses; I2 diverges on purpose after that)", lim_wm);
            else
                $display("  FAIL [8]: limiter input sequences differ at %0d (within the first %0d pulses)", bad_in, lim_wm);
            if (bad_g == 0)
                $display("  OK   [9]: limiter gain sequences agree");
            else
                $display("  FAIL [9]: limiter gain sequences differ at %0d", bad_g);

            engaged = 0;
            for (i = 0; (i < nln) && (i < MAXA); i = i + 1)
                if (lgn_new[i] < 18'd32768) engaged = engaged + 1;
            if (engaged > 100)
                $display("  OK   [12]: the limiter really clamped (%0d/%0d samples had gain < 1.0)", engaged, nln);
            else begin
                $display("  FAIL [12]: the limiter never clamped (only %0d samples with gain < 1.0)", engaged);
                errors = errors + 1;
            end
        end

        if (errors == 0) $display("\n=== ALL TESTS PASSED ===");
        else             $display("\n=== %0d ERRORS ===", errors);
        $finish;
    end

    initial begin
        #20000000;
        $display("TIMEOUT (nl=%0d nu=%0d)", nl, nu);
        $finish;
    end
endmodule
