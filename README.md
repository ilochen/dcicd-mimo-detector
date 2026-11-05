# DCICD · 3 × 3 16-QAM MIMO detector

A fixed-point SystemVerilog receiver accepts a QR-preprocessed channel and a stream of observations. It detects three complex 16-QAM symbols per observation by searching six real axes. [Interactive survivor-search walkthrough](https://ilochen.github.io/dcicd-mimo-detector/)

## Run the complete regression

Use Verilator 5.052, a C++ toolchain, GNU Make, Python 3, Node.js 22+, and GNU Octave. From the repository root:

```sh
make test
```

This runs the MATLAB-compatible reference tests, generates input and expected-output vectors, checks the complete RTL against those vectors and an independent Python oracle, and runs the web model tests. CI invokes the same checks with a pinned Verilator image.

With MATLAB, the equivalent model and RTL workflow is:

```matlab
addpath('model')
test_model
generate_vectors('build/matlab-vectors.txt')
```

Then run `make rtl-test` from a shell in the same directory. See the [MATLAB guide](docs/matlab-guide.md) for complex channel preprocessing, data formats, and BER experiments. `make rtl-test` alone can also run the independent integer regression without MATLAB or Octave.

## Search architecture

Real coordinates are ordered `[I0 I1 I2 Q0 Q1 Q2]`. The search visits rows 5 through 0 of the upper triangular system. For each surviving parent, extend the suffix with each of `[3,1,-1,-3]`. Add the absolute residual for that row to the parent's accumulated cost. Retain the lowest **4, 16, 8, 8, 2, 1** candidates at successive layers. Equal scores are resolved by parent rank and then symbol order, including layers that retain every candidate. Beam pruning can discard the global minimum. The MATLAB exhaustive search over all 4,096 words provides an independent bound.

The active implementation registers one row per stage. Each stage uses signed shift/add products and a bitonic compare/exchange network to rank the expanded candidates. Registers carry the path, channel, observation, and validity through the corresponding stages. With the default input formats, metrics use a widened accumulator at the Q12 scale. This version changes the comparator topology from the original enumeration-list design. The archived 20 ns constraint is a target. Area, timing closure and power for the revised architecture require a new implementation run.

## Bus and clock contract

All input transactions are sampled at a rising edge with `i_valid=1`. Within the 96-bit bus, the most significant 16-bit lane comes first.

| Input | Accepted behavior |
|---|---|
| `flagChannelorData=0` | Four valid beats load 21 signed Q4.12 coefficients in upper-triangular row order. The last beat carries three coefficients and three ignored fields. The channel commits atomically at beat four. |
| `flagChannelorData=1` | Six signed Q6.10 observation words. Accept one observation per cycle once a channel is complete. During a reload, observations use the last committed channel. |
| `i_valid=0` | Insert a bubble. Channel-load position is preserved and older observations continue down the pipeline. |
| Active-high reset | Discard pending detections and partial channel loads. A new complete matrix is required. |

An observation accepted at edge **n** yields one `o_valid` result immediately after edge **n+6**. Only sample `OutData` when `o_valid` is high. Its three nibbles represent transmitters 0, 1 and 2, most significant first. In each nibble the upper two bits encode I and the lower two encode Q. Axis codes are `+1=00, +3=01, −1=10, −3=11`.

## Audit and reproduction

- `make characterize` runs the original noiseless identity-channel case on the repaired top. For `[3,-1,1,-3,3,-1]`, the expected and observed output is **0x792**. The bench fails on a wrong word or a wrong count of valid cycles.
- `make stream-test` checks every valid and invalid clock. It covers all 4,096 noiseless identity-channel words, dense signed channels, noisy observations, ties, input extremes, bubbles, back-to-back vectors, channel replacement with data in flight, and reset during a partial reload. When present, `build/matlab-vectors.txt` adds the generated complex-channel and quantization cases.
- `make archive-test` separately builds the historical RTL and reproduces **0x781** on the identity case. The preserved source also has its original 60-case metric-unit regression.

The original hand-expanded front end accumulated a signed residual and used an incorrect product in its second-layer metric. It also wrote beyond several declared observation-delay arrays and generated `o_valid` from a free-running counter. The corrected path uses the same absolute-residual recurrence at every row and pipelines each accepted observation explicitly.

| Path | Contents |
|---|---|
| `rtl/mimo_detector.sv` | Active detector and registered K-best row logic |
| `rtl/archive/mimo_detector.sv` | Previous course snapshot, built separately |
| `model/` | MATLAB preprocessing, quantization, detector, exhaustive oracle, test vectors, and BER experiment |
| `tests/` | SystemVerilog benches, Python scoreboard and JavaScript model checks |
| `constraints/interface.sdc` | Original design timing target |
| `docs/` | Standalone GitHub Pages walkthrough and model guide |
