'use strict';
const assert = require('assert/strict');
const fs = require('fs');
const path = require('path');
const {decodeTreeShadow, resizeSprite, sourceCutout, shoreIslets, shallowsGround, flattenTerrain, importPack, groundBounds, grade} = require('./import_environment.js');
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
assert.deepEqual(groundBounds({width:1,height:1,hotspot:[0,0],rgba:Buffer.from([40,80,20,255])}),[0,0,0,0]);
assert.deepEqual(grade([20,30,160],identity),[20,30,160]);
const corrected=grade([20,30,160],{...identity,blue_foliage:true});
assert.ok(corrected[1]>corrected[2] && corrected[1]>corrected[0]);
const definitionFile=path.resolve(__dirname,'../../prototype/data/environment/aoe2_temperate.json');
const entries=JSON.parse(fs.readFileSync(definitionFile)).objects.filter(x=>x.placement);
assert.equal(entries.reduce((n,x)=>n+x.frames.length,0),115);
for(const key of ['ror_stone_dirt_trail','ror_stone_grass_trail','overgrown_trail']){
  assert.ok(!entries.some(entry=>entry.key===key),'Excluded road family must stay out of generation: '+key);
}
for(const entry of entries){
  assert.equal(entry.ground_bounds.length,entry.frames.length);
  assert.ok(entry.placement.materials.length>0 && entry.placement.spacing>0);
  for(const b of entry.ground_bounds)assert.ok(b.length===4 && b.every(Number.isFinite) && b[0]<=b[2] && b[1]<=b[3]);
}
console.log('Importer resampling, alpha, geometry, palette isolation and terrain frame-order tests passed.');
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

