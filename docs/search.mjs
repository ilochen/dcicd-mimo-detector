// Integer reference for the default 16-bit input formats. Scores are displayed
// in real units; all decisions use the exact integer residual in R's Q12 units.
export const budgets = [4, 16, 8, 8, 2, 1];
export const symbols = [3, 1, -1, -3];
export const channel = [
  [1.5, .25, 0, .25, 0, 0], [0, 1.25, .5, 0, 0, .25],
  [0, 0, 1, .25, .25, 0], [0, 0, 0, 1.25, .25, .5],
  [0, 0, 0, 0, 1.5, .25], [0, 0, 0, 0, 0, 1.25]
];
export const identity = Array.from({length:6}, (_, i) =>
  Array.from({length:6}, (_, j) => Number(i === j)));
export const sent = [3, -1, 1, -3, 3, -1];
export const observed = observation(channel);

export function observation(R) {
  return R.map(row => row.reduce((sum, coeff, i) => sum + coeff * sent[i], 0));
}

function signedWord(value, frac) {
  if (!Number.isFinite(value)) throw new RangeError('Inputs must be finite.');
  const rounded = Math.sign(value) * Math.round(Math.abs(value) * 2 ** frac);
  return Math.min(32767, Math.max(-32768, rounded));
}

export function inputWords(R, z) {
  if (R.length !== 6 || z.length !== 6 || R.some(row => row.length !== 6))
    throw new RangeError('Expected a real 6×6 channel and a six-coordinate observation.');
  if (R.some((row, i) => row.some((v, j) => j < i && v !== 0)))
    throw new RangeError('The channel must be upper triangular.');
  return {R: R.map(row => row.map(v => signedWord(v, 12))), z: z.map(v => signedWord(v, 10))};
}

export function search(R, z) {
  const words = inputWords(R, z);
  let paths = [{vector:Array(6).fill(null), rawCost:0}];
  const layers = [];
  for (let row = 5; row >= 0; row--) {
    const expanded = [];
    for (const parent of paths) {
      let history = words.z[row] * 4;
      for (let j = row + 1; j < 6; j++) history -= words.R[row][j] * parent.vector[j];
      for (const s of symbols) {
        const vector = parent.vector.slice();
        vector[row] = s;
        const residual = history - words.R[row][row] * s;
        const rawCost = parent.rawCost + Math.abs(residual);
        expanded.push({vector, residual:residual / 4096, rawCost, cost:rawCost / 4096, order:expanded.length});
      }
    }
    expanded.sort((a, b) => a.rawCost - b.rawCost || a.order - b.order);
    paths = expanded.slice(0, budgets[5 - row]);
    layers.push({row, count:expanded.length, paths});
  }
  return layers;
}

export function packedWord(vector) {
  const bits = new Map([[1, 0], [3, 1], [-1, 2], [-3, 3]]);
  if (vector.length !== 6 || vector.some(s => !bits.has(s)))
    throw new RangeError('Expected six detected ±1 or ±3 amplitudes.');
  let word = 0;
  for (let i = 0; i < 3; i++)
    word = (word << 4) | (bits.get(vector[i]) << 2) | bits.get(vector[i + 3]);
  return '0x' + word.toString(16).toUpperCase().padStart(3, '0');
}
