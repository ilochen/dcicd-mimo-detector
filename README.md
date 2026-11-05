# DCICD · 3 × 3 MIMO detector

A fixed-point SystemVerilog receiver for 16-QAM. The detector takes a QR-preprocessed channel matrix R and observation z, converts the symbol search into six real dimensions, and uses a different survivor budget at each layer. [Project walkthrough](https://ilochen.github.io/dcicd-mimo-detector/)

## Architecture

A 3 × 3 complex system becomes six real coordinates: three real components followed by three imaginary components. From the bottom of the upper triangular matrix upwards, each coordinate admits four symbols (−3, −1, +1, +3). The survivor budgets are **4, 16, 8, 8, 2, 1**. A history unit subtracts already-selected off-diagonal contributions, and a metric unit adds the absolute residual for the current diagonal term. Comparator trees and enumerators select candidates, while registers align observations with survivor histories.

## Interface

- `clk` and active-high `rst` control the top module.
- `InData[95:0]` packs six signed 16-bit quantities, most-significant field first. Four valid input beats load the 21 upper-triangular coefficients in row order. The fourth beat has three padding fields. The original top advances by its FSM; the declared `flagChannelorData` port is unused.
- In the calculation state the same bus carries six z coordinates. The defaults give R 12 fractional bits and z 10. z is shifted to align the binary points.
- `OutData[11:0]` holds three four-bit detections. The first nibble combines real axis 0 with imaginary axis 3. The module exposes `o_valid`; in this source it is driven by a counter threshold rather than a per-vector valid pipeline.

## Reproduce

With Verilator 5, a C++ compiler and Make, run `make test`. This elaborates the complete top and exercises the MCU for 60 signed residual/constellation combinations. In MATLAB, run `cd model; example` to recover a known transmitted vector from a triangular channel. The MATLAB algorithmic reference was written for this package, independently of the RTL. It uses floating-point arithmetic and direct beam expansion.

## Scope of validation

The supplied course folder contains the detector and a handwritten SDC targeting 20 ns. The local RTL had a procedural loop indexed by a genvar; the repository changes that index to a local integer so it elaborates. The detector still contains width, incomplete-case and combinational-loop warnings, and early hard-wired candidate calculations differ from the general MCU formula. Top-level valid/data alignment and detector decisions require an end-to-end RTL vector bench before using this snapshot for BER, latency, timing closure, or throughput claims. Lint and metric tests establish a narrower result.

## Files

| Path | Contents |
|---|---|
| `rtl/mimo_detector.sv` | Detector top, search layers, enumeration lists, history and metric units, comparator trees |
| `model/` | MATLAB beam-search reference and deterministic example |
| `tests/` | Self-checking SystemVerilog arithmetic test |
| `constraints/interface.sdc` | Original design timing target and I/O assumptions |
| `docs/` | Standalone GitHub Pages walkthrough |
