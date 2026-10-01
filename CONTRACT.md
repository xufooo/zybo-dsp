# Hardware/software contract

The DSP lives in the AXI register group of `axi_i2s_adi` itself, base
`0x43C00000`. The driver writes parameters; audio flows untouched otherwise.

**Frame rule.** One audio frame is 1041.7 clocks at 100 MHz / 48 kHz. A slot
table that cannot be executed inside that budget drops samples; the counter is
reported in `STATUS[31:24]` and never wraps silently. This is why the engine is
time-multiplexed rather than fully parallel, and why per-opcode cycle costs are
part of the contract.

**Fixed-point discipline.** Coefficients are Q3.15 (18 bit); samples are 24 bit;
the accumulator is 56 bit. Rounding is round-half-up with saturation on output,
so a chain of many sections does not accumulate truncation bias.

## v0.1.0 register map (word offsets)

| AXI word | Offset | Name | Meaning |
|---|---|---|---|
| 12 | `0x30` | `CTRL` | bit0 = full bypass (1); bit[3:1] = `NR_BANDS` (last active band + 1); bit4 = limiter bypass (1) |
| 13 | `0x34` | `CIDX` | coefficient index 0..29 (low 5 bits used) |
| 14 | `0x38` | `CDAT` | write → `coef[CIDX]` (low 18 bits), index auto-increments **next** cycle; read → sign-extended |
| 15/16/17 | `0x3C/0x40/0x44` | `LIM_THR/ATT/REL` | limiter threshold / attack / release (Q1.15) |

`idx = band*5 + k`, k = `b0,b1,b2,a1,a2`. A disabled band in the middle is a
unity section (`b0 = 32768`, rest 0) — there is no per-band bypass bit.

## v0.2.0 register map (slot-table engine; extends words 12..17)

| Word(s) | Name | Meaning |
|---|---|---|
| 12 | `CTRL` | v0.1 bits + bit16 COMMIT pulse (self-clearing) / bit17 BANK_SEL / bit18 LIM_TP (0 = legacy feedback limiter, 1 = true-peak) / bit19 HEADROOM |
| 13 | `CIDX` | widened to 16 bit (low 5 bits stay `band*5+k` compatible) |
| 14 | `CDAT` | writes parameter RAM (low 18 bits) + auto-increment; reads the inactive bank |
| 15..17 | `LIM_THR/ATT/REL` | unchanged semantics |
| 18/19 | `SLOT_ADDR/SLOT_DATA` | slot-table window, 8 words per slot: opcode/flags/n, coef_base, state_base, in_a, in_b, out_bus, param_base |
| 20 | `STATUS` | bit0 commit-pending / bit1 active bank / [15:8] live slots / [23:16] live biquad sections / [31:24] dropped-sample counter |
| 21..24 | `CAP0..CAP3` | `CAP0[31:16]=0x5A44` ("ZD") magic + version — the only way to tell a new bitstream from an old one; `CAP1` = opcode bitmap (bit1 BIQUAD, bit5 FIR, bit6 POLY, bit9 true-peak limiter, bit10 headroom, bit11 DYN); `CAP2/3` = limits and costs |
| 25 | `CAP4` | extended limits |

Opcodes: `NOP / BIQUAD / DYN / MIX2 / DELAY / FIR / POLY / SAT / ...`

### Atomic commit

A slot table takes effect on a frame boundary only: the driver fills the
inactive bank, pulses COMMIT, and the hardware swaps at the next frame start.
Until then `STATUS[0]` reports commit-pending and the audio path keeps running
the previous table. That is what removes the audible click a parameter write
would otherwise cause — a mid-frame swap would tear one sample period.

### Capabilities as the compatibility contract

Software never hard-codes "this bitstream has a convolver". It reads `CAP1`
and refuses, in software, a chain the hardware cannot execute; `CAP2/3/4`
carry the cycle costs and limits needed for that check. A bitstream too old to
report capabilities has no `CAP0` magic and is rejected outright rather than
driven blind.
