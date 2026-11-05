function [x, cost] = kbest(R, z)
% Algorithmic reference for a triangular six-dimensional 16-QAM problem.
% R and z are real-valued. Costs use absolute residuals as in the MCU.
assert(isequal(size(R), [6 6]) && isvector(z) && numel(z)==6);
assert(isequal(R,triu(R)), 'R must be upper triangular.');
z = z(:);
keep = [4 16 8 8 2 1];
symbols = [3 1 -1 -3];
paths = zeros(1,6);
costs = 0;
for depth = 1:6
    i = 7-depth;
    next = repelem(paths,4,1);
    next(:,i) = repmat(symbols(:),size(paths,1),1);
    scores = repelem(costs(:),4) + abs(z(i) - next(:,i:end)*R(i,i:end).');
    [~,order] = sort(scores,'ascend');
    ids = order(1:keep(depth));
    paths = next(ids,:);
    costs = scores(ids);
end
x = paths(1,:).';
cost = costs(1);
end
