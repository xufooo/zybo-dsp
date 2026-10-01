// SPDX-License-Identifier: GPL-2.0-only


`timescale 1ns / 1ps

module tb_engine_fir;

    localparam SLOT_HDR = 192;

    localparam SAMPLE_W = 24;
    localparam COEF_W   = 18;
    localparam SHIFT    = 15;
    localparam NB       = 6;
    localparam HEADROOM = 0;

    localparam NCOEF    = 240;
    localparam FIR_BASE = 2*NCOEF;

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
        .lim_bypass(lim_bypass), .lim_tp(lim_tp),
        .lim_thr(lim_thr), .lim_att(lim_att), .lim_rel(lim_rel),
        .headroom(headroom)
    );

    task put_coef(input integer idx, input integer val);
        begin
            @(negedge clk); cidx = idx[15:0]; cdat = val[31:0]; cwr = 1;
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

    task put_fir_slot(input integer i, input integer nbits,
                      input integer ina, input integer outb, input integer cfb);
        begin

            put_slot(i*8 + 0, {8'd0, nbits[7:0], 8'd0, 8'd5});
            put_slot(i*8 + 1, cfb[31:0]);
            put_slot(i*8 + 2, 32'd0);
            put_slot(i*8 + 3, ina[31:0]);
            put_slot(i*8 + 4, 32'hFFFF);
            put_slot(i*8 + 5, outb[31:0]);
            put_slot(i*8 + 6, 32'd0);
            put_slot(i*8 + 7, 32'd0);
        end
    endtask

    reg [SAMPLE_W-1:0] lval = 0, rval = 0;
    reg [SAMPLE_W-1:0] cur = 0;
    reg parity = 0;

    localparam MAXV = 256;
    reg [SAMPLE_W-1:0] cap [0:MAXV-1];
    integer nc = 0;

    reg [15:0] ack_per = 16'd1200;
    initial begin
        out_ack = 0;
        forever begin
            repeat (ack_per) @(negedge clk);
            out_ack = 1;
            @(negedge clk);
            out_ack = 0;
        end
    end

    always @(posedge clk) if (resetn && out_ack && nc < MAXV) begin
        cap[nc] = out_data;
        in_data <= (nc == 0) ? 4194304 : 0;
        nc = nc + 1;
    end

    integer fdbg = 0;
    always @(posedge clk) if (resetn && (u_dut.u_fir.g_core[0].u_core.fstate === 2'd1 || u_dut.state === 4'd13) && fdbg < 20) begin
        $display("  FDBG st=%0d j=%0d en=%b start=%b ch=%0d ch_r=%0d s_in=%0d xin=%0d wp0=%0d wp1=%0d | c_r0=%0d h_r0=%0d radr0=%0d | prod0=%0d acc0=%0d",
                 u_dut.state, u_dut.u_fir.g_core[0].u_core.jcnt, u_dut.u_fir.g_core[0].u_core.lane_en,
                 u_dut.u_fir.g_core[0].u_core.start, u_dut.u_fir.g_core[0].u_core.ch, u_dut.u_fir.g_core[0].u_core.ch_r,
                 $signed(u_dut.s_in), $signed(u_dut.u_fir.g_core[0].u_core.x_in),
                 u_dut.u_fir.g_core[0].u_core.wp[0], u_dut.u_fir.g_core[0].u_core.wp[1],
                 $signed(u_dut.u_fir.g_core[0].u_core.g_bank[0].c_r), $signed(u_dut.u_fir.g_core[0].u_core.g_bank[0].h_r),
                 u_dut.u_fir.g_core[0].u_core.radr[0], $signed(u_dut.u_fir.g_core[0].u_core.prod_r[0]),
                 $signed(u_dut.u_fir.g_core[0].u_core.acc_lane[0]));
        fdbg = fdbg + 1;
    end

    integer fdon = 0;
    always @(posedge clk) if (resetn && u_dut.u_fir.g_core[0].u_core.done && fdon < 24) begin
        $display("  FDONE ch=%0d j=%0d acc0=%0d acc7=%0d s10=%0d s11=%0d y=%0d yX=%b",
                 u_dut.u_fir.g_core[0].u_core.ch_r, u_dut.u_fir.g_core[0].u_core.jcnt,
                 $signed(u_dut.u_fir.g_core[0].u_core.acc_lane[0]), $signed(u_dut.u_fir.g_core[0].u_core.acc_lane[7]),
                 $signed(u_dut.u_fir.g_core[0].u_core.mrg_a), $signed(u_dut.u_fir.g_core[0].u_core.mrg_b),
                 $signed(u_dut.u_fir.g_core[0].u_core.y_out), (^u_dut.u_fir.g_core[0].u_core.y_out === 1'bx));
        fdon = fdon + 1;
    end

    integer cdbg = 0;
    always @(posedge clk) if (resetn && out_ack && nc < 24) begin
        $display("  CDBG nc=%0d st=%0d slot=%0d out=%0d yfir=%0d fdone=%b fstate=%0d j=%0d cur=%0d sin=%0d chpar=%b",
                 nc, u_dut.state, u_dut.slot_idx, $signed(out_data),
                 $signed(u_dut.u_fir.g_core[0].u_core.y_out), u_dut.u_fir.g_core[0].u_core.done, u_dut.u_fir.g_core[0].u_core.fstate,
                 u_dut.u_fir.g_core[0].u_core.jcnt, $signed(cur), $signed(u_dut.s_in), u_dut.ch_par);
        cdbg = cdbg + 1;
    end

    integer fails = 0;
    task ck(input cond, input integer id);
        begin
            if (cond) $display("  OK   [%0d]", id);
            else begin $display("  FAIL [%0d]", id); fails = fails + 1; end
        end
    endtask

    integer i;
    reg [SAMPLE_W-1:0] yL, yR;
    initial begin
        $display("\n== tb_engine_fir: slot table -> OP_FIR -> output bus ==");
        in_stb = 1;
        repeat (8) @(negedge clk);
        resetn = 1;
        while (u_dut.clr_busy) @(negedge clk);
        repeat (8) @(negedge clk);
        dsp_bypass = 0; lim_bypass = 1; headroom = 0;
        bank_sel = 1;

        put_coef(FIR_BASE + 0,    16384);
        put_coef(FIR_BASE + 7,     8192);
        put_coef(FIR_BASE + 8,     4096);
        put_coef(FIR_BASE + 64,    2048);
        put_coef(FIR_BASE + 8192 + 0,  8192);
        put_coef(FIR_BASE + 8192 + 64,  512);

        put_fir_slot(0, 9, 0, 1, FIR_BASE);

        put_slot(SLOT_HDR, 32'd1);
        do_commit;

        for (i = 0; i < 40; i = i + 1) begin
            @(negedge clk);
            $display("  DBG st=%0d slot=%0d op=%0d fl=%0d n=%0d ina=%0d out=%0d nslots=%0d cur=%0d",
                     u_dut.state, u_dut.slot_idx, u_dut.sl_op_r, u_dut.sl_fl_r,
                     u_dut.sl_n_r, u_dut.sl_ina_r, u_dut.sl_out_r, u_dut.nslot_eff,
                     $signed(u_dut.s_in));
        end

        in_data = 0;
        repeat (3000) @(posedge clk);

        nc = 0;
        while (nc < 140) @(posedge clk);

        begin : scan_blk
            integer k, k0, nzpos [0:7], nzn [0:7], nzc, ph;
            nzc = 0; k0 = -1;

            for (k = 0; k < 140; k = k + 1) begin
                if ((^cap[k] === 1'bx)) begin
                    if (k0 >= 0) begin
                        $display("        cap[%0d] is X again (must not appear after the transient)", k);
                    end
                end else if (k0 < 0) begin
                    k0 = k;
                end
            end

            ck(k0 === 0, 11);
            for (k = k0; k < 140; k = k + 1) begin
                if ($signed(cap[k]) !== 0 && nzc < 8) begin
                    nzpos[nzc] = k; nzn[nzc] = $signed(cap[k]); nzc = nzc + 1;
                end
            end
            $display("  DUMP non-zero terms: %0d", nzc);
            for (k = 0; k < nzc; k = k + 1)
                $display("        cap[%0d] = %0d", nzpos[k], nzn[k]);

            if (nzc === 4) begin
                ck((nzpos[1]-nzpos[0]) === 14 &&
                   (nzpos[2]-nzpos[0]) === 16 &&
                   (nzpos[3]-nzpos[0]) === 128, 1);
                ck(nzn[0] === 2097152 && nzn[1] === 1048576 &&
                   nzn[2] === 524288  && nzn[3] === 262144, 2);
                ck(nzpos[0] > 0 && (nzpos[0] % 2) === (nzpos[1] % 2), 3);
                $display("        => L impulse: all four taps correct");
            end else if (nzc === 2) begin
                ck((nzpos[1]-nzpos[0]) === 128, 4);
                ck(nzn[0] === 1048576 && nzn[1] === 65536, 5);
                $display("        => R impulse: both taps correct");
            end else begin
                ck(0, 6);
            end
        end
        ck((cap1 & 32'h20) === 32'h20, 10);

        ck(cap2[15:8] === 8'd9, 11);

        ck(cap3[31:24] === NCOEF[7:0], 15);
        ck(cap2[7:0] === 8'd24, 12);

        $display("        status=%08x slots=%0d sections=%0d bank=%0d",
                 status, (status >> 8) & 8'hFF, (status >> 16) & 8'hFF, (status >> 1) & 1);
        ck(((status >> 8) & 8'hFF) === 8'd1, 13);

        $display("\n-- Phase B: budget (16 EQ sections + FIR, ack=1041 cycles = real 48 kHz) --");

        bank_sel = ~bank_sel;
        begin : bud_blk
            integer k2, ov;

            for (k2 = 0; k2 < 16; k2 = k2 + 1) begin
                put_coef(k2*5 + 0, 32767);
                put_coef(k2*5 + 1, 0);
                put_coef(k2*5 + 2, 0);
                put_coef(k2*5 + 3, 0);
                put_coef(k2*5 + 4, 0);
            end

            put_slot(0*8 + 0, {8'd0, 8'd16, 8'd0, 8'd1});
            put_slot(0*8 + 1, 32'd0);
            put_slot(0*8 + 2, 32'd0);
            put_slot(0*8 + 3, 32'd0);
            put_slot(0*8 + 4, 32'hFFFF);
            put_slot(0*8 + 5, 32'd1);
            put_slot(0*8 + 6, 32'd0);
            put_slot(0*8 + 7, 32'd0);
            put_fir_slot(1, 9, 1, 2, FIR_BASE);
            put_slot(SLOT_HDR, 32'd2);
            do_commit;

            ack_per = 16'd1041;
            nc = 0;
            while (nc < 40) @(posedge clk);
            ov = (status >> 24) & 8'hFF;
            $display("     collected 40 samples; status=%08x dropped=%0d nsec=%0d nslot=%0d",
                     status, ov, (status >> 16) & 8'hFF, (status >> 8) & 8'hFF);
            ck(ov === 0, 12);
            ck(nc >= 40, 13);

            ck(((status >> 8) & 8'hFF) === 8'd2, 15);
            ck(((status >> 16) & 8'hFF) === 8'd16, 16);

            ck(nc >= 40, 14);
        end

        if (fails == 0) $display("\n== tb_engine_fir ALL PASSED ==\n");
        else            $display("\n== tb_engine_fir: %0d failed ==\n", fails);
        $finish;
    end

    initial begin
        #40000000;
        $display("!! simulation timeout (nc=%0d)", nc);
        $finish;
    end
endmodule
