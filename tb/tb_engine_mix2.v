// SPDX-License-Identifier: GPL-2.0-only


module tb_engine_mix2;

    localparam CROSS_BUS = 22;

    localparam SLOT_HDR = 192;

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

    task put_desc(input integer i, input integer op, input integer ina, input integer inb,
                  input integer outb, input integer cfb, input integer stb);
        begin
            put_slot(i*8 + 0, {8'd0, 8'd1, 8'd0, op[7:0]});
            put_slot(i*8 + 1, cfb[31:0]);
            put_slot(i*8 + 2, stb[31:0]);
            put_slot(i*8 + 3, ina[31:0]);
            put_slot(i*8 + 4, inb[31:0]);
            put_slot(i*8 + 5, outb[31:0]);
            put_slot(i*8 + 6, 32'd0);
            put_slot(i*8 + 7, 32'd0);
        end
    endtask

    task load_arith(input integer c0, input integer c1);
        begin

            bank_sel = ~u_dut.active_bank;
            put_coef(0, c0); put_coef(1, c1);
            put_desc(0, 8'd3, 0, 0, 1, 0, 0);
            put_slot(SLOT_HDR, 32'd1);
            do_commit;
        end
    endtask

    task load_cross();
        begin
            bank_sel = ~u_dut.active_bank;

            put_coef(0, 16384); put_coef(1, 0); put_coef(2, 0); put_coef(3, 0); put_coef(4, 0);

            put_coef(5, 32768); put_coef(6, 32768);
            put_desc(0, 8'd1, 0, 0, CROSS_BUS, 0, 0);
            put_desc(1, 8'd3, 0, CROSS_BUS, 1, 5, 0);
            put_slot(SLOT_HDR, 32'd2);
            do_commit;
        end
    endtask

    reg [SAMPLE_W-1:0] lval = 0, rval = 0;
    reg [SAMPLE_W-1:0] cur = 0;
    reg parity = 0;
    always @(negedge clk) if (resetn && in_stb) in_data <= cur;

    localparam MAXV = 4096;
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

        parity <= ~parity;
        cur    <= parity ? rval : lval;
    end

    task wait_acks(input integer n);
        integer target;
        begin
            target = nc + n;
            while (nc < target) @(posedge clk);
        end
    endtask

    integer dbgn = -1;
    always @(posedge clk) if (resetn && u_dut.state == 4'd10 && dbgn >= 0 && dbgn < 24) begin
        $display("  DBG mac=%0d s_in=%0d sc_in=%0d c0=%0d c1=%0d acc=%0d y=%0d xflo=(%0d,%0d) ch_par=%0d",
                 u_dut.mac, $signed(u_dut.s_in), $signed(u_dut.sc_in),
                 $signed(u_dut.c0), $signed(u_dut.c1), $signed(u_dut.acc_reg),
                 $signed(u_dut.y_sat), $signed(u_dut.xf_lo[0]), $signed(u_dut.xf_lo[1]),
                 u_dut.ch_par);
        dbgn = dbgn + 1;
    end

    integer dspn = -1;
    always @(posedge clk) if (resetn && u_dut.state == 4'd3 && dspn >= 0 && dspn < 24) begin
        $display("  DISP slot=%0d op=%0d n=%0d fl=%0d ina=%0d inb=%0d out=%0d cfb=%0d stb=%0d",
                 u_dut.slot_idx, u_dut.sl_op_r, u_dut.sl_n_r, u_dut.sl_fl_r,
                 u_dut.sl_ina_r, u_dut.sl_inb_r, u_dut.sl_out_r, u_dut.sl_cfb_r, u_dut.sl_stb_r);
        dspn = dspn + 1;
    end

    integer i, bad;
    initial begin
        $display("== tb_engine_mix2 ==");
        in_stb = 1;
        repeat (8) @(negedge clk);
        resetn = 1;

        while (u_dut.clr_busy) @(negedge clk);
        repeat (8) @(negedge clk);
        dsp_bypass = 0; lim_bypass = 1; lim_tp = 0; headroom = 0;
        bank_sel = 1;

        $display("-- criterion (1): MIX2 weighted sum = 0.75·x --");
        load_arith(16384, 8192);
        lval = 24'sd8000; rval = 24'sd8000; parity = 0; cur = lval;
        wait_acks(200);
        bad = 0;
        for (i = nc - 16; i < nc; i = i + 1) begin
            if ($signed(cap[i]) !== 24'sd6000) bad = bad + 1;
        end
        if (bad == 0) $display("  OK   [1]: steady-state output = 0.5·x + 0.25·x = 6000 (last 16 samples bit-exact)");
        else begin
            $display("  ✗ criterion (1) failed: %0d/16 mismatches, last value %0d", bad, $signed(cap[nc-1]));
            $display("       window:");
            for (i = nc - 16; i < nc; i = i + 1) $display("         cap[%0d]=%0d", i, $signed(cap[i]));
            fail = fail + 1;
        end

        $display("-- criterion (2): cross-channel (L=1000 / R=0 alternating => the steady-state set should be {1000, 500}) --");
        load_cross();
        lval = 24'sd1000; rval = 24'sd0; parity = 0; cur = lval;
        dbgn = -1; dspn = -1;
        wait_acks(200);
        bad = 0;
        for (i = nc - 16; i < nc; i = i + 1) begin
            if ($signed(cap[i]) === 24'sd1000) ;
            else if ($signed(cap[i]) === 24'sd500) ;
            else begin
                $display("  ✗ cap[%0d] = %0d, neither 1000 nor 500 (self-feed would give 1500/0)",
                         i, $signed(cap[i]));
                bad = bad + 1;
            end
        end
        if (bad == 0) $display("  OK   [2]: output = {in_c + lo_other} = {1000, 500} => what gets crossed in is the **other channel** (self-feed would give {1500, 0})");
        else begin $display("  ✗ criterion (2) failed (%0d/16 mismatches)", bad); fail = fail + 1; end
        $display("       actually run this frame: slots=%0d sections=%0d", u_dut.nslot_last, u_dut.nsec_last);

        $display("-- criterion (3): L = R = 900 => both channels should be 900 + 450 = 1350 --");
        lval = 24'sd900; rval = 24'sd900; parity = 0; cur = lval;
        wait_acks(200);
        bad = 0;
        for (i = nc - 16; i < nc; i = i + 1) if ($signed(cap[i]) !== 24'sd1350) bad = bad + 1;
        if (bad == 0) $display("  OK   [3]: identical channels give identical output (the cross favours neither side and does not add twice)");
        else begin
            $display("  ✗ criterion (3) failed (%0d/16 mismatches, last value %0d)", bad, $signed(cap[nc-1]));
            fail = fail + 1;
        end

        if (cap1[3] === 1'b1) $display("  OK   [4]: CAP1 bit3 = 1 (this bitstream reports that it has MIX2)");
        else begin $display("  ✗ CAP1 bit3 = 0, software will think there is no MIX2"); fail = fail + 1; end

        if (fail == 0) $display("== tb_engine_mix2: ALL PASSED ==");
        else           $display("== tb_engine_mix2: %0d failed ==", fail);
        $finish;
    end
endmodule