// Read the original archives without repacking any project assets.
if(process.argv.includes('--source-readonly')){
  const {parseDrs,layerDrs,parsePalettes,decodeSlp}=require('./import_assets.js');
  const gameIndex=process.argv.indexOf('--game');
  const game=gameIndex<0?'D:/Games/Age of Empires II':process.argv[gameIndex+1];
  const archive=parseDrs(path.join(game,'Data/graphics.drs'));
  const palettes=parsePalettes(layerDrs([path.join(game,'Data/interfac.drs')]));
  const definition=JSON.parse(fs.readFileSync(definitionFile));
  for(const spec of definition.objects.filter(s=>s.role==='tree')){
    for(const frame of spec.frames){
      const tree=decodeSlp(archive.get('slp',spec.slp),palettes,frame);
      assert.equal(tree.semanticPixels.shadow,0,'Trees store their shadows in a separate DAT delta');
      const shadow=decodeTreeShadow(spec,archive,palettes,frame,definition.object_scale);
      assert.ok(shadow.source_shadow_pixels>100 && shadow.hotspot.length===2);
      assert.ok(shadow.rgba.some((v,i)=>i%4===3 && v>0 && v<255),'Shadows preserve transparency');
      for(let i=0;i<shadow.rgba.length;i+=4)assert.deepEqual([...shadow.rgba.subarray(i,i+3)],[0,0,0]);
      assert.equal(shadow.source_slp,spec.key==='oak'?2296:2304);
    }
  }
  console.log('All 8 tree variants resolve their original AoC shadow and direction (read-only).');
  const original='D:/Games/Age of Empires 1 - Rise of Rome';
  const ror=layerDrs([path.join(original,'data2/graphics.drs'),path.join(original,'data/graphics.drs')]);
  const rorPalettes=parsePalettes(layerDrs([path.join(original,'data/Interfac.drs')]));
  const rorTerrain=layerDrs([path.join(original,'data/Terrain.drs')]);
  const bed=shallowsGround(ror,rorTerrain,rorPalettes);
  let minimum=255,maximum=0;
  for(let i=0;i<bed.rgba.length;i+=4){
    assert.equal(bed.rgba[i+3],255,'Submerged bed has no holes');
    const [r,g,b]=bed.rgba.subarray(i,i+3);
    assert.ok(g>r && b>g*1.8 && Math.abs((g-r)-24)<=2 && Math.abs((b-g)-80)<=2,'Submerged bed follows the native Shallows blue family (39,63,143)');
    minimum=Math.min(minimum,g);maximum=Math.max(maximum,g);
  }
  assert.ok(maximum-minimum<30,'Submerged texture cannot regress into high-contrast confetti');
  console.log('Submerged bed has restrained contrast and continuous water colour.');
  const RiverArt=require('./river_art.js');
  const art=RiverArt.build(ror,rorTerrain,rorPalettes);
  const nativeWater=new Set(art.palette.map(p=>p.join(',')));
  for(const kind of ['flow','foam']){
    const d=art[kind],stride=d.rgba.length/RiverArt.FRAME_COUNT,hashes=new Set();
    for(let frame=0;frame<RiverArt.FRAME_COUNT;frame++)hashes.add(require('crypto').createHash('sha256').update(d.rgba.subarray(frame*stride,(frame+1)*stride)).digest('hex'));
    assert.equal(hashes.size,8,'Every water phase must visibly advance');
    for(let i=0;i<d.rgba.length;i+=4)if(d.rgba[i+3])assert.ok(nativeWater.has([...d.rgba.subarray(i,i+3)].join(',')),'Waterfall and foam stay in the exact native SLP 702 palette');
  }
  for(const bank of art.banks){
    const source=decodeSlp(ror.get('slp',283),rorPalettes,bank.source_frame);
    assert.deepEqual([bank.width,bank.height,...bank.hotspot],[source.width,source.height,source.hotspotX,source.hotspotY],'Native bank scale and anchor are preserved');
    let visible=0;
    for(let i=0;i<bank.rgba.length;i+=4){
      assert.ok(bank.rgba[i+3]<=source.rgba[i+3],'Derivative adds no opaque skirt');
      if(!bank.rgba[i+3])continue;
      visible++;
      assert.deepEqual([...bank.rgba.subarray(i,i+3)],[...source.rgba.subarray(i,i+3)],'Bank artwork is not recoloured or stretched');
    }
    assert.ok(visible>3000,'A complete bank mass survives the cutout');
  }
  console.log('River art: 8 moving native-palette phases, unchanged bank pixels, native scale, anchors and transparent edges.');
  const reeds=definition.objects.find(s=>s.key==='ror_reeds');
  for(let frame=0;frame<reeds.frames.length;frame++){
    const source=decodeSlp(ror.get('slp',596),rorPalettes,reeds.frames[frame]);
    const region=reeds.source_cutouts[frame],cut=sourceCutout(source,region);
    assert.deepEqual([cut.hotspotX,cut.hotspotY],[region.anchor[0]-region.rect[0],region.anchor[1]-region.rect[1]]);
    let opaque=0;
    for(let y=0;y<cut.height;y++)for(let x=0;x<cut.width;x++){
      const i=(y*cut.width+x)*4;
      if(!cut.rgba[i+3])continue;
      opaque++;
      const at=((y+region.rect[1])*source.width+x+region.rect[0])*4;
      assert.deepEqual([...cut.rgba.subarray(i,i+4)],[...source.rgba.subarray(at,at+4)],'Native reed pixels retain their exact source palette and alpha');
    }
    assert.ok(opaque>=10,'Native reed cutout is not empty');
  }
  console.log('Both native Shallows plant cutouts preserve source pixels and ground-root anchors (read-only).');
  for(let frame=0;frame<7;frame++){
    const source=decodeSlp(ror.get('slp',596),rorPalettes,frame),islets=shoreIslets(source);
    assert.deepEqual([islets.width,islets.height,islets.hotspotX,islets.hotspotY],[source.width,source.height,source.hotspotX,source.hotspotY]);
    let kept=0,removed=0;
    for(let i=0;i<source.rgba.length;i+=4){
      if(islets.rgba[i+3]){
        kept++;
        assert.deepEqual([...islets.rgba.subarray(i,i+3)],[...source.rgba.subarray(i,i+3)],'Islets retain authored pixels and palette exactly');
        assert.ok(islets.rgba[i+3]<=source.rgba[i+3],'The wet rim only reduces source alpha');
      }else if(source.rgba[i+3])removed++;
    }
    assert.ok(kept>30 && removed>100,'Native islets retain their sand and plants but lose the oval blue backing');
  }
  console.log('Seven native islet variants preserve source pixels and anchors without oval water backings.');
  const border=layerDrs([path.join(original,'data/Border.drs')]);
  for(const [kind,slp] of [['marine',20000],['fresh',20004]]){
    const source=decodeSlp(border.get('slp',slp),rorPalettes,8),strip=RiverArt.shoreline(border,rorPalettes,slp);
    const palette=new Set();
    for(let i=0;i<source.rgba.length;i+=4)if(source.rgba[i+3])palette.add([...source.rgba.subarray(i,i+3)].join(','));
    assert.deepEqual([strip.width,strip.height],[64,24]);
    let opaque=0;
    for(let y=0;y<strip.height;y++)for(let x=0;x<strip.width;x++){
      const at=(y*strip.width+x)*4;
      if(strip.rgba[at+3]){opaque++;assert.ok(palette.has([...strip.rgba.subarray(at,at+3)].join(',')),'Shore pixels use only their authored source palette');}
      if(y===0||y===23)assert.equal(strip.rgba[at+3],0,'Waterline blends into both surrounding surfaces');
      const mirror=(y*strip.width+63-x)*4;
      assert.deepEqual([...strip.rgba.subarray(at,at+4)],[...strip.rgba.subarray(mirror,mirror+4)],'Mirrored native repeats close without a cut');
    }
    assert.ok(opaque>1000,'A substantial native shore band survives import: '+kind);
  }
  console.log('Native shore ribbons: source palette, transparent edges and seamless mirrored repeats (read-only).');
}
