'use strict';
const assert = require('assert/strict');
const fs = require('fs');
const path = require('path');
const {resizeSprite, flattenTerrain, importPack} = require('./import_environment.js');
const identity={saturation:1,gain:[1,1,1]};
// Transparent black must not darken an opaque red edge after downsampling.
const resized=resizeSprite({width:2,height:2,hotspotX:1,hotspotY:2,rgba:Buffer.from([240,30,20,255,0,0,0,0,240,30,20,255,0,0,0,0])},0.5,identity);
assert.equal(resized.width,1);assert.equal(resized.height,1);
assert.deepEqual([...resized.rgba],[240,30,20,128]);
assert.deepEqual(resized.hotspot,[1,1]);
// Distinguishable constant-colour puzzle pieces verify AoC column/upward order.
const frames=Array.from({length:100},(_,f)=>{
  const rgba=Buffer.alloc(97*49*4);for(let i=0;i<rgba.length;i+=4){rgba[i]=f;rgba[i+1]=80;rgba[i+2]=100;rgba[i+3]=255;}
  return {width:97,height:49,rgba};
});
const atlas=flattenTerrain(frames,identity);
for(const [x,y,expected] of [[16,16,9],[16,304,0],[304,16,99],[304,304,90],[208,208,63]]){
  assert.equal(atlas.rgba[(y*320+x)*4],expected);
}
console.log('Importer resampling, alpha and terrain frame-order tests passed.');
if(process.argv.includes('--source')){
  const root=path.resolve(__dirname,'../..');
  const output=path.join(root,'prototype/qa/environment-pack/reimport-check');
  const definition=path.join(root,'prototype/data/environment/aoe2_temperate.json');
  const gameIndex=process.argv.indexOf('--game');
  const game=gameIndex<0?'D:/Games/Age of Empires II':process.argv[gameIndex+1];
  const first=importPack(game,output,definition);
  const second=importPack(game,output,definition);
  assert.deepEqual(first,second);
  const installed=JSON.parse(fs.readFileSync(path.join(root,'prototype/assets/generated/environment/aoe2_temperate/manifest.json'),'utf8'));
  assert.deepEqual(first,installed);
  console.log('Source reimport is byte-identical to installed pack (all PNG hashes and manifest).');
}
