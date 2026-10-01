# SPDX-License-Identifier: GPL-2.0-only


set_property -dict { PACKAGE_PIN K18   IOSTANDARD LVCMOS33 } [get_ports ac_bclk];
set_property -dict { PACKAGE_PIN T19   IOSTANDARD LVCMOS33 } [get_ports ac_mclk];
set_property -dict { PACKAGE_PIN P18   IOSTANDARD LVCMOS33 } [get_ports ac_muten];
set_property -dict { PACKAGE_PIN M17   IOSTANDARD LVCMOS33 } [get_ports ac_pbdat];
set_property -dict { PACKAGE_PIN L17   IOSTANDARD LVCMOS33 } [get_ports ac_pblrc];
set_property -dict { PACKAGE_PIN K17   IOSTANDARD LVCMOS33 } [get_ports ac_recdat];
set_property -dict { PACKAGE_PIN M18   IOSTANDARD LVCMOS33 } [get_ports ac_reclrc];

set_property -dict { PACKAGE_PIN N18   IOSTANDARD LVCMOS33 } [get_ports iic_codec_scl_io];
set_property -dict { PACKAGE_PIN N17   IOSTANDARD LVCMOS33 } [get_ports iic_codec_sda_io];

set_property -dict { PACKAGE_PIN R18   IOSTANDARD LVCMOS33 } [get_ports btn_4bits_tri_i[0]];
set_property -dict { PACKAGE_PIN P16   IOSTANDARD LVCMOS33 } [get_ports btn_4bits_tri_i[1]];
set_property -dict { PACKAGE_PIN V16   IOSTANDARD LVCMOS33 } [get_ports btn_4bits_tri_i[2]];
set_property -dict { PACKAGE_PIN Y16   IOSTANDARD LVCMOS33 } [get_ports btn_4bits_tri_i[3]];
