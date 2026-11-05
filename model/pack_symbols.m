function word = pack_symbols(x)
% Per-axis Gray codes: +1=00, +3=01, -1=10, -3=11.
% Each nibble = {real[1:0], imaginary[1:0]}; antenna 1 is most significant.
assert(isequal(size(x),[6,1]) && all(ismember(x,[-3 -1 1 3])), ...
    'Input must contain three real then three imaginary axis decisions.');
codes = [3;2;0;1];
bits = codes((x+5)/2);
nibbles = 4*bits(1:3) + bits(4:6);
word = uint16([256 16 1]*nibbles);
end
