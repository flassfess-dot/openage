"use strict";
// Deterministic layers cut from owned source pixels; no replacement artwork.
const FARM_HUT = [[97,-1],[123,15],[144,23],[144,29],[142,31],[143,48],[136,52],[120,54],[80,35],[77,31],[77,25],[81,18],[87,11],[94,6]];
const GALLEY_OARS = [
 [[14,32,0,36],[14,40,0,44],[14,48,0,52],[14,56,0,60],[46,32,60,36],[46,40,60,44],[46,48,60,52],[46,56,60,60]],
 [[37,46,49,59],[48,40,60,53],[59,35,71,48],[70,29,83,42]],
 [[34,26,34,39],[50,28,50,39],[67,28,67,39],[82,27,82,39]],
 [[12,32,0,42],[22,38,8,51],[31,45,16,58],[43,50,30,63]],
 [[14,28,0,33],[14,37,0,42],[14,46,0,51],[14,55,0,60],[47,28,60,33],[47,37,60,42],[47,46,60,51],[47,55,60,60]],
];
function inside(x,y,polygon) {
 let result=false;
 for(let i=0,j=polygon.length-1;i<polygon.length;j=i++) {
  const [xi,yi]=polygon[i],[xj,yj]=polygon[j];
  if(((yi>y)!=(yj>y)) && x<(xj-xi)*(y-yi)/(yj-yi)+xi) result=!result;
 }
 return result;
}
function splitFarm(decoded, part) {
 const rgba=Buffer.from(decoded.rgba);
 for(let y=0;y<decoded.height;y++)for(let x=0;x<decoded.width;x++) {
  const hut=inside(x+.5,y+.5,FARM_HUT);
  if(hut !== (part==='farm_hut')) rgba[(y*decoded.width+x)*4+3]=0;
 }
 return {...decoded,rgba};
}
function rowing(decoded,direction,phase) {
 const padding=10,width=decoded.width+padding*2,height=decoded.height+padding*2;
 const rgba=Buffer.alloc(width*height*4), oars=[];
 const segments=GALLEY_OARS[direction] || [];
 for(let y=0;y<decoded.height;y++)for(let x=0;x<decoded.width;x++) {
  const at=(y*decoded.width+x)*4;
  let segment=null;
  if(decoded.rgba[at+3]===255 && decoded.rgba[at]>decoded.rgba[at+2] && decoded.rgba[at]>decoded.rgba[at+1] && decoded.rgba[at]<decoded.rgba[at+1]*2.7) {
   for(const s of segments) {
    const dx=s[2]-s[0],dy=s[3]-s[1],length=dx*dx+dy*dy;
    const t=((x-s[0])*dx+(y-s[1])*dy)/length;
    if(t<0 || t>1.06)continue;
    if(Math.hypot(x-s[0]-t*dx,y-s[1]-t*dy)<=1.35){segment=s;break;}
   }
  }
  if(segment) oars.push({x,y,at,segment});
  else decoded.rgba.copy(rgba,((y+padding)*width+x+padding)*4,at,at+4);
 }
 // Individual blades turn about their own rowlock, so the hull stays still.
 const stroke=Math.sin(phase*Math.PI*2)*.36;
 const forward = [[0,-1],[.894,-.447],[1,0],[.894,.447],[0,1]][direction];
 for(const p of oars) {
  const [px,py]=p.segment, dx=p.x-px,dy=p.y-py;
  const angle=stroke*Math.sign(-(p.segment[3]-py)*forward[0]+(p.segment[2]-px)*forward[1]);
  const x=Math.round(px+dx*Math.cos(angle)-dy*Math.sin(angle))+padding;
  const y=Math.round(py+dx*Math.sin(angle)+dy*Math.cos(angle))+padding;
  if(x>=0&&y>=0&&x<width&&y<height) decoded.rgba.copy(rgba,(y*width+x)*4,p.at,p.at+4);
 }
 return {...decoded,width,height,hotspotX:decoded.hotspotX+padding,hotspotY:decoded.hotspotY+padding,rgba};
}
function cliffFoot(decoded) {
 const rgba=Buffer.from(decoded.rgba), w=decoded.width,h=decoded.height;
 // Only the lower footprint skirt blends into grass. Leave the crest and
 // vertical face crisp, and keep isolated terminal boulders intact.
 const bottom=[];
 for(let x=0;x<w;x++) {
  let y=h-1;
  while(y>=0 && decoded.rgba[(y*w+x)*4+3]===0)y--;
  bottom[x]=y;
 }
 for(let x=2;x<w-2;x++) {
  const y=bottom[x];
  if(y<0 || y<decoded.hotspotY-5)continue;
  if(Math.abs(bottom[x-2]-y)>4 || Math.abs(bottom[x+2]-y)>4)continue;
  for(let d=0;d<5;d++) {
   const at=((y-d)*w+x)*4+3;
   if(y-d>=0)rgba[at]=Math.round(rgba[at]*(d+1)/6);
  }
 }
 return {...decoded,rgba};
}
function derive(decoded,kind,frame,framesPerAngle=1) {
 if(kind==='farm_hut'||kind==='farm_field')return splitFarm(decoded,kind);
 if(kind==='galley_rowing')return rowing(decoded,Math.floor(frame/framesPerAngle),(frame%framesPerAngle)/framesPerAngle);
 if(kind==='cliff_foot')return cliffFoot(decoded);
 throw new Error('Unknown source presentation derivative: '+kind);
}
module.exports={derive,FARM_HUT,GALLEY_OARS};
