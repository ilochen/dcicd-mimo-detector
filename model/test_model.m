function test_model()
% Run with addpath('model'); test_model from the repository root.
% Check axis codes, nibble ordering, signed limits and halfway rounding.
levels = [3;1;-1;-3];
gray = [1;0;2;3];
for r=1:4
    for j=1:4
        nib = 4*gray(r)+gray(j);
        assert(pack_symbols([levels(r);1;1;levels(j);1;1])==256*nib);
    end
end
truth = [3;-1;1;-3;3;-1];
assert(pack_symbols(truth)==hex2dec('792'));
[words,clipped] = quantize_words([-9,-8,-.5/4096,0,.5/4096,32767/4096,8,9],12);
assert(isequal(words,[-32768,-32768,-1,0,1,32767,32767,32767]));
assert(isequal(clipped,logical([1 0 0 0 0 0 1 1])));
p = detector_packets(eye(6),truth);
assert(p.word==hex2dec('792') && p.cost_q12==0);
assert(strcmp(p.channel_hex{1},'100000000000000000000000'));
assert(strcmp(p.channel_hex{4},'100000001000000000000000'));
assert(strcmp(p.data_hex{1},'0C00FC000400F4000C00FC00'));

% All-equal alternatives retain original parent then symbol order, even at
% layers 1 and 2 that keep all candidates.
[xt,c,trace] = kbest(zeros(6),zeros(6,1));
assert(isequal(xt,3*ones(6,1)) && c==0);
assert(isequal(trace{1}.paths(:,6),levels));
assert(isequal(trace{2}.paths(:,6),repelem(levels,4,1)));
assert(isequal(trace{2}.paths(:,5),repmat(levels,4,1)));
assert(all(cellfun(@(s) all(diff(s.costs)>=0),trace)));
assert(isequal(cellfun(@(s) numel(s.costs),trace),[4 16 8 8 2 1]));

% Real equivalent is formed before QR; mixing real/imaginary axes incorrectly
% can pass a purely real diagonal test. Verify reconstruction and projections.
H = [1.2+.2i,-.15+.3i,.12-.08i; .1-.2i,1+.25i,.2+.1i; .2+.12i,-.18+.03i,1.4-.1i];
tx = complex(truth(1:3),truth(4:6));
y = H*tx;
p = receive16qam(H,y);
A = [real(H),-imag(H);imag(H),real(H)];
assert(norm(p.Q*p.R-A,'fro') < 1e-11 && norm(p.Q.'*p.Q-eye(6),'fro') < 1e-11);
assert(all(diag(p.R)>=0) && norm(p.Z-p.R*truth)<1e-11);
assert(isequal(p.x,truth) && p.word==hex2dec('792'));
[x_oracle,bound] = exhaustive_l1(p.r_words,4*p.z_words);
assert(isequal(x_oracle,p.x) && bound==p.cost_q12);
% Even when noise pushes the beam away from truth, its reported metric must
% equal its own residual and may never beat exhaustive search.
p = receive16qam(H,y+[.8-.1i;-.2+.75i;1.7+1.2i]);
[~,bound] = exhaustive_l1(p.r_words,4*p.z_words);
assert(p.cost_q12==sum(abs(4*p.z_words-p.r_words*p.x)) && p.cost_q12>=bound);
% Directed noisy case where pruning matters. The K-best decision has an L1
% score of 23 while a full 4096-leaf search finds score 13.
R = [1 2 -1 3 1 2; 0 1 0 -3 -1 3; 0 0 2 -4 4 -5; ...
     0 0 0 1 5 -2; 0 0 0 0 2 5; 0 0 0 0 0 2];
z = [-3;7;-9;3;5;2];
[xk,kcost] = kbest(R,z);
[~,fullcost] = exhaustive_l1(R,z);
assert(isequal(xk,[-3;3;-1;1;1;1]) && kcost==23 && fullcost==13);
% Deliberately exercise widened residual accumulations beyond 20-bit signed.
[~,extreme] = kbest(zeros(6),repmat(-131072,6,1));
assert(extreme==786432);

% Confirm BER accounting and reproducibility without relying on a particular
% randn algorithm across different MATLAB/Octave releases.
stats = ber_experiment([4 18],8,42);
again = ber_experiment([4 18],8,42);
assert(isequal(stats,again) && all(stats.bits==96));
assert(all(stats.errors>=0 & stats.errors<=stats.bits));
disp('PASS: quantization, packing, tie order, QR, exhaustive L1 and BER accounting.');
end
