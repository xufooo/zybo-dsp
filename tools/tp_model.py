# SPDX-License-Identifier: GPL-2.0-only


import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTDIR = os.path.join(ROOT, "build", "sim")

SAMPLE_W, SHIFT = 24, 15
FULL = 1 << (SAMPLE_W - 1)
LOOK = 96
THR = 29491
K_ATT = 1310
K_REL = 8
N = 600

LOG_TBL = [min(int(round(math.log2(1.0 + i / 256.0) * 2048.0)), 2047) for i in range(256)]
EXP_TBL = [int(round((2.0 ** (i / 256.0)) * 32768.0)) for i in range(256)]

def s17(v):

    v &= 0x1FFFF
    return v - 0x20000 if v & 0x10000 else v

def abs24(v):
    return -v if v < 0 else v

def sat24(v):
    if v > FULL - 1:
        return FULL - 1
    if v < -FULL:
        return -FULL
    return v

def tp_log2(mag):

    if mag == 0:
        return 0
    k = mag.bit_length() - 1
    nrm = (mag << (23 - k)) & 0xFFFFFF
    idx = (nrm >> 15) & 0xFF
    return (k << 11) + LOG_TBL[idx]

def tp_exp2(x):

    ipart = x >> 11
    fpart = x & 0x7FF
    frac = EXP_TBL[fpart >> 3]
    if ipart > 0:
        g = 32768
    elif -ipart >= 17:
        g = 0
    else:
        g = frac >> (-ipart)
    return 32768 if g > 32768 else (g & 0xFFFF)

def make_stimulus(n):

    x = []
    for i in range(n):
        if i < 150:
            x.append((((i * 0x1357) ^ 0xA5A5) & 0x7FFFF) - 0x40000)
        elif i < 300:
            x.append(0x7FFFF0 if i % 4 < 2 else -((i * 0x1B3D) & 0x3FFFF))
        else:
            x.append(sat24(int(0.98 * FULL * math.sin(2 * math.pi * 1000.0 * i / 48000.0))))
    return x

def run(x):

    thr_abs24 = (THR << (SAMPLE_W - 1 - SHIFT)) & 0xFFFFFF
    thr_lg = tp_log2(thr_abs24)
    dl = [0] * (1 << 7)
    w = 0
    g = 0
    outs, gains = [], []
    for k, v in enumerate(x):
        dly = dl[(w - LOOK) % 128]
        dl[w] = v
        w = (w + 1) % 128
        mx = abs24(v)
        for j in range(1, LOOK):
            a = abs24(dl[(w + j) % 128])
            if a > mx:
                mx = a
        peak_lg = tp_log2(mx)
        tgt = 0 if mx <= thr_abs24 else (thr_lg - peak_lg)
        kk = K_ATT if tgt < g else K_REL
        g = s17(g + (((tgt - g) * kk) >> 15))
        gain = tp_exp2(g)
        outs.append(sat24((dly * gain) >> 15))
        gains.append(gain)
    return outs, gains

def main():
    os.makedirs(OUTDIR, exist_ok=True)
    x = make_stimulus(N)
    outs, gains = run(x)

    with open(os.path.join(OUTDIR, "tp_gold_in.hex"), "w") as f:
        for v in x:
            f.write("%06x\n" % (v & 0xFFFFFF))
    with open(os.path.join(OUTDIR, "tp_gold_out.hex"), "w") as f:
        for v in outs:
            f.write("%06x\n" % (v & 0xFFFFFF))
    with open(os.path.join(OUTDIR, "tp_gold_gain.hex"), "w") as f:
        for v in gains:
            f.write("%04x\n" % (v & 0xFFFF))

    pk = max(abs(v) for v in outs)
    nj = 0
    mx = 0
    for i in range(1, N):
        d = abs(gains[i] - gains[i - 1])
        mx = max(mx, d)
        if d * 100 > 32768 * 5:
            nj += 1
    print(f"golden vectors generated: {N} samples -> {OUTDIR}/tp_gold_*.hex")
    print(f"  input peak {max(abs(v) for v in x)}  output peak {pk} (threshold {THR << 8})")
    print(f"  gain jumps >5%: {nj} (largest jump {mx}/32768 = {mx * 100 // 32768}%)")

if __name__ == "__main__":
    main()
