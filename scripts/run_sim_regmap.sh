# SPDX-License-Identifier: GPL-2.0-only


set -e
if [ -z "${XILINX_BIN:-}" ]; then
    if command -v xvlog >/dev/null 2>&1; then
        XILINX_BIN="$(dirname "$(command -v xvlog)")"
    elif [ -x /opt/Xilinx/Vivado/2024.1/bin/xvlog ]; then
        XILINX_BIN=/opt/Xilinx/Vivado/2024.1/bin
    else
        echo "vivado not found: set XILINX_BIN=/path/to/Vivado/2024.1/bin" >&2
        exit 2
    fi
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IP="$ROOT/build/ip/digilent/ip/axi_i2s_adi_1.2/hdl"
export PATH="$XILINX_BIN:$PATH"

mkdir -p "$ROOT/build/sim"; cd "$ROOT/build/sim"
rm -rf xsim.dir *.log *.pb *.jou adi_common_v1_00_a axi_i2s_adi_v1_00_a

echo "== Build library adi_common_v1_00_a =="
xvhdl --work adi_common_v1_00_a "$IP/adi_common/dma_fifo.vhd"
xvhdl --work adi_common_v1_00_a "$IP/adi_common/pl330_dma_fifo.vhd" \
                                  "$IP/adi_common/axi_streaming_dma_tx_fifo.vhd" \
                                  "$IP/adi_common/axi_streaming_dma_rx_fifo.vhd" \
                                  "$IP/adi_common/axi_ctrlif.vhd"

echo "== Build library axi_i2s_adi_v1_00_a =="
xvhdl --work axi_i2s_adi_v1_00_a "$IP/fifo_synchronizer.vhd" "$IP/i2s_clkgen.vhd" \
                                  "$IP/i2s_tx.vhd" "$IP/i2s_rx.vhd" "$IP/i2s_controller.vhd"

echo "== work: IP top + insert layer + TB =="
xvhdl --work work "$IP/axi_i2s_adi_S_AXI.vhd" "$IP/axi_i2s_adi_v1_2.vhd"

xvlog --work work "$IP/dsp_insert.v" "$IP/biquad_filter.v" "$IP/saturator.v" "$IP/limiter.v" \
                  "$IP/dsp_engine.v" "$IP/fir_bank.v" "$IP/fir_bank_long.v" \
                  "$IP/tp_log2.v" "$IP/tp_exp2.v" "$IP/truepeak_limiter.v" \
                  "$ROOT/tb/tb_axi_regmap.v"

echo "== elaborate + run =="
xelab -L adi_common_v1_00_a -L axi_i2s_adi_v1_00_a work.tb_axi_regmap \
      -s regmap_sim -timescale 1ns/1ps
xsim regmap_sim -runall | grep -vE '^\s*$|^\*\*|^# xsim|^source |^Time resolution|^run -all|^exit$'
