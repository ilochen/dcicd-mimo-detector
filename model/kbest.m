function [x,cost,trace] = kbest(R,z)
% Six-layer real beam search using accumulated absolute residual.
% Inputs may be ordinary real data or exact integer codes in a common scale.
assert(isnumeric(R) && isreal(R) && isequal(size(R),[6,6]) && ...
    all(isfinite(R(:))) && isequal(R,triu(R)), 'R must be finite, real and upper triangular.');
assert(isnumeric(z) && isreal(z) && isvector(z) && numel(z)==6 && all(isfinite(z)), ...
    'z must contain six finite real values.');
R = double(R);
z = double(z(:));
keep = [4 16 8 8 2 1];
alphabet = [3;1;-1;-3];
paths = zeros(1,6);
costs = 0;
trace = cell(1,6);
for depth = 1:6
    row = 7-depth;
    % Enumeration order is also the tie breaker: parent rank, then alphabet.
    next = repelem(paths,4,1);
    next(:,row) = repmat(alphabet,size(paths,1),1);
    delta = abs(z(row) - next(:,row:end)*R(row,row:end).');
    scores = repelem(costs(:),4,1) + delta;
    serial = (1:numel(scores)).';
    [~,order] = sortrows([scores,serial],[1 2]);
    ids = order(1:keep(depth));
    paths = next(ids,:);
    costs = scores(ids);
    if nargout > 2
        trace{depth} = struct('row',row,'paths',paths,'costs',costs);
    end
end
x = paths(1,:).';
cost = costs(1);
end
