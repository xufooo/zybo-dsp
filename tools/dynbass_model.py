# SPDX-License-Identifier: GPL-2.0-only


import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTDIR = os.path.join(ROOT, "build", "sim")
os.makedirs(OUTDIR, exist_ok=True)

SAMPLE_W, COEF_W, SHIFT = 24, 18, 15
COEF_ONE = 1 << SHIFT
MAX24, MIN24 = (1 << 23) - 1, -(1 << 23)

FS = 48000
LP_HZ = 55.0
BASS_PCT = 0.0
PRE_SCALE = 256.0
N = 200

def sat24(v):
    if v > MAX24:
        return MAX24
    if v < MIN24:
        return MIN24
    return v

def q315(v):

    return int(math.floor(v * COEF_ONE + 0.5)) if v >= 0 else -int(math.floor(-v * COEF_ONE + 0.5))

def bass_gain(pct):

    return (pct * 20.0 + 100.0) / 100.0

def q_peak(gain):
    x = (gain - 1.0) / 20.0 * 1600.0
    return min(max(x, 0.0), 1600.0)

def q_factor(pct):
    return q_peak(bass_gain(pct)) / 666.0 + 0.5

def v4a_lowpass(freq, q, fs):

    w = 2.0 * math.pi * freq / fs
    s, c = math.sin(w), math.cos(w)
    alpha = s / (q + q)
    a0 = alpha + 1.0
    return (1.0 - c) / 2.0 / a0, (1.0 - c) / a0, (1.0 - c) / 2.0 / a0, -2.0 * c / a0, (1.0 - alpha) / a0

Q = q_factor(BASS_PCT)
B0, B1, B2, A1, A2 = v4a_lowpass(LP_HZ, Q, FS)
LP = [q315(B0 * PRE_SCALE), q315(B1 * PRE_SCALE), q315(B2 * PRE_SCALE), q315(A1), q315(A2)]
SIDE_W = q315(1.0 / PRE_SCALE)
ADD_W = q315(1.0)

AMPL = 1_000_000.0

def stim(n):
    l = AMPL * (0.50 * math.sin(2 * math.pi * 30.0 * n / FS)
                + 0.30 * math.sin(2 * math.pi * 200.0 * n / FS)
                + 0.20 * math.sin(2 * math.pi * 1000.0 * n / FS))
    r = AMPL * (0.50 * math.sin(2 * math.pi * 30.0 * n / FS + 0.7)
                + 0.30 * math.sin(2 * math.pi * 200.0 * n / FS + 2.1)
                + 0.20 * math.sin(2 * math.pi * 1000.0 * n / FS + 1.1))
    return int(round(l)), int(round(r))

class Biquad:

    def __init__(self, co):
        self.b0, self.b1, self.b2, self.a1, self.a2 = co
        self.x1 = self.x2 = self.y1 = self.y2 = 0

    def step(self, x):
        acc = (self.b0 * x + self.b1 * self.x1 + self.b2 * self.x2
               - self.a1 * self.y1 - self.a2 * self.y2)
        y = sat24(acc >> SHIFT)
        self.x2, self.x1 = self.x1, x
        self.y2, self.y1 = self.y1, y
        return y

def mix2(a, b, c0, c1):

    return sat24((c0 * a + c1 * b) >> SHIFT)

def run_engine():

    bq_l, bq_r = Biquad(LP), Biquad(LP)
    xf = [0, 0]
    outs_l, outs_r = [], []
    for n in range(N):
        xl, xr = stim(n)

        bus22 = xl
        side = mix2(bus22, xf[1], SIDE_W, SIDE_W)
        outs_l.append(mix2(bus22, bq_l.step(side), ADD_W, ADD_W))
        xf[0] = bus22

        bus22 = xr
        side = mix2(bus22, xf[0], SIDE_W, SIDE_W)
        outs_r.append(mix2(bus22, bq_r.step(side), ADD_W, ADD_W))
        xf[1] = bus22
    return outs_l, outs_r

out_l, out_r = run_engine()

def v4a_float():

    x1 = x2 = y1 = y2 = 0.0
    res_l, res_r = [], []
    for n in range(N):
        xl, xr = stim(n)
        s = xl + xr
        y = B0 * s + B1 * x1 + B2 * x2 - A1 * y1 - A2 * y2
        x2, x1 = x1, s
        y2, y1 = y1, y
        res_l.append(xl + y)
        res_r.append(xr + y)
    return res_l, res_r

def write_hex(name, vals, width):
    with open(os.path.join(OUTDIR, name), "w") as f:
        for v in vals:
            f.write("%0*x\n" % (width, v & ((1 << (4 * width)) - 1)))

write_hex("dynbass_lp.hex", LP, 8)
write_hex("dynbass_side.hex", [SIDE_W, SIDE_W], 8)
write_hex("dynbass_add.hex", [ADD_W, ADD_W], 8)
inp = []
for n in range(N):
    l, r = stim(n)
    inp += [l, r]
write_hex("dynbass_in.hex", inp, 6)
write_hex("dynbass_out_l.hex", out_l, 6)
write_hex("dynbass_out_r.hex", out_r, 6)

if "--report" in sys.argv:
    fl, fr = v4a_float()

    def rms(v):
        return math.sqrt(sum(x * x for x in v) / len(v))

    add_l = [out_l[n] - stim(n)[0] for n in range(N)]
    add_r = [out_r[n] - stim(n)[1] for n in range(N)]
    ref_l = [fl[n] - stim(n)[0] for n in range(N)]
    ref_r = [fr[n] - stim(n)[1] for n in range(N)]
    d_l = [add_l[n] - ref_l[n] for n in range(N)]
    d_r = [add_r[n] - ref_r[n] for n in range(N)]
    print("Q = %g（bass=%g%%），K=%g" % (Q, BASS_PCT, PRE_SCALE))
    print("55 Hz low-pass coefficients (Q3.15, numerator xK):", LP)
    print("side signal weight: %d  add-back weight: %d" % (SIDE_W, ADD_W))
    for tag, d, ref in (("R pass (filter input = L[n]+R[n], bit-for-bit the V4A input sequence)", d_r, ref_r),
                        ("L pass (filter input = L[n]+R[n−1], R delayed by 1 sample)", d_l, ref_l)):
        print("%s：" % tag)
        print("    added low-frequency rms = %.0f; rms difference against the V4A float model = %.0f => %+.1f dB"
              % (rms(ref), rms(d), 20 * math.log10(rms(d) / rms(ref))))
        print("    peak difference = %d (%.1f dBFS), relative to the dry peak 2e6 = %.2e"
              % (max(abs(x) for x in d), 20 * math.log10(max(abs(x) for x in d) / 2 ** 23),
                 max(abs(x) for x in d) / 2e6))
