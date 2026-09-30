#!/usr/bin/env node
'use strict';
// Offline importer. Source archives stay read-only; outputs are local build assets.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const {parseDrs, layerDrs, parsePalettes, decodeSlp, writePng} = require('./import_assets.js');
const VERSION = 'aoe2-environment-1';
const ROOT = path.resolve(__dirname, '../..');
function option(name, fallback) { const i=process.argv.indexOf(name); return i<0?fallback:process.argv[i+1]; }
function json(file) { return JSON.parse(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,'')); }
function hash(data) { return crypto.createHash('sha256').update(data).digest('hex'); }
function grade(rgb, spec) {
  const l=rgb[0]*0.299+rgb[1]*0.587+rgb[2]*0.114;
  return rgb.map((v,k)=>Math.max(0,Math.min(255,Math.round((l+(v-l)*spec.saturation)*spec.gain[k]))));
}
// Alpha-aware area averaging: transparent pixels never add black fringes.
function resizeSprite(d, scale, spec) {
  const width=Math.ceil(d.width*scale), height=Math.ceil(d.height*scale);
  const rgba=Buffer.alloc(width*height*4);
  for(let y=0;y<height;y++)for(let x=0;x<width;x++){
    const x0=x/scale,x1=Math.min(d.width,(x+1)/scale),y0=y/scale,y1=Math.min(d.height,(y+1)/scale);
    const sum=[0,0,0];let alpha=0,area=0;
    for(let sy=Math.floor(y0);sy<Math.ceil(y1);sy++)for(let sx=Math.floor(x0);sx<Math.ceil(x1);sx++){
      const w=Math.max(0,Math.min(x1,sx+1)-Math.max(x0,sx))*Math.max(0,Math.min(y1,sy+1)-Math.max(y0,sy));
      const i=(sy*d.width+sx)*4,a=d.rgba[i+3]/255;
      area+=w;alpha+=a*w;for(let k=0;k<3;k++)sum[k]+=d.rgba[i+k]*a*w;
    }
    const i=(y*width+x)*4;
    if(alpha>0){const rgb=grade(sum.map(v=>v/alpha),spec);for(let k=0;k<3;k++)rgba[i+k]=rgb[k];rgba[i+3]=Math.round(alpha/area*255);}
  }
  return {width,height,rgba,hotspot:[Math.round(d.hotspotX*scale),Math.round(d.hotspotY*scale)]};
}
function sampleOpaque(d,x,y) {
  // Source diamonds have shared edge pixels. At pixel centres stay inside them.
  const sums=[0,0,0];let sum=0;
  for(let dy=0;dy<2;dy++)for(let dx=0;dx<2;dx++){
    const sx=Math.max(0,Math.min(d.width-1,Math.floor(x)+dx));
    const sy=Math.max(0,Math.min(d.height-1,Math.floor(y)+dy));
    const i=(sy*d.width+sx)*4,w=(dx?x-Math.floor(x):1-(x-Math.floor(x)))*(dy?y-Math.floor(y):1-(y-Math.floor(y)))*d.rgba[i+3]/255;
    sum+=w;for(let k=0;k<3;k++)sums[k]+=d.rgba[i+k]*w;
  }
  if(sum===0)throw Error('Transparent interior in terrain source');
  return sums.map(v=>v/sum);
}
function flattenTerrain(frames,spec) {
  // AoC frame order: columns left-to-right, each column bottom-to-top.
  // Keep all 100 puzzle pieces together (see terrain_merge.pyx), 32 texels/cell.
  const width=320,height=320,rgba=Buffer.alloc(width*height*4);
  for(let f=0;f<100;f++){
    const d=frames[f],col=Math.floor(f/10),row=9-f%10;
    for(let y=0;y<32;y++)for(let x=0;x<32;x++){
      const u=(x+0.5)/32,v=(y+0.5)/32;
      const rgb=grade(sampleOpaque(d,48+48*(u-v),24*(u+v)),spec);
      const i=((row*32+y)*320+col*32+x)*4;
      for(let k=0;k<3;k++)rgba[i+k]=rgb[k];rgba[i+3]=255;
    }
  }
  return {width,height,rgba};
}
function importPack(game,output,definitionPath) {
  const definition=json(definitionPath), dataDir=path.join(game,'Data');
  const paths={terrain:path.join(dataDir,'terrain.drs'),graphics:path.join(dataDir,'graphics.drs'),palette:path.join(dataDir,'interfac.drs')};
  for(const file of Object.values(paths))if(!fs.existsSync(file))throw Error('Missing classic AoE2 archive: '+file);
  const terrain=parseDrs(paths.terrain),graphics=parseDrs(paths.graphics),palettes=parsePalettes(layerDrs([paths.palette]));
  const manifest={format_version:1,pack_id:definition.id,importer:VERSION,definition_sha256:hash(fs.readFileSync(definitionPath)),source_sha256:Object.fromEntries(Object.entries(paths).map(([key,file])=>[key,hash(fs.readFileSync(file))])),tile_pitch:definition.tile_pitch,materials:{},objects:{}};
  fs.mkdirSync(output,{recursive:true});
  function save(file,d){writePng(path.join(output,file),d.width,d.height,d.rgba);return {file,width:d.width,height:d.height,sha256:hash(fs.readFileSync(path.join(output,file)))};}
  for(const spec of definition.materials){
    const slp=terrain.get('slp',spec.slp);if(!slp)throw Error('Missing terrain '+spec.slp);
    const first=decodeSlp(slp,palettes,0);if(first.frameCount!==100||first.width!==97||first.height!==49)throw Error('Unexpected classic terrain geometry '+spec.slp);
    const frames=Array.from({length:100},(_,f)=>decodeSlp(slp,palettes,f));
    const atlas=flattenTerrain(frames,spec);
    manifest.materials[spec.key]={...save(spec.key+'.png',atlas),source_slp:spec.slp,source_frames:100,pattern_cells:[10,10],texels_per_cell:32,frame_order:'column_bottom_to_top'};
  }
  for(const spec of definition.objects){
    const slp=graphics.get('slp',spec.slp);if(!slp)throw Error('Missing object '+spec.slp);
    const frames=[];
    for(const frame of spec.frames){
      const d=decodeSlp(slp,palettes,frame);
      if(d.semanticPixels.player_color!==0)throw Error('Player-colour sprite is not static environment art');
      const resized=resizeSprite(d,definition.object_scale,spec);
      frames.push({...save(spec.key+'_'+String(frames.length).padStart(2,'0')+'.png',resized),hotspot:resized.hotspot,source_frame:frame,source_hotspot:[d.hotspotX,d.hotspotY],source_size:[d.width,d.height],source_shadow_pixels:d.semanticPixels.shadow});
    }
    manifest.objects[spec.key]={source_slp:spec.slp,frames};
  }
  fs.writeFileSync(path.join(output,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
  return manifest;
}
module.exports={resizeSprite,flattenTerrain,importPack,grade};
if(require.main===module){
  try{
    const definition=option('--definition',path.join(ROOT,'prototype/data/environment/aoe2_temperate.json'));
    const game=option('--game','D:/Games/Age of Empires II');
    const output=option('--output',path.join(ROOT,'prototype/assets/generated/environment/aoe2_temperate'));
    const m=importPack(game,output,definition);
    console.log(`Imported ${Object.keys(m.materials).length} materials and ${Object.values(m.objects).reduce((n,v)=>n+v.frames.length,0)} object variants into ${output}`);
  }catch(error){console.error(error.message);process.exitCode=1;}
}
