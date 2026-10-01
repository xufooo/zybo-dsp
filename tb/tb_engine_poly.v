// SPDX-License-Identifier: GPL-2.0-only


`timescale 1ns / 1ps

module tb_engine_poly;

    localparam SLOT_HDR = 192;

    localparam [7:0] SLOT_D_Q = 8'd21;

    localparam SAMPLE_W = 24;
    localparam COEF_W   = 18;
    localparam SHIFT    = 15;
    localparam NB       = 6;
    localparam HEADROOM = 0;
    localparam FIR_BASE = 480;
    localparam OP_POLY  = 6;

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

    task use_idle_bank;
        begin
            bank_sel = ~u_dut.active_bank;
        end
    endtask

    task do_commit;
        begin
            @(negedge clk); commit = 1;
            @(negedge clk); commit = 0;
            while (status[0]) @(negedge clk);
            repeat (8) @(negedge clk);

            use_idle_bank;
        end
    endtask

    task put_poly_slot(input integer i, input integer cfb, input integer stb,
                       input integer ina, input integer outb);
        begin
            put_slot(i*8 + 0, {8'd0, 8'd11, 8'd0, OP_POLY[7:0]});
            put_slot(i*8 + 1, cfb[31:0]);
            put_slot(i*8 + 2, stb[31:0]);
            put_slot(i*8 + 3, ina[31:0]);
            put_slot(i*8 + 4, 32'hFFFF);
            put_slot(i*8 + 5, outb[31:0]);
            put_slot(i*8 + 6, 32'd0);
            put_slot(i*8 + 7, 32'd0);
        end
    endtask
    task put_biquad_slot(input integer i, input integer n, input integer cfb,
                         input integer stb, input integer ina, input integer outb);
        begin
            put_slot(i*8 + 0, {8'd0, n[7:0], 8'd0, 8'd1});
            put_slot(i*8 + 1, cfb[31:0]);
            put_slot(i*8 + 2, stb[31:0]);
            put_slot(i*8 + 3, ina[31:0]);
            put_slot(i*8 + 4, 32'hFFFF);
            put_slot(i*8 + 5, outb[31:0]);
            put_slot(i*8 + 6, 32'd0);
            put_slot(i*8 + 7, 32'd0);
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

    reg signed [63:0] rc [0:10];
    reg signed [63:0] r_mute;
    reg signed [63:0] r_pp [0:1];
    reg signed [63:0] r_py [0:1];
    reg signed [63:0] r_pc [0:1];
    integer rj;

    task ref_reset;
        begin
            r_pp[0] = 0; r_py[0] = 0; r_pc[0] = 0;
            r_pp[1] = 0; r_py[1] = 0; r_pc[1] = 0;
        end
    endtask

    function signed [23:0] tsat(input signed [63:0] v);
        begin
            if (v > 64'sd8388607)       tsat = 24'sd8388607;
            else if (v < -64'sd8388608) tsat = -24'sd8388608;
            else                        tsat = v[23:0];
        end
    endfunction

    function signed [23:0] ref_step(input integer ch, input signed [23:0] xin);
        reg signed [63:0] a, x18, prod, pnow, ynow, pprev;
        integer k;
        begin
            x18 = xin;
            x18 = x18 >>> 6;
            a = rc[10] <<< 23;
            for (k = 9; k >= 0; k = k - 1) begin
                prod = (a >>> 17) * x18;
                a = prod + (rc[k] <<< 23);
            end
            pnow  = tsat(a >>> 15);
            pprev = r_pp[ch];
            a = (a - (pprev <<< 15)) + (r_py[ch] * 32735);
            ynow = tsat(a >>> 15);
            r_pp[ch] = pnow;
            r_py[ch] = ynow;
            if (r_pc[ch] < r_mute) begin
                r_pc[ch] = r_pc[ch] + 1;
                ref_step = 24'sd0;
            end else begin
                ref_step = ynow;
            end
        end
    endfunction

    localparam MAXV = 256;
    reg [SAMPLE_W-1:0] cap [0:MAXV-1];
    reg [SAMPLE_W-1:0] seq [0:63];
    integer nc = 0;
    reg [15:0] ack_per = 16'd220;

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
        in_data <= seq[(nc + 1 > 63) ? 63 : nc + 1];
        nc = nc + 1;
    end

    integer fails = 0;
    task ck(input cond, input integer id);
        begin
            if (cond) $display("  OK   [%0d]", id);
            else begin $display("  FAIL [%0d]", id); fails = fails + 1; end
        end
    endtask

    integer i, k, k0, nbad;
    reg signed [23:0] expct;

    initial begin

        for (i = 0; i < 64; i = i + 1) seq[i] = 0;
        $display("\n== tb_engine_poly: slot table -> OP_POLY (Horner + leaky integrator) -> output bus ==");
        in_stb = 1;
        repeat (8) @(negedge clk);
        resetn = 1;
        while (u_dut.clr_busy) @(negedge clk);
        repeat (8) @(negedge clk);
        dsp_bypass = 0; lim_bypass = 1; headroom = 0;
        use_idle_bank;

        for (i = 0; i < 11; i = i + 1) rc[i] = 0;
        rc[1] = 32768;
        rc[3] = 16384;
        rc[10] = 16384;
        r_mute = 0;
        for (k = 0; k < 12; k = k + 1) put_coef(k, 0);
        put_coef(1,  32768);
        put_coef(3,  16384);
        put_coef(10, 16384);
        put_coef(11, 0);
        put_poly_slot(0, 0, 0, 0, 1);
        put_slot(SLOT_HDR, 32'd1);
        do_commit;

        repeat (4000) @(posedge clk);

        seq[0]=4194304;  seq[1]=2097152;  seq[2]=-4194304; seq[3]=0;
        seq[4]=1048576;  seq[5]=6291456;  seq[6]=-2097152; seq[7]=8388607;
        for (i = 8; i < 64; i = i + 1) seq[i] = seq[i-8];
        in_data = seq[0];
        nc = 0;
        while (nc < 24) @(posedge clk);

        $display("  DUMP capture (first 24):");
        for (i = 0; i < 24; i = i + 1)
            $display("        cap[%0d] = %0d%s", i, $signed(cap[i]),
                     ((^cap[i]) === 1'bx) ? "  <X>" : "");

        begin : align_blk
            integer off, nb, best, bestoff, jj;
            best = 9999; bestoff = -1;
            for (off = 1; off <= 3; off = off + 1) begin
                ref_reset;
                nb = 0;
                for (i = 0; i < 24; i = i + 1) begin
                    jj = i - off;
                    if (jj >= 0) begin
                        expct = ref_step(jj % 2, seq[jj]);
                        if ($signed(cap[i]) !== $signed(expct)) begin
                            if (nb < 5 && off == 1)
                                $display("        diff(off=1) cap[%0d]=%0d want %0d (seq[%0d])",
                                         i, $signed(cap[i]), $signed(expct), jj);
                            nb = nb + 1;
                        end
                    end
                end
                if (nb < best) begin best = nb; bestoff = off; end
            end
            $display("        best alignment off=%0d (%0d mismatches)", bestoff, best);
            ck(best === 0, 1);
            ck(bestoff >= 1 && bestoff <= 3, 2);
        end

        ck((cap1 & 32'h40) === 32'h40, 3);
        ck((cap1 & 32'h20) === 32'h20, 4);
        ck(cap3[15:8] === 8'd26, 5);

        ck(cap3[7:0] === 8'd9, 6);
        $display("        cap1=%08x cap3=%08x status=%08x slots=%0d sections=%0d",
                 cap1, cap3, status, (status >> 8) & 8'hFF, (status >> 16) & 8'hFF);
        ck(((status >> 8) & 8'hFF) === 8'd1, 7);
        ck(((status >> 16) & 8'hFF) === 8'd0, 8);

        $display("\n-- phase B: de-click (|c|max*10000 = 4 cycles)--");
        use_idle_bank;
        put_coef(11, 4);
        put_slot(SLOT_HDR, 32'd1);
        do_commit;
        for (i = 0; i < 64; i = i + 1) seq[i] = 0;
        for (i = 0; i < 64; i = i + 1) seq[i] = 4194304;
        in_data = 4194304;
        nc = 0;
        while (nc < 12) @(posedge clk);
        begin : mute_blk
            integer m, mz, found, kk, okz;
            found = -1;

            for (m = 0; m <= 4; m = m + 1) begin
                okz = 1;
                for (kk = 0; kk < 8; kk = kk + 1)
                    if (((^cap[m+kk]) === 1'bx) || ($signed(cap[m+kk]) !== 0)) okz = 0;
                if (okz === 1 && ((^cap[m+8]) !== 1'bx) && ($signed(cap[m+8]) !== 0) && found < 0)
                    found = m;
            end
            $display("        mute: first position of '8 zeros followed by non-zero' = %0d; cap[8..12]=%0d,%0d,%0d,%0d,%0d",
                     found, $signed(cap[8]), $signed(cap[9]), $signed(cap[10]),
                     $signed(cap[11]), $signed(cap[12]));
            ck(found >= 0, 9);
        end

        $display("\n-- phase C: budget (15 EQ sections + POLY + an 8192-tap FIR, ack=1041 cycles)--");
        begin : bud_blk
            integer ov;
            ack_per = 16'd1041;
            repeat (4000) @(posedge clk);
            use_idle_bank;
            for (k = 0; k < 16; k = k + 1) begin
                put_coef(k*5 + 0, 32767);
                put_coef(k*5 + 1, 0);
                put_coef(k*5 + 2, 0);
                put_coef(k*5 + 3, 0);
                put_coef(k*5 + 4, 0);
            end
            for (k = 0; k < 12; k = k + 1) put_coef(100 + k, 0);
            put_coef(100 + 1, 32768);
            put_coef(100 + 3, 16384);

            put_biquad_slot(0, 15, 0, 0, 0, 1);
            put_poly_slot(1, 100, 15, 1, 2);
            put_fir_slot(2, 9, 2, 3, FIR_BASE);
            put_slot(SLOT_HDR, 32'd3);
            do_commit;

            nc = 0;
            while (nc < 40) @(posedge clk);
            ov = (status >> 24) & 8'hFF;
            $display("        collected 40 samples; status=%08x dropped=%0d nslot=%0d nsec=%0d",
                     status, ov, (status >> 8) & 8'hFF, (status >> 16) & 8'hFF);
            ck(ov === 0, 10);
            ck(nc >= 40, 11);
            ck(((status >> 8) & 8'hFF) === 8'd3, 12);
            ck(((status >> 16) & 8'hFF) === 8'd15, 13);
        end

        $display("\n-- phase D: %0d slots (the dedicated NSLOT=24 growth case)--", SLOT_D_Q);
        begin : slot_blk
            integer q, ov;
            for (q = 0; q < SLOT_D_Q; q = q + 1) begin
                put_coef(q*5 + 0, 32767);
                put_coef(q*5 + 1, 0);
                put_coef(q*5 + 2, 0);
                put_coef(q*5 + 3, 0);
                put_coef(q*5 + 4, 0);
            end
            for (q = 0; q < SLOT_D_Q; q = q + 1)
                put_biquad_slot(q, 1, q*5, q, q, q+1);
            put_slot(SLOT_HDR, SLOT_D_Q);
            do_commit;
            nc = 0;
            while (nc < 20) @(posedge clk);
            ov = (status >> 24) & 8'hFF;
            $display("        STATUS=%08x slots=%0d sections=%0d dropped=%0d",
                     status, (status >> 8) & 8'hFF, (status >> 16) & 8'hFF, ov);
            ck(((status >> 8) & 8'hFF) === SLOT_D_Q, 14);
            ck(((status >> 16) & 8'hFF) === SLOT_D_Q, 15);
            ck(ov === 0, 16);
            ck(cap2[7:0] === 8'd24, 17);
        end

        if (fails == 0) $display("\n== tb_engine_poly: all passed ==\n");
        else            $display("\n== tb_engine_poly: %0d FAILED ==\n", fails);
        $finish;
    end

    initial begin
        #40000000;
        $display("!! simulation timeout (nc=%0d)", nc);
        $finish;
    end
endmodule
