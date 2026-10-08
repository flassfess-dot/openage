from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib, json, time, urllib.request, zipfile
from huggingface_hub import hf_hub_download
ROOT=Path('D:/Develop/Rise of Rome/.tools/qwen-image-2.1-local')
ROOT.mkdir(parents=True,exist_ok=True)
START=time.monotonic()
MODEL_FILES=[
 ('leejet/Qwen-Image-2.1-GGUF','qwen_image_2.1-Q4_K.gguf'),
 ('Qwen/Qwen3-VL-8B-Instruct-GGUF','Qwen3VL-8B-Instruct-Q4_K_M.gguf'),
 ('Qwen/Qwen3-VL-8B-Instruct-GGUF','mmproj-Qwen3VL-8B-Instruct-F16.gguf'),
 ('Comfy-Org/Qwen-Image-2.1','vae/qwen_image_2.1_vae_bf16.safetensors')]
TAG='master-931-9db0db6'
RELEASE_API='https://api.github.com/repos/leejet/stable-diffusion.cpp/releases/tags/'+TAG
req=urllib.request.Request(RELEASE_API,headers={'User-Agent':'qwen-art-evaluation'})
release=json.load(urllib.request.urlopen(req,timeout=60))
ZIP_NAMES=['sd-master-9db0db6-bin-win-cuda12-x64.zip','cudart-sd-bin-win-cu12-x64.zip']
ZIP_ASSETS=[a for a in release['assets'] if a['name'] in ZIP_NAMES]

def model(repo,name):
 print(json.dumps({'phase':'downloading_model','repo':repo,'file':name}),flush=True)
 listing=json.load(urllib.request.urlopen('https://huggingface.co/api/models/'+repo+'/tree/main?recursive=true&limit=1000',timeout=60))
 entry=next(x for x in listing if x['path']==name)
 expected=entry['size']; digest=entry.get('lfs',{}).get('oid')
 p=ROOT/'models'/name; p.parent.mkdir(parents=True,exist_ok=True)
 partial=p.with_name(p.name+'.download')
 if not p.exists() or p.stat().st_size!=expected:
  offset=partial.stat().st_size if partial.exists() else 0
  url='https://huggingface.co/'+repo+'/resolve/main/'+name+'?download=true'
  chunk_size=256*1024*1024
  chunks=[(start,min(start+chunk_size-1,expected-1)) for start in range(offset,expected,chunk_size)]
  part_dir=p.with_name(p.name+'.parts'); part_dir.mkdir(exist_ok=True)
  def fetch_range(bounds):
   begin,end=bounds; dest=part_dir/(str(begin)+'-'+str(end)+'.part'); count=end-begin+1
   if dest.exists() and dest.stat().st_size==count: return dest
   request=urllib.request.Request(url,headers={'Range':f'bytes={begin}-{end}','User-Agent':'qwen-art-evaluation'})
   with urllib.request.urlopen(request,timeout=120) as src:
    if src.status!=206: raise RuntimeError('Server did not accept range transfer')
    with dest.open('wb') as dst:
     while data:=src.read(4*1024*1024): dst.write(data)
   if dest.stat().st_size!=count: raise RuntimeError('Incomplete range transfer')
   print(json.dumps({'phase':'range_complete','file':name,'begin':begin,'end':end,'bytes':count}),flush=True)
   return dest
  print(json.dumps({'phase':'parallel_transfer_started','file':name,'offset':offset,'total_bytes':expected,'ranges':len(chunks)}),flush=True)
  with ThreadPoolExecutor(max_workers=6) as range_pool:
   parts=list(range_pool.map(fetch_range,chunks))
  with partial.open('ab' if offset else 'wb') as dst:
   for part in parts:
    with part.open('rb') as stream:
     while data:=stream.read(8*1024*1024): dst.write(data)
  if partial.stat().st_size!=expected: raise RuntimeError('Unexpected model download size')
  partial.replace(p)
 if digest:
  h=hashlib.sha256()
  with p.open('rb') as stream:
   while chunk:=stream.read(8*1024*1024): h.update(chunk)
  if h.hexdigest()!=digest: raise RuntimeError('Model checksum mismatch for '+name)
 return {'repo':repo,'file':name,'path':str(p),'bytes':p.stat().st_size,'sha256':digest}

def binary(asset):
 target=ROOT/asset['name']
 print(json.dumps({'phase':'downloading_runtime','file':asset['name'],'bytes':asset['size']}),flush=True)
 if not target.exists() or target.stat().st_size!=asset['size']:
  request=urllib.request.Request(asset['browser_download_url'],headers={'User-Agent':'qwen-art-evaluation'})
  with urllib.request.urlopen(request,timeout=120) as src, target.open('wb') as dst:
   while chunk:=src.read(4*1024*1024): dst.write(chunk)
 digest=asset.get('digest')
 if digest and digest.startswith('sha256:'):
  h=hashlib.sha256()
  with target.open('rb') as f:
   while chunk:=f.read(4*1024*1024): h.update(chunk)
  if h.hexdigest()!=digest.split(':',1)[1]: raise RuntimeError('Runtime checksum mismatch')
 dest=(ROOT/'bin').resolve()
 dest.mkdir(exist_ok=True)
 with zipfile.ZipFile(target) as archive:
  for entry in archive.infolist():
   path=(dest/entry.filename).resolve()
   if not path.is_relative_to(dest): raise RuntimeError('Unsafe archive path')
  archive.extractall(dest)
 return {'file':asset['name'],'path':str(target),'bytes':target.stat().st_size,'digest':digest}

records=[]
with ThreadPoolExecutor(max_workers=3) as pool:
 futures=[pool.submit(binary,a) for a in ZIP_ASSETS]+[pool.submit(model,*f) for f in MODEL_FILES]
 for future in as_completed(futures):
  result=future.result(); records.append(result)
  print(json.dumps({'phase':'download_complete',**result}),flush=True)
manifest={'model':'Qwen/Qwen-Image-2.1','quantization':'Q4_K','text_encoder_quantization':'Q4_K_M','runtime_release':TAG,'files':records,'elapsed_seconds':round(time.monotonic()-START,2)}
(ROOT/'installation.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print(json.dumps({'phase':'installation_complete','elapsed_seconds':manifest['elapsed_seconds']}),flush=True)