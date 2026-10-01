# SPDX-License-Identifier: GPL-2.0-only


set_clock_groups -asynchronous \
    -group [get_clocks -quiet clk_fpga_0] \
    -group [get_clocks -quiet -filter {NAME =~ *clk_out1*}]
