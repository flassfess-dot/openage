from PIL import Image, ImageDraw, ImageFont
from pathlib import Path
ROOT=Path('D:/Develop/Rise of Rome/visualizations/qwen-image-2.1-sample-2026-10-06')
board=Image.new('RGB',(1600,1000),'#f2ead9'); d=ImageDraw.Draw(board)
font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',27); small=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',20)
d.text((32,20),'Qwen-Image-2.1 — первые отдельные ассеты',font=font,fill='#453629')
d.rounded_rectangle((24,68,780,554),radius=12,fill='#f8f3e8',outline='#c4b596',width=2)
d.rounded_rectangle((820,68,1576,554),radius=12,fill='#f8f3e8',outline='#c4b596',width=2)
d.rounded_rectangle((24,578,1576,976),radius=12,fill='#f8f3e8',outline='#c4b596',width=2)
d.text((48,86),'Дом',font=font,fill='#453629'); d.text((846,86),'Дуб',font=font,fill='#453629')
d.text((48,594),'Рабочий: внешность сохранена, фазы ног требуют исправления',font=small,fill='#453629')
def crop(im):
 alpha=im.getchannel('A'); bounds=alpha.point(lambda v:255 if v>=40 else 0).getbbox()
 return im.crop(bounds)
def paste(im,cx,bottom,maxw,maxh):
 im=crop(im); scale=min(maxw/im.width,maxh/im.height)
 im=im.resize((round(im.width*scale),round(im.height*scale)),Image.Resampling.LANCZOS)
 board.paste(im,(round(cx-im.width/2),round(bottom-im.height)),im)
paste(Image.open(ROOT/'house.png'),404,526,645,375)
paste(Image.open(ROOT/'oak.png'),1198,530,625,391)
worker=Image.open(ROOT/'worker-walk-sheet.png')
for i in range(4):
 im=worker.crop(((i%2)*512,(i//2)*512,(i%2+1)*512,(i//2+1)*512))
 paste(im,245+i*370,950,230,286)
board.save(ROOT/'first-assets-preview.png')