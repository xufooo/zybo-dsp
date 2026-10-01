# zybo-dsp — FPGA audio DSP for Digilent ZYBO Rev B

Open-source, GPL-2.0-only parametric DSP chain living inside the I2S data path
of a ZYBO (XC7Z010) board. It takes I2S audio in, applies EQ / convolution /
limiting in programmable logic, and hands it back — all sample-synchronous at
48 kHz.

- Board: Digilent ZYBO Rev B · Codec: SSM2603 (PL-side I2C) · Toolchain: Vivado 2024.1
- This repo holds **our own RTL only**. Third-party IP (Digilent `axi_i2s_adi`,
  ADI HDL, Xilinx primitives) is fetched at build time, pinned by hash
  (`scripts/fetch_ip.sh`); see THIRD-PARTY.md.
- `CONTRACT.md` is the hardware/software contract (registers, opcodes,
  capabilities) — the software driver is written against it.
- **Sources ship without comments.** Design intent lives here and in
  CONTRACT.md; the code is meant to be read as it is.

## Layout

```
rtl/        our synthesizable modules (the product)
tb/         testbenches (run with xsim on a machine with Vivado)
xdc/        pin/timing constraints for ZYBO Rev B
scripts/    fetch vendor IP, patch it reproducibly, build BD → bitstream, run sims
```

`scripts/` holds only what you need to build and test: vendor-IP fetch/patch,
the Vivado build, and the simulation drivers. One-off synthesis probes from
development are not shipped; what they found is written up in CONTRACT.md.
Which DSP engine gets built is a matter of which **tag** you check out
(`v0.1.0` = `dsp_insert`, `v0.2.0`+ = `dsp_engine`).

## Build (needs Vivado 2024.1 on Linux, batch mode)

```bash
bash scripts/fetch_ip.sh                # vendor IP, sha256-asserted
bash scripts/build_retry.sh 3 -tclargs -force
# → build/fpga/zybo_audio/zybo_audio.{bit,xsa}  (build/ never enters git)
```

## Test

```bash
bash scripts/run_sim.sh                 # all testbenches, self-checking
bash scripts/run_sim.sh tb_biquad       # one of them
```

Each testbench prints PASS/FAIL lines and exits non-zero on failure.

## Versions

- `v0.1.0` — 6 fixed biquad stages + peak limiter inserted in parallel
  (`dsp_insert`). Fixed register map, coefficients in Q3.15.
