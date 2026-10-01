# SPDX-License-Identifier: GPL-2.0-only


import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTDIR = os.path.join(ROOT, "build", "sim")
os.makedirs(OUTDIR, exist_ok=True)

SAMPLE_W, COEF_W, SHIFT = 24, 18, 15
COEF_ONE = 1 << SHIFT
MAX24, MIN24 = (1 << 23) - 1, -(1 << 23)

FS = 48000
CUTOFF_HZ = 40.0
Q = 0.53
GAIN = 50.0
PRE_SCALE = 32.0
WET_DELAY = 64
N = 200

POLYPHASE_COEFFICIENTS_2 = [
    -0.002339, -0.002073, -0.001940, -0.001675, -0.001515, -0.001329,
    -0.001223, -0.001037, -0.000904, -0.000851, -0.000532, -0.000851,
    -0.000106, -0.001010, 0.000558, -0.001435, 0.001302, -0.001967,
    0.002259, -0.002605, 0.003216, -0.003562, 0.004784, -0.005475,
    0.007655, -0.008506, 0.017622, -0.024639, 0.028679, -0.017303,
    -0.032507, 0.623321, 0.184702, -0.166867, 0.025729, -0.078490,
    -0.015735, -0.041199, -0.023151, -0.031524, -0.020121, -0.024985,
    -0.017303, -0.019616, -0.015018, -0.015204, -0.012838, -0.011881,
    -0.010951, -0.009516, -0.009090, -0.007788, -0.007442, -0.006353,
    -0.006087, -0.005183, -0.004970, -0.004253, -0.003987, -0.003482,
    -0.003216, -0.002871, -0.002578,
]
assert len(POLYPHASE_COEFFICIENTS_2) == 63

def f2q(v):

    x = v * COEF_ONE
    q = int(math.floor(x + 0.5)) if x >= 0 else -int(math.floor(-x + 0.5))
    return max(-(1 << 17), min((1 << 17) - 1, q))

def q315_round(v):

    x = (v + math.copysign(0.5 / COEF_ONE, v)) * COEF_ONE
    q = int(math.floor(x + 0.5)) if x >= 0 else -int(math.floor(-x + 0.5))
    return max(-(1 << 17), min((1 << 17) - 1, q))

def sat24(v):

    if v > MAX24:
        return MAX24
    if v < MIN24:
        return MIN24
    return v

def arshift(v, n):

    return v >> n

def rbj_lowpass(fc, q, fs):

    w0 = 2.0 * math.pi * fc / fs
    alpha = math.sin(w0) / (2.0 * q)
    cw = math.cos(w0)
    a0 = 1.0 + alpha
    return ((1.0 - cw) / 2.0 / a0, (1.0 - cw) / a0, (1.0 - cw) / 2.0 / a0,
            -2.0 * cw / a0, (1.0 - alpha) / a0)

class Biquad:

    def __init__(self, c):
        self.b0, self.b1, self.b2, self.a1, self.a2 = c
        self.x1 = self.x2 = self.y1 = self.y2 = 0

    def step(self, x):
        acc = (self.b0 * x + self.b1 * self.x1 + self.b2 * self.x2
               - self.a1 * self.y1 - self.a2 * self.y2)
        y = sat24(arshift(acc, SHIFT))
        self.x2, self.x1 = self.x1, x
        self.y2, self.y1 = self.y1, y
        return y

def fir63(hq, x):

    out = []
    for n in range(len(x)):
        acc = 0
        for k in range(64):
            if n - k >= 0:
                acc += hq[k] * x[n - k]
        out.append(sat24(arshift(acc, SHIFT)))
    return out

def main():
    hq = [f2q(v) for v in POLYPHASE_COEFFICIENTS_2] + [0]
    b0, b1, b2, a1, a2 = rbj_lowpass(CUTOFF_HZ, Q, FS)
    k = PRE_SCALE
    pre = [f2q(1.0 / PRE_SCALE), 0, 0, 0, 0]
    lp = [f2q(b0 * k), f2q(b1 * k), f2q(b2 * k), f2q(a1), f2q(a2)]
    wet = GAIN / 100.0
    w = min(wet, 4.0)

    c1 = q315_round(w)
    c0 = q315_round(1.0)

    A = MAX24
    H = A // 2
    resp_a = fir63(hq, [A] + [0] * 64)
    resp_h = fir63(hq, [H] + [0] * 64)

    x = [A] + [0] * (N - 1)
    dry = fir63(hq, x + [0] * 64)
    preq, lpq = Biquad(pre), Biquad(lp)
    out = []
    for n in range(N):
        d = x[n - WET_DELAY] if n - WET_DELAY >= 0 else 0
        wetn = lpq.step(preq.step(d))
        acc = c0 * dry[n] + c1 * wetn
        out.append(sat24(arshift(acc, SHIFT)))

    def w16(name, vals, width=6):
        with open(os.path.join(OUTDIR, name), "w") as f:
            for v in vals:
                f.write(("%0*x\n" % (width, v & ((1 << (4 * width)) - 1))))

    w16("pbp_sfir.hex", hq, 5)
    w16("pbp_delay.hex", [WET_DELAY], 2)
    w16("pbp_pre.hex", pre, 5)
    w16("pbp_lp.hex", lp, 5)
    w16("pbp_mix.hex", [c0, c1], 5)
    w16("pbp_resp_a.hex", resp_a, 6)
    w16("pbp_resp_h.hex", resp_h, 6)
    w16("pbp_out.hex", out, 6)

    print("pbp_model: 63 taps in Q3.15 generated; sum(h) = %.4f (%+.2f dB), centre tap @%d"
          % (sum(POLYPHASE_COEFFICIENTS_2),
             20 * math.log10(sum(POLYPHASE_COEFFICIENTS_2)),
             max(range(63), key=lambda i: abs(POLYPHASE_COEFFICIENTS_2[i]))))
    print("  pre=%s" % pre)
    print("  lp =%s" % lp)
    print("  mix=%s  (c0=%.6f c1=%.6f; q315Round convention)" % ([c0, c1], c0 / COEF_ONE, c1 / COEF_ONE))
    print("  small FIR taps (first 6 / last 3): %s ... %s" % (hq[:6], hq[-3:]))
    print("  resp_a[0..3]=%s resp_a[31]=%d resp_a[63]=%d"
          % (resp_a[:4], resp_a[31], resp_a[63]))
    print("  non-zero entries in pbp_out: %s" % [(i, v) for i, v in enumerate(out) if v != 0][:5])
    print("  → %s" % OUTDIR)

if __name__ == "__main__":
    main()
