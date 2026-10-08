from pathlib import Path
import argparse, json, runpy, subprocess, time
from datetime import datetime, timezone
from PIL import Image
ROOT=Path(__file__).resolve().parent
TOOLS=Path('D:/Develop/Rise of Rome/.tools/qwen-image-2.1-local')
ASSETS=runpy.run_path(str(ROOT/'generate-sample.py'))['ASSETS']
ASSETS['worker-walk-v2-sheet']={
 'size':[1024,1024],'seed':1060205,'references':['worker-walk-sheet.png','worker-pose-guide.png'],
 'prompt':'This is an RGBA image with transparency. Image 1 shows our approved villager design and fine pen-and-wash rendering. Image 2 is a schematic guide to four DISTINCT phases of a walk. Generate exactly four full-body sprites in a precise 2 by 2 grid. Keep the same adult man, face, short dark hair, cream linen knee-length tunic, reddish-brown belt, brown sandals, proportions, illustration style, lighting and fixed three-quarter right-facing camera as Image 1. Change ONLY his poses to match the four skeletons in Image 2. Pose 1 and 3 have a wide stride, with opposite arms swinging. Pose 2 and 4 MUST be different from the stride poses: the weight-bearing leg is almost straight directly beneath the hip, the other knee is bent and its foot is lifted, with both feet close to the body. For every cell follow the hip, knee, ankle and arm positions of the corresponding diagram. The red and blue are schematic limb identifiers ONLY, never paint the final man red or blue. The diagram is a pose reference, not the final drawing style. Same body size and baseline in all cells, entire figures visible, generous empty margins, no overlap. No text, grid lines, reference diagrams, numbers, cast shadows, ground, scenery or background. The image has alpha channel and the background is transparent.'}
parser=argparse.ArgumentParser(); parser.add_argument('asset',choices=ASSETS); parser.add_argument('--steps',type=int,default=40)
args=parser.parse_args(); asset=ASSETS[args.asset]
exes=list((TOOLS/'bin').rglob('sd-cli.exe'))
if not exes: raise RuntimeError('Local runtime is not installed yet')
exe=exes[0]; models=TOOLS/'models'; output=ROOT/(args.asset+'.png')
command=[str(exe),'--diffusion-model',str(models/'qwen_image_2.1-Q4_K.gguf'),
 '--llm',str(models/'Qwen3VL-8B-Instruct-Q4_K_M.gguf'),
 '--vae',str(models/'vae/qwen_image_2.1_vae_bf16.safetensors'),
 '-p',asset['prompt'],'--cfg-scale','1.0','--sampling-method','euler','--steps',str(args.steps),
 '-W',str(asset['size'][0]),'-H',str(asset['size'][1]),'-s',str(asset['seed']),
 '--auto-fit','on','--mmap','--fa','--vae-tiling','-t','4','-o',str(output)]
references=asset.get('references') or ([asset['reference']] if asset.get('reference') else [])
if references:
 command+=['--llm_vision',str(models/'mmproj-Qwen3VL-8B-Instruct-F16.gguf'),
             '--model-args','qwen_image_2_1_prefix_cache_type=q8_0',
             '--image-preprocess','target=ref,mode=fit-pad,width=512,height=512']
 for name in references: command+=['-r',str(ROOT/name)]
started=time.monotonic()
record={'model':'Qwen/Qwen-Image-2.1','provider':'local stable-diffusion.cpp',
 'quantization':'Q4_K','text_encoder_quantization':'Q4_K_M','runtime_release':'master-931-9db0db6',
 'hardware':'RTX 3080 Ti 12GB, i7-7700, 16GB RAM','asset':args.asset,'settings':asset,
 'num_inference_steps':args.steps,'cfg_scale':1.0,'reference_files':references,'reference_resolution':512 if references else None,
 'timestamp':datetime.now(timezone.utc).isoformat(),'status':'started'}
logpath=ROOT/(args.asset+'.local.log'); metapath=ROOT/(args.asset+'.generation.json')
print(json.dumps({'phase':'local_generation_started','asset':args.asset,'steps':args.steps}),flush=True)
try:
 with logpath.open('w',encoding='utf-8') as log:
  result=subprocess.run(command,cwd=exe.parent,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
 if result.returncode!=0: raise RuntimeError('Runtime exited with code '+str(result.returncode)+', see '+logpath.name)
 if not output.is_file(): raise RuntimeError('Runtime created no output image')
 with Image.open(output) as im:
  alpha=im.getchannel('A') if 'A' in im.getbands() else None
  record.update({'status':'complete','file':output.name,'size':list(im.size),'mode':im.mode,'alpha_extrema':list(alpha.getextrema()) if alpha else None})
 print(json.dumps({k:record[k] for k in ['status','file','size','mode','alpha_extrema']}),flush=True)
except Exception as exc:
 record.update({'status':'failed','error':str(exc)}); print(json.dumps({'status':'failed','error':str(exc)}),flush=True); raise
finally:
 record['elapsed_seconds']=round(time.monotonic()-started,2)
 metapath.write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
 print(json.dumps({'elapsed_seconds':record['elapsed_seconds']}),flush=True)