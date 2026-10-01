// SPDX-License-Identifier: GPL-2.0-only


module tb_engine_xphase;

    localparam CROSS_BUS = 22;

    localparam SLOT_HDR  = 192;

    localparam SAMPLE_W = 24;
    localparam COEF_W   = 18;
    localparam SHIFT    = 15;
    localparam NB       = 6;
    localparam HEADROOM = 0;

    localparam integer MAXP   = 256;
    localparam integer NFRAME = 64;

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

    reg [SAMPLE_W-1:0] pin  [0:MAXP-1];
    reg [SAMPLE_W-1:0] pout [0:MAXP-1];
    reg                pl   [0:MAXP-1];
    integer np = 0;

    always @(posedge clk) if (resetn) begin

        if (u_dut.dsp_v && (np < MAXP)) begin
            pout[np] = u_dut.dsp_d;
            np = np + 1;
        end
        if (u_dut.start && (u_dut.state == 4'd0) && (np < MAXP)) begin
            pl[np]  = (u_dut.ch_par == 1'b0);
            pin[np] = in_data;
        end
    end

    function [SAMPLE_W-1:0] val_of(input integer p);
        begin
            if ((p % 2) == 0) val_of = 24'sd1000 + (p / 2);
            else              val_of = 24'sd2000 + ((p - 1) / 2);
        end
    endfunction

    function integer dec_chan(input [SAMPLE_W-1:0] v);
        begin
            if (($signed(v) >= 24'sd1000) && ($signed(v) <= 24'sd1000 + NFRAME)) dec_chan = 0;
            else if (($signed(v) >= 24'sd2000) && ($signed(v) <= 24'sd2000 + NFRAME)) dec_chan = 1;
            else dec_chan = -1;
        end
    endfunction
    function integer dec_frm(input [SAMPLE_W-1:0] v);
        begin
            if (dec_chan(v) == 0) dec_frm = $signed(v) - 1000;
            else                  dec_frm = $signed(v) - 2000;
        end
    endfunction

    reg [SAMPLE_W-1:0] cur = 24'sd1000;
    reg [15:0]         passno = 0;
    always @(negedge clk) if (resetn && in_stb) in_data <= cur;
    always @(posedge clk) if (resetn && u_dut.start && (u_dut.state == 4'd0)) begin
        passno <= passno + 16'd1;
        cur    <= val_of(passno + 1);
    end

    initial begin
        out_ack = 0;
        forever begin
            repeat (48) @(negedge clk);
            out_ack = 1;
            @(negedge clk);
            out_ack = 0;
        end
    end

    task wait_passes(input integer n);
        integer target;
        begin
            target = np + n;
            while (np < target) @(posedge clk);
        end
    endtask

    task load_reader_biquad;
        begin
            bank_sel = ~u_dut.active_bank;

            put_coef(0, 32768); put_coef(1, 0); put_coef(2, 0); put_coef(3, 0); put_coef(4, 0);
            put_coef(5, 32768); put_coef(6, 0); put_coef(7, 0); put_coef(8, 0); put_coef(9, 0);
            put_desc(0, 8'd1, 0, 16'hFFFF, CROSS_BUS, 0, 0);
            put_desc(1, 8'd1, CROSS_BUS, 16'hFFFF, 1, 5, 2);
            put_slot(SLOT_HDR, 32'd2);
            do_commit;
        end
    endtask

    task load_reader_mix2;
        begin
            bank_sel = ~u_dut.active_bank;
            put_coef(0, 32768); put_coef(1, 0); put_coef(2, 0); put_coef(3, 0); put_coef(4, 0);
            put_coef(5, 32768); put_coef(6, 0); put_coef(7, 0); put_coef(8, 0); put_coef(9, 0);
            put_desc(0, 8'd1, 0, 16'hFFFF, CROSS_BUS, 0, 0);
            put_desc(1, 8'd3, CROSS_BUS, 0, 1, 5, 0);
            put_slot(SLOT_HDR, 32'd2);
            do_commit;
        end
    endtask

    task table_reset;
        begin
            np = 0;
            passno = 0;
            cur = val_of(0);
        end
    endtask

    integer k, bad, nbad, vchan, vfrm, n_sameL, n_lagR, n_lagL, n_sameR, nrows, expect;
    task check_table;
        begin
            bad = 0; nbad = 0;
            n_lagL = 0; n_sameL = 0; n_sameR = 0; n_lagR = 0;
            nrows = 0;
            for (k = 0; k < np && k < MAXP; k = k + 1) begin
                vchan = dec_chan(pin[k]);
                vfrm  = dec_frm(pin[k]);
                if (vchan < 0) begin

                end else if (vchan != (pl[k] ? 0 : 1)) begin
                    nbad = nbad + 1;
                end else if (k < 4) begin

                end else begin
                    nrows = nrows + 1;
                    if (pl[k]) expect = 2000 + (vfrm - 1);
                    else       expect = 1000 + vfrm;
                    if ($signed(pout[k]) !== expect) begin
                        if (bad < 8)
                            $display("      row %0d: pass channel=%s frame=%0d read=%0d, want=%0d",
                                     k, pl[k] ? "L" : "R", vfrm, $signed(pout[k]), expect);
                        bad = bad + 1;
                    end

                    if (pl[k]  && ($signed(pout[k]) === 2000 + vfrm))       n_sameL = n_sameL + 1;
                    if (pl[k]  && ($signed(pout[k]) === 2000 + (vfrm - 1))) n_lagL  = n_lagL  + 1;
                    if (!pl[k] && ($signed(pout[k]) === 1000 + (vfrm - 1))) n_lagR  = n_lagR  + 1;
                    if (!pl[k] && ($signed(pout[k]) === 1000 + vfrm))       n_sameR = n_sameR + 1;
                end
            end
            if (nbad != 0) begin
                $display("  FAIL (1): %0d rows have stimulus channel != DUT pass channel (table misaligned)", nbad);
                fail = fail + 1;
            end else if (bad != 0) begin
                $display("  FAIL (2)/(3): %0d/%0d rows mismatch", bad, nrows);
                fail = fail + 1;
            end else begin
                $display("  OK   (2)/(3): %0d rows bit-exact", nrows);
            end
            $display("       counter-hypothesis counts (must be 0): L pass read current R frame = %0d, R pass read prev L frame = %0d",
                     n_sameL, n_lagR);
            $display("       positive counts: L pass read prev R frame = %0d, R pass read current L frame = %0d",
                     n_lagL, n_sameR);
            if (n_sameL != 0 || n_lagR != 0) begin
                $display("  FAIL (4): rows inconsistent with L-lag-1/R-same-frame exist");
                fail = fail + 1;
            end else if (n_lagL == 0 || n_sameR == 0) begin
                $display("  FAIL (4): positive hypothesis never hit (table measured nothing)");
                fail = fail + 1;
            end else begin
                $display("  OK   (4): both-passes-same-cycle and both-passes-lagging both ruled out");
            end
        end
    endtask

    task dump_table(input integer n);
        begin
            $display("       row | pass channel | this-pass input (channel,frame) | other channel read (channel,frame)");
            for (k = 0; k < n && k < np; k = k + 1) begin
                vchan = dec_chan(pin[k]);
                vfrm  = dec_frm(pin[k]);
                $display("       %3d |   %s    | (%s,%0d)         | %0d (%s,%0d)",
                         k, pl[k] ? "L" : "R",
                         (vchan == 0) ? "L" : ((vchan == 1) ? "R" : "?"), vfrm,
                         $signed(pout[k]),
                         (dec_chan(pout[k]) == 0) ? "L" : ((dec_chan(pout[k]) == 1) ? "R" : "?"),
                         dec_frm(pout[k]));
            end
        end
    endtask

    reg [SAMPLE_W-1:0] sa_pout [0:MAXP-1];
    reg [SAMPLE_W-1:0] sa_pin  [0:MAXP-1];
    reg                sa_pl   [0:MAXP-1];
    integer            sa_np   = 0;

    integer m, diff;
    initial begin
        $display("== tb_engine_xphase ==");
        in_stb = 1;
        repeat (8) @(negedge clk);
        resetn = 1;
        while (u_dut.clr_busy) @(negedge clk);
        repeat (8) @(negedge clk);
        dsp_bypass = 0; lim_bypass = 1; lim_tp = 0; headroom = 0;
        bank_sel = 1;

        $display("-- phase A: reader slot = OP_BIQUAD --");
        dsp_bypass = 1;
        repeat (4) @(negedge clk);
        load_reader_biquad();
        table_reset();
        dsp_bypass = 0;
        wait_passes(3 * NFRAME);
        dump_table(9);
        check_table;
        $display("       this phase actually ran: slots=%0d sections=%0d", u_dut.nslot_last, u_dut.nsec_last);
        sa_np = np;
        for (m = 0; m < MAXP; m = m + 1) begin
            sa_pout[m] = pout[m];
            sa_pin[m]  = pin[m];
            sa_pl[m]   = pl[m];
        end

        $display("-- phase B: reader slot = OP_MIX2 --");
        dsp_bypass = 1;
        repeat (4) @(negedge clk);
        load_reader_mix2();
        table_reset();
        dsp_bypass = 0;
        wait_passes(3 * NFRAME);
        check_table;
        $display("       this phase actually ran: slots=%0d sections=%0d", u_dut.nslot_last, u_dut.nsec_last);

        $display("-- criterion (5): OP_BIQUAD and OP_MIX2 xf_rd sample points agree --");
        diff = 0;
        if (sa_np != np) begin
            $display("  FAIL (5): pass counts differ between phases (%0d vs %0d)", sa_np, np);
            fail = fail + 1;
        end else begin
            for (m = 4; m < np && m < MAXP; m = m + 1) begin
                if (sa_pout[m] !== pout[m] || sa_pin[m] !== pin[m] || sa_pl[m] !== pl[m])
                    diff = diff + 1;
            end
            if (diff == 0) $display("  OK   (5): (input,output,channel) bit-exact over %0d rows in both phases", np - 4);
            else begin $display("  FAIL (5): %0d rows differ", diff); fail = fail + 1; end
        end

        if (cap1[3] === 1'b1) $display("  OK   (6): CAP1 bit3 = 1 (this bitstream reports MIX2)");
        else begin $display("  FAIL (6): CAP1 bit3 = 0"); fail = fail + 1; end

        $display("  OK   (7): that 1 sample at 55 Hz = %.4f deg (= 360*55/48000); for reference the same sample at 10 kHz = %.2f deg",
                 360.0*55.0/48000.0, 360.0*10000.0/48000.0);

        if (fail == 0) $display("== tb_engine_xphase: ALL PASSED ==");
        else           $display("== tb_engine_xphase: %0d FAILED ==", fail);
        $finish;
    end
endmodule
