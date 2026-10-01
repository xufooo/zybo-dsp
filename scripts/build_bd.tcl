# SPDX-License-Identifier: GPL-2.0-only


set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir ..]]
set build_dir  [file join $repo_root build fpga]
file mkdir $build_dir

set_param board.repoPaths [list [file join $repo_root build ip boards]]
create_project zybo_audio [file join $build_dir zybo_audio.xpr] -part xc7z010clg400-1 -force
if {[catch { set_property board_part digilentinc.com:zybo:part0:2.0 [current_project] } err]} {
    puts "WARN: board part not in effect ($err), continuing pure-part xc7z010clg400-1"
}
set_property XPM_LIBRARIES {XPM_MEMORY XPM_FIFO XPM_CDC} [current_project]
set_property ip_repo_paths [list [file join $repo_root build ip]] [current_project]
update_ip_catalog

create_bd_design zybo_audio

set DDR       [create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddrx_rtl:1.0 DDR]
set FIXED_IO  [create_bd_intf_port -mode Master -vlnv xilinx.com:display_processing_system7:fixedio_rtl:1.0 FIXED_IO]
set IIC       [create_bd_intf_port -mode Master -vlnv xilinx.com:interface:iic_rtl:1.0 iic_codec]
set BTN       [create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 btn_4bits]
set ac_bclk   [create_bd_port -dir O ac_bclk]
set ac_mclk   [create_bd_port -dir O ac_mclk]
set ac_muten  [create_bd_port -dir O ac_muten]
set ac_pbdat  [create_bd_port -dir O ac_pbdat]
set ac_pblrc  [create_bd_port -dir O ac_pblrc]
set ac_recdat [create_bd_port -dir I ac_recdat]
set ac_reclrc [create_bd_port -dir O ac_reclrc]

set ps7      [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0]
set i2s      [create_bd_cell -type ip -vlnv digilentinc.com:user:axi_i2s_adi:1.2 axi_i2s_adi_0]
set clk_wiz  [create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_0]
set iic      [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_iic:2.1 axi_iic_0]
set gpio     [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_0]
set const1   [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconstant_0]
set periph_ic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_periph_ic]
set rst      [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_rst_0]

if {[catch {
    apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
        -config {make_external "" apply_board_preset "1" Master "Disable" Slave "Disable"} $ps7
    puts "== PS7 board preset applied: digilentinc.com:zybo:part0:2.0 =="
} err]} {
    puts "WARN: board preset failed ($err), continuing with the explicit attributes below"
}

set_property -dict [list \
    CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} CONFIG.PCW_UART1_UART1_IO {MIO 48 .. 49} \
    CONFIG.PCW_SD0_PERIPHERAL_ENABLE {1} CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_USB0_PERIPHERAL_ENABLE {1} CONFIG.PCW_QSPI_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_USE_M_AXI_GP0 {1} CONFIG.PCW_EN_CLK0_PORT {1} \
    CONFIG.PCW_USE_DMA0 {1} CONFIG.PCW_USE_DMA1 {1} \
    CONFIG.PCW_FCLK0_PERIPHERAL_CLKSRC {IO PLL} CONFIG.PCW_FCLK0_PERIPHERAL_DIVISOR0 {5} \
    CONFIG.PCW_FCLK0_PERIPHERAL_DIVISOR1 {2} CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_IRQ_F2P_INTR {1} CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
    CONFIG.PCW_CRYSTAL_PERIPHERAL_FREQMHZ {50.000000} \
    CONFIG.PCW_DDR_RAM_HIGHADDR {0x1FFFFFFF} CONFIG.PCW_PACKAGE_NAME {clg400} \
] $ps7

set_property -dict [list CONFIG.C_DMA_TYPE {1} CONFIG.C_HAS_TX {1} CONFIG.C_HAS_RX {1} \
                        CONFIG.C_S00_AXI_ADDR_WIDTH {7}] $i2s

