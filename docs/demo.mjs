import {search, channel, identity, sent, observation, budgets, inputWords, packedWord} from './search.mjs';
const $ = id => document.getElementById(id);
const perturb = [.8, -.4, .6, -1.1, .3, 1.7];
let index = 0;

function draw() {
  const R = $('channel').value === 'identity' ? identity : channel;
  const mode = $('noise').value;
  const z = observation(R).map((v, i) => mode === 'zero' ? 0 : v + (mode === 'perturbed' ? perturb[i] : 0));
  const layer = search(R, z)[index];
  const words = inputWords(R, z);
  $('progress').textContent = 'Layer ' + (index + 1) + ' / 6';
  $('prev').disabled = index === 0;
  $('next').disabled = index === 5;
  $('stages').replaceChildren(...budgets.map((k, i) => {
    const b = document.createElement('button');
    b.textContent = 's' + (6 - i) + ' · K=' + k;
    b.setAttribute('aria-pressed', String(i === index));
    b.onclick = () => { index = i; draw(); };
    return b;
  }));
  $('matrix').innerHTML = '<table><caption>Quantized [R | z] · active row ' + (layer.row + 1) + '</caption><tbody>' +
    words.R.map((row, i) => '<tr class="' + (i === layer.row ? 'active' : '') + '">' +
      [...row.map(v => v / 4096), words.z[i] / 1024].map(v => '<td>' + Number(v.toFixed(4)) + '</td>').join('') +
      '</tr>').join('') + '</tbody></table>';
  $('survivors').innerHTML = '<table><caption>' + layer.paths.length + ' retained from ' + layer.count +
    ' extensions</caption><thead><tr><th>Path [s₁ … s₆]</th><th>Cost</th></tr></thead><tbody>' +
    layer.paths.map(p => '<tr><td>' + p.vector.map(v => v === null ? '·' : v).join('　') +
      '</td><td>' + Number(p.cost.toFixed(4)) + '</td></tr>').join('') + '</tbody></table>';
  const best = layer.paths[0].vector;
  $('status').textContent = index < 5 ?
    'Row ' + (layer.row + 1) + ' extends each retained path in the order +3, +1, −1, −3.' :
    'Detected [' + best.join(', ') + '] · ' + packedWord(best) +
    (mode === 'zero' ? '. Zero observation illustrates equal-cost branches.' :
      '. Transmitted [' + sent.join(', ') + '] · ' + packedWord(sent) + '.');
}
function resetLayer() { index = 0; draw(); }
$('channel').onchange = resetLayer;
$('noise').onchange = resetLayer;
$('prev').onclick = () => { index--; draw(); };
$('next').onclick = () => { index++; draw(); };
draw();
