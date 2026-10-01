// SPDX-License-Identifier: GPL-2.0-only


`default_nettype none

module dsp_engine #(
    parameter SAMPLE_W = 24,
    parameter COEF_W   = 18,
    parameter SHIFT    = 15,
    parameter NB       = 6,
    parameter NCH      = 2,
    parameter ACC_W    = 56,
    parameter AW       = 3,

    parameter NSLOT    = 24,
    parameter NSEC     = 48,
    parameter NCOEF    = 240,

    parameter HEADROOM = 3
) (
    input  wire                     clk,
    input  wire                     resetn,

    input  wire                     in_stb,
    input  wire [SAMPLE_W-1:0]      in_data,
    output wire                     in_ack,

    output wire                     out_stb,
    output wire [SAMPLE_W-1:0]      out_data,
    input  wire                     out_ack,

    input  wire                     dsp_bypass,
    input  wire [3:0]               nbands,
    input  wire [15:0]              cidx,
    input  wire                     cwr,
    input  wire [31:0]              cdat,
    output reg  [31:0]              cdat_rd,

    input  wire [15:0]              slot_addr,
    input  wire [31:0]              slot_data,
    input  wire                     slot_we,
    input  wire                     bank_sel,
    input  wire                     commit,
    output wire [31:0]              status,
    output wire [31:0]              cap0,
    output wire [31:0]              cap1,
    output wire [31:0]              cap2,
    output wire [31:0]              cap3,
    output wire [31:0]              cap4,

    input  wire                     lim_bypass,
    input  wire [17:0]              lim_thr,
    input  wire [17:0]              lim_att,
    input  wire [17:0]              lim_rel,

    input  wire                     lim_tp,

    input  wire                     headroom
);

    wire use_dsp = ~dsp_bypass;

    wire signed [SAMPLE_W:0]   in_round = $signed(in_data) + (1 <<< (HEADROOM-1));
    wire signed [SAMPLE_W-1:0] in_shr   = in_round >>> HEADROOM;

    assign in_ack = out_ack;

    localparam [4:0] NSLOT5 = NSLOT[4:0];
    wire [4:0] nb_eff = ({1'b0, nbands} > NSLOT5) ? NSLOT5 : {1'b0, nbands};

    localparam [7:0] OP_NOP    = 8'd0;

    localparam [7:0] OP_DYN    = 8'd2;
    localparam [7:0] OP_BIQUAD = 8'd1;

    localparam [7:0] OP_MIX2   = 8'd3;

    localparam [7:0] OP_DELAY  = 8'd4;
    localparam [7:0] OP_FIR    = 8'd5;

    localparam [7:0] OP_POLY   = 8'd6;
    localparam [7:0] OP_SAT    = 8'd8;

    localparam [7:0] OP_JDST   = 8'd9;
    localparam [7:0] OP_J3DS   = 8'd10;

    localparam SW_CFG  = 3'd0;
    localparam SW_CFB  = 3'd1;
    localparam SW_STB  = 3'd2;
    localparam SW_INA  = 3'd3;
    localparam SW_INB  = 3'd4;
    localparam SW_OUTB = 3'd5;
    localparam SW_PRM  = 3'd6;

    localparam FL_BYPASS = 8'h01;
    localparam FL_MUTE   = 8'h02;

    localparam FL_DLY_R  = 8'h04;

    localparam FL_L_ONLY = 8'h08;
    localparam FL_R_ONLY = 8'h10;

    localparam DLY_WORDS = 8192;
    localparam DLY_AB    = 13;
    localparam [DLY_AB:0] DLY_BASE_CH1 = DLY_WORDS;
    localparam [7:0] DLY_AB8 = DLY_AB;

    localparam [15:0] CAP_MAGIC = 16'h5A44;
    localparam [15:0] CAP_VER   = 16'd1;
    localparam [7:0]  NSLOT8    = NSLOT;

    assign cap0 = {CAP_MAGIC, CAP_VER};

    assign cap1 = 32'h0000_1F7B;

    localparam [7:0] FIR_LOG2 = 9;

    localparam [7:0] NSEC8  = NSEC;
    localparam [7:0] NCOEF8 = NCOEF;

    localparam [7:0] DLYSLOT8 = NSLOT;

    assign cap2 = {NSEC8, DLY_AB8, FIR_LOG2, NSLOT8};

    assign cap3 = {NCOEF8, DLYSLOT8, 8'd26, 8'd9};

    assign cap4 = 32'd0;

    localparam [15:0] CLR_MAX = 2*NCOEF + NCH*NSEC + NCH*DLY_WORDS;
    reg  [15:0] clr_i;
    reg         clr_busy;

    wire [15:0] clr_s = {13'd0, clr_i[5:3]};
    wire [2:0]  clr_w = clr_i[2:0];
    reg  [31:0] clr_wdata;
    always @* begin
        if (clr_s >= NB) clr_wdata = 32'd0;
        else case (clr_w)
            3'd0: clr_wdata = {8'd0, 8'd1, 8'd0, OP_BIQUAD};
            3'd1: clr_wdata = clr_s*5;
            3'd2: clr_wdata = clr_s;
            3'd3: clr_wdata = clr_s;
            3'd4: clr_wdata = 16'hFFFF;
            3'd5: clr_wdata = clr_s + 1;
            default: clr_wdata = 32'd0;
        endcase
    end

    localparam [15:0] COEF_FIR_BASE = 2 * NCOEF;

    localparam FIR_BLK_TAPS = 4096;
    localparam FIR_BLKS     = 2;
    localparam FIR_TAPS     = FIR_BLK_TAPS * FIR_BLKS;
    localparam [15:0] FIR_MACS = 16;

    localparam [15:0] COEF_SFIR_BASE = COEF_FIR_BASE + NCH*FIR_TAPS;

    wire        fir_cwr    = cwr && (cidx >= COEF_FIR_BASE) && (cidx < COEF_SFIR_BASE);
    wire [15:0] fir_caddr  = cidx - COEF_FIR_BASE;
    reg         fir_start;
    wire        fir_done;
    wire signed [SAMPLE_W-1:0] fir_y;

    fir_bank_long #(
        .SAMPLE_W(SAMPLE_W), .COEF_W(COEF_W), .SHIFT(SHIFT), .ACC_W(ACC_W),
        .BLK_TAPS(FIR_BLK_TAPS), .BLKS(FIR_BLKS), .MACS(FIR_MACS), .NCH(NCH)
    ) u_fir (
        .clk(clk), .resetn(resetn),
        .cwr(fir_cwr), .caddr(fir_caddr), .cdat(cdat[COEF_W-1:0]),

        .start(fir_start), .ch(~ch_par), .ntaps(FIR_MACS << sl_n_r),
        .x_in(s_in), .done(fir_done), .y_out(fir_y)
    );

    localparam NSLOTW  = NSLOT*8;
    localparam SW_HDR  = NSLOTW;
    localparam [15:0] BK_W16   = NSLOTW;
    localparam [15:0] NCOEF16  = NCOEF;
    (* ram_style = "distributed" *) reg [31:0] slot_t [0:2*NSLOTW-1];

    reg        active_bank;
    reg        commit_pend;

    reg  [15:0] hdr_bank [0:1];

    (* ram_style = "distributed" *) reg signed [COEF_W-1:0] coef [0:2*NCOEF-1];

    wire [15:0] tbl_act = active_bank ? BK_W16  : 16'd0;
    wire [15:0] tbl_wr  = bank_sel    ? BK_W16  : 16'd0;
    wire [15:0] cfb_act = active_bank ? NCOEF16 : 16'd0;
    wire [15:0] cfb_wr  = bank_sel    ? NCOEF16 : 16'd0;

    (* ram_style = "distributed" *) reg signed [SAMPLE_W-1:0] st_x1 [0:NCH*NSEC-1];
    (* ram_style = "distributed" *) reg signed [SAMPLE_W-1:0] st_x2 [0:NCH*NSEC-1];
    (* ram_style = "distributed" *) reg signed [SAMPLE_W-1:0] st_y1 [0:NCH*NSEC-1];
    (* ram_style = "distributed" *) reg signed [SAMPLE_W-1:0] st_y2 [0:NCH*NSEC-1];

    localparam [7:0] JS_STATE0 = NSEC - 2;

    localparam NBUS = 24;
    localparam [15:0] BUS_XF_LO = 16'd22;
    reg signed [SAMPLE_W-1:0] bus [0:NBUS-1];

    reg signed [SAMPLE_W-1:0] xf_lo [0:1];

    always @(posedge clk) begin
        if (!resetn) begin

            hdr_bank[0] <= 16'd0;
            hdr_bank[1] <= 16'd0;
        end else if (slot_we && (slot_addr == SW_HDR)) begin
            hdr_bank[bank_sel] <= slot_data[15:0];
        end
        if (slot_we && (slot_addr < NSLOTW))
            slot_t[tbl_wr + slot_addr] <= slot_data;
        else if (clr_busy && (clr_i < 2*NSLOTW))

            slot_t[clr_i] <= clr_wdata;
    end

    always @(posedge clk) begin
        if (cwr && (cidx < NCOEF))
            coef[cfb_wr + cidx] <= cdat[COEF_W-1:0];
        else if (clr_busy && (clr_i < 2*NCOEF))
            coef[clr_i] <= {COEF_W{1'b0}};

    end

    reg signed [COEF_W-1:0] coef_sel;

    always @* coef_sel = (cidx < NCOEF) ? coef[cfb_wr + cidx] : {COEF_W{1'b0}};
    always @* cdat_rd = {{(32-COEF_W){coef_sel[COEF_W-1]}}, coef_sel};

    wire start = use_dsp & out_ack & in_stb;
    reg  ch_par;

    wire signed [SAMPLE_W-1:0] xf_rd = xf_lo[ch_par];

    reg  [DLY_AB:0] dl_wr [0:1][0:NSLOT-1];
    reg  [DLY_AB:0] dl_len_r;
    reg  [DLY_AB:0] dl_a;

    wire signed [SAMPLE_W-1:0] dl_rd_r;

    reg                       dl_we;
    reg  [DLY_AB:0]           dl_wa;
    reg  signed [SAMPLE_W-1:0] dl_wd;

    xpm_memory_sdpram #(
        .ADDR_WIDTH_A(14), .ADDR_WIDTH_B(14),
        .AUTO_SLEEP_TIME(0),
        .BYTE_WRITE_WIDTH_A(SAMPLE_W),
        .CASCADE_HEIGHT(0),
        .CLOCKING_MODE("common_clock"),
        .ECC_MODE("no_ecc"),
        .IGNORE_INIT_SYNTH(0),
        .MEMORY_INIT_FILE("none"), .MEMORY_INIT_PARAM("0"),
        .MEMORY_OPTIMIZATION("true"),
        .MEMORY_PRIMITIVE("block"),
        .MEMORY_SIZE(NCH*DLY_WORDS*SAMPLE_W),
        .READ_DATA_WIDTH_B(SAMPLE_W), .READ_LATENCY_B(1),
        .READ_RESET_VALUE_B("0"), .RST_MODE_B("SYNC"),
        .SIM_ASSERT_CHK(0), .USE_EMBEDDED_CONSTRAINT(0),
        .USE_MEM_INIT(0), .USE_MEM_INIT_MMI(0),
        .WAKEUP_TIME("disable_sleep"),
        .WRITE_DATA_WIDTH_A(SAMPLE_W), .WRITE_MODE_B("read_first")
    ) u_dly_ring (
        .doutb(dl_rd_r), .dbiterrb(), .sbiterrb(),
        .addra(dl_wa[13:0]), .addrb(dl_a[13:0]),
        .clka(clk), .clkb(clk),
        .dina(dl_wd), .ena(dl_we), .enb(1'b1), .wea(dl_we),
        .injectdbiterra(1'b0), .injectsbiterra(1'b0),
        .regceb(1'b1), .rstb(1'b0), .sleep(1'b0)
    );
    wire [DLY_AB:0] dl_base = (~ch_par) ? DLY_BASE_CH1 : {DLY_AB+1{1'b0}};

    localparam [15:0] COMMIT_WAIT_MAX = 16'd8191;
    reg [15:0] commit_wait;
    always @(posedge clk) begin
        if (!resetn) begin
            active_bank <= 1'b0;
            commit_pend <= 1'b0;
            commit_wait <= 16'd0;
        end else if (!commit_pend) begin
            commit_wait <= 16'd0;
            if (commit) commit_pend <= 1'b1;
        end else if (start && (ch_par == 1'b0)) begin
            active_bank <= ~active_bank;
            commit_pend <= 1'b0;
            commit_wait <= 16'd0;
        end else if (commit_wait >= COMMIT_WAIT_MAX) begin
            active_bank <= ~active_bank;
            commit_pend <= 1'b0;
            commit_wait <= 16'd0;
        end else begin
            commit_wait <= commit_wait + 16'd1;
        end
    end

    localparam [3:0] S_IDLE = 4'd0,
                     S_SLOT = 4'd1,
                     S_DESC = 4'd2,
                     S_DISP = 4'd3,
                     S_FETCH= 4'd4,
                     S_MAC  = 4'd5,

                     S_FETCHN = 4'd15,
                     S_FIN  = 4'd6,
                     S_SAT  = 4'd7,
                     S_DYN  = 4'd9,
                     S_MIX  = 4'd10,
                     S_DELAY= 4'd11,
                     S_FIRW = 4'd13,
                     S_FIR  = 4'd12,
                     S_POLY = 4'd14,
                     S_DONE = 4'd8;

    localparam [4:0] S_JDST = 5'd16;
    localparam [4:0] S_J3DS = 5'd17;

    reg  [4:0]  state;
    reg  [15:0] slot_idx;
    reg  [15:0] sec;
    reg  [2:0]  mac;
    reg  [7:0]  sidx;
    reg  signed [SAMPLE_W-1:0] s_in;

    reg  signed [SAMPLE_W-1:0] sc_in;
    reg  signed [SAMPLE_W-1:0] env_r;
    reg  signed [COEF_W-1:0]   dyn_gmax, dyn_gmin, dyn_ref, dyn_ks;
    reg  [4:0]                 dyn_satt, dyn_srel;
    reg  signed [SAMPLE_W-1:0] dyn_d, dyn_env_n, dyn_gain;
    reg  signed [SAMPLE_W-1:0] cur_x1, cur_x2, cur_y1, cur_y2;    reg  signed [COEF_W-1:0]   c0, c1, c2, c3, c4;

    reg  signed [COEF_W-1:0]   c0p, c1p, c2p, c3p, c4p;
    reg  [15:0]                cfp_a;
    reg  signed [ACC_W-1:0]    acc_reg;
    reg                        dsp_v;
    reg  signed [SAMPLE_W-1:0] dsp_d;
    reg  overrun;

    reg  [7:0]  overrun_cnt;
    reg  [15:0] last_out;

    reg  [7:0]  nslot_run, nsec_run, nslot_last, nsec_last;
    integer fi;
    integer fj;

    reg  [15:0] tbl_a;
    reg  [15:0] cf_a;
    reg  [15:0] st_a;
    wire [31:0]                slot_rd = slot_t[tbl_a];

    wire [15:0]                cf_rd_a = (state == S_MAC) ? cfp_a : cf_a;
    wire signed [COEF_W-1:0]   coef_rd = coef[cf_rd_a];
    wire signed [SAMPLE_W-1:0] sx1_rd  = st_x1[st_a];
    wire signed [SAMPLE_W-1:0] sx2_rd  = st_x2[st_a];
    wire signed [SAMPLE_W-1:0] sy1_rd  = st_y1[st_a];
    wire signed [SAMPLE_W-1:0] sy2_rd  = st_y2[st_a];

    reg  [7:0]  sl_op_r, sl_fl_r, sl_n_r;
    reg  [15:0] sl_cfb_r, sl_stb_r, sl_ina_r, sl_inb_r, sl_out_r;

    wire [DLY_AB:0] dl_off = sl_stb_r[DLY_AB:0];

    wire [DLY_AB:0] dl_wr_cur = dl_wr[~ch_par][slot_idx[4:0]];
    reg  [2:0]  dcnt;
    reg  [2:0]  fcnt;
    reg  [15:0] cbase_r;
    reg  [15:0] st_r;

    reg  signed [COEF_W-1:0]   pc0,  pc1,  pc2,  pc3,  pc4,  pc5;
    reg  signed [COEF_W-1:0]   pc6,  pc7,  pc8,  pc9,  pc10, pc11;
    reg  signed [COEF_W-1:0]   pk_r;
    reg  signed [SAMPLE_W-1:0] pp_r;
    reg  signed [SAMPLE_W-1:0] py_r;
    reg  signed [SAMPLE_W-1:0] pm_r;
    reg  [4:0]  pcnt;
    reg         poly_c;

    wire [7:0]  hdr_n = hdr_bank[active_bank][7:0];
    wire        sf_en = hdr_bank[active_bank][8];
    wire [4:0]  jbus  = hdr_bank[active_bank][13:9];
    wire [15:0] nslot_eff = (hdr_n != 8'd0) ? {8'd0, hdr_n} : {11'd0, nb_eff};

    wire pass_l = ch_par;
    reg  signed [SAMPLE_W-1:0] jsl, jsr;
    reg  signed [SAMPLE_W-1:0] js_cap_l;
    reg                        js_cap_done;
    reg  signed [SAMPLE_W-1:0] js_out_l, js_out_r;
    reg  signed [SAMPLE_W-1:0] js_new_l, js_new_r;
    reg                        js_ran;
    reg  [4:0]                 jcnt;
    reg  signed [SAMPLE_W-1:0] js_a, js_b;
    reg  signed [SAMPLE_W-1:0] js_d0, js_d1;
    reg  signed [SAMPLE_W-1:0] js_p0, js_p1;

    reg  signed [SAMPLE_W-1:0] js_prev0, js_prev1;
    reg  signed [SAMPLE_W-1:0] js_ls, js_rs;
    reg  signed [SAMPLE_W-1:0] js_lmr, js_lpr;
    reg  signed [SAMPLE_W-1:0] js_x1, js_x2, js_y1, js_y2;
    reg  signed [SAMPLE_W-1:0] js_yy, js_dif, js_ee, js_ol, js_or;
    reg  signed [COEF_W-1:0]   js_g;
    reg  signed [COEF_W-1:0]   js_g1;
    reg  signed [COEF_W-1:0]   js_hb0, js_hb1, js_hb2, js_ha1, js_ha2;
    reg  signed [COEF_W-1:0]   js_ca, js_cb;
    reg  [DLY_AB:0]            js_len0, js_len1;

    reg  signed [SAMPLE_W-1:0] jad_a, jad_b;
    reg                        jad_sub;
    localparam signed [SAMPLE_W:0] JS_MAX =  (1 <<< (SAMPLE_W-1)) - 1;
    localparam signed [SAMPLE_W:0] JS_MIN = -(1 <<< (SAMPLE_W-1));

    wire signed [SAMPLE_W:0] jad_sum =
        {jad_a[SAMPLE_W-1], jad_a} +
        (jad_sub ? -{jad_b[SAMPLE_W-1], jad_b} : {jad_b[SAMPLE_W-1], jad_b});
    wire signed [SAMPLE_W-1:0] jad_sat =
        (jad_sum > JS_MAX) ? JS_MAX[SAMPLE_W-1:0] :
        (jad_sum < JS_MIN) ? JS_MIN[SAMPLE_W-1:0] : jad_sum[SAMPLE_W-1:0];

    wire [DLY_AB:0] js_a0  =                dl_off + dl_wr[1'b0][slot_idx[4:0]];
    wire [DLY_AB:0] js_ad1 = DLY_BASE_CH1 + dl_off + dl_wr[1'b1][slot_idx[4:0]];
    wire [DLY_AB:0] js_nx0 = (dl_wr[1'b0][slot_idx[4:0]] + 1'b1 >= js_len0)
                           ? {(DLY_AB+1){1'b0}} : (dl_wr[1'b0][slot_idx[4:0]] + 1'b1);
    wire [DLY_AB:0] js_nx1 = (dl_wr[1'b1][slot_idx[4:0]] + 1'b1 >= js_len1)
                           ? {(DLY_AB+1){1'b0}} : (dl_wr[1'b1][slot_idx[4:0]] + 1'b1);

    wire signed [SAMPLE_W-1:0] js_diff_w = js_lmr >>> 1;
    wire signed [SAMPLE_W-1:0] js_avg_w  = js_lpr >>> 1;
    wire is_joint = (sl_op_r == OP_JDST) || (sl_op_r == OP_J3DS);

    reg  signed [SAMPLE_W-1:0] m_a;
    reg  signed [COEF_W-1:0]   m_b;
    reg                        m_sub;
    wire signed [SAMPLE_W+COEF_W-1:0] m_p   = m_a * m_b;

    wire signed [ACC_W-1:0]    poly_cval = {{(ACC_W-COEF_W-23){pk_r[COEF_W-1]}}, pk_r, 23'd0};
    wire signed [ACC_W-1:0]    acc_base = poly_c ? poly_cval : acc_reg;
    wire signed [ACC_W-1:0]    acc_nxt = m_sub ? (acc_base - m_p) : (acc_base + m_p);
    wire signed [ACC_W-1:0]    acc_sh  = acc_reg >>> SHIFT;

    wire signed [SAMPLE_W-1:0] accn_red = acc_nxt[17+SAMPLE_W-1:17];

    wire signed [COEF_W-1:0]   x18 = s_in >>> 6;
    wire signed [SAMPLE_W-1:0] y_sat;

    saturator #(.IN_W(ACC_W), .OUT_W(SAMPLE_W)) u_sat (
        .in_sample (acc_sh),
        .out_sample(y_sat)
    );

    wire signed [SAMPLE_W-1:0] dyn_sc_sh  = sc_in >>> 8;
    wire signed [SAMPLE_W-1:0] dyn_sc_abs = dyn_sc_sh[SAMPLE_W-1] ? -dyn_sc_sh : dyn_sc_sh;

    wire signed [SAMPLE_W-1:0] dyn_env0  = env_r;
    wire signed [SAMPLE_W-1:0] dyn_d0    = dyn_sc_abs - dyn_env0;

    wire [4:0] dyn_satt_c = dyn_satt[4:0];
    wire [4:0] dyn_srel_c = dyn_srel[4:0];
    wire signed [SAMPLE_W-1:0] dyn_inc0  = (dyn_d0 >= 0) ? (dyn_d0 >>> dyn_satt_c)
                                                        : (dyn_d0 >>> dyn_srel_c);
    wire signed [SAMPLE_W-1:0] dyn_env0n = dyn_env0 + dyn_inc0;

    wire signed [ACC_W-1:0]    dyn_gtry    = $signed(dyn_gmax) - acc_sh;
    wire signed [COEF_W-1:0]   dyn_clamp_gain =
        (dyn_gtry > $signed(dyn_gmax)) ? dyn_gmax :
        (dyn_gtry < $signed(dyn_gmin)) ? dyn_gmin : dyn_gtry[COEF_W-1:0];

    wire [2:0] mac_n = mac + 3'd1;
    reg signed [SAMPLE_W-1:0] m_a_n;
    reg signed [COEF_W-1:0]   m_b_n;
    reg                       m_sub_n;
    always @* begin
        case (mac_n)
            3'd0: begin m_a_n = s_in;   m_b_n = c0; m_sub_n = 1'b0; end
            3'd1: begin m_a_n = cur_x1; m_b_n = c1; m_sub_n = 1'b0; end
            3'd2: begin m_a_n = cur_x2; m_b_n = c2; m_sub_n = 1'b0; end
            3'd3: begin m_a_n = cur_y1; m_b_n = c3; m_sub_n = 1'b1; end
            default: begin m_a_n = cur_y2; m_b_n = c4; m_sub_n = 1'b1; end
        endcase
    end

    always @(posedge clk) begin
        if (!resetn) begin
            state  <= S_IDLE;
            slot_idx <= 16'd0; sec <= 16'd0; mac <= 3'd0; sidx <= 8'd0;
            s_in <= 0; acc_reg <= 0; dsp_v <= 1'b0; dsp_d <= 0;
            m_a <= 0; m_b <= 0; m_sub <= 1'b0;
            fir_start <= 1'b0;
            c0 <= 0; c1 <= 0; c2 <= 0; c3 <= 0; c4 <= 0;
            c0p <= 0; c1p <= 0; c2p <= 0; c3p <= 0; c4p <= 0; cfp_a <= 0;
            cur_x1 <= 0; cur_x2 <= 0; cur_y1 <= 0; cur_y2 <= 0;
            ch_par <= 1'b0;
            overrun <= 1'b0;
            overrun_cnt <= 8'd0;
            last_out <= 16'd0;
            st_r <= 16'd0; cbase_r <= 16'd0;

            pc0 <= 0; pc1 <= 0; pc2 <= 0; pc3 <= 0; pc4 <= 0; pc5 <= 0;
            pc6 <= 0; pc7 <= 0; pc8 <= 0; pc9 <= 0; pc10 <= 0; pc11 <= 0;
            pk_r <= 0; pp_r <= 0; py_r <= 0; pm_r <= 0;
            pcnt <= 5'd0; poly_c <= 1'b0;

            jsl <= 0; jsr <= 0; js_cap_l <= 0; js_cap_done <= 1'b0;
            js_out_l <= 0; js_out_r <= 0; js_new_l <= 0; js_new_r <= 0;
            js_ran <= 1'b0; jcnt <= 5'd0;
            js_a <= 0; js_b <= 0; js_d0 <= 0; js_d1 <= 0; js_p0 <= 0; js_p1 <= 0;
            js_ls <= 0; js_rs <= 0; js_lmr <= 0; js_lpr <= 0;
            js_x1 <= 0; js_x2 <= 0; js_y1 <= 0; js_y2 <= 0;
            js_yy <= 0; js_dif <= 0; js_ee <= 0; js_ol <= 0; js_or <= 0;
            js_g <= 0; js_g1 <= 0; js_hb0 <= 0; js_hb1 <= 0; js_hb2 <= 0; js_ha1 <= 0; js_ha2 <= 0;
            js_ca <= 0; js_cb <= 0; js_len0 <= 0; js_len1 <= 0;
            js_prev0 <= 0; js_prev1 <= 0;
            jad_a <= 0; jad_b <= 0; jad_sub <= 1'b0;
            tbl_a <= 16'd0; cf_a <= 16'd0; st_a <= 16'd0;
            dcnt <= 3'd0; fcnt <= 3'd0;
            sl_op_r <= 8'd0; sl_fl_r <= 8'd0; sl_n_r <= 8'd0;
            sl_cfb_r <= 0; sl_stb_r <= 0; sl_ina_r <= 0; sl_inb_r <= 0; sl_out_r <= 0;
            nslot_run <= 8'd0; nsec_run <= 8'd0;
            nslot_last <= 8'd0; nsec_last <= 8'd0;
            clr_busy <= 1'b1;
            clr_i    <= 16'd0;
            for (fi = 0; fi < NBUS; fi = fi + 1)
                bus[fi] <= 0;
            xf_lo[0] <= 0; xf_lo[1] <= 0;
            for (fi = 0; fi < 2; fi = fi + 1)
                for (fj = 0; fj < NSLOT; fj = fj + 1)
                    dl_wr[fi][fj] <= 0;
            dl_a     <= 0;
        end else if (clr_busy) begin

            if (clr_i >= 2*NCOEF && clr_i < 2*NCOEF + NCH*NSEC) begin
                st_x1[clr_i - 2*NCOEF] <= {SAMPLE_W{1'b0}};
                st_x2[clr_i - 2*NCOEF] <= {SAMPLE_W{1'b0}};
                st_y1[clr_i - 2*NCOEF] <= {SAMPLE_W{1'b0}};
                st_y2[clr_i - 2*NCOEF] <= {SAMPLE_W{1'b0}};

                if (clr_i == 2*NCOEF + JS_STATE0) begin
                    js_prev0 <= {SAMPLE_W{1'b0}};
                    js_prev1 <= {SAMPLE_W{1'b0}};
                end
            end else if (clr_i >= 2*NCOEF + NCH*NSEC && clr_i < CLR_MAX) begin

                dl_we <= 1'b1;
                dl_wa <= clr_i - (2*NCOEF + NCH*NSEC);
                dl_wd <= {SAMPLE_W{1'b0}};
            end
            if (clr_i + 16'd1 >= CLR_MAX) clr_busy <= 1'b0;
            else                          clr_i    <= clr_i + 16'd1;
        end else begin
            dsp_v <= 1'b0;
            dl_we <= 1'b0;

            if (!use_dsp) begin
                nslot_last <= 8'd0;
                nsec_last  <= 8'd0;
            end
            if (start && state != S_IDLE) begin

                overrun <= 1'b1;
                if (overrun_cnt != 8'hFF) overrun_cnt <= overrun_cnt + 8'd1;
            end

            case (state)
                S_IDLE: begin
                    if (start) begin

                        bus[0]   <= headroom ? in_shr : in_data;

                        if (sf_en) bus[jbus] <= ch_par ? js_out_r : js_out_l;
                        sidx     <= ch_par ? NSEC : 8'd0;
                        last_out <= 16'd0;
                        nslot_run <= 8'd0;
                        nsec_run  <= 8'd0;
                        slot_idx <= 16'd0;
                        js_cap_done <= 1'b0;
                        js_ran      <= 1'b0;
                        ch_par   <= ~ch_par;
                        state    <= S_SLOT;
                    end
                end

                S_SLOT: begin
                    if (slot_idx >= nslot_eff) begin
                        state <= S_DONE;
                    end else begin
                        tbl_a <= tbl_act + {slot_idx, 3'b0};
                        dcnt  <= 3'd0;
                        state <= S_DESC;
                    end
                end

                S_DESC: begin
                    case (dcnt)
                        3'd0: begin
                            sl_op_r <= slot_rd[7:0];
                            sl_fl_r <= slot_rd[15:8];
                            sl_n_r  <= slot_rd[23:16];
                        end
                        3'd1: sl_cfb_r <= slot_rd[15:0];
                        3'd2: sl_stb_r <= slot_rd[15:0];
                        3'd3: sl_ina_r <= slot_rd[15:0];
                        3'd4: sl_inb_r <= slot_rd[15:0];
                        default: sl_out_r <= slot_rd[15:0];
                    endcase
                    if (dcnt == 3'd5) begin
                        state <= S_DISP;
                    end else begin
                        tbl_a <= tbl_a + 16'd1;
                        dcnt  <= dcnt + 3'd1;
                    end
                end

                S_DISP: begin
                    if (((sl_fl_r & FL_BYPASS) != 8'd0) || (sl_n_r == 8'd0) ||

                        (((sl_fl_r & FL_L_ONLY) != 8'd0) && !pass_l) ||
                        (((sl_fl_r & FL_R_ONLY) != 8'd0) &&  pass_l)) begin

                        bus[sl_out_r] <= bus[sl_ina_r];
                        last_out      <= sl_out_r;
                        slot_idx      <= slot_idx + 16'd1;
                        state         <= S_SLOT;
                    end else if (sf_en && is_joint && pass_l) begin

                        if (!js_cap_done) begin
                            js_cap_l    <= bus[sl_inb_r[4:0]];
                            js_cap_done <= 1'b1;
                        end
                        last_out <= {11'd0, jbus};
                        slot_idx <= slot_idx + 16'd1;
                        state    <= S_SLOT;
                    end else if (sf_en && (sl_op_r == OP_JDST)) begin
                        nslot_run <= nslot_run + 8'd1;
                        js_ran    <= 1'b1;
                        jsl       <= js_cap_l;
                        jsr       <= bus[sl_inb_r[4:0]];
                        st_r      <= {8'd0, JS_STATE0};

                        st_a      <= {8'd0, JS_STATE0} + 16'd1;
                        cf_a      <= cfb_act + sl_cfb_r;
                        dl_a      <= js_a0;
                        jad_a     <= 0; jad_b <= 0; jad_sub <= 1'b0;
                        jcnt      <= 5'd0;
                        state     <= S_JDST;
                    end else if (sf_en && (sl_op_r == OP_J3DS)) begin
                        nslot_run <= nslot_run + 8'd1;
                        js_ran    <= 1'b1;
                        jsl       <= bus[sl_ina_r[4:0]];
                        jsr       <= bus[sl_inb_r[4:0]];
                        cf_a      <= cfb_act + sl_cfb_r;
                        jcnt      <= 5'd0;
                        state     <= S_J3DS;
                    end else if (sl_op_r == OP_BIQUAD) begin
                        nslot_run <= nslot_run + 8'd1;
                        s_in      <= (sl_ina_r == BUS_XF_LO) ? xf_rd : bus[sl_ina_r[4:0]];
                        sec       <= 16'd0;
                        cbase_r   <= sl_cfb_r;
                        st_r      <= {8'd0, sidx} + sl_stb_r;
                        fcnt      <= 3'd0;
                        cf_a      <= cfb_act + sl_cfb_r;
                        state     <= S_FETCH;
                    end else if (sl_op_r == OP_DYN) begin
                        nslot_run <= nslot_run + 8'd1;
                        s_in   <= (sl_ina_r == BUS_XF_LO) ? xf_rd : bus[sl_ina_r[4:0]];
                        sc_in  <= (sl_inb_r == BUS_XF_LO) ? xf_rd : bus[sl_inb_r[4:0]];
                        st_r   <= {8'd0, sidx} + sl_stb_r;

                        cbase_r <= sl_cfb_r;
                        fcnt   <= 3'd0;
                        cf_a   <= cfb_act + sl_cfb_r;
                        st_a   <= {8'd0, sidx} + sl_stb_r;
                        state  <= S_FETCH;
                    end else if (sl_op_r == OP_FIR) begin

                        nslot_run <= nslot_run + 8'd1;
                        s_in      <= (sl_ina_r == BUS_XF_LO) ? xf_rd : bus[sl_ina_r[4:0]];
                        state     <= S_FIRW;
                    end else if (sl_op_r == OP_DELAY) begin

                        if (((sl_fl_r & FL_DLY_R) != 8'd0) && (ch_par == 1'b1)) begin
                            bus[sl_out_r] <= (sl_ina_r == BUS_XF_LO) ? xf_rd : bus[sl_ina_r[4:0]];
                            last_out      <= sl_out_r;
                            slot_idx      <= slot_idx + 16'd1;
                            state         <= S_SLOT;
                        end else begin
                            nslot_run <= nslot_run + 8'd1;
                            s_in   <= (sl_ina_r == BUS_XF_LO) ? xf_rd : bus[sl_ina_r[4:0]];
                            cbase_r <= sl_cfb_r;
                            fcnt   <= 3'd0;
                            cf_a   <= cfb_act + sl_cfb_r;

                            dl_a   <= dl_base + dl_off + dl_wr_cur;
                            mac    <= 3'd0;
                            state  <= S_FETCH;
                        end
                    end else if (sl_op_r == OP_MIX2) begin
                        nslot_run <= nslot_run + 8'd1;
                        s_in   <= (sl_ina_r == BUS_XF_LO) ? xf_rd : bus[sl_ina_r[4:0]];
                        sc_in  <= (sl_inb_r == BUS_XF_LO) ? xf_rd : bus[sl_inb_r[4:0]];
                        cbase_r <= sl_cfb_r;
                        fcnt   <= 3'd0;
                        cf_a   <= cfb_act + sl_cfb_r;
                        state  <= S_FETCH;
                    end else if (sl_op_r == OP_POLY) begin
                        nslot_run <= nslot_run + 8'd1;
                        s_in      <= (sl_ina_r == BUS_XF_LO) ? xf_rd : bus[sl_ina_r[4:0]];
                        st_r      <= {8'd0, sidx} + sl_stb_r;

                        cf_a      <= cfb_act + sl_cfb_r;
                        st_a      <= {8'd0, sidx} + sl_stb_r;
                        pcnt      <= 5'd0;
                        poly_c    <= 1'b0;
                        state     <= S_POLY;
                    end else if (sl_op_r == OP_SAT) begin
                        nslot_run <= nslot_run + 8'd1;
                        s_in      <= bus[sl_ina_r];
                        st_r      <= {8'd0, sidx} + sl_stb_r;

                        st_a      <= {8'd0, sidx} + sl_stb_r;
                        state     <= S_SAT;
                    end else begin
                        slot_idx <= slot_idx + 16'd1;
                        state    <= S_SLOT;
                    end
                end

                S_FETCH: begin
                    case (fcnt)
                        3'd0: c0 <= coef_rd;
                        3'd1: c1 <= coef_rd;
                        3'd2: c2 <= coef_rd;
                        3'd3: c3 <= coef_rd;
                        3'd4: c4 <= coef_rd;
                        default: begin
                            if (st_r >= NCH*NSEC) begin
                                cur_x1 <= 0; cur_x2 <= 0; cur_y1 <= 0; cur_y2 <= 0;
                            end else begin
                                cur_x1 <= sx1_rd; cur_x2 <= sx2_rd;
                                cur_y1 <= sy1_rd; cur_y2 <= sy2_rd;
                            end
                            m_a     <= s_in;
                            m_b     <= c0;
                            m_sub   <= 1'b0;
                            acc_reg <= 0;
                            mac     <= 3'd0;
                        end
                    endcase
                    if (fcnt == 3'd5) begin
                        if (sl_op_r == OP_DELAY) begin

                            dl_len_r <= (c0[COEF_W-1:DLY_AB] != 0 || c0[DLY_AB:0] == 0)
                                        ? DLY_WORDS[DLY_AB:0] : c0[DLY_AB:0];

                            mac   <= 3'd0;
                            state <= S_DELAY;
                        end else if (sl_op_r == OP_MIX2) begin

                            m_a     <= s_in;
                            m_b     <= c0;
                            m_sub   <= 1'b0;
                            acc_reg <= 0;
                            mac     <= 3'd0;
                            state   <= S_MIX;
                        end else if (sl_op_r == OP_DYN) begin

                            env_r     <= (st_r >= NCH*NSEC) ? 24'sd0 : sx1_rd;
                            dyn_gmax  <= c0;
                            dyn_gmin  <= c1;
                            dyn_ref   <= c2;
                            dyn_ks    <= c3;
                            dyn_satt  <= c4[4:0];
                            dyn_srel  <= c4[9:5];

                            m_a       <= 24'sd0;
                            m_b       <= {COEF_W{1'b0}};
                            m_sub     <= 1'b0;
                            acc_reg   <= 0;
                            mac       <= 3'd0;
                            state     <= S_DYN;
                        end else begin

                            cfp_a <= cfb_act + cbase_r + 16'd5;
                            state <= S_MAC;
                        end
                    end else if (fcnt == 3'd4) begin
                        st_a <= st_r;
                        fcnt <= fcnt + 3'd1;
                    end else begin
                        cf_a <= cfb_act + cbase_r + {13'd0, fcnt} + 16'd1;
                        fcnt <= fcnt + 3'd1;
                    end
                end

                S_FETCHN: begin
                    if (st_r >= NCH*NSEC) begin
                        cur_x1 <= 0; cur_x2 <= 0; cur_y1 <= 0; cur_y2 <= 0;
                    end else begin
                        cur_x1 <= sx1_rd; cur_x2 <= sx2_rd;
                        cur_y1 <= sy1_rd; cur_y2 <= sy2_rd;
                    end
                    m_a     <= s_in;
                    m_b     <= c0;
                    m_sub   <= 1'b0;
                    acc_reg <= 0;
                    mac     <= 3'd0;
                    state   <= S_MAC;
                end

                S_MAC: begin

                    case (mac)
                        3'd0: c0p <= coef_rd;
                        3'd1: c1p <= coef_rd;
                        3'd2: c2p <= coef_rd;
                        3'd3: c3p <= coef_rd;
                        default: c4p <= coef_rd;
                    endcase
                    cfp_a <= cfp_a + 16'd1;
                    acc_reg <= acc_nxt;
                    if (mac == 3'd4) begin
                        state <= S_FIN;
                    end else begin
                        mac   <= mac + 3'd1;
                        m_a   <= m_a_n;
                        m_b   <= m_b_n;
                        m_sub <= m_sub_n;
                    end
                end

                S_FIN: begin

                    if (st_r < NCH*NSEC) begin
                        st_x1[st_r] <= s_in;
                        st_x2[st_r] <= cur_x1;
                        st_y1[st_r] <= y_sat;
                        st_y2[st_r] <= cur_y1;
                    end
                    nsec_run <= nsec_run + 8'd1;
                    if ({8'd0, sec} + 16'd1 >= {8'd0, sl_n_r}) begin
                        bus[sl_out_r] <= y_sat;
                        last_out      <= sl_out_r;
                        slot_idx      <= slot_idx + 16'd1;
                        state         <= S_SLOT;
                    end else begin
                        s_in    <= y_sat;
                        sec     <= sec + 16'd1;
                        cbase_r <= cbase_r + 16'd5;
                        st_r    <= st_r + 16'd1;

                        c0 <= c0p; c1 <= c1p; c2 <= c2p; c3 <= c3p; c4 <= c4p;
                        st_a  <= st_r + 16'd1;
                        cfp_a <= cfb_act + cbase_r + 16'd10;
                        fcnt  <= 3'd0;
                        cf_a  <= cfb_act + cbase_r + 16'd5;
                        state <= S_FETCHN;
                    end
                end

                S_DELAY: begin

                    bus[sl_out_r]  <= dl_rd_r;
                    last_out       <= sl_out_r;
                    dl_we          <= 1'b1;
                    dl_wa          <= dl_a;
                    dl_wd          <= s_in;
                    dl_wr[~ch_par][slot_idx[4:0]] <= (dl_wr_cur + 1 >= dl_len_r) ? 0 : dl_wr_cur + 1;
                    slot_idx       <= slot_idx + 16'd1;
                    state          <= S_SLOT;
                end

                S_FIRW: begin
                    fir_start  <= 1'b1;
                    state      <= S_FIR;
                end

                S_FIR: begin
                    fir_start  <= 1'b0;
                    if (fir_done) begin
                        bus[sl_out_r] <= fir_y;
                        last_out      <= sl_out_r;
                        slot_idx      <= slot_idx + 16'd1;
                        state         <= S_SLOT;

                    end
                end

                S_MIX: begin
                    case (mac)
                        3'd0: begin
                            acc_reg <= acc_nxt;
                            m_a     <= sc_in;
                            m_b     <= c1;
                            m_sub   <= 1'b0;
                            mac     <= 3'd1;
                        end
                        3'd1: begin
                            acc_reg <= acc_nxt;
                            mac     <= 3'd2;
                        end
                        default: begin
                            bus[sl_out_r] <= y_sat;
                            last_out      <= sl_out_r;
                            slot_idx      <= slot_idx + 16'd1;
                            state         <= S_SLOT;
                        end
                    endcase
                end

                S_DYN: begin
                    case (mac)
                        3'd0: begin
                            dyn_env_n <= dyn_env0n;
                            m_a       <= dyn_env0 - dyn_ref;
                            m_b       <= dyn_ks;
                            m_sub     <= 1'b0;
                            acc_reg   <= 0;
                            mac       <= 3'd1;
                        end
                        3'd1: begin
                            acc_reg <= acc_nxt;
                            mac     <= 3'd2;
                        end
                        3'd2: begin
                            dyn_gain <= dyn_clamp_gain;
                            m_a      <= s_in;
                            m_b      <= dyn_clamp_gain;
                            m_sub    <= 1'b0;
                            acc_reg  <= 0;
                            mac      <= 3'd3;
                        end
                        3'd3: begin
                            acc_reg <= acc_nxt;
                            mac     <= 3'd4;
                        end
                        default: begin
                            if (st_r < NCH*NSEC) begin
                                st_x1[st_r] <= dyn_env_n;
                            end
                            nsec_run      <= nsec_run + 8'd1;
                            bus[sl_out_r] <= y_sat;
                            last_out      <= sl_out_r;
                            slot_idx      <= slot_idx + 16'd1;
                            state         <= S_SLOT;
                        end
                    endcase
                end

                S_POLY: begin
                    case (pcnt)
                        5'd0: begin
                            pc0  <= coef_rd;
                            pp_r <= sx2_rd;
                            py_r <= sx1_rd;
                            pm_r <= sy1_rd;
                            cf_a <= cf_a + 16'd1;
                            pcnt <= 5'd1;
                        end
                        5'd1:  begin pc1  <= coef_rd; cf_a <= cf_a + 16'd1; pcnt <= 5'd2;  end
                        5'd2:  begin pc2  <= coef_rd; cf_a <= cf_a + 16'd1; pcnt <= 5'd3;  end
                        5'd3:  begin pc3  <= coef_rd; cf_a <= cf_a + 16'd1; pcnt <= 5'd4;  end
                        5'd4:  begin pc4  <= coef_rd; cf_a <= cf_a + 16'd1; pcnt <= 5'd5;  end
                        5'd5:  begin pc5  <= coef_rd; cf_a <= cf_a + 16'd1; pcnt <= 5'd6;  end
                        5'd6:  begin pc6  <= coef_rd; cf_a <= cf_a + 16'd1; pcnt <= 5'd7;  end
                        5'd7:  begin pc7  <= coef_rd; cf_a <= cf_a + 16'd1; pcnt <= 5'd8;  end
                        5'd8:  begin pc8  <= coef_rd; cf_a <= cf_a + 16'd1; pcnt <= 5'd9;  end
                        5'd9:  begin pc9  <= coef_rd; cf_a <= cf_a + 16'd1; pcnt <= 5'd10; end
                        5'd10: begin pc10 <= coef_rd; cf_a <= cf_a + 16'd1; pcnt <= 5'd11; end
                        5'd11: begin
                            pc11  <= coef_rd;
                            m_a   <= 24'sd0;
                            m_b   <= 18'sd0;
                            m_sub <= 1'b0;
                            poly_c <= 1'b1;

                            pk_r  <= pc10;
                            pcnt  <= 5'd12;
                        end

                        5'd12: begin
                            acc_reg <= acc_nxt;
                            pk_r <= pc9;
                            m_a  <= accn_red;
                            m_b  <= x18;
                            m_sub <= 1'b0;
                            pcnt <= 5'd13;
                        end
                        5'd13: begin acc_reg <= acc_nxt; pk_r <= pc8; m_a <= accn_red; m_b <= x18; pcnt <= 5'd14; end
                        5'd14: begin acc_reg <= acc_nxt; pk_r <= pc7; m_a <= accn_red; m_b <= x18; pcnt <= 5'd15; end
                        5'd15: begin acc_reg <= acc_nxt; pk_r <= pc6; m_a <= accn_red; m_b <= x18; pcnt <= 5'd16; end
                        5'd16: begin acc_reg <= acc_nxt; pk_r <= pc5; m_a <= accn_red; m_b <= x18; pcnt <= 5'd17; end
                        5'd17: begin acc_reg <= acc_nxt; pk_r <= pc4; m_a <= accn_red; m_b <= x18; pcnt <= 5'd18; end
                        5'd18: begin acc_reg <= acc_nxt; pk_r <= pc3; m_a <= accn_red; m_b <= x18; pcnt <= 5'd19; end
                        5'd19: begin acc_reg <= acc_nxt; pk_r <= pc2; m_a <= accn_red; m_b <= x18; pcnt <= 5'd20; end
                        5'd20: begin acc_reg <= acc_nxt; pk_r <= pc1; m_a <= accn_red; m_b <= x18; pcnt <= 5'd21; end
                        5'd21: begin acc_reg <= acc_nxt; pk_r <= pc0; m_a <= accn_red; m_b <= x18; pcnt <= 5'd22; end
                        5'd22: begin
                            acc_reg <= acc_nxt;

                            m_a   <= pp_r;
                            m_b   <= 18'sd32768;
                            m_sub <= 1'b1;
                            poly_c <= 1'b0;
                            pcnt  <= 5'd23;
                        end
                        5'd23: begin

                            acc_reg <= acc_nxt;
                            if (st_r < NCH*NSEC) st_x2[st_r] <= y_sat;
                            m_a   <= py_r;
                            m_b   <= 18'sd32735;
                            m_sub <= 1'b0;
                            pcnt  <= 5'd24;
                        end
                        5'd24: begin
                            acc_reg <= acc_nxt;
                            pcnt <= 5'd25;
                        end
                        default: begin
                            if (st_r < NCH*NSEC) st_x1[st_r] <= y_sat;
                            if ($signed(pm_r) < $signed({6'd0, pc11})) begin

                                bus[sl_out_r] <= 24'sd0;
                                if (st_r < NCH*NSEC) st_y1[st_r] <= pm_r + 24'd1;
                            end else begin
                                bus[sl_out_r] <= y_sat;
                            end
                            last_out <= sl_out_r;
                            slot_idx <= slot_idx + 16'd1;
                            state    <= S_SLOT;
                        end
                    endcase
                end

                S_JDST: begin

                    case (jcnt)
                        5'd0: begin
                            js_g    <= coef_rd;
                            js_p0   <= js_prev0; js_p1 <= js_prev1;
                            st_a    <= st_r + 16'd1;
                            cf_a    <= cf_a + 16'd1;

                            dl_a    <= js_ad1;
                            jad_a   <= jsl;

                            jad_b   <= js_prev1;
                            jad_sub <= 1'b0;
                            jcnt    <= 5'd1;
                        end
                        5'd1: begin
                            js_a    <= jad_sat;
                            js_g1   <= coef_rd;
                            cf_a    <= cf_a + 16'd1;
                            js_d0   <= dl_rd_r;
                            js_x1   <= sy1_rd; js_x2 <= sy2_rd;
                            js_y1   <= sx1_rd; js_y2 <= sx2_rd;
                            jcnt    <= 5'd2;
                        end
                        5'd2: begin
                            js_len0 <= coef_rd;
                            cf_a    <= cf_a + 16'd1;
                            js_d1   <= dl_rd_r;
                            m_a     <= js_d0;
                            m_b     <= js_g;
                            m_sub   <= 1'b0;
                            acc_reg <= 0;
                            jcnt    <= 5'd3;
                        end
                        5'd3: begin
                            js_len1 <= coef_rd;
                            cf_a    <= cf_a + 16'd1;
                            acc_reg <= acc_nxt;

                            dl_we   <= 1'b1;
                            dl_wa   <= js_a0;
                            dl_wd   <= js_a;
                            dl_wr[1'b0][slot_idx[4:0]] <= js_nx0;
                            jcnt    <= 5'd4;
                        end
                        5'd4: begin
                            js_p0   <= y_sat;
                            js_hb0  <= coef_rd;
                            cf_a    <= cf_a + 16'd1;
                            m_a     <= js_d1;
                            m_b     <= js_g1;
                            m_sub   <= 1'b0;
                            acc_reg <= 0;
                            jad_a   <= jsr;
                            jad_b   <= y_sat;
                            jad_sub <= 1'b0;
                            jcnt    <= 5'd5;
                        end
                        5'd5: begin
                            js_b    <= jad_sat;
                            js_hb1  <= coef_rd;
                            cf_a    <= cf_a + 16'd1;
                            acc_reg <= acc_nxt;
                            jad_a   <= jsl;
                            jad_b   <= js_p0;
                            jad_sub <= 1'b0;
                            jcnt    <= 5'd6;
                        end
                        5'd6: begin
                            js_ls   <= jad_sat;
                            js_p1   <= y_sat;
                            js_hb2  <= coef_rd;
                            cf_a    <= cf_a + 16'd1;

                            dl_we   <= 1'b1;
                            dl_wa   <= js_ad1;
                            dl_wd   <= js_b;
                            dl_wr[1'b1][slot_idx[4:0]] <= js_nx1;
                            jad_a   <= jsr;
                            jad_b   <= y_sat;
                            jad_sub <= 1'b0;
                            jcnt    <= 5'd7;
                        end
                        5'd7: begin
                            js_rs   <= jad_sat;
                            js_ha1  <= coef_rd;
                            cf_a    <= cf_a + 16'd1;
                            jad_a   <= js_ls;

                            jad_b   <= jad_sat;
                            jad_sub <= 1'b1;
                            jcnt    <= 5'd8;
                        end
                        5'd8: begin
                            js_lmr  <= jad_sat;
                            js_ha2  <= coef_rd;
                            cf_a    <= cf_a + 16'd1;
                            jad_a   <= js_ls;
                            jad_b   <= js_rs;
                            jad_sub <= 1'b0;
                            jcnt    <= 5'd9;
                        end
                        5'd9: begin
                            js_lpr  <= jad_sat;
                            m_a     <= js_lmr >>> 1;
                            m_b     <= js_hb0;
                            m_sub   <= 1'b0;
                            acc_reg <= 0;
                            jcnt    <= 5'd10;
                        end
                        5'd10: begin acc_reg <= acc_nxt; m_a <= js_x1; m_b <= js_hb1; jcnt <= 5'd11; end
                        5'd11: begin acc_reg <= acc_nxt; m_a <= js_x2; m_b <= js_hb2; jcnt <= 5'd12; end
                        5'd12: begin acc_reg <= acc_nxt; m_a <= js_y1; m_b <= js_ha1; jcnt <= 5'd13; end
                        5'd13: begin acc_reg <= acc_nxt; m_a <= js_y2; m_b <= js_ha2; jcnt <= 5'd14; end
                        5'd14: begin
                            acc_reg <= acc_nxt;
                            jcnt    <= 5'd15;
                        end
                        5'd15: begin
                            js_yy   <= y_sat;
                            js_dif  <= js_lmr >>> 1;
                            jad_a   <= js_lmr >>> 1;
                            jad_b   <= y_sat;
                            jad_sub <= 1'b1;
                            jcnt    <= 5'd16;
                        end
                        5'd16: begin
                            js_ee   <= jad_sat;
                            jad_a   <= js_lpr >>> 1;
                            jad_b   <= jad_sat;
                            jad_sub <= 1'b0;
                            jcnt    <= 5'd17;
                        end
                        5'd17: begin
                            js_ol   <= jad_sat;
                            jad_a   <= js_lpr >>> 1;
                            jad_b   <= js_ee;
                            jad_sub <= 1'b1;
                            jcnt    <= 5'd18;
                        end
                        default: begin
                            js_or   <= jad_sat;

                            if (st_r + 16'd1 < NCH*NSEC) begin
                                st_x1[st_r+16'd1]  <= js_yy;
                                st_x2[st_r+16'd1]  <= js_y1;
                                st_y1[st_r+16'd1]  <= js_dif;
                                st_y2[st_r+16'd1]  <= js_x1;
                            end
                            js_prev0 <= js_p0;
                            js_prev1 <= js_p1;

                            js_new_l <= js_ol;
                            js_new_r <= jad_sat;
                            if (sl_ina_r != 16'hFFFF) bus[sl_ina_r[4:0]] <= js_ol;
                            if (sl_out_r != 16'hFFFF) bus[sl_out_r[4:0]] <= jad_sat;
                            last_out <= {11'd0, jbus};
                            slot_idx <= slot_idx + 16'd1;
                            state    <= S_SLOT;
                        end
                    endcase
                end

                S_J3DS: begin

                    case (jcnt)
                        5'd0: begin
                            js_ca   <= coef_rd;
                            cf_a    <= cf_a + 16'd1;
                            m_a     <= jsl;
                            m_b     <= coef_rd;
                            m_sub   <= 1'b0;
                            acc_reg <= 0;
                            jcnt    <= 5'd1;
                        end
                        5'd1: begin
                            js_cb   <= coef_rd;
                            cf_a    <= cf_a + 16'd1;
                            acc_reg <= acc_nxt;
                            m_a     <= jsr;
                            m_b     <= coef_rd;
                            jcnt    <= 5'd2;
                        end
                        5'd2: begin
                            acc_reg <= acc_nxt;
                            jcnt    <= 5'd3;
                        end
                        5'd3: begin
                            js_ol   <= y_sat;
                            acc_reg <= 0;
                            m_a     <= jsl;
                            m_b     <= js_cb;
                            jcnt    <= 5'd4;
                        end
                        5'd4: begin
                            acc_reg <= acc_nxt;
                            m_a     <= jsr;
                            m_b     <= js_ca;
                            jcnt    <= 5'd5;
                        end
                        5'd5: begin
                            acc_reg <= acc_nxt;
                            jcnt    <= 5'd6;
                        end
                        default: begin
                            js_or    <= y_sat;
                            js_new_l <= js_ol;
                            js_new_r <= y_sat;

                            if (sl_out_r != 16'hFFFF) bus[sl_out_r[4:0]] <= y_sat;
                            last_out <= {11'd0, jbus};
                            slot_idx <= slot_idx + 16'd1;
                            state    <= S_SLOT;
                        end
                    endcase
                end

                S_SAT: begin
                    nslot_run <= nslot_run + 8'd1;
                    if ((s_in == 24'sh7FFFFF) || (s_in == 24'sh800000))
                        st_x1[st_r] <= sx1_rd + 24'd1;
                    bus[sl_out_r] <= s_in;
                    last_out      <= sl_out_r;
                    slot_idx      <= slot_idx + 16'd1;
                    state         <= S_SLOT;
                end

                S_DONE: begin

                    xf_lo[~ch_par] <= bus[BUS_XF_LO[4:0]];

                    if (js_ran) begin
                        js_out_l <= js_new_l;
                        js_out_r <= js_new_r;
                    end
                    dsp_d      <= bus[last_out];
                    dsp_v      <= 1'b1;
                    nslot_last <= nslot_run;
                    nsec_last  <= nsec_run;
                    state      <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    wire                    lim_valid;
    wire [SAMPLE_W-1:0]     lim_data;
    wire                    dsp_v_en = dsp_v & use_dsp;

    limiter #(
        .SAMPLE_W (SAMPLE_W),
        .PARAM_W  (18),
        .SHIFT    (SHIFT)
    ) u_lim (
        .clk          (clk),
        .resetn       (resetn),
        .sample_valid (dsp_v_en),
        .sample_in    (dsp_d),
        .thr          (lim_thr),
        .k_att        (lim_att),
        .k_rel        (lim_rel),
        .bypass       (lim_bypass),
        .out_valid    (lim_valid),
        .sample_out   (lim_data)
    );

    wire                    tp_valid;
    wire [SAMPLE_W-1:0]     tp_data;

    truepeak_limiter #(
        .SAMPLE_W (SAMPLE_W),
        .SHIFT    (SHIFT),
        .LOOK     (96)
    ) u_tp (
        .clk          (clk),
        .resetn       (resetn),
        .sample_valid (dsp_v_en),
        .sample_in    (dsp_d),
        .thr          (lim_thr),
        .k_att        (lim_att),
        .k_rel        (lim_rel),
        .bypass       (lim_bypass),
        .out_valid    (tp_valid),
        .sample_out   (tp_data),
        .gain_lg      (),
        .overrun      ()
    );

    wire                    lim_valid_sel = lim_tp ? tp_valid : lim_valid;
    wire [SAMPLE_W-1:0]     lim_data_sel  = lim_tp ? tp_data  : lim_data;

    localparam signed [SAMPLE_W+HEADROOM-1:0] OUT_MAX =  (1 <<< (SAMPLE_W-1)) - 1;
    localparam signed [SAMPLE_W+HEADROOM-1:0] OUT_MIN = -(1 <<< (SAMPLE_W-1));
    wire signed [SAMPLE_W+HEADROOM-1:0] lim_up =
        $signed(lim_data_sel) * $signed(1 <<< HEADROOM);
    wire [SAMPLE_W-1:0] lim_hr = (lim_up > OUT_MAX) ? OUT_MAX[SAMPLE_W-1:0] :
                                 (lim_up < OUT_MIN) ? OUT_MIN[SAMPLE_W-1:0] :
                                 lim_up[SAMPLE_W-1:0];
    wire [SAMPLE_W-1:0] push_data = headroom ? lim_hr : lim_data_sel;

    localparam DEPTH = 1 << AW;

    reg [SAMPLE_W-1:0] mem [0:DEPTH-1];
    reg [AW:0]         cnt;
    reg [AW-1:0]       wr, rd;
    reg                use_dsp_d;
    reg [3:0]          nbands_d;

    wire push = use_dsp & lim_valid_sel;
    wire pop  = use_dsp & out_ack & (cnt != 0);

    wire mode_chg = (use_dsp != use_dsp_d);

    always @(posedge clk) begin
        use_dsp_d <= use_dsp;
        nbands_d  <= nbands;
        if (!resetn || mode_chg) begin
            wr  <= {AW{1'b0}};
            rd  <= {AW{1'b0}};
            cnt <= {(AW+1){1'b0}};
        end else if (use_dsp) begin
            if (push) begin
                mem[wr] <= push_data;
                wr      <= wr + 1'b1;
            end
            if (pop)
                rd <= rd + 1'b1;
            if (push && !pop)
                cnt <= cnt + 1'b1;
            else if (!push && pop)
                cnt <= cnt - 1'b1;
        end
    end

    assign status = {overrun_cnt, nsec_last, nslot_last, 6'd0, active_bank, commit_pend};

    assign out_stb  = use_dsp ? (in_stb | (cnt != 0)) : in_stb;
    assign out_data = use_dsp ? mem[rd]              : in_data;

endmodule

`default_nettype wire