set _aw [get_property CONFIG.C_S00_AXI_ADDR_WIDTH $i2s]
if {$_aw ne "7"} {
    puts "ERROR: axi_i2s_adi C_S00_AXI_ADDR_WIDTH=$_aw (must be 7)"
    puts "       -> DSP registers 0x30..0x44 would be misaligned; writes to 0x40/0x44 would hit RESET/CTRL."
    puts "       Check whether xgui/axi_i2s_adi_v1_2.tcl has the C_S00_AXI_ADDR_WIDTH add_param."
    exit 1
}
puts "== BD self-check: axi_i2s_adi C_S00_AXI_ADDR_WIDTH = $_aw =="

set_property -dict [list \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {12.288} CONFIG.PRIM_IN_FREQ {100.000} \
    CONFIG.CLKOUT1_DRIVES {BUFG}] $clk_wiz
set_property -dict [list CONFIG.C_GPIO_WIDTH {4} CONFIG.C_ALL_INPUTS {1}] $gpio
set_property -dict [list CONFIG.NUM_MI {3} CONFIG.NUM_SI {1}] $periph_ic
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] $const1

set fclk [get_bd_pins $ps7/FCLK_CLK0]
set prst [get_bd_pins $rst/peripheral_aresetn]
set irst [get_bd_pins $rst/interconnect_aresetn]

if {[get_bd_intf_nets -quiet -of_objects [get_bd_intf_pins $ps7/DDR]] eq ""} {
    connect_bd_intf_net [get_bd_intf_pins $ps7/DDR] [get_bd_intf_ports DDR]
}
if {[get_bd_intf_nets -quiet -of_objects [get_bd_intf_pins $ps7/FIXED_IO]] eq ""} {
    connect_bd_intf_net [get_bd_intf_pins $ps7/FIXED_IO] [get_bd_intf_ports FIXED_IO]
}
connect_bd_intf_net [get_bd_intf_pins $iic/IIC] [get_bd_intf_ports iic_codec]
connect_bd_intf_net [get_bd_intf_pins $gpio/GPIO] [get_bd_intf_ports btn_4bits]
connect_bd_net [get_bd_pins $const1/dout] [get_bd_ports ac_muten]

connect_bd_net [get_bd_pins $i2s/BCLK_O]   [get_bd_ports ac_bclk]
connect_bd_net [get_bd_pins $i2s/LRCLK_O]  [get_bd_ports ac_pblrc]
connect_bd_net [get_bd_pins $i2s/LRCLK_O]  [get_bd_ports ac_reclrc]
connect_bd_net [get_bd_pins $i2s/SDATA_O]  [get_bd_ports ac_pbdat]
connect_bd_net [get_bd_pins $i2s/SDATA_I]  [get_bd_ports ac_recdat]
connect_bd_net [get_bd_pins $clk_wiz/clk_out1] [get_bd_pins $i2s/DATA_CLK_I]
connect_bd_net [get_bd_pins $clk_wiz/clk_out1] [get_bd_ports ac_mclk]
connect_bd_net $fclk [get_bd_pins $clk_wiz/clk_in1]

foreach {ip_pin ps_pin} {
    DMA_REQ_TX_DRVALID DMA0_DRVALID   DMA_REQ_TX_DRLAST DMA0_DRLAST
    DMA_REQ_TX_DRTYPE  DMA0_DRTYPE    DMA_REQ_TX_DRREADY DMA0_DRREADY
    DMA_REQ_TX_DAVALID DMA0_DAVALID   DMA_REQ_TX_DATYPE  DMA0_DATYPE
    DMA_REQ_TX_DAREADY DMA0_DAREADY
    DMA_REQ_RX_DRVALID DMA1_DRVALID   DMA_REQ_RX_DRLAST DMA1_DRLAST
    DMA_REQ_RX_DRTYPE  DMA1_DRTYPE    DMA_REQ_RX_DRREADY DMA1_DRREADY
    DMA_REQ_RX_DAVALID DMA1_DAVALID   DMA_REQ_RX_DATYPE  DMA1_DATYPE
    DMA_REQ_RX_DAREADY DMA1_DAREADY
} {
    connect_bd_net [get_bd_pins $i2s/$ip_pin] [get_bd_pins $ps7/$ps_pin]
}

