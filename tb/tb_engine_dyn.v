// SPDX-License-Identifier: GPL-2.0-only


module tb_engine_dyn;

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

    task load_dyn_chain(input integer gmax, input integer gmin, input integer ref,
                        input integer ks, input integer satt, input integer srel);
        begin
            put_coef(0, 32768); put_coef(1, 0); put_coef(2, 0); put_coef(3, 0); put_coef(4, 0);
            put_coef(5, gmax);  put_coef(6, gmin); put_coef(7, ref);
            put_coef(8, ks);

            put_coef(9, ({13'd0, srel[4:0]} << 5) | {13'd0, satt[4:0]});

            put_desc(0, 8'd2, 0, 0, 1, 5, 1);
            put_slot(SLOT_HDR, 32'd1);
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

    integer i, bad;
    integer fn = 0;
    always @(posedge clk) if (resetn && u_dut.state == 4'd4 && fn < 8) begin
        $display("  FETCH fcnt=%0d cf_a=%0d coef_rd=%0d c0=%0d active=%0d bsel=%0d cfb_act=%0d",
                 u_dut.fcnt, u_dut.cf_a, $signed(u_dut.coef_rd), $signed(u_dut.c0),
                 u_dut.active_bank, u_dut.bank_sel, u_dut.cfb_act);
        fn = fn + 1;
    end
    integer dbgn = 0;
    always @(posedge clk) if (resetn && u_dut.state == 4'd9 && dbgn < 14) begin
        $display("  DBG mac=%0d env=%0d sc=%0d acc=%0d gain=%0d envn=%0d gmax=%0d ks=%0d",
                 u_dut.mac, $signed(u_dut.env_r), $signed(u_dut.dyn_sc_abs),
                 $signed(u_dut.acc_reg), $signed(u_dut.dyn_gain),
                 $signed(u_dut.dyn_env_n), $signed(u_dut.dyn_gmax), $signed(u_dut.dyn_ks));
        dbgn = dbgn + 1;
    end
    initial begin
        $display("== tb_engine_dyn ==");
        in_stb = 1;
        repeat (8) @(negedge clk);
        resetn = 1;

        while (u_dut.clr_busy) @(negedge clk);
        repeat (8) @(negedge clk);
        dsp_bypass = 0; lim_bypass = 1; lim_tp = 0; headroom = 0;

        bank_sel = 1;

        load_dyn_chain(32768, 16384, 8192, 32768, 5'd2, 5'd6);

        cidx = 16'd5; @(negedge clk);
        $display("       dbg: read back coef[5]=%0d (expect 32768=gmax)", $signed(rd));
        cidx = 16'd6; @(negedge clk);
        $display("       dbg: read back coef[6]=%0d (expect 16384=gmin)", $signed(rd));
        cidx = 16'd0; @(negedge clk);
        $display("       dbg: read back coef[0]=%0d (unused slot, expect 0)", $signed(rd));

        cur = 24'sh001000;
        wait_acks(400);
        bad = 0;
        for (i = nc - 16; i < nc; i = i + 1) if (cap[i] !== 24'sh001000) bad = bad + 1;
        if (bad == 0) $display("  OK   1 quiet in: gain=gmax, out == in (%0d)", $signed(cap[nc-1]));
        else begin
            $display("  FAIL 1 quiet in should stay unit gain, last=%0d (%0d/16 bad)",
                     $signed(cap[nc-1]), bad);
            $write("       window: ");
            for (i = nc - 16; i < nc; i = i + 1) $write("%0d ", $signed(cap[i]));
            $write("\n");
            $display("       env=%0d sc=%0d gain=%0d satt=%0d srel=%0d ref=%0d",
                     $signed(u_dut.env_r), $signed(u_dut.dyn_sc_abs), $signed(u_dut.dyn_gain),
                     u_dut.dyn_satt, u_dut.dyn_srel, $signed(u_dut.dyn_ref));
            fail = fail + 1;
        end

        cur = 24'sh7FFFFF;
        wait_acks(1200);
        bad = 0;
        for (i = nc - 16; i < nc; i = i + 1)
            if ($signed(cap[i]) > 24'sd4259840 || $signed(cap[i]) < 24'sd4128768) bad = bad + 1;
        if (bad == 0) $display("  OK   2 loud in: gain clamped by gmin (out %0d ~ FS/2)", $signed(cap[nc-1]));
        else begin
            $display("  FAIL 2 loud in should be ~FS/2, last=%0d (%0d/16 bad)", $signed(cap[nc-1]), bad);
            $display("       dbg: state=%0d slot_idx=%0d op=%0d n=%0d ina=%0d inb=%0d out=%0d cfb=%0d stb=%0d",
                     u_dut.state, u_dut.slot_idx, u_dut.sl_op_r, u_dut.sl_n_r,
                     u_dut.sl_ina_r, u_dut.sl_inb_r, u_dut.sl_out_r, u_dut.sl_cfb_r, u_dut.sl_stb_r);
            $display("       dbg: nslot=%0d nsec=%0d env=%0d sc=%0d gain=%0d bus0=%0d bus1=%0d",
                     u_dut.nslot_last, u_dut.nsec_last, $signed(u_dut.env_r),
                     $signed(u_dut.dyn_sc_abs), $signed(u_dut.dyn_gain),
                     $signed(u_dut.bus[0]), $signed(u_dut.bus[1]));
            $display("       dbg: gmax=%0d gmin=%0d ref=%0d ks=%0d satt=%0d srel=%0d",
                     $signed(u_dut.dyn_gmax), $signed(u_dut.dyn_gmin), $signed(u_dut.dyn_ref),
                     $signed(u_dut.dyn_ks), u_dut.dyn_satt, u_dut.dyn_srel);
            fail = fail + 1;
        end

        cur = 24'sh001000;
        wait_acks(800);
        bad = 0;
        for (i = nc - 16; i < nc; i = i + 1) if (cap[i] !== 24'sh001000) bad = bad + 1;
        if (bad == 0) $display("  OK   3 back to quiet: gain recovered to gmax (release ok)");
        else begin
            $display("  FAIL 3 should recover unit gain, last=%0d (%0d/16 bad)", $signed(cap[nc-1]), bad);
            fail = fail + 1;
        end

        if (fail == 0) $display("== tb_engine_dyn: ALL PASSED ==");
        else           $display("== tb_engine_dyn: %0d failed ==", fail);
        $finish;
    end

    initial begin
        #20000000;
        $display("== tb_engine_dyn: TIMEOUT ==");
        $finish;
    end
endmodule
