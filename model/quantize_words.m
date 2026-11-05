function [words,clipped] = quantize_words(a,fraction_bits)
% Signed 16-bit integer codes held in doubles for exact widened arithmetic.
% Nearest integer; halfway values round away from zero. Saturate on input.
assert(isnumeric(a) && isreal(a) && all(isfinite(a(:))), 'Input must be finite and real.');
assert(isscalar(fraction_bits) && fraction_bits==fix(fraction_bits) && ...
    fraction_bits>=0 && fraction_bits<=15, 'Invalid fraction width.');
raw = round(double(a)*2^fraction_bits);
clipped = raw < -32768 | raw > 32767;
words = min(32767,max(-32768,raw));
end
