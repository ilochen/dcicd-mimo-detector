import {search,channel,sent,observed,budgets} from './search.mjs';
const $ = id=>document.getElementById(id);
const perturb = [0.8,-0.4,0.6,-1.1,0.3,1.7];
let index=0;
function draw(){
 const z=observed.map((v,i)=>v+(+$('noise').value)*perturb[i]);
 const layer=search(channel,z)[index];
 $('progress').textContent='Layer '+(index+1)+' / 6';
 $('prev').disabled=index===0;$('next').disabled=index===5;
 $('stages').replaceChildren(...budgets.map((k,i)=>{
  const b=document.createElement('button'); b.textContent='s'+(6-i)+' · K='+k;
  b.setAttribute('aria-pressed',String(i===index));b.onclick=()=>{index=i;draw();};return b;
 }));
 $('matrix').innerHTML='<table><caption>[R | z] · active row '+(layer.row+1)+'</caption><tbody>'+
 channel.map((r,i)=>'<tr class="'+(i===layer.row?'active':'')+'">'+[...r,z[i]].map(v=>'<td>'+Number(v.toFixed(2))+'</td>').join('')+'</tr>').join('')+'</tbody></table>';
 $('survivors').innerHTML='<table><caption>'+layer.paths.length+' retained from '+layer.count+' extensions</caption><thead><tr><th>Path [s₁ … s₆]</th><th>Cost</th></tr></thead><tbody>'+
 layer.paths.map(p=>'<tr><td>'+p.vector.map(v=>v===null?'·':v).join('　')+'</td><td>'+p.cost.toFixed(2)+'</td></tr>').join('')+'</tbody></table>';
 $('status').textContent=index<5?'Expand each survivor with s'+(layer.row+1)+' ∈ {−3, −1, 1, 3}.':('Detected ['+layer.paths[0].vector.join(', ')+']. Transmitted ['+sent.join(', ')+'].');
}
$('noise').onchange=()=>{index=0;draw();};
$('prev').onclick=()=>{index--;draw();};$('next').onclick=()=>{index++;draw();};draw();
