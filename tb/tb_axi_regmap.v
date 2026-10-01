// SPDX-License-Identifier: GPL-2.0-only


`timescale 1ns/1ps

module tb_axi_regmap;
    reg s_axi_aclk = 0;
    always #5 s_axi_aclk = ~s_axi_aclk;

    reg data_clk = 0;
    always #40.69 data_clk = ~data_clk;

    reg dma_aclk = 0;
    always #5 dma_aclk = ~dma_aclk;

    reg         aresetn = 0;

    reg  [6:0]  awaddr  = 0;
    reg  [2:0]  awprot  = 0;
    reg         awvalid = 0;
    wire        awready;
    reg  [31:0] wdata   = 0;
    reg  [3:0]  wstrb   = 4'hF;
    reg         wvalid  = 0;
    wire        wready;
    wire [1:0]  bresp;
    wire        bvalid;
    reg         bready  = 0;

    reg  [6:0]  araddr  = 0;
    reg  [2:0]  arprot  = 0;
    reg         arvalid = 0;
    wire        arready;
    wire [31:0] rdata;
    wire [1:0]  rresp;
    wire        rvalid;
    reg         rready  = 0;

    wire        BCLK_O, LRCLK_O, SDATA_O, MUTEN_O;
    wire        S_AXIS_TREADY, M_AXIS_TVALID, M_AXIS_TLAST;
    wire [31:0] M_AXIS_TDATA;
    wire [3:0]  M_AXIS_TKEEP;

    wire        tx_daready, tx_drvalid, tx_drlast;
    wire [1:0]  tx_drtype;
    wire        rx_daready, rx_drvalid, rx_drlast;
    wire [1:0]  rx_drtype;

    axi_i2s_adi_v1_2 #(
        .C_SLOT_WIDTH         (24),
        .C_S00_AXI_ADDR_WIDTH (7),
        .C_LRCLK_POL          (0),
        .C_BCLK_POL           (0),
        .C_DMA_TYPE           (1),
        .C_NUM_CH             (1),
        .C_HAS_TX             (1),
        .C_HAS_RX             (1)
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
        .DMA_REQ_TX_RSTN    (aresetn),
        .DMA_REQ_TX_DAVALID (1'b0),
        .DMA_REQ_TX_DATYPE  (2'b00),
        .DMA_REQ_TX_DAREADY (tx_daready),
        .DMA_REQ_TX_DRVALID (tx_drvalid),
        .DMA_REQ_TX_DRTYPE  (tx_drtype),
        .DMA_REQ_TX_DRLAST  (tx_drlast),
        .DMA_REQ_TX_DRREADY (1'b0),

        .DMA_REQ_RX_ACLK    (dma_aclk),
        .DMA_REQ_RX_RSTN    (aresetn),
        .DMA_REQ_RX_DAVALID (1'b0),
        .DMA_REQ_RX_DATYPE  (2'b00),
        .DMA_REQ_RX_DAREADY (rx_daready),
        .DMA_REQ_RX_DRVALID (rx_drvalid),
        .DMA_REQ_RX_DRTYPE  (rx_drtype),
        .DMA_REQ_RX_DRLAST  (rx_drlast),
        .DMA_REQ_RX_DRREADY (1'b0),

        .s00_axi_aclk       (s_axi_aclk),
        .s00_axi_aresetn    (aresetn),
        .s00_axi_awaddr     (awaddr),
        .s00_axi_awprot     (awprot),
        .s00_axi_awvalid    (awvalid),
        .s00_axi_awready    (awready),
        .s00_axi_wdata      (wdata),
        .s00_axi_wstrb      (wstrb),
        .s00_axi_wvalid     (wvalid),
        .s00_axi_wready     (wready),
        .s00_axi_bresp      (bresp),
        .s00_axi_bvalid     (bvalid),
        .s00_axi_bready     (bready),
        .s00_axi_araddr     (araddr),
        .s00_axi_arprot     (arprot),
        .s00_axi_arvalid    (arvalid),
        .s00_axi_arready    (arready),
        .s00_axi_rdata      (rdata),
        .s00_axi_rresp      (rresp),
        .s00_axi_rvalid     (rvalid),
        .s00_axi_rready     (rready)
    );

    integer idx;
    integer errors = 0;
    reg [31:0] rd_val;
    integer k;
    reg [31:0] show_idx;

    reg [31:0] exp [0:17];
    reg [6:0]  wr_list [0:9];
    reg [31:0] wv_list [0:9];

    initial begin
        for (k = 0; k < 18; k = k + 1) exp[k] = 32'hxxxx_xxxx;

        aresetn = 0;
        repeat (10) @(posedge s_axi_aclk);
        aresetn = 1;
        repeat (10) @(posedge s_axi_aclk);

        @(posedge s_axi_aclk);
        awaddr <= 7'h00; wdata <= 32'h2;       awvalid <= 1; wvalid <= 1; bready <= 1;
        @(posedge s_axi_aclk);
        while (!(awready && wready)) @(posedge s_axi_aclk);
        awvalid <= 0; wvalid <= 0;
        while (!bvalid) @(posedge s_axi_aclk);
        @(posedge s_axi_aclk); bready <= 0;

        @(posedge s_axi_aclk);
        awaddr <= 7'h08; wdata <= 32'h001F_0001; awvalid <= 1; wvalid <= 1; bready <= 1;
        @(posedge s_axi_aclk);
        while (!(awready && wready)) @(posedge s_axi_aclk);
        awvalid <= 0; wvalid <= 0;
        while (!bvalid) @(posedge s_axi_aclk);
        @(posedge s_axi_aclk); bready <= 0;

        @(posedge s_axi_aclk);
        awaddr <= 7'h04; wdata <= 32'h1;       awvalid <= 1; wvalid <= 1; bready <= 1;
        @(posedge s_axi_aclk);
        while (!(awready && wready)) @(posedge s_axi_aclk);
        awvalid <= 0; wvalid <= 0;
        while (!bvalid) @(posedge s_axi_aclk);
        @(posedge s_axi_aclk); bready <= 0;

        wr_list[0] = 7'h30; wv_list[0] = 32'h0000_0002;
        wr_list[1] = 7'h34; wv_list[1] = 32'h0000_0005;
        wr_list[2] = 7'h38; wv_list[2] = 32'h0001_0000;
        wr_list[3] = 7'h38; wv_list[3] = 32'hFFFF_6325;

        wr_list[4] = 7'h50; wv_list[4] = 32'hDEAD_BEEF;
        wr_list[5] = 7'h30; wv_list[5] = 32'h0000_0002;

        wr_list[6] = 7'h34; wv_list[6] = 32'h0000_0006;

        for (k = 0; k < 7; k = k + 1) begin
            @(posedge s_axi_aclk);
            awaddr <= wr_list[k]; wdata <= wv_list[k];
            awvalid <= 1; wvalid <= 1; bready <= 1;
            @(posedge s_axi_aclk);
            while (!(awready && wready)) @(posedge s_axi_aclk);
            awvalid <= 0; wvalid <= 0;
            while (!bvalid) @(posedge s_axi_aclk);
            @(posedge s_axi_aclk); bready <= 0;
        end

        exp[0] = 32'h0;
        exp[1] = 32'h1;
        exp[2] = 32'h001F_0001;
        exp[12] = 32'h2;
        exp[13] = 32'h6;
        exp[14] = 32'hFFFF_6325;
        exp[15] = 32'h0000_7333;
        exp[16] = 32'h0000_6666;
        exp[17] = 32'h0000_8010;

        $display("=== register-map self-check ===");
        for (idx = 0; idx < 18; idx = idx + 1) begin
            @(posedge s_axi_aclk);
            araddr <= idx[6:0] << 2; arvalid <= 1; rready <= 1;
            @(posedge s_axi_aclk);
            while (!arready) @(posedge s_axi_aclk);
            arvalid <= 0;
            while (!rvalid) @(posedge s_axi_aclk);
            rd_val = rdata;
            show_idx = idx;
            @(posedge s_axi_aclk);
            rready <= 0;

            if (exp[idx] !== 32'hxxxx_xxxx) begin
                if (rd_val !== exp[idx]) begin
                    $display("  FAIL w%h: expected %h, got %h", show_idx, exp[idx], rd_val);
                    errors = errors + 1;
                end else
                    $display("  OK   w%h = %h", show_idx, rd_val);
            end else if (rd_val !== 32'h0) begin
                $display("  ..   w%h = %h (nonzero)", show_idx, rd_val);
            end
        end

        if (errors == 0) $display("\n=== ALL TESTS PASSED ===");
        else             $display("\n=== %0d ERRORS ===", errors);
        $finish;
    end

    initial begin
        #2000000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
