function p = detector_packets(R,Z)
% Convert a triangular real system to the default RTL port format and decode.
% Z contains one six-axis observation per column, sharing the same channel.
assert(isnumeric(R) && isequal(size(R),[6,6]) && isequal(R,triu(R)), ...
    'Expected 6-by-6 upper triangular R.');
if isvector(Z), Z = Z(:); end
assert(isnumeric(Z) && size(Z,1)==6 && size(Z,2)>=1, 'Z must have six rows.');
[p.r_words,p.r_clipped] = quantize_words(R,12);
[p.z_words,p.z_clipped] = quantize_words(Z,10);
% Row-major packed upper triangle; six 16-bit fields in each 96-bit word.
coeffs = zeros(24,1);
cursor = 1;
for row=1:6
    width = 7-row;
    coeffs(cursor:cursor+width-1) = p.r_words(row,row:6).';
    cursor = cursor+width;
end
p.channel_hex = cell(4,1);
for i=1:4
    p.channel_hex{i} = bus_hex(coeffs(6*i-5:6*i));
end
n = size(Z,2);
p.data_hex = cell(1,n);
p.x = zeros(6,n);
p.cost_q12 = zeros(1,n);
p.word = zeros(1,n,'uint16');
for i=1:n
    p.data_hex{i} = bus_hex(p.z_words(:,i));
    % Widen z from Q6.10 to the R scale (Q4.12) before any multiplication.
    [p.x(:,i),p.cost_q12(i)] = kbest(p.r_words,4*p.z_words(:,i));
    p.word(i) = pack_symbols(p.x(:,i));
end
end

function h = bus_hex(fields)
h = reshape(dec2hex(mod(fields,65536),4).',1,[]);
end
