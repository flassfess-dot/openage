'use strict';

// Derivatives of the installed RoR artwork. World geometry supplies the landform;
// these sheets supply its native palette, pixel density and authored rock edges.
const {decodeSlp}=require('./import_assets.js');
const {derive}=require('./presentation_derivatives.js');
const FRAME_COUNT=8, FLOW_HEIGHT=96, FOAM_HEIGHT=32;
const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
const mix=(a,b,t)=>a+(b-a)*t;
function hash(x,y){
  let h=Math.imul(x+41,73856093)^Math.imul(y+13,19349663);
  h=Math.imul(h^(h>>>16),0x7feb352d);h=Math.imul(h^(h>>>15),0x846ca68b);
  return ((h^(h>>>16))>>>0)/4294967295;
}
function noise(x,y,period=0){
  const ix=Math.floor(x),iy=Math.floor(y),sx=x-ix,sy=y-iy,u=sx*sx*(3-2*sx),v=sy*sy*(3-2*sy);
  const at=(a,b)=>hash(a,period?((b%period)+period)%period:b);
  return mix(mix(at(ix,iy),at(ix+1,iy),u),mix(at(ix,iy+1),at(ix+1,iy+1),u),v);
}
function colours(sprites,predicate=()=>true){
  const result=new Map();
  for(const d of sprites)for(let i=0;i<d.rgba.length;i+=4){
    const rgb=[...d.rgba.subarray(i,i+3)];
    if(d.rgba[i+3]===255&&predicate(rgb))result.set(rgb.join(','),rgb);
  }
  return [...result.values()];
}
function nearest(rgb,palette){
  let best=palette[0],distance=Infinity;
  for(const p of palette){
    const d=(p[0]-rgb[0])**2+(p[1]-rgb[1])**2+(p[2]-rgb[2])**2;
    if(d<distance){distance=d;best=p;}
  }
  return best;
}
function sheet(width,height){return {width,height,rgba:Buffer.alloc(width*height*4)};}
function pixel(d,x,y){return [...d.rgba.subarray((y*d.width+x)*4,(y*d.width+x)*4+3)];}
function set(d,x,y,rgb,alpha=255){d.rgba.set([...rgb,alpha],(y*d.width+x)*4);}
function nativeAtlas(frames,transform){
  const out=sheet(320,320);
  for(let y=0;y<320;y++)for(let x=0;x<320;x++){
    const col=Math.floor(x/32),row=Math.floor(y/32),d=frames[(col*7+row*11)%frames.length];
    const u=(x%32+.5)/32,v=(y%32+.5)/32;
    let sx=clamp(Math.round(32+32*(u-v)),0,d.width-1),sy=clamp(Math.round(16*(u+v)),0,d.height-1);
    for(let repair=0;repair<3&&d.rgba[(sy*d.width+sx)*4+3]<255;repair++){
      sx+=Math.sign(32-sx);sy+=Math.sign(16-sy);
    }
    set(out,x,y,transform(pixel(d,sx,sy),x,y));
  }
  return out;
}
function waterPalette(graphics,palettes){
  const fall=decodeSlp(graphics.get('slp',702),palettes,0);
  return colours([fall],([r,g,b])=>b>r*1.12&&b>g*1.02).sort((a,b)=>a[0]+a[1]+a[2]-b[0]-b[1]-b[2]);
}
function shallowsGround(graphics,terrain,palettes){
  const water=Array.from({length:4},(_,i)=>decodeSlp(terrain.get('slp',15002),palettes,i));
  return nativeAtlas(water,rgb=>{
    const wave=(rgb[0]+rgb[1]+rgb[2])/3-75;
    // Match the dominant blue of source Shallows (SLP 596) while preserving
    // native wave grain. A small palette alone made visible flat blocks.
    return [39,63,143].map(value=>Math.round((value+wave*.20)/2)*2);
  });
}
function groundMaterials(graphics,terrain,palettes){
  // Only 0..8 are flat variants. The remaining terrain frames are authored
  // slopes; flattening them into an atlas would bake diagonal cliff shadows.
  const sand=Array.from({length:9},(_,i)=>decodeSlp(terrain.get('slp',15000),palettes,i));
  const rocks=[1,2,4,5].map(i=>decodeSlp(graphics.get('slp',283),palettes,i));
  const palette=colours([...sand,...rocks],([r,g,b])=>r>g&&g>b&&r>50);
  const silt=nativeAtlas(sand,rgb=>nearest([rgb[0]*.92,rgb[1]*.94,rgb[2]*.97],palette));
  const gravel=nativeAtlas(sand,(rgb,x,y)=>{
    const grain=(noise(x/2,y/2)-.5)*24;
    return nearest([rgb[0]*.72+grain,rgb[1]*.80+grain,rgb[2]*.98+grain],palette);
  });
  return {silt,gravel};
}
function flowSheet(palette){
  const out=sheet(256,FLOW_HEIGHT*FRAME_COUNT);
  for(let frame=0;frame<FRAME_COUNT;frame++)for(let y=0;y<FLOW_HEIGHT;y++)for(let x=0;x<256;x++){
    const py=(y-frame*12+FLOW_HEIGHT)%FLOW_HEIGHT;
    const warp=(noise(x/18,py/24,4)-.5)*7;
    const n=noise((x+warp)/3.2,py/12,8)*.42+noise(x/12,py/48,2)*.33+noise(x/1.6,py/4,24)*.25;
    // Dense dark water, with clustered pale streamlets. Every colour comes
    // from SLP 702; there are no smooth cyan gradients or procedural whites.
    const level=clamp((n-.23)*1.38,0,1);
    const index=Math.round(level*(palette.length-1));
    set(out,x,frame*FLOW_HEIGHT+y,palette[index]);
  }
  return out;
}
function foamSheet(palette){
  const out=sheet(128,FOAM_HEIGHT*FRAME_COUNT),foam=palette.filter(p=>p[0]>=127);
  for(let frame=0;frame<FRAME_COUNT;frame++)for(let y=0;y<FOAM_HEIGHT;y++)for(let x=0;x<128;x++){
    const nx=(x-63.5)/63.5,ny=(y-15.5)/15.5;
    const shape=1-nx*nx-ny*ny;
    if(shape<0)continue;
    const n=noise(x/1.25,(y-frame*4+32)%32/1,32);
    const ripple=Math.sin(y*1.9+x*.11-frame*TAU/FRAME_COUNT);
    if(n<.70+Math.max(0,.4-shape)*.5||Math.abs(ripple)>.72)continue;
    const rgb=foam[clamp(Math.floor((n-.65)*foam.length*2),0,foam.length-1)];
    set(out,x,frame*FOAM_HEIGHT+y,rgb,Math.round(clamp(shape*2.6,0,1)*175));
  }
  return out;
}
const TAU=Math.PI*2;
function rockFace(graphics,palettes){
  const frames=[1,2,4,5].map(i=>decodeSlp(graphics.get('slp',283),palettes,i));
  const out=sheet(512,64);
  for(let x=0;x<out.width;x++){
    const d=frames[Math.floor(x/128)],sx=clamp(Math.floor(d.width*.23+(x%128)*d.width*.54/128),0,d.width-1);
    const ys=[];
    for(let y=0;y<d.height;y++)if(d.rgba[(y*d.width+sx)*4+3]===255)ys.push(y);
    const first=ys[0]+9,last=ys[ys.length-1]-4;
    const height=Math.max(1,last-first);
    for(let y=0;y<64;y++){
      const folded=y%(height*2),sy=first+(folded<height?folded:height*2-folded-1);
      let at=clamp(sy,0,d.height-1);
      while(at>ys[0]&&d.rgba[(at*d.width+sx)*4+3]<255)at--;
      set(out,x,y,pixel(d,sx,at));
    }
  }
  return out;
}
function bankRocks(graphics,palettes){
  return [16,17,18,19,24].map(frame=>{
    const d=derive(decodeSlp(graphics.get('slp',283),palettes,frame),'cliff_foot',frame);
    // Terminal cliff frames include detached boulders. They belong to their
    // original footprint, not to the water beside this bank abutment.
    const visited=new Uint8Array(d.width*d.height),components=[];
    for(let i=0;i<visited.length;i++){
      if(visited[i]||d.rgba[i*4+3]===0)continue;
      const queue=[i];visited[i]=1;
      for(let at=0;at<queue.length;at++){
        const p=queue[at],x=p%d.width,y=Math.floor(p/d.width);
        for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++){
          const nx=x+dx,ny=y+dy,n=ny*d.width+nx;
          if(nx<0||ny<0||nx>=d.width||ny>=d.height||visited[n]||d.rgba[n*4+3]===0)continue;
          visited[n]=1;queue.push(n);
        }
      }
      components.push(queue);
    }
    components.sort((a,b)=>b.length-a.length);
    const rgba=Buffer.alloc(d.rgba.length);
    for(const i of components[0])d.rgba.copy(rgba,i*4,i*4,i*4+4);
    return {...d,rgba,hotspot:[d.hotspotX,d.hotspotY],source_frame:frame};
  });
}
// Unroll an authored straight waterline into a repeating terrain ribbon.
// Only coordinates and alpha change: sand, wet edge and wave pixels remain
// from the native Border.drs palette. Mirrored repeats meet at the same texel.
function shoreline(border,palettes,slpId){
  const d=decodeSlp(border.get('slp',slpId),palettes,8),out=sheet(64,24);
  const at=(u,v)=>{
    const x=clamp(Math.round(32+(u-v)*32),0,d.width-1),y=clamp(Math.round((u+v)*16),0,d.height-1);
    return (y*d.width+x)*4;
  };
  const boundaries=[];
  for(let x=0;x<32;x++){
    const v=.08+(x+.5)/32*.84;
    let edge=.5;
    for(let i=0;i<65;i++){
      const u=i/64,p=at(u,v),[r,g,b,a]=d.rgba.subarray(p,p+4);
      if(a&&r>b*1.12&&r>g*1.03){edge=u;break;}
    }
    boundaries.push(edge);
  }
  for(let x=0;x<64;x++)for(let y=0;y<24;y++){
    const along=x<32?x:63-x,v=.08+(along+.5)/32*.84;
    const center=(boundaries[clamp(along-1,0,31)]+boundaries[along]+boundaries[clamp(along+1,0,31)])/3;
    const u=center+(y-7)*.025,p=at(u,v),to=(y*64+x)*4;
    const fade=clamp(y/3,0,1)*clamp((23-y)/7,0,1);
    d.rgba.copy(out.rgba,to,p,p+4);
    out.rgba[to+3]=Math.round(d.rgba[p+3]*fade);
    // Palette-black pinholes in the grass/water border must reveal the
    // already rendered ground; tiled opaquely they become an oily dotted line.
    if(d.rgba[p]===0&&d.rgba[p+1]===0&&d.rgba[p+2]===0)out.rgba[to+3]=0;
  }
  return out;
}
function build(graphics,terrain,palettes){
  const palette=waterPalette(graphics,palettes);
  return {...groundMaterials(graphics,terrain,palettes),bed:shallowsGround(graphics,terrain,palettes),flow:flowSheet(palette),foam:foamSheet(palette),rock:rockFace(graphics,palettes),banks:bankRocks(graphics,palettes),palette};
}
module.exports={build,shoreline,shallowsGround,waterPalette,FRAME_COUNT,FLOW_HEIGHT,FOAM_HEIGHT};
