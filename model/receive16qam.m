function p = receive16qam(H,Y)
% H: 3-by-3 complex channel; Y: 3-by-N received complex samples, Y=H*S+N.
% Unnormalized QAM symbols have per-axis levels {-3,-1,+1,+3}.
assert(isnumeric(H) && isequal(size(H),[3,3]) && all(isfinite(H(:))), ...
    'H must be a finite 3-by-3 channel.');
if isvector(Y), Y = Y(:); end
assert(isnumeric(Y) && size(Y,1)==3 && size(Y,2)>=1 && all(isfinite(Y(:))), ...
    'Y must contain three complex samples per column.');
A = [real(H) -imag(H); imag(H) real(H)];
b = [real(Y);imag(Y)];
[Q,R] = qr(A,0);
% QR sign convention differs across libraries. Enforce nonnegative diagonals.
sgn = sign(diag(R));
sgn(sgn==0) = 1;
Q = Q*diag(sgn);
R = triu(diag(sgn)*R);
Z = Q.'*b;
p = detector_packets(R,Z);
p.Q = Q;
p.R = R;
p.Z = Z;
end