connect_bd_intf_net [get_bd_intf_pins $ps7/M_AXI_GP0] [get_bd_intf_pins $periph_ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins $periph_ic/M00_AXI] [get_bd_intf_pins $iic/S_AXI]
connect_bd_intf_net [get_bd_intf_pins $periph_ic/M01_AXI] [get_bd_intf_pins $gpio/S_AXI]
connect_bd_intf_net [get_bd_intf_pins $periph_ic/M02_AXI] [get_bd_intf_pins $i2s/S00_AXI]

connect_bd_net $fclk [get_bd_pins $rst/slowest_sync_clk]
connect_bd_net $fclk [get_bd_pins $iic/s_axi_aclk] [get_bd_pins $gpio/s_axi_aclk]
connect_bd_net $fclk [get_bd_pins $periph_ic/ACLK] [get_bd_pins $periph_ic/S00_ACLK]
connect_bd_net $fclk [get_bd_pins $periph_ic/M00_ACLK] [get_bd_pins $periph_ic/M01_ACLK] [get_bd_pins $periph_ic/M02_ACLK]
connect_bd_net $fclk [get_bd_pins $ps7/FCLK_CLK0] [get_bd_pins $ps7/M_AXI_GP0_ACLK] \
                     [get_bd_pins $ps7/DMA0_ACLK] [get_bd_pins $ps7/DMA1_ACLK]
connect_bd_net $fclk [get_bd_pins $i2s/s00_axi_aclk] [get_bd_pins $i2s/DMA_REQ_TX_ACLK] [get_bd_pins $i2s/DMA_REQ_RX_ACLK]

connect_bd_net [get_bd_pins $ps7/FCLK_RESET0_N] [get_bd_pins $rst/ext_reset_in]
connect_bd_net $prst [get_bd_pins $iic/s_axi_aresetn] [get_bd_pins $gpio/s_axi_aresetn]
connect_bd_net $prst [get_bd_pins $periph_ic/M00_ARESETN] [get_bd_pins $periph_ic/M01_ARESETN]
connect_bd_net $prst [get_bd_pins $periph_ic/M02_ARESETN] [get_bd_pins $periph_ic/S00_ARESETN]
connect_bd_net $prst [get_bd_pins $i2s/s00_axi_aresetn] \
                     [get_bd_pins $i2s/DMA_REQ_TX_RSTN] [get_bd_pins $i2s/DMA_REQ_RX_RSTN]
connect_bd_net $irst [get_bd_pins $periph_ic/ARESETN]

connect_bd_net [get_bd_pins $iic/iic2intc_irpt] [get_bd_pins $ps7/IRQ_F2P]

assign_bd_address
regenerate_bd_layout
validate_bd_design
save_bd_design

set design_name [get_bd_designs]
make_wrapper -files [get_files ${design_name}.bd] -top
set wrapper_file ""
foreach pat [list \
    [file join $build_dir *.xpr *.gen sources_1 bd ${design_name} hdl ${design_name}_wrapper.v] \
    [file join $build_dir *.srcs sources_1 bd ${design_name} hdl ${design_name}_wrapper.v] \
    [file join $build_dir ** ${design_name}_wrapper.v]] {
    set hit [glob -nocomplain $pat]
    if {$hit ne ""} { set wrapper_file [lindex $hit 0]; break }
}
if {$wrapper_file eq ""} {
    puts "WARN: could not auto-locate ${design_name}_wrapper.v (Vivado version difference), add_files manually"
} else {
    add_files -norecurse $wrapper_file
    puts "wrapper: $wrapper_file"
}
add_files -fileset constrs_1 [file join $repo_root xdc zybo_audio.xdc]

add_files -fileset constrs_1 [file join $repo_root xdc zybo_audio_timing.xdc]
set_property used_in_synthesis false [get_files zybo_audio_timing.xdc]
update_compile_order -fileset sources_1

puts "== BD OK: $design_name (build/fpga). Next: see build_vivado.tcl =="
