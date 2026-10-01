// SPDX-License-Identifier: GPL-2.0-only


`timescale 1ns/1ps
`default_nettype none

module tb_engine_vbass_plan;
    localparam SLOT_HDR = 192;
    localparam SAMPLE_W = 24;
    localparam COEF_W   = 18;
    localparam SHIFT    = 15;
    localparam NB       = 6;
    localparam HEADROOM = 3;

    localparam FS   = 48000;
    localparam F0   = 60;
    localparam PER  = FS / F0;
    localparam AMP  = 2097152;
    localparam NMAX = 2600;
    localparam WARM = 1600;

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

    task put_desc(input integer i, input integer op, input integer n, input integer flags,
                  input integer cfb, input integer stb, input integer ina, input integer inb,
                  input integer outb);
        begin
            put_slot(i*8 + 0, {8'd0, n[7:0], flags[7:0], op[7:0]});
            put_slot(i*8 + 1, cfb[31:0]);
            put_slot(i*8 + 2, stb[31:0]);
            put_slot(i*8 + 3, ina[31:0]);
            put_slot(i*8 + 4, inb[31:0]);
            put_slot(i*8 + 5, outb[31:0]);
            put_slot(i*8 + 6, 32'd0);
            put_slot(i*8 + 7, 32'd0);
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

    task load_vbass_plan(input integer bypass_vb);
        integer fl;
        begin
            bank_sel = ~u_dut.active_bank;

            put_coef(0, 1024); put_coef(1, 0); put_coef(2, 0); put_coef(3, 0); put_coef(4, 0);

            put_coef(5, 24); put_coef(6, 48); put_coef(7, 24);
            put_coef(8, -65052); put_coef(9, 32286);

            put_coef(10, 32769); put_coef(11, 131071);
            fl = bypass_vb ? 8'h01 : 8'h00;

            put_desc(0, 8'd1, 2, fl, 0, 0, 0, 16'hFFFF, 1);

            put_desc(1, 8'd3, 1, fl, 10, 2, 0, 1, 1);
            put_slot(SLOT_HDR, 32'd2);
            do_commit;
        end
    endtask

    task load_board_plan(input integer bypass_vb);
        begin
            bank_sel = ~u_dut.active_bank;
            put_coef(0, 32768);
            put_coef(1, -27780);
            put_coef(2, 0);
            put_coef(3, 18438);
            put_coef(4, 0);
            put_coef(5, 32768);
            put_coef(6, 53169);
            put_coef(7, 21278);
            put_coef(8, 53143);
            put_coef(9, 21257);
            put_coef(10, 32768);
            put_coef(11, -1297);
            put_coef(12, -31122);
            put_coef(13, -1360);
            put_coef(14, -31182);
            put_coef(15, 32768);
            put_coef(16, 23139);
            put_coef(17, 2641);
            put_coef(18, 0);
            put_coef(19, 0);
            put_coef(20, 32768);
            put_coef(21, 2482);
            put_coef(22, 802);
            put_coef(23, 0);
            put_coef(24, 0);
            put_coef(25, 32768);
            put_coef(26, -25442);
            put_coef(27, 5646);
            put_coef(28, -43423);
            put_coef(29, 21025);
            put_coef(30, 32768);
            put_coef(31, -45298);
            put_coef(32, 20268);
            put_coef(33, -52521);
            put_coef(34, 22597);
            put_coef(35, 32768);
            put_coef(36, -9405);
            put_coef(37, 25949);
            put_coef(38, -9221);
            put_coef(39, 23570);
            put_coef(40, 32768);
            put_coef(41, -35521);
            put_coef(42, 24962);
            put_coef(43, -35285);
            put_coef(44, 24620);
            put_coef(45, 32768);
            put_coef(46, 9410);
            put_coef(47, 28169);
            put_coef(48, 9171);
            put_coef(49, 27091);
            put_coef(50, 32768);
            put_coef(51, -40277);
            put_coef(52, 28265);
            put_coef(53, -39600);
            put_coef(54, 27244);
            put_coef(55, 32768);
            put_coef(56, -54913);
            put_coef(57, 28769);
            put_coef(58, -54745);
            put_coef(59, 28623);
            put_coef(60, 32768);
            put_coef(61, 10189);
            put_coef(62, 29025);
            put_coef(63, 10193);
            put_coef(64, 29023);
            put_coef(65, 32768);
            put_coef(66, -61535);
            put_coef(67, 29515);
            put_coef(68, -62054);
            put_coef(69, 29886);
            put_coef(70, 32768);
            put_coef(71, -63311);
            put_coef(72, 30602);
            put_coef(73, -62586);
            put_coef(74, 29940);
            put_coef(75, 32768);
            put_coef(76, 62593);
            put_coef(77, 30103);
            put_coef(78, 62593);
            put_coef(79, 30103);
            put_coef(80, 32768);
            put_coef(81, -59307);
            put_coef(82, 30204);
            put_coef(83, -59322);
            put_coef(84, 30219);
            put_coef(85, 32768);
            put_coef(86, 0);
            put_coef(87, 0);
            put_coef(88, 0);
            put_coef(89, 0);
            put_coef(90, 1024);
            put_coef(91, 0);
            put_coef(92, 0);
            put_coef(93, 0);
            put_coef(94, 0);
            put_coef(95, 24);
            put_coef(96, 48);
            put_coef(97, 24);
            put_coef(98, -65052);
            put_coef(99, 32286);
            put_coef(100, 32769);
            put_coef(101, 131071);
            put_coef(102, 0);
            put_coef(103, 0);
            put_coef(104, 0);
            put_desc(0, 5, 9, 1, 360, 0, 0, 65535, 1);
            put_desc(1, 1, 3, 0, 0, 0, 1, 65535, 2);
            put_desc(2, 1, 3, 0, 15, 3, 2, 65535, 3);
            put_desc(3, 1, 3, 0, 30, 6, 3, 65535, 4);
            put_desc(4, 1, 3, 0, 45, 9, 4, 65535, 5);
            put_desc(5, 1, 3, 0, 60, 12, 5, 65535, 6);
            put_desc(6, 1, 3, 0, 75, 15, 6, 65535, 7);
            put_desc(7, 1, 2, bypass_vb ? 1 : 0, 90, 18, 7, 65535, 8);
            put_desc(8, 3, 1, bypass_vb ? 1 : 0, 100, 20, 7, 8, 8);
            put_slot(SLOT_HDR, 32'd9);
            do_commit;
        end
    endtask

    integer stim [0:NMAX-1];
    reg [SAMPLE_W-1:0] mono [0:NMAX-1];
    reg [SAMPLE_W-1:0] cur = 0;
    integer nw = 0;
    integer mk = 0;
    integer interleaved = 1;
    integer capture_all = 0;

    always @(negedge clk) if (resetn && in_stb) in_data <= cur;

    localparam ACK_PERIOD = 600;

    initial begin
        out_ack = 0;
        forever begin
            repeat (ACK_PERIOD - 1) @(negedge clk);
            out_ack = 1;
            @(negedge clk);
            out_ack = 0;
        end
    end

    always @(posedge clk) if (resetn && out_ack) begin

        if (interleaved) begin
            if (((nw % 2) == 1) && ((nw / 2) + 1 < NMAX)) cur <= stim[(nw / 2) + 1];
        end else begin
            if (nw + 1 < NMAX) cur <= stim[nw + 1];
        end
        if ((capture_all || (nw % 2) == 0) && mk < NMAX) begin
            mono[mk] = out_data;
            mk = mk + 1;
        end
        nw = nw + 1;
    end

    real sumI, sumQ, amp;
    task measure60(input integer w0);
        integer k, v;
        real ph;
        begin
            sumI = 0.0; sumQ = 0.0;
            for (k = w0; k < w0 + PER; k = k + 1) begin
                v = $signed(mono[k]);
                ph = 2.0 * 3.14159265358979 * (k % PER) / PER;
                sumI = sumI + $itor(v) * $sin(ph);
                sumQ = sumQ + $itor(v) * $cos(ph);
            end
            amp = 2.0 * $sqrt(sumI*sumI + sumQ*sumQ) / PER;
        end
    endtask

    task dump_state;
        begin
            $display("    [DUT] use_dsp=%b active_bank=%b hdr=(%0d,%0d) nslot_eff=%0d nslot_last=%0d nsec_last=%0d",
                     u_dut.use_dsp, u_dut.active_bank,
                     u_dut.hdr_bank[0], u_dut.hdr_bank[1], u_dut.nslot_eff,
                     u_dut.nslot_last, u_dut.nsec_last);
        end
    endtask

    real ampDry, ampWet, dbDry, dbWet, boost, ampMono, dbMono, boostMono;
    real boardDry, boardWet, dbBoardDry, dbBoardWet, boardBoost;
    reg [7:0] boardOvr;
    integer i;

    task run_phase(input integer bypass_vb, input integer ilv);
        begin
            interleaved = ilv;
            capture_all = (ilv == 0) ? 1 : 0;
            load_vbass_plan(bypass_vb);
            nw = 0; mk = 0; cur = stim[0];
            while (mk < NMAX) @(negedge clk);
        end
    endtask

    task run_board_plan(input integer bypass_vb);
        begin
            interleaved = 1;
            capture_all = 0;
            load_board_plan(bypass_vb);
            nw = 0; mk = 0; cur = stim[0];
            while (mk < NMAX) @(negedge clk);
        end
    endtask

    initial begin
        $display("== tb_engine_vbass_plan ==");
        for (i = 0; i < NMAX; i = i + 1)
            stim[i] = $rtoi(1.0 * AMP * $sin(2.0 * 3.14159265358979 * i / PER));
        in_stb = 1;
        repeat (8) @(negedge clk);
        resetn = 1;
        while (u_dut.clr_busy) @(negedge clk);
        repeat (8) @(negedge clk);
        dsp_bypass = 0; lim_bypass = 1; lim_tp = 0; headroom = 0;
        bank_sel = 1;
        dump_state;

        run_phase(1, 1);
        measure60(WARM);
        ampDry = amp;
        dbDry  = 20.0 * $log10(ampDry / (1.0 * AMP));
        $display("  reference (ViPERBass bypassed, interleaved): 60 Hz magnitude = %f (input %f) => %f dB",
                 ampDry, 1.0*AMP, dbDry);

        run_phase(0, 1);
        measure60(WARM);
        ampWet = amp;
        dbWet  = 20.0 * $log10(ampWet / (1.0 * AMP));
        $display("  ViPERBass on (interleaved)   : 60 Hz magnitude = %f => %f dB; engine reports slots=%0d sections=%0d",
                 ampWet, dbWet, u_dut.nslot_last, u_dut.nsec_last);
        boost = dbWet - dbDry;
        $display("  60 Hz boost (interleaved) = %f dB", boost);

        if (dbDry > 0.5 || dbDry < -0.5) begin
            $display("  X criterion 1: dry-path gain with ViPERBass bypassed is %f dB, want 0 dB +/- 0.5", dbDry);
            fail = fail + 1;
        end else $display("  OK   [1]: bypassed dry path = %f dB (scale section not leaking into dry)", dbDry);

        if (boost < 10.0) begin
            $display("  X criterion 2: enabling ViPERBass boosts only %f dB (want >= +10 dB) => wet never really added to output",
                     boost);
            fail = fail + 1;
        end else $display("  OK   [2]: 60 Hz boost with ViPERBass on is %f dB (>=10 dB)", boost);

        if (u_dut.nslot_last !== 8'd2 || u_dut.nsec_last !== 8'd2) begin
            $display("  X criterion 3: engine reports slots=%0d sections=%0d, want 2 / 2",
                     u_dut.nslot_last, u_dut.nsec_last);
            fail = fail + 1;
        end else $display("  OK   [3]: engine really ran these 2 slots / 2 sections (not bypassed)");

        run_phase(0, 0);
        measure60(WARM);
        ampMono = amp;
        dbMono  = 20.0 * $log10(ampMono / (1.0 * AMP));
        boostMono = dbMono - dbDry;
        $display("  [diag] non-interleaved drive (new sample per frame): 60 Hz magnitude = %f => %f dB (boost %f dB)",
                 ampMono, dbMono, boostMono);
        $display("         analytic prediction: per-channel effective rate halves => 60 Hz looks like 120 Hz to the lowpass (|H|=0.206, -128.5 deg)");
        $display("         => dry + 4*wet cancel = 1.0000 (~0 dB): this is the 'maxed out but inaudible' mechanism");

        run_board_plan(1);
        measure60(WARM);
        boardOvr = u_dut.overrun_cnt;
        boardDry = amp;
        dbBoardDry = 20.0 * $log10(boardDry / (1.0 * AMP));
        run_board_plan(0);
        measure60(WARM);
        boardWet = amp;
        dbBoardWet = 20.0 * $log10(boardWet / (1.0 * AMP));
        boardBoost = dbBoardWet - dbBoardDry;
        if (boardOvr !== 8'd0) begin
            $display("  X dropped samples: on-board-plan phase overrun_cnt=%0d => this phase conclusion void (widen ACK_PERIOD)", boardOvr);
            fail = fail + 1;
        end
        $display("  [full on-board plan] 9 slots: bypass %f dB / on %f dB => boost %f dB (engine reports slots=%0d sections=%0d)",
                 dbBoardDry, dbBoardWet, boardBoost, u_dut.nslot_last, u_dut.nsec_last);
        if (boardBoost < 10.0) begin
            $display("  X criterion 4: full on-board plan boosts only %f dB (want >= +10 dB)", boardBoost);
            fail = fail + 1;
        end else $display("  OK   [4]: full on-board plan (DDC+FIR+ViPERBass, 9 slots) 60 Hz boost %f dB", boardBoost);

        if (fail == 0) $display("== tb_engine_vbass_plan: ALL PASSED ==");
        else           $display("== tb_engine_vbass_plan: %0d FAILED ==", fail);
        $finish;
    end
endmodule

`default_nettype wire
