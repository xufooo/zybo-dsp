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

SRCHDL="$ROOT/rtl"

XILINX_VIVADO="$(dirname "$XILINX_BIN")"
xvlog -sv --work dsp "$XILINX_VIVADO/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv"
xvlog --work dsp "$SRCHDL/dsp_insert.v" "$SRCHDL/biquad_filter.v" \
      "$SRCHDL/saturator.v" "$SRCHDL/limiter.v" "$SRCHDL/dsp_engine.v" \
      "$SRCHDL/fir_bank.v" "$SRCHDL/fir_bank_long.v" \
      "$SRCHDL/tp_log2.v" "$SRCHDL/tp_exp2.v" "$SRCHDL/truepeak_limiter.v"
xvlog --work dsp "$ROOT"/tb/*.v

python3 "$ROOT/tools/tp_model.py" > /dev/null

python3 "$ROOT/tools/pbp_model.py" > /dev/null

python3 "$ROOT/tools/colm_model.py" > /dev/null

python3 "$ROOT/tools/dynbass_model.py" > /dev/null

if [ $# -gt 0 ]; then
    TBS="$*"
else
    TBS="tb_biquad tb_limiter tb_dsp_insert tb_dsp_engine tb_engine_headroom \
          tb_engine_dyn tb_engine_mix2 tb_engine_delay tb_tp_math tb_truepeak \
          tb_truepeak_golden tb_fir_bank tb_fir_bank_long tb_engine_fir \
          tb_engine_poly tb_engine_vbass_plan tb_engine_js \
          tb_engine_xphase tb_engine_dynbass"
fi

rc=0
for tb in $TBS; do
    echo "== RUN $tb =="

    if ! xelab -L dsp "dsp.$tb" -s "${tb}_sim" -timescale 1ns/1ps > "$tb.elab.log" 2>&1; then
        echo "== $tb: xelab failed =="
        grep -E "ERROR" "$tb.elab.log" | head -20
        rc=1
        continue
    fi
    xsim "${tb}_sim" -runall | grep -vE '^\s*$|^\*\*|^# xsim|^source |^Time resolution|^run -all|^exit$' || rc=1
done
exit $rc
