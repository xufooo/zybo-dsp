// SPDX-License-Identifier: GPL-2.0-only


module tb_engine_dynbass;
    localparam CROSS_BUS = 22;
    localparam SLOT_HDR  = 192;

    localparam SAMPLE_W = 24;
    localparam COEF_W   = 18;
    localparam SHIFT    = 15;
    localparam NB       = 6;
    localparam HEADROOM = 0;

    localparam OP_BIQUAD = 1, OP_MIX2 = 3;

    localparam integer NFRAME = 200;
    localparam integer MAXP   = 512;

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

    reg [SAMPLE_W-1:0] in_vec [0:2*NFRAME-1];
    reg [SAMPLE_W-1:0] gold_l [0:NFRAME-1];
    reg [SAMPLE_W-1:0] gold_r [0:NFRAME-1];

    reg [31:0] lp [0:4];
    reg [31:0] sw [0:1];
    reg [31:0] aw [0:1];

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

    task put_desc(input integer i, input integer op, input integer n, input integer ina,
                  input integer inb, input integer outb, input integer cfb, input integer stb);
        begin
            put_slot(i*8 + 0, {8'd0, n[7:0], 8'd0, op[7:0]});
            put_slot(i*8 + 1, cfb[31:0]);
            put_slot(i*8 + 2, stb[31:0]);
            put_slot(i*8 + 3, ina[31:0]);
            put_slot(i*8 + 4, inb[31:0]);
            put_slot(i*8 + 5, outb[31:0]);
            put_slot(i*8 + 6, 32'd0);
            put_slot(i*8 + 7, 32'd0);
        end
    endtask

    task load_plan;
        begin
            bank_sel = ~u_dut.active_bank;

            put_coef(0, sw[0]); put_coef(1, sw[0]); put_coef(2, 0); put_coef(3, 0); put_coef(4, 0);
            put_coef(5, lp[0]); put_coef(6, lp[1]); put_coef(7, lp[2]); put_coef(8, lp[3]); put_coef(9, lp[4]);
            put_coef(10, aw[0]); put_coef(11, aw[0]); put_coef(12, 0); put_coef(13, 0); put_coef(14, 0);
            put_desc(0, 8'd0, 0, 0, 16'hFFFF, CROSS_BUS, 0, 0);
            put_desc(1, OP_MIX2, 1, 0, CROSS_BUS, 1, 0, 0);
            put_desc(2, OP_BIQUAD, 1, 1, 16'hFFFF, 2, 5, 1);
            put_desc(3, OP_MIX2, 1, 0, 2, 3, 10, 2);
            put_slot(SLOT_HDR, 32'd4);
            do_commit;
        end
    endtask

    reg [SAMPLE_W-1:0] pout [0:MAXP-1];
    reg                pl   [0:MAXP-1];
    integer np = 0;
    always @(posedge clk) if (resetn) begin
        if (u_dut.dsp_v && (np < MAXP)) begin
            pout[np] = u_dut.dsp_d;
            np = np + 1;
        end
        if (u_dut.start && (u_dut.state == 4'd0) && (np < MAXP))
            pl[np] = (u_dut.ch_par == 1'b0);
    end

    reg [SAMPLE_W-1:0] cur = 0;
    reg [15:0]         passno = 0;
    always @(negedge clk) if (resetn && in_stb) in_data <= cur;
    always @(posedge clk) if (resetn && u_dut.start && (u_dut.state == 4'd0)) begin
        passno <= passno + 16'd1;

        if ((passno + 1) < 2*NFRAME) cur <= in_vec[passno + 1];
    end

    initial begin
        out_ack = 0;
        forever begin
            repeat (1041) @(negedge clk);
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

    integer k, m, bad, n_l, n_r;
    initial begin
        $display("== tb_engine_dynbass ==");
        $readmemh("dynbass_in.hex",    in_vec);
        $readmemh("dynbass_out_l.hex", gold_l);
        $readmemh("dynbass_out_r.hex", gold_r);
        $readmemh("dynbass_lp.hex",    lp);
        $readmemh("dynbass_side.hex",  sw);
        $readmemh("dynbass_add.hex",   aw);
        cur = in_vec[0];
        in_stb = 1;
        repeat (8) @(negedge clk);
        resetn = 1;
        while (u_dut.clr_busy) @(negedge clk);
        repeat (8) @(negedge clk);
        dsp_bypass = 1; lim_bypass = 1; lim_tp = 0; headroom = 0;
        repeat (4) @(negedge clk);
        load_plan();
        np = 0; passno = 0; cur = in_vec[0];
        dsp_bypass = 0;

        wait_passes(2 * NFRAME + 4);

        bad = 0; n_l = 0; n_r = 0;
        for (m = 4; m < NFRAME; m = m + 1) begin
            k = 2*m;
            if (k < np) begin
                if (pl[k] !== 1'b1) begin
                    $display("  FAIL: pass %0d should be an L pass (the ch_par convention changed)", k);
                    bad = bad + 1;
                end else begin
                    n_l = n_l + 1;
                    if (pout[k] !== gold_l[m]) begin
                        if (bad < 8)
                            $display("  FAIL L frame %0d: engine %0d, golden %0d", m,
                                     $signed(pout[k]), $signed(gold_l[m]));
                        bad = bad + 1;
                    end
                end
            end
            k = 2*m + 1;
            if (k < np) begin
                if (pl[k] !== 1'b0) begin
                    $display("  FAIL: pass %0d should be an R pass", k);
                    bad = bad + 1;
                end else begin
                    n_r = n_r + 1;
                    if (pout[k] !== gold_r[m]) begin
                        if (bad < 8)
                            $display("  FAIL R frame %0d: engine %0d, golden %0d", m,
                                     $signed(pout[k]), $signed(gold_r[m]));
                        bad = bad + 1;
                    end
                end
            end
        end
        if (bad == 0)
            $display("  OK   [1/2]: %0d frames match bit-exact (L %0d passes / R %0d passes, incl. the full 55 Hz lowpass rise)",
                     NFRAME - 4, n_l, n_r);
        else begin
            $display("  FAIL [1/2]: %0d mismatches", bad);
            fail = fail + 1;
        end

        if (u_dut.nslot_last == 8'd3 && u_dut.nsec_last == 8'd1)
            $display("  OK   [3]: header says 4 slots; this frame actually ran %0d timed slots / %0d timed sections (the feed slot n=0 and the two MIX2 are not timed; the Go budget convention of 4 slots/3 sections is a different thing)",
                     u_dut.nslot_last, u_dut.nsec_last);
        else begin
            $display("  FAIL [3]: ran %0d timed slots / %0d timed sections, expected 3 / 1",
                     u_dut.nslot_last, u_dut.nsec_last);
            fail = fail + 1;
        end

        if (status[31:24] == 8'd0)
            $display("  OK   [4]: dropped-sample count = 0 (4 slots + 3 sections are inside the frame budget)");
        else begin
            $display("  FAIL [4]: dropped %0d samples", status[31:24]);
            fail = fail + 1;
        end

        if (cap1[1] === 1'b1 && cap1[3] === 1'b1)
            $display("  OK   [5]: CAP1 bit1 (BIQUAD) and bit3 (MIX2) both set — a precondition of the simplified path");
        else begin
            $display("  FAIL [5]: CAP1 = %08x, missing BIQUAD or MIX2", cap1);
            fail = fail + 1;
        end

        if (fail == 0) $display("== tb_engine_dynbass: ALL PASSED ==");
        else           $display("== tb_engine_dynbass: %0d failed ==", fail);
        $finish;
    end
endmodule
