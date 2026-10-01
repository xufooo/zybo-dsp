# Third-party components (not shipped in this repo)

Everything below is fetched or provided by its owner at build time.
Nothing in this list is vendored here.

| Component | Owner / license | How it enters the build |
|---|---|---|
| `axi_i2s_adi` v1.2 I2S IP | Digilent, MIT | `scripts/fetch_ip.sh` (pinned commit) |
| 6 derived VHDL files (`i2s_controller`, `i2s_tx/rx`, `i2s_clkgen`, `fifo_synchronizer`, `axi_ctrlif`) | Analog Devices, dual-licensed; this project uses the **GPL-2.0** branch (`analogdevicesinc/hdl`, pinned commit, zero RTL changes) | `scripts/fetch_ip.sh` (sha256-asserted) |
| processing_system7, axi_iic, clk_wiz, axi_gpio, interconnect, reset | Xilinx, proprietary EULA | come with Vivado; used, never redistributed |
| ZYBO Rev B board preset | Digilent | applied at BD build time |
| Cookbook biquad formulas | RBJ Audio EQ Cookbook (public reference) | math only, re-implemented |
| Saturator / volume-ramp concepts | MIT (attributed in source) | ideas only, re-implemented |

`scripts/patch_ip.py` applies our own changes to the fetched IP reproducibly
(three Verilog modules, two VHDL files, one user parameter). It is a patch, not
a fork: re-running the fetch gives the pristine upstream tree again.
