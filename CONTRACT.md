# Hardware/software contract

The DSP lives in the AXI register group of `axi_i2s_adi` itself, base
`0x43C00000`. The driver writes parameters; audio flows untouched otherwise.

**Frame rule.** One audio frame is 1041.7 clocks at 100 MHz / 48 kHz. A slot
table that cannot be executed inside that budget drops samples; the counter is
reported in `STATUS[31:24]` and never wraps silently. This is why the engine
is time-multiplexed rather than fully parallel, and why per-opcode cycle costs
are part of the contract.

**Fixed-point discipline.** Coefficients are Q3.15 (18 bit); samples are 24 bit;
the accumulator is 56 bit. A slot's cost is counted in clock cycles, and the
budget check is the driver's job (`CAP2`/`CAP3`/`CAP4` report the numbers it
needs).

## v0.1.0 register map (word offsets)

| AXI word | Offset | Name | Meaning |
|---|---|---|---|
| 12 | `0x30` | `CTRL` | bit0 = full bypass (1); bit[3:1] = `NR_BANDS` (last active band + 1); bit4 = limiter bypass (1) |
| 13 | `0x34` | `CIDX` | coefficient index 0..29 (low 5 bits used) |
| 14 | `0x38` | `CDAT` | write → `coef[CIDX]` (low 18 bits), index auto-increments **next** cycle; read → sign-extended |
| 15/16/17 | `0x3C/0x40/0x44` | `LIM_THR/ATT/REL` | limiter threshold / attack / release (Q1.15) |

`idx = band*5 + k`, k = `b0,b1,b2,a1,a2`. A disabled band in the middle is a
unity section (`b0 = 32768`, rest 0) — there is no per-band bypass bit.

The engine computes in a **floating-point-aware** pipeline: it keeps 56-bit
accumulators and rounds (round-half-up) + saturates on the way out, so a chain
of 24 sections does not accumulate truncation bias.
