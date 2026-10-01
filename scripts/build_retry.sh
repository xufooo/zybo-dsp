# SPDX-License-Identifier: GPL-2.0-only


set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRIES="${1:-3}"; shift || true
if [ -z "${VIVADO:-}" ]; then
    if [ -z "${XILINX_BIN:-}" ] && command -v xvlog >/dev/null 2>&1; then
        XILINX_BIN="$(dirname "$(command -v xvlog)")"
    fi
    VIVADO="${XILINX_BIN:-/opt/Xilinx/Vivado/2024.1/bin}/vivado"
fi
BIT="$ROOT/build/fpga/zybo_audio.xpr/zybo_audio.runs/impl_1/zybo_audio_wrapper.bit"
for i in $(seq 1 "$TRIES"); do
    echo "== Build attempt $i/$TRIES =="
    rm -f "$ROOT"/hs_err_pid*.log
    BEFORE=$(stat -c %Y "$BIT" 2>/dev/null || echo 0)
    env TMPDIR="$ROOT/build/tmp" "$VIVADO" -mode batch -nojournal \
        -log "$ROOT/build/fpga_build.log" -source "$ROOT/scripts/build_vivado.tcl" \
        "$@" 2>&1 | tee "$ROOT/build/fpga_build.out"
    RC=${PIPESTATUS[0]}
    AFTER=$(stat -c %Y "$BIT" 2>/dev/null || echo 0)

    if grep -q 'BUILD COMPLETE' "$ROOT/build/fpga_build.out" && [ "$AFTER" != "$BEFORE" ]; then
        if [ "$RC" != "0" ]; then
            echo "== Attempt $i: build complete (exit $RC is the exit-phase segfault, outputs valid) =="
        else
            echo "== Attempt $i succeeded =="
        fi
        exit 0
    fi
    echo "== Attempt $i failed (rc=$RC, most likely the nondeterministic crash), retry in 10 s =="
    sleep 10
done
echo "== All $TRIES attempts failed, giving up =="
exit 1
