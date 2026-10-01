#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
note() { printf '%s\n' "$*"; }
bad() { fail=1; note "FAIL: $*"; }

if grep -rIlP '[\x{4e00}-\x{9fff}\x{3040}-\x{30ff}]' . --exclude-dir=.git >/tmp/zybo-cjk.txt 2>/dev/null; then
  bad "non-English text in $(wc -l </tmp/zybo-cjk.txt) file(s):"
  sed 's/^/  /' /tmp/zybo-cjk.txt
else
  note "ok: no CJK text"
fi

missing=0
while IFS= read -r f; do
  head -6 "$f" | grep -q 'SPDX-License-Identifier: GPL-2.0-only' || { note "  no SPDX header: $f"; missing=1; }
done < <(git ls-files '*.v' '*.vhd' '*.tcl' '*.py' '*.sh' '*.xdc')
[ "$missing" -eq 0 ] && note "ok: SPDX headers"
[ "$missing" -eq 1 ] && fail=1

if git ls-files | grep -qiE '(^|/)(i2s_controller|i2s_tx|i2s_rx|i2s_clkgen|fifo_synchronizer|axi_ctrlif)[^/]*\.(v|vhd)$'; then
  bad "vendor IP is committed; it must be fetched by scripts/fetch_ip.sh"
else
  note "ok: no vendor IP committed"
fi

if git ls-files | grep -qiE '\.(bit|xsa|bin|img|ext4)$'; then
  bad "build output is committed (.bit/.xsa/.bin/.img)"
else
  note "ok: no build output committed"
fi

while IFS= read -r f; do bash -n "$f" || bad "shell syntax: $f"; done < <(git ls-files '*.sh')
note "ok: shell syntax"

while IFS= read -r f; do python3 -m py_compile "$f" || bad "python syntax: $f"; done < <(git ls-files '*.py')
rm -rf __pycache__ scripts/__pycache__
note "ok: python syntax"

for tag in v0.1.0 v0.2.0 v0.3.0; do
  git rev-parse -q --verify "refs/tags/$tag" >/dev/null || bad "missing tag $tag"
done
note "ok: tags present"

exit "$fail"
