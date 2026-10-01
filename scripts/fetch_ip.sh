# SPDX-License-Identifier: GPL-2.0-only


set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="https://github.com/Digilent/vivado-library"
COMMIT="f4613fff005b098065fd5d619a2b88e55720a423"
SUBPATH="ip/axi_i2s_adi_1.2"
DEST="$ROOT/build/ip/digilent/$SUBPATH"

ADI_REPO="https://github.com/analogdevicesinc/hdl"
ADI_COMMIT="4840c81f2af172b036cb3ccb3f9f2dc45ed9c1d3"

BOARDS_REPO="https://github.com/Digilent/vivado-boards"
BOARDS_COMMIT="36f34ab687b7fa9c778b779d027f3bce63b3ace9"
BOARDS_SUBPATH="new/board_files/zybo"
BOARDS_DEST="$ROOT/build/ip/boards/zybo"
declare -A BOARDS_SHA=(
    ["B.4/board.xml"]="a8f0c7ebe957bdd1ef335772a9dabc17e81ddd1414f8d76f68212726d4ab4651"
    ["B.4/part0_pins.xml"]="953202a3dd50e8ecb395ce0f7259dfd7b667bd519f9b5b693999a370f9c3469c"
    ["B.4/preset.xml"]="f28f930855a04fb753a2afba72bbf7d932aa6a99494d7532fbd6ddee541f4f44"
)

declare -A ADI_SRC=(
    ["library/axi_i2s_adi/i2s_controller.vhd"]="hdl/i2s_controller.vhd"
    ["library/axi_i2s_adi/i2s_tx.vhd"]="hdl/i2s_tx.vhd"
    ["library/axi_i2s_adi/i2s_rx.vhd"]="hdl/i2s_rx.vhd"
    ["library/axi_i2s_adi/i2s_clkgen.vhd"]="hdl/i2s_clkgen.vhd"
    ["library/axi_i2s_adi/fifo_synchronizer.vhd"]="hdl/fifo_synchronizer.vhd"
    ["library/common/axi_ctrlif.vhd"]="hdl/adi_common/axi_ctrlif.vhd"
)

declare -A ADI_SHA=(
    ["hdl/i2s_controller.vhd"]="fb0356934bbc1ea0f13e32f1f4522da286722cc67699f73568022ca0172c353a"
    ["hdl/i2s_tx.vhd"]="6be31bee25ff1ecdc8fe06611d5ef57376aed0a08873e51d08a94ad47bf78a9a"
    ["hdl/i2s_rx.vhd"]="cfec34309500f9b4580c3e0bca18f495b9b49acd06cf6ab73ff13047ea6fc91a"
    ["hdl/i2s_clkgen.vhd"]="66d9e8a4d1b43465c4c9f707e1cd01f43039158f1a2a09e38862123377fa3f8c"
    ["hdl/fifo_synchronizer.vhd"]="d5ccc358e34694b2e491878c887f950530bb59717a77d9aac9044c8abd7770f3"
    ["hdl/adi_common/axi_ctrlif.vhd"]="e95191764a257c917584871c0b2346dc44c8cef1301329e0f9f3ac2017deae19"
)

ADI_ORDER=(
    "hdl/i2s_controller.vhd"
    "hdl/i2s_tx.vhd"
    "hdl/i2s_rx.vhd"
    "hdl/i2s_clkgen.vhd"
    "hdl/fifo_synchronizer.vhd"
    "hdl/adi_common/axi_ctrlif.vhd"
)

verify_adi() {
    local bad=0 rel exp got
    for rel in "${ADI_ORDER[@]}"; do
        if [ ! -f "$DEST/$rel" ]; then
            echo "  ✗ missing $rel" >&2; bad=1; continue
        fi
        exp="${ADI_SHA[$rel]}"
        got="$(sha256sum "$DEST/$rel" | cut -d' ' -f1)"
        if [ "$got" != "$exp" ]; then
            echo "  ✗ $rel differs from ADI pin ${ADI_COMMIT:0:12}" >&2
            echo "      expected $exp" >&2
            echo "      actual $got" >&2
            bad=1
        else
            echo "  ✓ $rel"
        fi
    done
    return $bad
}

if [ "${1:-}" = "--check" ]; then
    [ -f "$DEST/component.xml" ] || { echo "missing: $SUBPATH -- run ./scripts/fetch_ip.sh first" >&2; exit 1; }
    echo "== Checking ADI dual-license resourcing =="
    verify_adi || exit 1
    echo "== Checking board files =="
    for rel in "${!BOARDS_SHA[@]}"; do
        exp="${BOARDS_SHA[$rel]}"
        got="$(sha256sum "$BOARDS_DEST/$rel" 2>/dev/null | cut -d' ' -f1)"
        if [ "$got" != "$exp" ]; then
            echo "  ✗ boards/$rel differs from pin ${BOARDS_COMMIT:0:12}" >&2
            exit 1
        fi
    done
    echo "  ✓ boards/zybo (B.4, ${#BOARDS_SHA[@]} files)"
    echo "== Checking our patches =="
    python3 "$ROOT/scripts/patch_ip.py" "$DEST" --check
    exit $?
