% End-to-end noiseless complex channel, QR preprocessing, quantization and packing.
H = [1+.1i, .2-.1i, 0; -.1i, 1.3, .15i; 0, -.2+.1i, .95];
s = [3-3i; -1+3i; 1-1i];
p = receive16qam(H,H*s);
assert(isequal(p.x,[real(s);imag(s)]) && p.word==hex2dec('792'));
fprintf('Decision word: 0x%03X; integer Q12 L1 path cost: %d\n',p.word,p.cost_q12);
disp('Channel bus beats (96 bits each):'); disp(p.channel_hex);
disp('Observation bus beat:'); disp(p.data_hex);
