// SPDX-License-Identifier: GPL-2.0-only


module tb_fir_bank_long;
    localparam SAMPLE_W = 24, COEF_W = 18, SHIFT = 15, ACC_W = 56, NCH = 2;
    localparam BLK_TAPS = 64, BLKS = 2, MACS8 = 8, MACS16 = 16;
    localparam TOT = BLK_TAPS * BLKS;

    reg clk = 0;
    always #5 clk = ~clk;

    reg                       resetn = 0;
    reg                       cwr = 0;
    reg  [15:0]               caddr = 0;
    reg  signed [COEF_W-1:0]  cdat = 0;
    reg                       start = 0;
    reg                       ch = 0;
    reg  [15:0]               ntaps = TOT;
    reg  signed [SAMPLE_W-1:0] x_in = 0;
    wire                      done8, done16;
    wire signed [SAMPLE_W-1:0] y8, y16;

    fir_bank_long #(
        .SAMPLE_W(SAMPLE_W), .COEF_W(COEF_W), .SHIFT(SHIFT), .ACC_W(ACC_W),
        .NCH(NCH), .BLK_TAPS(BLK_TAPS), .BLKS(BLKS), .MACS(MACS8)
    ) dut8 (
        .clk(clk), .resetn(resetn), .cwr(cwr), .caddr(caddr), .cdat(cdat),
        .start(start), .ch(ch), .ntaps(ntaps), .x_in(x_in),
        .done(done8), .y_out(y8)
    );

    fir_bank_long #(
        .SAMPLE_W(SAMPLE_W), .COEF_W(COEF_W), .SHIFT(SHIFT), .ACC_W(ACC_W),
        .NCH(NCH), .BLK_TAPS(BLK_TAPS), .BLKS(BLKS), .MACS(MACS16)
    ) dut16 (
        .clk(clk), .resetn(resetn), .cwr(cwr), .caddr(caddr), .cdat(cdat),
        .start(start), .ch(ch), .ntaps(ntaps), .x_in(x_in),
        .done(done16), .y_out(y16)
    );

    integer fails = 0;
    integer mdiff = 0;
    integer dbg = 0;
    task check(input cond, input [255:0] what);
        begin
            if (!cond) begin $display("  FAIL: %0s", what); fails = fails + 1; end
            else        $display("  OK  : %0s", what);
        end
    endtask

    task put_coef(input integer chn, input integer k, input integer val);
        begin
            @(negedge clk);
            caddr = chn*TOT + (k/BLK_TAPS)*BLK_TAPS + (k%BLK_TAPS);
            cdat  = val[COEF_W-1:0];
            cwr   = 1;
            @(negedge clk); cwr = 0;
        end
    endtask

    task sample(input signed [SAMPLE_W-1:0] s, output signed [SAMPLE_W-1:0] y);
        reg seen8, seen16;
        integer w;
        begin
            @(negedge clk); x_in = s; start = 1;
            @(negedge clk); start = 0;
            seen8 = 0; seen16 = 0; w = 0;
            while (!(seen8 && seen16) && w < 8000) begin
                @(negedge clk); w = w + 1;
                if (done8)  seen8  = 1;
                if (done16) seen16 = 1;
            end
            y = y16;
            if (w >= 8000) begin $display("  FAIL: done timeout"); fails = fails + 1; end
            if (y8 !== y16) begin
                mdiff = mdiff + 1;
                if (mdiff <= 3)
                    $display("      [diff] ch=%0d ntaps=%0d x=%0d : M8=%0d M16=%0d",
                             ch, ntaps, s, y8, y16);
            end
            if (dbg < 6) begin
                $display("      [dbg] ch=%0d ntaps=%0d x=%0d y(M16)=%0d y(M8)=%0d | c0(M16).y=%0d c1(M16).y=%0d bx1=%0d dp0=%0d",
                         ch, ntaps, s, y, y8,
                         dut16.g_core[0].u_core.y_out, dut16.g_core[1].u_core.y_out,
                         dut16.bx[1], dut16.dp[0]);
                $display("            DLEN=%0d dly[0]=%0d dly[1]=%0d dly[64]=%0d",
                         dut16.DLEN, dut16.dly[0], dut16.dly[1], dut16.dly[64]);
                dbg = dbg + 1;
            end
            @(negedge clk);
        end
    endtask

    integer i, nz, npk;
    integer pk_pos [0:15];
    integer pk_val [0:15];
    reg signed [SAMPLE_W-1:0] y;
    localparam PULSE = 24'sd32768;

    task impulse_and_collect(input integer chn, input integer n);
        begin
            ch = chn[0]; ntaps = n[15:0];
            nz = 0;
            for (i = 0; i < 200; i = i + 1) begin
                sample((i == 0) ? PULSE : 24'sd0, y);
                if (y != 0 && nz < 16) begin
                    pk_pos[nz] = i; pk_val[nz] = y; nz = nz + 1;
                end
            end
            $display("  channel %0d / ntaps=%0d: %0d nonzero", chn, n, nz);
            for (i = 0; i < nz; i = i + 1)
                $display("      n=%0d y=%0d", pk_pos[i], pk_val[i]);
        end
    endtask

    initial begin
        resetn = 0; repeat(4) @(negedge clk);
        resetn = 1; repeat(2) @(negedge clk);

        put_coef(0, 0,   16384);
        put_coef(0, 64,   8192);
        put_coef(1, 0,    8192);
        put_coef(1, 127,  4096);

        $display("\n== tb_fir_bank_long: parallel-core block decomposition (BLK_TAPS=%0d, BLKS=%0d, MACS=%0d and %0d) ==",
                 BLK_TAPS, BLKS, MACS8, MACS16);

        $display("\n-- 1. left-channel impulse (tap 0 in block 0, tap 64 in block 1)--");
        impulse_and_collect(0, TOT);
        check(nz == 2, "left channel should have only 2 nonzeros (tap 0 and tap 64)");
        if (nz == 2) begin
            check(pk_pos[0] == 0  && pk_val[0] == 16384, "tap0  = 0.5  → 16384");
            check(pk_pos[1] == 64 && pk_val[1] == 8192,  "tap64 = 0.25 -> 8192 (block 1 routing/delay line correct)");
        end

        $display("\n-- 2. right-channel impulse (tap 127 = last tap of block 1)--");
        impulse_and_collect(1, TOT);
        check(nz == 2, "right channel should have only 2 nonzeros (tap 0 and tap 127)");
        if (nz == 2) begin
            check(pk_pos[0] == 0   && pk_val[0] == 8192, "tap0   = 0.25  → 8192");
            check(pk_pos[1] == 127 && pk_val[1] == 4096, "tap127 = 0.125 -> 4096 (block-tail boundary)");
        end

        $display("\n-- 3. short IR: ntaps=64 => only block 0 works --");
        impulse_and_collect(0, 64);
        check(nz == 1 && pk_val[0] == 16384, "with ntaps=64 tap64 must not appear (block 1 ntaps clamped to 0)");

        $display("\n-- 4. both MACS bit-exact --");
        check(mdiff == 0, "y(MACS=8) === y(MACS=16) throughout (bit-exact, incl. block boundary and wrap)");

        if (fails == 0) $display("\n== tb_fir_bank_long ALL PASSED ==");
        else            $display("\n== tb_fir_bank_long: %0d FAILED ==", fails);
        $finish;
    end
endmodule
