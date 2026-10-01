// SPDX-License-Identifier: GPL-2.0-only


module tb_engine_headroom;

    localparam SLOT_HDR = 192;

    localparam SAMPLE_W = 24;
    localparam COEF_W   = 18;
    localparam SHIFT    = 15;
    localparam NB       = 6;
    localparam HEADROOM = 3;

    localparam integer QMAX = (1 << (COEF_W-1)) - 1;

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
    task load_chain(input integer b0);
        begin
            put_coef(0, b0); put_coef(1, 0); put_coef(2, 0);
            put_coef(3, 0);  put_coef(4, 0);

            put_slot(0, {8'd0, 8'd1, 8'd0, 8'd1});
            put_slot(1, 32'd0);
            put_slot(2, 32'd0);
            put_slot(3, 32'd0);
            put_slot(4, 32'hFFFF);
            put_slot(5, 32'd1);
            put_slot(6, 32'd0);
            put_slot(7, 32'd0);
            put_slot(SLOT_HDR, 32'd1);
            do_commit;
        end
    endtask
    task clear_chain;
        begin
            put_slot(SLOT_HDR, 32'd0);
            do_commit;
        end
    endtask

    reg [SAMPLE_W-1:0] cur = 0;
    always @(negedge clk) if (resetn && in_stb) in_data <= cur;

    localparam MAXV = 8192;
    reg [SAMPLE_W-1:0] cap [0:MAXV-1];
    integer nc = 0;
    initial begin
        out_ack = 0;
        forever begin

            repeat (48) @(negedge clk);
            out_ack = 1;
            @(negedge clk);
            out_ack = 0;
        end
    end
    always @(posedge clk) if (resetn && out_ack && nc < MAXV) begin
        cap[nc] = out_data;
        nc = nc + 1;
    end
    task wait_acks(input integer n);
        integer target;
        begin
            target = nc + n;
            while (nc < target) @(posedge clk);
        end
    endtask

    integer i, want, bad, neg, pos, sat;

    initial begin
        $display("== tb_engine_headroom ==");
        in_stb = 1;
        repeat (8) @(negedge clk);
        resetn = 1;

        while (u_dut.clr_busy) @(negedge clk);
        repeat (8) @(negedge clk);

        dsp_bypass = 1; lim_bypass = 1; headroom = 0;
        cur = 24'sd800000;
        wait_acks(60);
        bad = 0;
        for (i = nc - 16; i < nc; i = i + 1) if (cap[i] !== 24'sd800000) bad = bad + 1;
        if (bad == 0) $display("  OK   A1 hr=0 bypass: output bit-exact == input");
        else begin $display("  FAIL A1 hr=0 bypass: output bit-exact == input"); fail = fail + 1; end

        headroom = 1;
        cur = 24'sd123456;
        wait_acks(60);
        bad = 0;
        for (i = nc - 16; i < nc; i = i + 1) if (cap[i] !== 24'sd123456) bad = bad + 1;
        if (bad == 0) $display("  OK   A2 hr=1 bypass: output bit-exact == input (shifts only in DSP path)");
        else begin $display("  FAIL A2 hr=1 bypass: output bit-exact == input (shifts only in DSP path)"); fail = fail + 1; end

        dsp_bypass = 0; headroom = 0;
        cur = 24'sh7FFFFF;
        wait_acks(60);
        bad = 0;
        for (i = nc - 16; i < nc; i = i + 1) if (cap[i] !== 24'sh7FFFFF) bad = bad + 1;
        if (bad == 0) $display("  OK   B1 hr=0 empty table: output bit-exact == input (legacy path bit-exact)");
        else begin $display("  FAIL B1 hr=0 empty table: output bit-exact == input (legacy path bit-exact)"); fail = fail + 1; end

        headroom = 1;
        cur = 24'sh7FFFFF;
        wait_acks(60);

        want = (24'sh7FFFFF + (1 << (HEADROOM-1))) >>> HEADROOM << HEADROOM;
        if (want > 24'sh7FFFFF) want = 24'sh7FFFFF;
        bad = 0;
        for (i = nc - 16; i < nc; i = i + 1) if (cap[i] !== want[23:0]) bad = bad + 1;
        if (bad == 0) $display("  OK   B2 hr=1 empty table: round-half-up downshift + saturating restore (+FS in, +FS out)");
        else begin $display("  FAIL B2 hr=1 empty table: round-half-up downshift + saturating restore (+FS in, +FS out)"); fail = fail + 1; end

        cur = -24'sd1234567;
        wait_acks(60);
        want = -24'sd1234567 >>> HEADROOM << HEADROOM;
        bad = 0;
        for (i = nc - 16; i < nc; i = i + 1) if (cap[i] !== want[23:0]) bad = bad + 1;
        if (bad == 0) $display("  OK   B3 hr=1 empty table (negative): arithmetic shift, not logical shift");
        else begin
            $display("  FAIL B3 hr=1 empty table (negative): arithmetic shift, not logical shift");
            $display("       dbg: in=%h bus0=%h sel=%h up=%h hr=%b push=%h",
                     in_data, u_dut.bus[0], u_dut.lim_data_sel, u_dut.lim_up,
                     u_dut.headroom, u_dut.push_data);
            $display("       want %0d(%h), last 4: %0d(%h) %0d(%h) %0d(%h) %0d(%h)",
                     $signed(want[23:0]), want[23:0],
                     $signed(cap[nc-1]), cap[nc-1], $signed(cap[nc-2]), cap[nc-2],
                     $signed(cap[nc-3]), cap[nc-3], $signed(cap[nc-4]), cap[nc-4]);
            fail = fail + 1;
        end

        load_chain(QMAX);
        lim_bypass = 1; headroom = 1;

        cur = 24'sh7FFFFF;
        wait_acks(200);
        neg = 0; sat = 0;
        for (i = nc - 32; i < nc; i = i + 1) begin
            if ($signed(cap[i]) < 0) neg = neg + 1;
            if (cap[i] > 24'sd8300000) sat = sat + 1;
        end
        if (neg == 0) $display("  OK   C1 full-scale +12dB: positive input never goes negative (saturates, no wrap)");
        else begin $display("  FAIL C1 full-scale +12dB: positive input never goes negative (saturates, no wrap)"); fail = fail + 1; end
        if (sat >= 16) $display("  OK   C2 full-scale +12dB: does saturate near +FS");
        else begin $display("  FAIL C2 full-scale +12dB: does saturate near +FS"); fail = fail + 1; end

        cur = 24'sh800000;
        wait_acks(200);
        pos = 0; sat = 0;
        for (i = nc - 32; i < nc; i = i + 1) begin
            if ($signed(cap[i]) > 0) pos = pos + 1;
            if ($signed(cap[i]) < -24'sd8300000) sat = sat + 1;
        end
        if (pos == 0) $display("  OK   C3 negative full-scale +12dB: negative input never goes positive (saturates, no wrap)");
        else begin $display("  FAIL C3 negative full-scale +12dB: negative input never goes positive (saturates, no wrap)"); fail = fail + 1; end
        if (sat >= 16) $display("  OK   C4 negative full-scale +12dB: does saturate near -FS");
        else begin $display("  FAIL C4 negative full-scale +12dB: does saturate near -FS"); fail = fail + 1; end

        lim_bypass = 0; lim_tp = 0; lim_thr = 18'd3277;
        headroom = 1;
        cur = 24'sh7FFFFF;
        wait_acks(400);
        bad = 0;
        for (i = nc - 32; i < nc; i = i + 1)
            if ($signed(cap[i]) > 24'sd8300000 || $signed(cap[i]) < 24'sd3000000) bad = bad + 1;
        if (bad == 0) $display("  OK   D1 +12dB + limiter 0.1FS: restored output at 8x-threshold magnitude (limiter holds output)");
        else begin $display("  FAIL D1 +12dB + limiter 0.1FS: restored output at 8x-threshold magnitude (limiter holds output)"); fail = fail + 1; end
        $display("       last value %0d (8x threshold = 26216)", $signed(cap[nc-1]));

        if (fail == 0) $display("== tb_engine_headroom: ALL PASSED ==");
        else           $display("== tb_engine_headroom: %0d FAILED ==", fail);
        $finish;
    end

    initial begin
        #20000000;
        $display("== tb_engine_headroom: TIMEOUT ==");
        $finish;
    end
endmodule
