from pathlib import Path
from PIL import Image, ImageDraw
ROOT=Path('D:/Develop/Rise of Rome/visualizations/qwen-image-2.1-sample-2026-10-06')
im=Image.new('RGB',(1024,1024),'#ffffff'); d=ImageDraw.Draw(im)
# This independently drawn pose diagram contains no game art.
legs=[
 [((244,279),(222,345),(206,401),(226,420)),((263,283),(292,348),(313,430),(343,443))],
 [((244,279),(252,354),(251,436),(281,444)),((263,283),(299,328),(279,378),(302,388))],
 [((244,279),(286,351),(308,432),(339,445)),((263,283),(233,342),(214,402),(238,418))],
 [((244,279),(287,331),(244,381),(268,394)),((263,283),(270,355),(269,436),(301,446))]]
arms=[
 [((238,157),(254,215),(298,251)),((272,158),(256,216),(240,259))],
 [((238,157),(236,218),(250,262)),((272,158),(282,213),(292,253))],
 [((238,157),(224,218),(212,258)),((272,158),(284,213),(303,247))],
 [((238,157),(258,215),(282,250)),((272,158),(256,219),(242,262))]]
for i in range(4):
 ox=(i%2)*512; oy=(i//2)*512
 def move(p): return p[0]+ox,p[1]+oy
 d.text((ox+25,oy+15),f'{i+1}: '+('STRIDE' if i%2==0 else 'PASSING - FEET UNDER HIPS'),fill='#202020')
 d.line([move((100,449)),move((412,449))],fill='#aaaaaa',width=2)
 d.ellipse((ox+234,oy+58,ox+287,oy+118),fill='#b0b0b0',outline='#555555',width=2)
 d.polygon([move(p) for p in [(235,148),(275,148),(273,274),(239,274)]],fill='#c5c5c5',outline='#666666')
 d.line([move((260,119)),move((259,148))],fill='#777777',width=14)
 for idx,leg in enumerate(legs[i]):
  color='#aa493c' if idx==0 else '#356ba0'
  d.line([move(p) for p in leg],fill=color,width=15,joint='curve')
  for p in leg[:3]:
   x,y=move(p); d.ellipse((x-8,y-8,x+8,y+8),fill=color)
 for idx,arm in enumerate(arms[i]):
  color='#aa493c' if idx==0 else '#356ba0'
  d.line([move(p) for p in arm],fill=color,width=13,joint='curve')
 d.line([move((244,278)),move((266,284))],fill='#555555',width=14)
im.save(ROOT/'worker-pose-guide.png')