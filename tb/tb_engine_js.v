// SPDX-License-Identifier: GPL-2.0-only


`timescale 1ns / 1ps

module tb_engine_js;

    localparam SLOT_HDR = 192;

    localparam SAMPLE_W = 24;
    localparam COEF_W   = 18;
    localparam SHIFT    = 15;
    localparam NB       = 6;
    localparam HEADROOM = 0;
    localparam NCOEF    = 240;
    localparam FIR_BASE = 2*NCOEF;

    localparam OP_BIQUAD = 1, OP_FIR = 5, OP_JDST = 9, OP_J3DS = 10;
    localparam [7:0] FL_R_ONLY = 8'h10;

    localparam [15:0] SF_EN = 16'h0100;

    localparam NFR  = 1800;
    localparam NSMP = 2*NFR;
    localparam MAXV = NSMP + 64;

    reg clk = 0;
    always #5 clk = ~clk;

    reg         resetn = 0;
    reg         dsp_bypass = 0;
    reg  [3:0]  nbands = 0;
    reg  [15:0] cidx = 0;
    reg         cwr = 0;
    reg  [31:0] cdat = 0;
    reg  [15:0] slot_addr = 0;
    reg  [31:0] slot_data = 0;
    reg         slot_we = 0;
    reg         bank_sel = 0;
    reg         commit = 0;
    wire [31:0] status, cap0, cap1, cap2, cap3, cap4, rd;
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
        .status(status), .cap0(cap0), .cap1(cap1), .cap2(cap2), .cap3(cap3), .cap4(cap4),
        .lim_bypass(lim_bypass), .lim_tp(lim_tp),
        .lim_thr(lim_thr), .lim_att(lim_att), .lim_rel(lim_rel),
        .headroom(headroom)
    );

    reg [23:0] din  [0:NSMP-1];
    reg [23:0] exp1 [0:NSMP-1];
    reg [23:0] exp2 [0:NSMP-1];
    reg [23:0] exp3 [0:NSMP-1];
    reg [23:0] exp4 [0:NSMP-1];
    reg [23:0] jsd1 [0:8];  reg [23:0] js31 [0:1];
    reg [23:0] jsd2 [0:8];  reg [23:0] js32 [0:1];
    reg [23:0] jsd3 [0:8];  reg [23:0] js33 [0:1];
    reg [23:0] pre_c[0:4];  reg [23:0] post_c[0:4];
    reg [23:0] half_c[0:4];

    reg [SAMPLE_W-1:0] cap [0:MAXV-1];
    integer nc = 0;

    task put_coef(input integer idx, input [23:0] val);
        begin
            @(negedge clk); cidx = idx[15:0]; cdat = {{14{val[17]}}, val[17:0]}; cwr = 1;
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

    reg [15:0] ack_per = 16'd100;

    reg ack_en = 0;
    initial begin
        out_ack = 0;
        forever begin
            repeat (ack_per) @(negedge clk);
            if (ack_en) begin
                out_ack = 1;
                @(negedge clk);
                out_ack = 0;
            end
        end
    end

    always @(posedge clk) if (resetn && out_ack && nc < MAXV) begin
        cap[nc] = out_data;
        in_data <= (nc + 1 < NSMP) ? din[nc+1] : {SAMPLE_W{1'b0}};
        nc = nc + 1;
    end

    integer fails = 0;
    integer s, k, hit, ok, mism;

    function [23:0] expv(input integer idx, input integer kk);
        begin
            case (idx)
                1: expv = exp1[kk];
                2: expv = exp2[kk];
                3: expv = exp3[kk];
                default: expv = exp4[kk];
            endcase
        end
    endfunction

    task locate(input integer expidx);
        begin
            hit = -1;
            for (s = 0; s <= MAXV-NSMP && hit < 0; s = s + 1) begin
                ok = 1;
                for (k = 0; k < 40; k = k + 1)
                    if (cap[s+k] !== expv(expidx, k)) ok = 0;
                if (ok) hit = s;
            end
        end
    endtask

    task verify(input integer id, input integer expidx);
        begin
            locate(expidx);
            if (hit < 0) begin
                $display("  FAIL [%0d] no alignment point found (no 40 consecutive samples match anywhere)", id);
                $display("        DUMP cap[0..9]: %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
                         $signed(cap[0]),$signed(cap[1]),$signed(cap[2]),$signed(cap[3]),
                         $signed(cap[4]),$signed(cap[5]),$signed(cap[6]),$signed(cap[7]),
                         $signed(cap[8]),$signed(cap[9]));
                $display("        DUMP exp[0..9]: %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
                         $signed(expv(expidx,0)),$signed(expv(expidx,1)),$signed(expv(expidx,2)),
                         $signed(expv(expidx,3)),$signed(expv(expidx,4)),$signed(expv(expidx,5)),
                         $signed(expv(expidx,6)),$signed(expv(expidx,7)),$signed(expv(expidx,8)),
                         $signed(expv(expidx,9)));
                fails = fails + 1;
            end else begin
                mism = 0;
                for (k = 0; k < NSMP; k = k + 1)
                    if (cap[hit+k] !== expv(expidx, k)) mism = mism + 1;
                if (mism == 0)
                    $display("  OK   [%0d] aligned at s=%0d: %0d samples bit-exact with the reference model",
                             id, hit, NSMP);
                else begin
                    $display("  FAIL [%0d] aligned at s=%0d: %0d/%0d samples differ from the reference model",
                             id, hit, mism, NSMP);
                    for (k = 0; k < NSMP && k < 400; k = k + 1)
                        if (cap[hit+k] !== expv(expidx, k) && mism > 0) begin
                            $display("        first mismatch: sample %0d got %0d expected %0d",
                                     k, $signed(cap[hit+k]), $signed(expv(expidx,k)));
                            k = NSMP;
                        end
                    fails = fails + 1;
                end
            end
        end
    endtask

    integer i;

    task load_pure;
        begin
            bank_sel = ~u_dut.active_bank;

            put_desc(0, OP_JDST, 1, 0, 0, 0, 1, 0, 2);

            put_desc(1, OP_J3DS, 1, 0, 9, 0, 1, 2, 16'hFFFF);
            put_slot(SLOT_HDR, 16'd2 | SF_EN | (16'd3 << 9));
            do_commit;
        end
    endtask

    task load_mixed;
        begin
            bank_sel = ~u_dut.active_bank;
            for (i = 0; i < 5; i = i + 1) put_coef(i, pre_c[i]);
            for (i = 0; i < 9; i = i + 1) put_coef(5+i, jsd3[i]);
            for (i = 0; i < 2; i = i + 1) put_coef(14+i, js33[i]);
            for (i = 0; i < 5; i = i + 1) put_coef(16+i, post_c[i]);
            put_desc(0, OP_BIQUAD, 1, 0, 0,  0, 0, 16'hFFFF, 1);
            put_desc(1, OP_JDST,   1, 0, 5,  0, 2, 1, 3);
            put_desc(2, OP_J3DS,   1, 0, 14, 0, 2, 3, 16'hFFFF);
            put_desc(3, OP_BIQUAD, 1, 0, 16, 1, 4, 16'hFFFF, 5);
            put_slot(SLOT_HDR, 16'd4 | SF_EN | (16'd4 << 9));
            do_commit;
        end
    endtask

    task load_right_only;
        begin
            bank_sel = ~u_dut.active_bank;
            for (i = 0; i < 5; i = i + 1) put_coef(i, half_c[i]);
            put_desc(0, OP_BIQUAD, 1, FL_R_ONLY, 0, 0, 0, 16'hFFFF, 1);
            put_slot(SLOT_HDR, 16'd1);
            do_commit;
        end
    endtask

    task phase_reset;
        begin
            ack_en = 0;
            resetn = 0;
            repeat (8) @(negedge clk);
            resetn = 1;
            repeat (8) @(negedge clk);
            while (u_dut.clr_busy) @(negedge clk);
            dsp_bypass = 0; lim_bypass = 1; lim_tp = 0; headroom = 0;
            nc = 0;
        end
    endtask

    task run_acks(input integer n);
        integer target;
        begin
            target = nc + n;
            while (nc < target) @(posedge clk);
        end
    endtask

    localparam JCFB = 5*3*15;

    initial begin
        $display("\n== tb_engine_js: joint-stereo frame pass / V4A ColorfulMusic ==");
        $readmemh("colm_in.hex",   din);
        $readmemh("colm_exp1.hex", exp1);
        $readmemh("colm_exp2.hex", exp2);
        $readmemh("colm_exp3.hex", exp3);
        $readmemh("colm_exp4.hex", exp4);
        $readmemh("colm_jsd1.hex", jsd1);  $readmemh("colm_js31.hex", js31);
        $readmemh("colm_jsd2.hex", jsd2);  $readmemh("colm_js32.hex", js32);
        $readmemh("colm_jsd3.hex", jsd3);  $readmemh("colm_js33.hex", js33);
        $readmemh("colm_pre.hex",  pre_c);
        $readmemh("colm_post.hex", post_c);
        $readmemh("colm_half.hex", half_c);

        in_stb = 1;
        repeat (8) @(negedge clk);
        resetn = 1;
        while (u_dut.clr_busy) @(negedge clk);
        repeat (8) @(negedge clk);
        dsp_bypass = 0; lim_bypass = 1; lim_tp = 0; headroom = 0;

        $display("\n-- criterion (1): pure ColorfulMusic (strength=1000, negative branch), bit-exact compare --");
        phase_reset;
        ack_en = 0;
        bank_sel = ~u_dut.active_bank;
        for (i = 0; i < 9; i = i + 1) put_coef(i, jsd1[i]);
        for (i = 0; i < 2; i = i + 1) put_coef(9+i, js31[i]);
        load_pure;
        $display("  [dbg] hdr=%0d sf_en=%b jbus=%0d nslot_eff=%0d",
                 u_dut.hdr_bank[u_dut.active_bank], u_dut.sf_en, u_dut.jbus, u_dut.nslot_eff);
        in_data = din[0]; nc = 0; ack_per = 16'd100; ack_en = 1;
        run_acks(NSMP + 4);
        verify(1, 1);

        $display("\n-- criterion (2): strength=300 (positive branch: g positive), bit-exact compare --");
        phase_reset;
        ack_en = 0;
        bank_sel = ~u_dut.active_bank;
        for (i = 0; i < 9; i = i + 1) put_coef(i, jsd2[i]);
        for (i = 0; i < 2; i = i + 1) put_coef(9+i, js32[i]);
        load_pure;
        in_data = din[0]; nc = 0; ack_en = 1;
        run_acks(NSMP + 4);
        verify(2, 2);

        $display("\n-- criterion (3): front biquad + joint section + back biquad (coexisting, bit-exact compare) --");
        phase_reset;
        load_mixed;
        in_data = din[0]; nc = 0; ack_en = 1;
        run_acks(NSMP + 4);
        verify(3, 3);
        $display("        STATUS: slots=%0d sections=%0d", (status >> 8) & 8'hFF, (status >> 16) & 8'hFF);

        $display("\n-- criterion (4): flags bit4 (FL_R_ONLY) => left passes through, right x0.5 --");
        phase_reset;
        load_right_only;
        in_data = din[0]; nc = 0; ack_en = 1;
        run_acks(NSMP + 4);
        verify(4, 4);

        $display("\n-- criterion (5): CAP1 bit12 = joint-stereo frame pass --");
        if (cap1[12] === 1'b1) $display("  OK   [5]: CAP1 bit12 = 1 (software only allows ColorfulMusic when this is set)");
        else begin $display("  FAIL [5]: CAP1 bit12 = 0"); fails = fails + 1; end
        if (cap1[11:0] === 12'hF7B) $display("  OK   [5b]: CAP1[11:0] = F7B (bit-exact with before the change)");
        else begin $display("  FAIL [5b]: CAP1[11:0] = %03x (expected F7B)", cap1[11:0]); fails = fails + 1; end

        $display("\n-- criterion (6): real beat ack=1041 + 45 sections + convolution + joint section --");
        phase_reset;
        bank_sel = ~u_dut.active_bank;
        for (i = 0; i < JCFB; i = i + 1) put_coef(i, (i % 5 == 0) ? 24'sd32767 : 24'sd0);
        for (i = 0; i < 9; i = i + 1) put_coef(JCFB + i, jsd1[i]);
        for (i = 0; i < 2; i = i + 1) put_coef(JCFB + 9 + i, js31[i]);
        for (i = 0; i < 15; i = i + 1)
            put_desc(i, OP_BIQUAD, 3, 0, i*15, i*3, (i == 0) ? 0 : i, 16'hFFFF, i+1);
        put_desc(15, OP_FIR,  9, 0, FIR_BASE, 0, 15, 16'hFFFF, 16);
        put_desc(16, OP_JDST, 1, 0, JCFB,     0, 17, 16, 18);
        put_desc(17, OP_J3DS, 1, 0, JCFB + 9, 0, 17, 18, 16'hFFFF);
        put_slot(SLOT_HDR, 16'd18 | SF_EN | (16'd19 << 9));
        do_commit;
        ack_per = 16'd1041;
        nc = 0; in_data = din[0]; ack_en = 1;
        run_acks(240);
        if (((status >> 24) & 8'hFF) === 8'd0)
            $display("  OK   [6]: 240 samples at ack=1041, dropped-sample count = 0 (slots=%0d sections=%0d)",
                     (status >> 8) & 8'hFF, (status >> 16) & 8'hFF);
        else begin
            $display("  FAIL [6]: dropped-sample count = %0d (the engine cannot keep up => the real chain would stutter)", (status >> 24) & 8'hFF);
            fails = fails + 1;
        end

        if (fails == 0) $display("\n== tb_engine_js: ALL PASSED ==");
        else            $display("\n== tb_engine_js: %0d failed ==", fails);
        $finish;
    end
endmodule
