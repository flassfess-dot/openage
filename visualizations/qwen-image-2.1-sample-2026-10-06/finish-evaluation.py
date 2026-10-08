from pathlib import Path
import hashlib, json, zipfile
from PIL import Image
ROOT=Path(__file__).resolve().parent
for kind in ['scene','worker']:
 frames=[Image.open(ROOT/'frames'/f'{kind}-{i:02d}.png').convert('RGB') for i in range(4)]
 frames[0].save(ROOT/(('assembled-scene' if kind=='scene' else 'worker-walk')+'.gif'),save_all=True,append_images=frames[1:],duration=[170]*4,loop=0,optimize=False)
records=[]
for path in sorted(ROOT.glob('*.generation.json')):
 record=json.loads(path.read_text(encoding='utf-8'))
 records.append({'metadata_file':path.name,**record})
files=[]
for name in ['house.png','oak.png','grass.png','earth.png','worker-walk-sheet.png','worker-walk-v2-sheet.png']:
 path=ROOT/name
 if not path.exists(): continue
 with Image.open(path) as im:
  alpha=im.getchannel('A') if 'A' in im.getbands() else None
  files.append({'file':name,'size':list(im.size),'mode':im.mode,'alpha_extrema':list(alpha.getextrema()) if alpha else None,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
report={'model':'Qwen/Qwen-Image-2.1','purpose':'Private standalone evaluation, no game integration','cloud_model':'official full-model demo','local_model':'same Qwen-Image-2.1, Q4_K diffusion and Q4_K_M text encoder','hardware':'RTX 3080 Ti 12GB; i7-7700; 16GB RAM','direct_paid_generation_cost_usd':0,'electricity_and_Codex_usage_not_included':True,'records':records,'files':files,'commercial_model_license':'Separate Qwen commercial model license required; no purchase made','license_source':'https://huggingface.co/Qwen/Qwen-Image-2.1/blob/main/LICENSE'}
(ROOT/'evaluation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
selected=[path for path in ROOT.iterdir() if path.is_file() and path.suffix.lower() in ['.png','.gif','.json','.txt','.gd','.godot']]
selected += list((ROOT/'frames').glob('*.png'))
archive=ROOT/'qwen-image-2.1-evaluation.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as pack:
 for path in sorted(selected): pack.write(path,path.relative_to(ROOT))
print(json.dumps({'package':archive.name,'size_bytes':archive.stat().st_size,'assets':len(files),'attempts':len(records)}))