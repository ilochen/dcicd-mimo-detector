function [x,cost] = exhaustive_l1(R,z)
% Validation oracle: evaluate all 4^6 leaf vectors, independently of beam search.
% Equal-cost optimal vectors can have different packed words.
assert(isequal(size(R),[6,6]) && numel(z)==6);
candidates = zeros(4096,6);
levels = [3;1;-1;-3];
indices = (0:4095).';
for i=1:6
    candidates(:,i) = levels(1+mod(floor(indices/4^(i-1)),4));
end
residual = bsxfun(@minus,candidates*double(R).',double(z(:)).');
[cost,idx] = min(sum(abs(residual),2));
x = candidates(idx,:).';
end
