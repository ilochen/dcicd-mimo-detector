function stats = ber_experiment(esn0_db,nframes,seed)
% Toolbox-free Monte Carlo BER for the quantized detector reference.
% Independent flat Rayleigh channel per frame, three unnormalized 16-QAM symbols.
if nargin<1, esn0_db = [0 8 16 24]; end
if nargin<2, nframes = 250; end
if nargin<3, seed = 73; end
assert(isvector(esn0_db) && isreal(esn0_db) && all(isfinite(esn0_db)), 'Invalid Es/N0.');
assert(isscalar(nframes) && nframes==floor(nframes) && nframes>=1, 'Invalid frame count.');
old_state = rng;
cleanup = onCleanup(@() rng(old_state)); %#ok<NASGU>
levels = [3;1;-1;-3];
stats = struct('esn0_db',esn0_db(:),'errors',zeros(numel(esn0_db),1), ...
    'bits',repmat(12*nframes,numel(esn0_db),1),'clipped_frames',zeros(numel(esn0_db),1));
for k=1:numel(esn0_db)
    % Use common random channel/symbol/noise draws across SNRs.
    rng(seed,'twister');
    sigma = sqrt(10/(2*10^(esn0_db(k)/10)));
    for f=1:nframes
        axes = levels(randi(4,6,1));
        tx = complex(axes(1:3),axes(4:6));
        H = (randn(3)+1i*randn(3))/sqrt(6);
        noise = sigma*(randn(3,1)+1i*randn(3,1));
        p = receive16qam(H,H*tx+noise);
        difference = bitxor(pack_symbols(axes),p.word);
        for b=1:12
            stats.errors(k) = stats.errors(k) + double(bitget(difference,b));
        end
        stats.clipped_frames(k) = stats.clipped_frames(k) + ...
            (any(p.r_clipped(:)) || any(p.z_clipped(:)));
    end
end
stats.ber = stats.errors./stats.bits;
fprintf('Es/N0(dB)   errors / bits       BER       clipped frames\n');
for k=1:numel(esn0_db)
    fprintf('%8.2f   %5d / %-8d   %.6g    %d\n',stats.esn0_db(k), ...
        stats.errors(k),stats.bits(k),stats.ber(k),stats.clipped_frames(k));
end
end