fi

command -v git >/dev/null || { echo "git required" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "== (1) Fetching Digilent pristine bundle: $REPO @ ${COMMIT:0:12} =="
git clone --filter=blob:none --no-checkout --quiet "$REPO" "$TMP/vl"
git -C "$TMP/vl" checkout --quiet "$COMMIT" -- "$SUBPATH" License.txt

mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST"
cp -a "$TMP/vl/$SUBPATH" "$DEST"
[ -f "$TMP/vl/License.txt" ] && cp "$TMP/vl/License.txt" "$DEST/License.txt"

echo "== (2) Swapping in ADI upstream dual-licensed files: $ADI_REPO @ ${ADI_COMMIT:0:12} =="
git clone --filter=blob:none --no-checkout --quiet "$ADI_REPO" "$TMP/adi"
if ! git -C "$TMP/adi" cat-file -e "${ADI_COMMIT}^{commit}" 2>/dev/null; then
    git -C "$TMP/adi" fetch --quiet origin "$ADI_COMMIT"
fi
git -C "$TMP/adi" checkout --quiet "$ADI_COMMIT" -- \
    "${!ADI_SRC[@]}" LICENSE LICENSE_GPL2 LICENSE_ADIBSD

for src in "${!ADI_SRC[@]}"; do
    dst="${ADI_SRC[$src]}"
    mkdir -p "$DEST/$(dirname "$dst")"
    cp "$TMP/adi/$src" "$DEST/$dst"
done

mkdir -p "$DEST/ADI_LICENSES"
cp "$TMP/adi/LICENSE" "$DEST/ADI_LICENSES/LICENSE"
cp "$TMP/adi/LICENSE_GPL2" "$DEST/ADI_LICENSES/LICENSE_GPL2"
cp "$TMP/adi/LICENSE_ADIBSD" "$DEST/ADI_LICENSES/LICENSE_ADIBSD"

echo "== (2b) Fetching board files: $BOARDS_REPO @ ${BOARDS_COMMIT:0:12} =="
git clone --filter=blob:none --no-checkout --quiet "$BOARDS_REPO" "$TMP/boards"
git -C "$TMP/boards" checkout --quiet "$BOARDS_COMMIT" -- "$BOARDS_SUBPATH"
mkdir -p "$BOARDS_DEST"
cp -a "$TMP/boards/$BOARDS_SUBPATH/." "$BOARDS_DEST/"
for rel in "${!BOARDS_SHA[@]}"; do
    exp="${BOARDS_SHA[$rel]}"
    got="$(sha256sum "$BOARDS_DEST/$rel" | cut -d' ' -f1)"
    if [ "$got" != "$exp" ]; then
        echo "  ✗ boards/$rel differs from pin ${BOARDS_COMMIT:0:12}" >&2
        echo "      expected $exp" >&2
        echo "      actual $got" >&2
        exit 1
    fi
done
echo "  ✓ boards/zybo (B.4, ${#BOARDS_SHA[@]} files, sha256-asserted)"

verify_adi

{
    echo "# ADI HDL License Election (LICENSE ELECTION)"
    echo
    echo "These 6 files in this directory are **ADI HDL**, taken verbatim from upstream with no changes by this project:"
    echo
    echo '```'
    for rel in "${ADI_ORDER[@]}"; do printf '%s  %s\n' "${ADI_SHA[$rel]}" "$rel"; done
    echo '```'
    echo
    echo "Source: <$ADI_REPO> commit \`$ADI_COMMIT\` (branch \`hdl_2026_r1\`)"
    echo
    echo "Upstream **dual-licenses** this code as:"
    echo
    echo "1. GNU General Public License version 2 (\`ADI_LICENSES/LICENSE_GPL2\`); or"
    echo "2. ADI BSD license (\`ADI_LICENSES/LICENSE_ADIBSD\`)."
    echo
    echo "**This project elects branch 1 (GPL-2.0).** Branch 2 is unusable: it requires the software"
    echo "\"must be run on or directly connected to an Analog Devices Inc."
    echo "component\", while this board is Xilinx Zynq + TI codec, which does not satisfy it."
    echo
    echo "So this directory is distributed as a whole under **GPL-2.0**; the remaining files (Digilent bundle) are"
    echo "MIT / BSD-3-Clause, see \`License.txt\`."
    echo
    echo "This directory is generated by \`scripts/fetch_ip.sh\`; **do not edit by hand**;"
    echo "our own changes live in \`rtl/\` and are overlaid by \`patch_ip.py\`."
} > "$DEST/ADI-LICENSING.md"

echo "== (3) Patching =="
python3 "$ROOT/scripts/patch_ip.py" "$DEST"

echo
echo "✓ Done: $DEST"
echo "  ℹ️  ADI 6 files = upstream dual-licensed rev, this project elects GPL-2.0 (see ADI-LICENSING.md)"
echo "  ℹ️  Pre-build check: ./scripts/fetch_ip.sh --check"
