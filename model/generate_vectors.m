function counts = generate_vectors(destination)
% Emit one accepted DUT transaction per line: flag, 96-bit hex bus, 12-bit hex decision.
% Four flag=0 rows load a channel. Every flag=1 row is a separate observation.
% Bubbles, clock timing and valid checking belong to the RTL bench.
if nargin<1, destination = fullfile(fileparts(mfilename('fullpath')),'fixtures','vectors.txt'); end
parent = fileparts(destination);
if ~isempty(parent) && ~isfolder(parent), mkdir(parent); end
fid = fopen(destination,'w');
assert(fid~=-1,'Cannot write vector file.');
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

truth = [3;-1;1;-3;3;-1];
identity = receive16qam(eye(3),complex(truth(1:3),truth(4:6)));
assert(identity.word==hex2dec('792'));
batches = {identity};

% Deterministic stream exercises all antenna positions and signs.
% Park-Miller products fit exactly in doubles and do not depend on rng().
seed = 419;
levels = [3;1;-1;-3];
S = zeros(6,32);
for i=1:numel(S)
    seed = mod(16807*seed,2147483647);
    S(i) = levels(1+mod(seed,4));
end
S = complex(S(1:3,:),S(4:6,:));
H = [1.3+0.1i, -.28+.31i, .17-.11i; ...
    .11-.27i, 1.20+.02i, -.24+.12i; ...
    .36+.21i, -.13-.09i, 1.1+.15i];
noisy = H*S;
for n=1:size(S,2)
    for j=1:3
        noisy(j,n) = noisy(j,n) + complex(mod(3*n+j,9)-4,mod(n+2*j,7)-3)/3;
    end
end
batches{end+1} = receive16qam(H,[H*S,noisy]);

% Ties on every axis and half-LSB quantization boundary.
batches{end+1} = detector_packets(eye(6),[zeros(6,1), ...
    [2;0;-2;2;0;-2], [2;-2;0;0;2;-2]+[-1;1;1;-1;1;-1]*0.5/1024]);

% Force signed extremes, widened dot products and competing survivor metrics.
R = triu([ -8   8  -8   8  -8   8;
             0   8   8  -8   8  -8;
             0   0  -8   8  -8   8;
             0   0   0   8   8  -8;
             0   0   0   0  -8   8;
             0   0   0   0   0   8 ]);
Z = [32*(-1).^(1:6).', -32*(-1).^(1:6).', zeros(6,1)];
batches{end+1} = detector_packets(R,Z);
% Zero channel: every branch has equal cost, including large nonzero z.
batches{end+1} = detector_packets(zeros(6),[zeros(6,1),32*ones(6,1)]);

% Pruned beam and exhaustive search have distinct answers for this channel.
R = [1 2 -1 3 1 2; 0 1 0 -3 -1 3; 0 0 2 -4 4 -5; ...
     0 0 0 1 5 -2; 0 0 0 0 2 5; 0 0 0 0 0 2];
batches{end+1} = detector_packets(R,[-3;7;-9;3;5;2]);

counts = [0 0];
for k=1:numel(batches)
    p = batches{k};
    for b=1:4
        fprintf(fid,'0 %s 000\n',p.channel_hex{b});
    end
    for n=1:numel(p.word)
        fprintf(fid,'1 %s %03X\n',p.data_hex{n},p.word(n));
    end
    counts = counts + [4,numel(p.word)];
end
fprintf('Wrote %d channel beats and %d observations to %s\n',counts(1),counts(2),destination);
end
