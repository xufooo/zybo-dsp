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
export PATH="$XILINX_BIN:$PATH"

mkdir -p "$ROOT/build/sim"
cd "$ROOT/build/sim"
rm -rf xsim.dir dsp *.log *.pb *.jou

IPHDL="$ROOT/build/ip/digilent/ip/axi_i2s_adi_1.2/hdl"

xvlog --work dsp "$IPHDL/dsp_insert.v" "$IPHDL/biquad_filter.v" \
      "$IPHDL/saturator.v" "$IPHDL/limiter.v"
xvlog --work dsp "$ROOT"/tb/*.v

rc=0
for tb in tb_biquad tb_limiter tb_dsp_insert; do
    echo "== RUN $tb =="
    xelab -L dsp "dsp.$tb" -s "${tb}_sim" -timescale 1ns/1ps > /dev/null
    xsim "${tb}_sim" -runall | grep -vE '^\s*$|^\*\*|^# xsim|^source |^Time resolution|^run -all|^exit$' || rc=1
done
exit $rc
