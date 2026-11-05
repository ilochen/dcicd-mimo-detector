% Run in this directory in MATLAB. The first three axes are real, then imaginary.
R = [1 .25 0 0 0 0; 0 1 .25 0 0 0; 0 0 1 .25 0 0; ...
     0 0 0 1 .25 0; 0 0 0 0 1 .25; 0 0 0 0 0 1];
truth = [3; -1; 1; -3; 3; -1];
[x,cost] = kbest(R,R*truth);
assert(isequal(x,truth) && cost==0);
disp(x.');
