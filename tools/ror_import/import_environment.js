#!/usr/bin/env node
'use strict';
// Offline importer. Source archives stay read-only; outputs are local build assets.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const {parseDrs, layerDrs, parsePalettes, decodeSlp, writePng} = require('./import_assets.js');
const RiverArt = require('./river_art.js');
const VERSION = 'ror-native-shoreline-1';
// AoC DAT graphics 2302/2310 attach ground-layer deltas 2300/2308.
// Each shadow uses the same direction as its tree, with its own hotspot.
const TREE_SHADOW_SLPS = {oak: 2296, pine: 2304};
const ROOT = path.resolve(__dirname, '../..');
function option(name, fallback) { const i=process.argv.indexOf(name); return i<0?fallback:process.argv[i+1]; }
function json(file) { return JSON.parse(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,'')); }
function hash(data) { return crypto.createHash('sha256').update(data).digest('hex'); }
function grade(rgb, spec) {
  // Some legacy AoC trail decorations contain saturated blue foliage. Correct
  // only those explicitly tagged source sprites; water artwork is untouched.
  if(spec.blue_foliage && rgb[2]>rgb[1]*1.35 && rgb[2]>rgb[0]*1.4) {
    const v=rgb[2]; rgb=[v*0.36,v*0.57,v*0.19];
  }
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
// Extract authored plants from the original Shallows sheet. Surviving pixels
// are copied verbatim; no new colours or painted plant shapes are introduced.
function sourceCutout(d, cutout) {
  if(!cutout)return d;
  const [left,top,width,height]=cutout.rect;
  if(left<0||top<0||left+width>d.width||top+height>d.height)throw Error('Source cutout exceeds SLP frame');
  const rgba=Buffer.alloc(width*height*4);
  for(let y=0;y<height;y++)for(let x=0;x<width;x++){
    const from=((y+top)*d.width+x+left)*4,to=(y*width+x)*4;
    const [r,g,b,a]=d.rgba.subarray(from,from+4);
    if(cutout.vegetation && !(Math.max(r,g)>b*1.35+2 && g>=r*0.65 && Math.max(r,g)>30))continue;
    d.rgba.copy(rgba,to,from,from+4);
  }
  return {...d,width,height,rgba,hotspotX:cutout.anchor[0]-left,hotspotY:cutout.anchor[1]-top};
}
// Keep the authored sand and plants, plus a restrained one-pixel wet edge.
// The large blue
// oval around each source Shallows decoration belongs to the original water
// tile; removing only that backing lets the islets join an arbitrary bank.
function shoreIslets(d) {
  const solid=new Uint8Array(d.width*d.height),rgba=Buffer.alloc(d.rgba.length);
  for(let i=0;i<solid.length;i++){
    const [r,g,b,a]=d.rgba.subarray(i*4,i*4+4);
    solid[i]=a>0 && Math.max(r,g)>b*1.15 && Math.max(r,g)>28 ? 1:0;
  }
  for(let y=0;y<d.height;y++)for(let x=0;x<d.width;x++){
    const keep=solid[y*d.width+x];
    let rim=false;
    if(!keep)for(let dy=-1;dy<=1&&!rim;dy++)for(let dx=-1;dx<=1;dx++){
      if(x+dx>=0&&x+dx<d.width&&y+dy>=0&&y+dy<d.height&&solid[(y+dy)*d.width+x+dx])rim=true;
    }
    const at=(y*d.width+x)*4;
    if(keep)d.rgba.copy(rgba,at,at,at+4);
    else if(rim&&d.rgba[at+3]){
      d.rgba.copy(rgba,at,at,at+4);
      rgba[at+3]=Math.round(d.rgba[at+3]*0.35);
    }
  }
  return {...d,rgba};
}
function shallowsGround(graphics,terrain,palettes) {
  return RiverArt.shallowsGround(graphics,terrain,palettes);
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
function groundMask(d) {
  const cells=new Map();
  for(let y=0;y<d.height;y++)for(let x=0;x<d.width;x++){
    if(d.rgba[(y*d.width+x)*4+3]<16)continue;
    const dx=x-d.hotspot[0],dy=y-d.hotspot[1];
    const a=Math.floor((dx/64+dy/32)*2),b=Math.floor((dy/32-dx/64)*2);
    cells.set(a+','+b,[a||0,b||0]);
  }
  return [...cells.values()].sort((a,b)=>a[1]-b[1]||a[0]-b[0]);
}
function groundBounds(d) {
  const bounds=[Infinity,Infinity,-Infinity,-Infinity];
  for(let y=0;y<d.height;y++)for(let x=0;x<d.width;x++){
    if(d.rgba[(y*d.width+x)*4+3]<16)continue;
    const dx=x-d.hotspot[0],dy=y-d.hotspot[1];
    const wx=dx/64+dy/32,wy=dy/32-dx/64;
    bounds[0]=Math.min(bounds[0],wx);bounds[1]=Math.min(bounds[1],wy);
    bounds[2]=Math.max(bounds[2],wx);bounds[3]=Math.max(bounds[3],wy);
  }
  return bounds.map((v,i)=> ((i<2?Math.floor(v*32):Math.ceil(v*32))/32)||0);
}
function decodeTreeShadow(spec,archive,palettes,frame,scale) {
  const slpId=spec.source_game==='ror'?null:TREE_SHADOW_SLPS[spec.key];
  if(!slpId)return null;
  const slp=archive.get('slp',slpId);
  if(!slp)throw Error('Missing tree shadow '+spec.key+'/'+slpId);
  const decoded=decodeSlp(slp,palettes,frame);
  if(decoded.semanticPixels.shadow===0)throw Error('Tree shadow has no shadow pixels: '+spec.key+'/'+frame);
  return {...resizeSprite(decoded,scale,{saturation:1,gain:[1,1,1]}),source_slp:slpId,source_shadow_pixels:decoded.semanticPixels.shadow};
}
function importPack(game,output,definitionPath,rorGame='D:/Games/Age of Empires 1 - Rise of Rome') {
  const definition=json(definitionPath), dataDir=path.join(game,'Data');
  const paths={terrain:path.join(dataDir,'terrain.drs'),graphics:path.join(dataDir,'graphics.drs'),palette:path.join(dataDir,'interfac.drs')};
  for(const file of Object.values(paths))if(!fs.existsSync(file))throw Error('Missing classic AoE2 archive: '+file);
  const terrain=parseDrs(paths.terrain),graphics=parseDrs(paths.graphics),palettes=parsePalettes(layerDrs([paths.palette]));
  const rorPaths={graphics:path.join(rorGame,'data/graphics.drs'),expansion:path.join(rorGame,'data2/graphics.drs'),palette:path.join(rorGame,'data/Interfac.drs'),terrain:path.join(rorGame,'data/Terrain.drs'),border:path.join(rorGame,'data/Border.drs')};
  const needsRor=definition.objects.some(spec=>spec.source_game==='ror');
  const rorGraphics=needsRor?layerDrs([rorPaths.expansion,rorPaths.graphics]):null;
  const rorPalettes=needsRor?parsePalettes(layerDrs([rorPaths.palette])):null;
  if(needsRor)for(const [key,value] of Object.entries(rorPaths))paths['ror_'+key]=value;
  const manifest={format_version:1,pack_id:definition.id,importer:VERSION,definition_sha256:hash(fs.readFileSync(definitionPath)),source_sha256:Object.fromEntries(Object.entries(paths).map(([key,file])=>[key,hash(fs.readFileSync(file))])),tile_pitch:definition.tile_pitch,materials:{},objects:{}};
  fs.mkdirSync(output,{recursive:true});
  function save(file,d){writePng(path.join(output,file),d.width,d.height,d.rgba);return {file,width:d.width,height:d.height,sha256:hash(fs.readFileSync(path.join(output,file)))};}
  const riverArt=definition.native_water_material?RiverArt.build(rorGraphics,parseDrs(rorPaths.terrain),rorPalettes):null;
  if(riverArt){
    manifest.native_water_material={...save('ror_shoal_ground.png',riverArt.bed),source_game:'ror',water_slp:15002,palette_slp:702,recipe:'native_submerged_silt',pattern_cells:[10,10],texels_per_cell:32};
    manifest.river_flow_material={...save('river_flow.png',riverArt.flow),frames:RiverArt.FRAME_COUNT,frame_height:RiverArt.FLOW_HEIGHT,source_game:'ror',palette_slp:702,recipe:'native_streamlets'};
    manifest.river_foam_material={...save('river_foam.png',riverArt.foam),frames:RiverArt.FRAME_COUNT,frame_height:RiverArt.FOAM_HEIGHT,source_game:'ror',palette_slp:702};
    manifest.river_rock_material={...save('river_rock.png',riverArt.rock),source_game:'ror',source_slp:283,source_frames:[1,2,4,5]};
    manifest.river_bank_rocks=riverArt.banks.map(d=>({...save('river_bank_'+d.source_frame+'.png',d),hotspot:d.hotspot,source_game:'ror',source_slp:283,source_frame:d.source_frame,derivative:'cliff_bank_mass'}));
  }
  if(definition.native_shoreline){
    const border=parseDrs(rorPaths.border);
    manifest.shoreline_materials={};
    for(const [key,slp] of [['marine',20000],['fresh',20004]]){
      manifest.shoreline_materials[key]={...save('shore_'+key+'.png',RiverArt.shoreline(border,rorPalettes,slp)),source_game:'ror',source_slp:slp,source_frame:8,world_period:2,recipe:'authored_waterline_ribbon'};
    }
  }
  for(const spec of definition.materials){
    if(spec.river_recipe){
      manifest.materials[spec.key]={...save(spec.key+'.png',riverArt[spec.river_recipe]),source_game:'ror',source_slp:15000,source_frames:9,pattern_cells:[10,10],texels_per_cell:32,recipe:spec.river_recipe};
      continue;
    }
    const slp=terrain.get('slp',spec.slp);if(!slp)throw Error('Missing terrain '+spec.slp);
    const first=decodeSlp(slp,palettes,0);if(first.frameCount!==100||first.width!==97||first.height!==49)throw Error('Unexpected classic terrain geometry '+spec.slp);
    const frames=Array.from({length:100},(_,f)=>decodeSlp(slp,palettes,f));
    const atlas=flattenTerrain(frames,spec);
    manifest.materials[spec.key]={...save(spec.key+'.png',atlas),source_slp:spec.slp,source_frames:100,pattern_cells:[10,10],texels_per_cell:32,frame_order:'column_bottom_to_top'};
  }
  for(const spec of definition.objects){
    const archive=spec.source_game==='ror'?rorGraphics:graphics;
    const sourcePalettes=spec.source_game==='ror'?rorPalettes:palettes;
    const scale=spec.scale??(spec.source_game==='ror'?1:definition.object_scale);
    const frames=[];
    for(let index=0;index<spec.frames.length;index++){
      const frame=spec.frames[index],slpId=spec.slps?.[index]??spec.slp;
      const slp=archive.get('slp',slpId);if(!slp)throw Error('Missing object '+spec.key+'/'+slpId);
      const d=decodeSlp(slp,sourcePalettes,frame,spec.neutral_player_color?0:1);
      if(d.semanticPixels.player_color!==0 && !spec.neutral_player_color)throw Error('Player-colour sprite is not static environment art: '+spec.key);
      const cutout=spec.source_cutouts?.[index];
      const source=spec.native_islets?shoreIslets(d):sourceCutout(d,cutout);
      const resized=resizeSprite(source,scale,spec),bounds=groundBounds(resized);
      if(spec.native_islets && JSON.stringify(spec.ground_bounds[index])!==JSON.stringify(bounds))throw Error('River islet geometry differs from source: '+index);
      if(spec.ground_masks && JSON.stringify(spec.ground_masks[index])!==JSON.stringify(groundMask(resized)))throw Error("Route mask differs from source: "+spec.key);
      if(spec.placement && JSON.stringify(spec.ground_bounds?.[index])!==JSON.stringify(bounds))throw Error('Placement geometry differs from source: '+spec.key+'/'+index);
      const shadowImage=decodeTreeShadow(spec,archive,sourcePalettes,frame,scale);
      const shadow=shadowImage?{...save(spec.key+'_shadow_'+String(index).padStart(2,'0')+'.png',shadowImage),hotspot:shadowImage.hotspot,source_slp:shadowImage.source_slp,source_frame:frame,source_shadow_pixels:shadowImage.source_shadow_pixels}:null;
      frames.push({...save(spec.key+'_'+String(frames.length).padStart(2,'0')+'.png',resized),hotspot:resized.hotspot,source_frame:frame,source_slp:slpId,source_hotspot:[source.hotspotX,source.hotspotY],source_size:[source.width,source.height],source_shadow_pixels:d.semanticPixels.shadow,scale,ground_bounds:bounds,...(cutout?{source_cutout:cutout,original_source_hotspot:[d.hotspotX,d.hotspotY],original_source_size:[d.width,d.height]}:{}),...(shadow?{shadow}:{})});
    }
    manifest.objects[spec.key]={source_game:spec.source_game??'aoe2',source_slp:spec.slp??null,frames};
  }
  fs.writeFileSync(path.join(output,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
  return manifest;
}
module.exports={TREE_SHADOW_SLPS,decodeTreeShadow,resizeSprite,sourceCutout,shoreIslets,shallowsGround,flattenTerrain,importPack,grade,groundBounds,groundMask};
if(require.main===module){
  try{
    const definition=option('--definition',path.join(ROOT,'prototype/data/environment/aoe2_temperate.json'));
    const game=option('--game','D:/Games/Age of Empires II');
    const output=option('--output',path.join(ROOT,'prototype/assets/generated/environment/aoe2_temperate'));
    const m=importPack(game,output,definition,option('--ror-game','D:/Games/Age of Empires 1 - Rise of Rome'));
    console.log(`Imported ${Object.keys(m.materials).length} materials and ${Object.values(m.objects).reduce((n,v)=>n+v.frames.length,0)} object variants into ${output}`);
  }catch(error){console.error(error.message);process.exitCode=1;}
}
