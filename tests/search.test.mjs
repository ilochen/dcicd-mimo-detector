import test from 'node:test';
import assert from 'node:assert/strict';
import {search,channel,sent,observed,budgets,identity,inputWords,packedWord} from '../docs/search.mjs';
test('all six layers retain the designed survivor counts and recover the transmitted vector',()=>{
 const layers=search(channel,observed);
 assert.deepEqual(layers.map(v=>v.paths.length),budgets);
 assert.deepEqual(layers.map(v=>v.count),[4,16,64,32,32,8]);
 assert.deepEqual(layers.at(-1).paths[0].vector,sent);
 assert.equal(layers.at(-1).paths[0].cost,0);
});
test('reported costs equal independent absolute residual sums for perturbed observations',()=>{
 const z=observed.map((v,i)=>v+(i%2===0?.5:-.25));
 for(const {row,paths} of search(channel,z))for(const p of paths){
   const cost=channel.slice(row).reduce((total,r,i)=>total+Math.abs(z[row+i]-r.reduce((s,c,j)=>s+c*(p.vector[j]??0),0)),0);
   assert.equal(cost,p.cost);
 }
});

test('original identity regression yields word 792 using real then imaginary coordinates',()=>{
  const winner=search(identity,sent).at(-1).paths[0];
  assert.deepEqual(winner.vector,[3,-1,1,-3,3,-1]);
  assert.equal(packedWord(winner.vector),'0x792');
  assert.equal(winner.rawCost,0);
});

test('constellation ties preserve parent rank before symbol order',()=>{
  const layers=search(identity,Array(6).fill(0));
  assert.deepEqual(layers[0].paths.map(p=>p.vector[5]),[1,-1,3,-3]);
  assert.deepEqual(layers[1].paths.slice(0,4).map(p=>p.vector.slice(-2)),[[1,1],[-1,1],[1,-1],[-1,-1]]);
  assert.equal(packedWord(layers[5].paths[0].vector),'0x000');
});

test('input encoding rounds signed half steps away from zero and clips both rails',()=>{
  const R=identity.map(r=>r.slice());
  R[0]=[-8.5,8.5,-.5/4096,.5/4096,0,0];
  const words=inputWords(R,[-40,40,-.5/1024,.5/1024,0,0]);
  assert.deepEqual(words.R[0],[-32768,32767,-1,1,0,0]);
  assert.deepEqual(words.z,[-32768,32767,-1,1,0,0]);
});

test('noisy bounded search can prune the exhaustive minimum',()=>{
  const R=[
    [.75,-1.5,-1.5,-.75,-.25,-1.5],[0,1.5,-.25,.5,-1.5,-1],
    [0,0,.5,.5,-1.25,-.25],[0,0,0,1.25,.75,-1],[0,0,0,0,1,.5],[0,0,0,0,0,.75]
  ],z=[-.25,3.25,6.25,3.5,-5,-2];
  let exhaustiveCost=Infinity;
  for(let k=0;k<4096;k++){
    const vector=Array.from({length:6},(_,i)=>2*((k>>(2*i))&3)-3);
    const cost=R.reduce((sum,row,i)=>sum+Math.abs(z[i]-row.reduce((v,r,j)=>v+r*vector[j],0)),0);
    exhaustiveCost=Math.min(exhaustiveCost,cost);
  }
  const winner=search(R,z).at(-1).paths[0];
  assert.equal(exhaustiveCost,4.5);
  assert.equal(winner.cost,5.5);
  assert.deepEqual(winner.vector,[-3,-3,3,1,-3,-3]);
});
