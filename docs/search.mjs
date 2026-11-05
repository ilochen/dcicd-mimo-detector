// Real-valued architectural reference. Ties retain the original branch order.
export const budgets = [4,16,8,8,2,1];
export const symbols = [3,1,-1,-3];
export function search(R, z) {
  let paths = [{vector: Array(6).fill(null), cost: 0}];
  const layers = [];
  for (let row=5; row>=0; row--) {
    const expanded = [];
    for (const parent of paths) {
      const history = parent.vector.slice(row+1).reduce(
        (residual, value, j) => residual-R[row][row+1+j]*value, z[row]);
      for (const symbol of symbols) {
        const vector = parent.vector.slice();
        vector[row] = symbol;
        const residual = history-R[row][row]*symbol;
        expanded.push({vector, residual, cost: parent.cost+Math.abs(residual)});
      }
    }
    expanded.sort((a,b)=>a.cost-b.cost);
    paths = expanded.slice(0,budgets[5-row]);
    layers.push({row, count: expanded.length, paths});
  }
  return layers;
}
export const channel = [
 [1.5,.25,0,.25,0,0],[0,1.25,.5,0,0,.25],[0,0,1,.25,.25,0],
 [0,0,0,1.25,.25,.5],[0,0,0,0,1.5,.25],[0,0,0,0,0,1.25]
];
export const sent = [3,-1,1,-3,3,-1];
export const observed = channel.map(row=>row.reduce((sum,r,i)=>sum+r*sent[i],0));
