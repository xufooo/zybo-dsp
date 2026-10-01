// SPDX-License-Identifier: GPL-2.0-only


`timescale 1ns/1ps

module tb_i2s_adi_dsp;
    localparam NSAMPLE = 240;

    reg s_axi_aclk = 0;
    always #5 s_axi_aclk = ~s_axi_aclk;

    reg data_clk = 0;
    always #40.69 data_clk = ~data_clk;

    reg dma_aclk = 0;
    always #5 dma_aclk = ~dma_aclk;

    reg         s00_axi_aresetn = 0;
    reg  [6:0]  s00_axi_awaddr  = 0;
    reg  [2:0]  s00_axi_awprot  = 0;
    reg         s00_axi_awvalid = 0;
    wire        s00_axi_awready;
    reg  [31:0] s00_axi_wdata   = 0;
    reg  [3:0]  s00_axi_wstrb   = 4'hF;
    reg         s00_axi_wvalid  = 0;
    wire        s00_axi_wready;
    wire [1:0]  s00_axi_bresp;
    wire        s00_axi_bvalid;
    reg         s00_axi_bready  = 0;
    reg  [6:0]  s00_axi_araddr  = 0;
    reg  [2:0]  s00_axi_arprot  = 0;
    reg         s00_axi_arvalid = 0;
    wire        s00_axi_arready;
    wire [31:0] s00_axi_rdata;
    wire [1:0]  s00_axi_rresp;
    wire        s00_axi_rvalid;
    reg         s00_axi_rready  = 0;

    reg         tx_davalid = 0;
    reg  [1:0]  tx_datype  = 0;
    wire        tx_daready;
    wire        tx_drvalid;
    wire [1:0]  tx_drtype;
    wire        tx_drlast;
    reg         tx_drready = 0;

    reg         rx_davalid = 0;
    reg  [1:0]  rx_datype  = 0;
    wire        rx_daready;
    wire        rx_drvalid;
    wire [1:0]  rx_drtype;
    wire        rx_drlast;
    reg         rx_drready = 0;

    wire        BCLK_O, LRCLK_O, SDATA_O, MUTEN_O;
    wire        S_AXIS_TREADY;
    wire [31:0] M_AXIS_TDATA;
    wire        M_AXIS_TLAST, M_AXIS_TVALID;
    wire [3:0]  M_AXIS_TKEEP;

    axi_i2s_adi_v1_2 #(
        .C_SLOT_WIDTH   (24),
        .C_S00_AXI_ADDR_WIDTH (7),
        .C_LRCLK_POL    (0),
        .C_BCLK_POL     (0),
        .C_DMA_TYPE     (1),
        .C_NUM_CH       (1),
        .C_HAS_TX       (1),
        .C_HAS_RX       (1)
    ) dut (
        .DATA_CLK_I         (data_clk),
        .BCLK_O             (BCLK_O),
        .LRCLK_O            (LRCLK_O),
        .SDATA_O            (SDATA_O),
        .SDATA_I            (1'b0),
        .MUTEN_O            (MUTEN_O),

        .S_AXIS_ACLK        (s_axi_aclk),
        .S_AXIS_TREADY      (S_AXIS_TREADY),
        .S_AXIS_TDATA       (32'h0),
        .S_AXIS_TLAST       (1'b0),
        .S_AXIS_TVALID      (1'b0),

        .M_AXIS_ACLK        (s_axi_aclk),
        .M_AXIS_TREADY      (1'b0),
        .M_AXIS_TDATA       (M_AXIS_TDATA),
        .M_AXIS_TLAST       (M_AXIS_TLAST),
        .M_AXIS_TVALID      (M_AXIS_TVALID),
        .M_AXIS_TKEEP       (M_AXIS_TKEEP),

        .DMA_REQ_TX_ACLK    (dma_aclk),
        .DMA_REQ_TX_RSTN    (s00_axi_aresetn),
        .DMA_REQ_TX_DAVALID (tx_davalid),
        .DMA_REQ_TX_DATYPE  (tx_datype),
        .DMA_REQ_TX_DAREADY (tx_daready),
        .DMA_REQ_TX_DRVALID (tx_drvalid),
        .DMA_REQ_TX_DRTYPE  (tx_drtype),
        .DMA_REQ_TX_DRLAST  (tx_drlast),
        .DMA_REQ_TX_DRREADY (tx_drready),

        .DMA_REQ_RX_ACLK    (dma_aclk),
        .DMA_REQ_RX_RSTN    (s00_axi_aresetn),
        .DMA_REQ_RX_DAVALID (rx_davalid),
        .DMA_REQ_RX_DATYPE  (rx_datype),
        .DMA_REQ_RX_DAREADY (rx_daready),
        .DMA_REQ_RX_DRVALID (rx_drvalid),
        .DMA_REQ_RX_DRTYPE  (rx_drtype),
        .DMA_REQ_RX_DRLAST  (rx_drlast),
        .DMA_REQ_RX_DRREADY (rx_drready),

        .s00_axi_aclk       (s_axi_aclk),
        .s00_axi_aresetn    (s00_axi_aresetn),
        .s00_axi_awaddr     (s00_axi_awaddr),
        .s00_axi_awprot     (s00_axi_awprot),
        .s00_axi_awvalid    (s00_axi_awvalid),
        .s00_axi_awready    (s00_axi_awready),
        .s00_axi_wdata      (s00_axi_wdata),
        .s00_axi_wstrb      (s00_axi_wstrb),
        .s00_axi_wvalid     (s00_axi_wvalid),
        .s00_axi_wready     (s00_axi_wready),
        .s00_axi_bresp      (s00_axi_bresp),
        .s00_axi_bvalid     (s00_axi_bvalid),
        .s00_axi_bready     (s00_axi_bready),
        .s00_axi_araddr     (s00_axi_araddr),
        .s00_axi_arprot     (s00_axi_arprot),
        .s00_axi_arvalid    (s00_axi_arvalid),
        .s00_axi_arready    (s00_axi_arready),
        .s00_axi_rdata      (s00_axi_rdata),
        .s00_axi_rresp      (s00_axi_rresp),
        .s00_axi_rvalid     (s00_axi_rvalid),
        .s00_axi_rready     (s00_axi_rready)
    );

    integer axi_timeouts = 0;
    integer g;

    task axi_write(input [6:0] addr, input [31:0] data);
        begin
            @(posedge s_axi_aclk);
            s00_axi_awaddr  <= addr;
            s00_axi_awvalid <= 1'b1;
            s00_axi_wdata   <= data;
            s00_axi_wstrb   <= 4'hF;
            s00_axi_wvalid  <= 1'b1;
            s00_axi_bready  <= 1'b1;

            @(posedge s_axi_aclk);
            g = 0;
            while (!(s00_axi_awready && s00_axi_wready)) begin
                @(posedge s_axi_aclk);
                g = g + 1;
                if (g > 200) begin
                    $display("  !! WRITE stuck addr=%h awv=%b awr=%b wv=%b wr=%b bv=%b aresetn=%b",
                             addr, s00_axi_awvalid, s00_axi_awready, s00_axi_wvalid,
                             s00_axi_wready, s00_axi_bvalid, s00_axi_aresetn);
                    axi_timeouts = axi_timeouts + 1;
                    s00_axi_awvalid <= 1'b0; s00_axi_wvalid <= 1'b0; s00_axi_bready <= 1'b0;
                    disable axi_write;
                end
            end
            s00_axi_awvalid <= 1'b0;
            s00_axi_wvalid  <= 1'b0;

            g = 0;
            while (!s00_axi_bvalid) begin
                @(posedge s_axi_aclk);
                g = g + 1;
                if (g > 200) begin
                    $display("  !! WRITE waiting bvalid stuck addr=%h", addr);
                    axi_timeouts = axi_timeouts + 1;
                    s00_axi_bready <= 1'b0;
                    disable axi_write;
                end
            end
            @(posedge s_axi_aclk);
            s00_axi_bready  <= 1'b0;
        end
    endtask

    task axi_read(input [6:0] addr, output [31:0] data);
        begin
            data = 32'hDEAD_BEEF;
            @(posedge s_axi_aclk);
            s00_axi_araddr  <= addr;
            s00_axi_arvalid <= 1'b1;
            s00_axi_rready  <= 1'b1;
            @(posedge s_axi_aclk);
            g = 0;
            while (!s00_axi_arready) begin
                @(posedge s_axi_aclk);
                g = g + 1;
                if (g > 200) begin
                    $display("  !! READ waiting arready stuck addr=%h arv=%b aresetn=%b",
                             addr, s00_axi_arvalid, s00_axi_aresetn);
                    axi_timeouts = axi_timeouts + 1;
                    s00_axi_arvalid <= 1'b0; s00_axi_rready <= 1'b0;
                    disable axi_read;
                end
            end
            s00_axi_arvalid <= 1'b0;
            g = 0;
            while (!s00_axi_rvalid) begin
                @(posedge s_axi_aclk);
                g = g + 1;
                if (g > 200) begin
                    $display("  !! READ waiting rvalid stuck addr=%h arr=%b arv=%b rv=%b rr=%b",
                             addr, s00_axi_arready, s00_axi_arvalid,
                             s00_axi_rvalid, s00_axi_rready);
                    axi_timeouts = axi_timeouts + 1;
                    s00_axi_rready <= 1'b0;
                    disable axi_read;
                end
            end
            data = s00_axi_rdata;
            @(posedge s_axi_aclk);
            s00_axi_rready <= 1'b0;
        end
    endtask

    reg [31:0] written [0:NSAMPLE*4];
    integer k, errors = 0, i;
    integer q2 = 0;
    integer q3 = 0;
    integer off = -1;
    integer q1 = 0;

    reg [23:0] decoded [0:NSAMPLE*24];
    integer    ndec = 0;
    integer    bc   = 0;
    reg [24:0] shreg = 0;
    reg        lrclk_d = 0;
    reg        cap_en  = 0;

    integer nack = 0, nfeed = 0, ncyc = 0, naxi = 0, nbclk = 0;
    always @(posedge dut.tx_ack) nack = nack + 1;
    always @(posedge dma_aclk)   ncyc = ncyc + 1;
    always @(posedge s_axi_aclk) naxi = naxi + 1;
    always @(posedge BCLK_O)     nbclk = nbclk + 1;

    integer nacc = 0;
    always @(posedge dut.tx_ack) if (dut.fifo_tx_stb) nacc = nacc + 1;

    task feed(input integer base, input integer n);
        integer j;
        begin
            for (j = 0; j < n; j = j + 1) begin

                written[base + j] = ((j * 24'h0009D1) ^ 24'h0055A3) & 24'hFFFFFE;
                while (!tx_drvalid) @(posedge dma_aclk);
                @(posedge dma_aclk);
                tx_drready <= 1'b1;
                @(posedge dma_aclk);
                tx_drready <= 1'b0;
                axi_write(7'h2C, written[base + j] << 8);

                while (tx_drvalid) @(posedge dma_aclk);
                @(posedge dma_aclk);
                tx_davalid <= 1'b1;
                tx_datype  <= 2'b00;
                @(posedge dma_aclk);
                tx_davalid <= 1'b0;
                nfeed = nfeed + 1;
            end
        end
    endtask

    task wait_out(input [23:0] val);
        integer t;
        reg     done;
        begin
            done = 0;
            t = 0;
            while (!done && t < 4000000) begin
                @(posedge s_axi_aclk);
                t = t + 1;
                if (ndec >= 2 && (decoded[ndec-1] === val || decoded[ndec-2] === val))
                    done = 1;
            end
            if (!done) begin
                $display("  WARN: waiting for sample %h output timed out (ndec=%0d nfeed=%0d nacc=%0d)",
                         val, ndec, nfeed, nacc);
                $display("    last 10 decoded slots:");
                for (t = 0; t < 10; t = t + 1)
                    $display("      decoded[%0d] = %h", ndec-1-t, decoded[ndec-1-t]);
                $display("    last 10 writes:");
                for (t = 0; t < 10; t = t + 1)
                    $display("      written[%0d] = %h", nfeed-1-t, written[nfeed-1-t]);
            end
        end
    endtask

    task check(input integer base, input integer n, input integer q0,
               input integer tag);
        integer j, off2, bad;
        begin
            off2 = -1;
            for (j = q0; j < ndec; j = j + 1)
                if (off2 < 0 && decoded[j] === written[base]) off2 = j;
            bad = 0;
            if (off2 < 0) begin
                $display("  FAIL [%0d]: segment-head sample %h not found", tag, written[base]);
                errors = errors + 1;
            end else begin
                for (j = 0; j < n; j = j + 1)
                    if (decoded[off2 + j] !== written[base + j]) begin
                        if (bad < 3) begin
                            $display("  FAIL [%0d] #%0d: wrote %h got %h",
                                     tag, j, written[base + j], decoded[off2 + j]);
                        end
                        bad = bad + 1;
                    end
                if (bad == 0)
                    $display("  OK   [%0d]: %0d samples match one by one (bit-perfect)", tag, n);
                else
                    errors = errors + 1;
            end
        end
    endtask

    always @(posedge BCLK_O) begin
        if (LRCLK_O !== lrclk_d) begin
            lrclk_d = LRCLK_O;
            shreg   = {24'b0, SDATA_O};
            bc      = 1;
            cap_en  = 1'b1;
        end else if (cap_en) begin
            shreg = {shreg[23:0], SDATA_O};
            bc    = bc + 1;
            if (bc == 25) begin
                decoded[ndec] = shreg[23:0];
                ndec = ndec + 1;
                cap_en = 1'b0;
            end
        end
    end

    initial begin
        s00_axi_aresetn = 0;
        repeat (10) @(posedge s_axi_aclk);
        s00_axi_aresetn = 1;
        repeat (10) @(posedge s_axi_aclk);

        axi_write(7'h00, 32'h0000_0002);
        axi_write(7'h08, (31 << 16) | 1);
        axi_write(7'h04, 32'h0000_0001);
        repeat (50) @(posedge s_axi_aclk);

        $display("[%0t] === IP-level integration check (PL330 mode + dsp_insert) ===", $time);
        $display("  waiting for i2s_tx to start...");

        feed(0, NSAMPLE);
        wait_out(written[NSAMPLE-1]);
        repeat (20000) @(posedge s_axi_aclk);
        q1 = ndec;

        $display("[%0t] === phase 2: DSP active (1 section unity gain) ===", $time);
        axi_write(7'h34, 32'h00000000);
        axi_write(7'h38, 32'h00008000);
        axi_write(7'h38, 32'h00000000);
        axi_write(7'h38, 32'h00000000);
        axi_write(7'h38, 32'h00000000);
        axi_write(7'h38, 32'h00000000);
        axi_write(7'h30, 32'h00000002);
        repeat (50) @(posedge s_axi_aclk);
        feed(NSAMPLE, NSAMPLE);
        wait_out(written[2*NSAMPLE-1]);
        repeat (20000) @(posedge s_axi_aclk);

        $display("[%0t] === phase 3: toggle TX_EN in DSP mode (reproduce aplay restart) ===", $time);
        axi_write(7'h04, 32'h0000_0000);
        repeat (20000) @(posedge s_axi_aclk);
        axi_write(7'h04, 32'h0000_0001);
        repeat (2000) @(posedge s_axi_aclk);
        q2 = ndec;
        feed(2*NSAMPLE, NSAMPLE);
        wait_out(written[3*NSAMPLE-1]);
        repeat (20000) @(posedge s_axi_aclk);

        $display("[%0t] === phase 4: two-section cascade (band0 x0.5 + band1 x2.0) ===", $time);
        axi_write(7'h34, 32'h00000000);
        axi_write(7'h38, 32'h00004000);
        axi_write(7'h38, 32'h00000000);
        axi_write(7'h38, 32'h00000000);
        axi_write(7'h38, 32'h00000000);
        axi_write(7'h38, 32'h00000000);
        axi_write(7'h38, 32'h00010000);
        axi_write(7'h38, 32'h00000000);
        axi_write(7'h38, 32'h00000000);
        axi_write(7'h38, 32'h00000000);
        axi_write(7'h38, 32'h00000000);
        axi_write(7'h30, 32'h00000004);
        repeat (50) @(posedge s_axi_aclk);
        q3 = ndec;
        feed(3*NSAMPLE, NSAMPLE);
        wait_out(written[4*NSAMPLE-1]);
        repeat (20000) @(posedge s_axi_aclk);

        $display("  each phase wrote %0d; decoded %0d slots total",
                 NSAMPLE, ndec);
        check(0,       NSAMPLE, 0,  0);
        check(NSAMPLE, NSAMPLE, q1, 1);
        check(2*NSAMPLE, NSAMPLE, q2, 2);
        check(3*NSAMPLE, NSAMPLE, q3, 3);

        if (errors == 0) $display("\n=== ALL TESTS PASSED ===");
        else             $display("\n=== %0d ERRORS ===", errors);
        $finish;
    end

    initial begin
        #60000000;
        $display("TIMEOUT scene: ndec=%0d nack=%0d nfeed=%0d dclk_axi=%0d/%0d bclk=%0d drvalid=%b fifo_stb=%b",
                 ndec, nack, nfeed, ndec, naxi, nbclk, tx_drvalid, dut.fifo_tx_stb);
        $finish;
    end
endmodule
