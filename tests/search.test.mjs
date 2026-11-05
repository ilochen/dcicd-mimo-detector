import test from 'node:test';
import assert from 'node:assert/strict';
import {search,channel,sent,observed,budgets} from '../docs/search.mjs';
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
