# MATLAB reference receiver

Run these commands from the repository root in MATLAB or GNU Octave:

```matlab
addpath('model');
test_model;
generate_vectors('build/matlab-vectors.txt');
ber_experiment([0 8 16 24],250,73);
```

All functions use base numerical operations. The wire model implements the default 16-bit RTL configuration. The BER driver exercises the algorithmic receiver; the file-driven RTL regression compares packed detector decisions on specified bus transactions.

## From complex samples to detector inputs

For complex channel `H` (3 × 3) and received observations `Y` (3 × N), call `p = receive16qam(H,Y)`. The transmitted symbol vector uses unnormalized levels `{-3,-1,+1,+3}` on each axis. The real equivalent is

```
A = [real(H) -imag(H); imag(H) real(H)];
b = [real(Y); imag(Y)];
A = Q*R,   Z = Q.'*b
```

QR acts on the real matrix, with nonnegative diagonal entries in `R`. Axes 1–3 are real parts, and axes 4–6 are imaginary parts. If triangular inputs are already available, use `p = detector_packets(R,Z)`.

`p.r_words` and `p.z_words` are signed integer codes. Round to nearest with halfway values away from zero, then saturate to [-32768,32767]. The R scale is 4096, and the Z scale is 1024. `p.r_clipped` and `p.z_clipped` identify saturated input fields. After quantization, the path metric adds exact integer absolute residuals. Each Z word is multiplied by four to align it to the R scale. The bounded integer calculations fit exactly in MATLAB doubles. The score in `p.cost_q12` is divided by 4096 to express it in physical residual units.

`kbest` visits axes 6,5,…,1 and keeps 4,16,8,8,2,1 paths. It sorts by score on **every** axis. Equal scores retain parent rank first, then symbol order +3,+1,-1,-3. Request a third output from `kbest` to inspect the survivor paths and costs at each level. `exhaustive_l1` independently evaluates all 4096 symbol vectors; for arbitrary noisy channels its optimal cost is a lower bound on the pruned search.

## Bus files

`generate_vectors` writes one accepted transaction per line, without a header:

```
0 100000000000000000000000 000
```

Column 1 selects a channel beat (0) or observation (1). Column 2 is exactly 24 hexadecimal digits: six signed two's-complement words, first word in bits 95:80. Four channel beats carry the 21 entries of the upper triangle in row order plus three zero padding words. Each observation is a single beat. Column 3 is the expected three-digit result for observations; channel rows carry the placeholder 000. Clock-level valid gaps can be inserted by a consuming bench.

The output nibbles are ordered by antenna. Within each nibble, the upper two bits encode the real component and the lower two the imaginary component. The axis codes for +1,+3,−1,−3 are 00,01,10,11 respectively. For `[3;-1;1;-3;3;-1]` the packed word is `792`. The fixture also covers a dense complex channel with clean and perturbed observations, tie cases, clipped triangular systems, and a zero channel.

## BER experiment

`ber_experiment(esn0_db, nframes, seed)` returns the tested bit count, errors, BER, and frames with clipping. Each frame carries three independently chosen symbols and twelve labelled bits. Independent complex Gaussian channel entries have mean power 1/3, giving mean received signal power 10 per complex receive coordinate for the unnormalized alphabet. Each real noise component has variance `10/(2*10^(EsN0_dB/10))`. The horizontal axis is average receive Es/N0. All SNR points reuse common random draws. Increase the frame count for statistical precision; the short default is a reproducible smoke experiment. Random streams can differ between MATLAB and Octave releases. The RTL stimulus generator uses a separate deterministic sequence.

The L1 detector uses the rotated, QR-domain absolute residual. The Monte Carlo output characterizes that quantized algorithmic model. The expected bus words in the vectors are the appropriate comparison for RTL decisions at asserted output-valid edges.
