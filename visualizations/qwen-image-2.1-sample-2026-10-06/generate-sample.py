from pathlib import Path
import argparse, json, shutil, time
from datetime import datetime, timezone
from gradio_client import Client, handle_file
from PIL import Image

ROOT = Path(__file__).resolve().parent
STYLE = 'Detailed original ancient Mediterranean RTS illustration. Very fine warm brown pen contours, sparse restrained hatching, soft hand-painted natural colors, only a whisper of parchment character. No sepia filter, heavy paper grain, glossy 3D rendering or thick black cartoon outlines. Orthographic game camera looking down 30 degrees, 2:1 ground-plane diagonals, parallel edges, soft daylight from upper left.'
ALPHA = 'This is an RGBA image with transparency. '
TAIL = ' The image has alpha channel and the background is transparent. No text, labels, border, watermark, terrain tile or scenery. Entire object visible with generous empty margins.'
ASSETS = {
 'house': {'size': [1024,1024], 'seed':1060101, 'prompt': ALPHA + 'ONE standalone compact single-storey Mediterranean cottage. Warm ivory plaster over a limestone base, low terracotta tiled gable roof, a timber entrance door, one small recessed window, one clay jar beside the door. Modest practical architecture, two walls and roof visible, no columns, monumental facade, compound, enclosed yard, people or vegetation. Small cottage: door height about one third of the facade height. Centered. ' + STYLE + TAIL},
 'oak': {'size':[1024,1024], 'seed':1060102, 'reference':'house.png', 'prompt':ALPHA + 'Use Image 1 only as the drawing style and daylight reference. Create ONE freestanding mature Mediterranean oak tree, irregular rounded crown, readable branching trunk and detailed bark. Olive, sage and moss-green foliage in broad masses, selected small leaf clusters, avoid uniformly busy leaf noise. No cottage, buildings, people, grass platform or other objects. ' + STYLE + TAIL},
 'grass': {'size':[1024,1024], 'seed':1060103, 'prompt':'ONE seamless square texture of short meadow turf for the ground of a hand-painted ancient Mediterranean RTS. Direct TOP-DOWN view, edge-to-edge opaque material, neutral diffuse lighting. Quiet muted natural sage and moss greens with extremely gentle broad blended variations. At least 95 percent reads as smooth continuous turf, only a few tiny understated tufts. Very low local contrast, no prominent blades, dark specks, stippling, grain, straw, flowers, stones or bright beige holes. The pen-and-parchment influence is nearly invisible in this background. Seamless wrapping on all four edges. No perspective, horizon, landscape, objects, paths, characters, text, grid, border or watermark. No sepia, yellow tint or photographic gritty detail.'},
 'earth': {'size':[1024,1024], 'seed':1060104, 'prompt':'ONE seamless square texture of quiet well-worn compacted earth for paths in a hand-painted ancient Mediterranean RTS. Direct TOP-DOWN view, opaque material filling the image, neutral diffuse lighting. Muted light gray-brown, taupe and warm beige, not yellow sand. Extremely low contrast, broad gentle painted variations, just a trace of texture. Seamless wrapping on all four edges. No drawn path shape, footprints, stones, cracks, dots, hatching carpet, grass, objects, scenery, perspective, horizon, text, border or watermark. Calm background beneath detailed sprites.'},
 'worker-walk-sheet': {'size':[1024,1024], 'seed':1060105, 'reference':'house.png', 'prompt':ALPHA + 'Use Image 1 only as the drawing style and lighting reference. Game sprite sheet with exactly FOUR full-body walking poses of the SAME adult Mediterranean male villager, evenly placed in a precise 2-column by 2-row grid, no grid lines. Reading order top-left, top-right, bottom-left, bottom-right is four phases of one walking cycle IN PLACE. All face screen LOWER-RIGHT at the same three-quarter angle. Phase 1 left foot forward and right arm forward; phase 2 feet passing under hips; phase 3 right foot forward and left arm forward; phase 4 opposite passing phase. Each figure has identical body height, head size and costume, a common baseline in its cell. Cream short linen tunic to knees, narrow reddish-brown belt, plain brown sandals, short dark hair, no hat or tools. Realistic adult proportions, readable hands and feet. Each entire figure inside its own cell, generous space between figures, no overlap. No building, terrain, ground platform or cast shadow. ' + STYLE + TAIL}
}
SPEC = {'model':'Qwen/Qwen-Image-2.1', 'provider':'https://huggingface.co/spaces/Qwen/Qwen-Image-2.1', 'purpose':'Standalone evaluation only, no game integration', 'assets':ASSETS}

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('asset',choices=ASSETS)
    args=parser.parse_args()
    asset=ASSETS[args.asset]
    (ROOT/'sample-spec.json').write_text(json.dumps(SPEC,ensure_ascii=False,indent=2),encoding='utf-8')
    client=Client('Qwen/Qwen-Image-2.1',download_files=ROOT/'downloads',verbose=False,httpx_kwargs={'timeout':120})
    ids={d.get('api_name'):d['id'] for d in client.config['dependencies'] if d.get('api_visibility')=='public'}
    print(json.dumps({'phase':'connected','model':SPEC['model'],'prepare':ids.get('prepare_request'),'generate':ids.get('generate_request')}),flush=True)
    refs=[]
    if asset.get('reference'):
        path=ROOT/asset['reference']
        if not path.is_file(): raise FileNotFoundError(path)
        refs=[{'image':handle_file(str(path)),'caption':None}]
    started=time.monotonic()
    record={'model':SPEC['model'],'provider':SPEC['provider'],'timestamp':datetime.now(timezone.utc).isoformat(),'asset':args.asset,'settings':asset,'num_inference_steps':40,'prompt_enhancement':False,'status':'started'}
    metadata=ROOT/(args.asset+'.generation.json')
    try:
        client.predict(refs,asset['prompt'],False,True,'speed',asset['seed'],False,fn_index=ids['prepare_request'])
        print(json.dumps({'phase':'prepared','asset':args.asset}),flush=True)
        result=client.predict(asset['prompt'],False,True,'./generation_logs_paper_case',asset['seed'],asset['size'][1],asset['size'][0],'',fn_index=ids['generate_request'])
        if isinstance(result,(list,tuple)): result=result[0]
        if isinstance(result,dict): result=result.get('path') or result.get('url')
        target=ROOT/(args.asset+'.png')
        shutil.copyfile(Path(result),target)
        with Image.open(target) as im:
            alpha=im.getchannel('A') if 'A' in im.getbands() else None
            record.update({'status':'complete','file':target.name,'size':list(im.size),'mode':im.mode,'alpha_extrema':list(alpha.getextrema()) if alpha else None})
        print(json.dumps({k:record[k] for k in ['status','file','size','mode','alpha_extrema']}),flush=True)
    except Exception as exc:
        record.update({'status':'failed','error':str(exc)})
        print(json.dumps({'status':'failed','error':str(exc)}),flush=True)
        raise
    finally:
        record['elapsed_seconds']=round(time.monotonic()-started,2)
        metadata.write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
        print(json.dumps({'elapsed_seconds':record['elapsed_seconds']}),flush=True)

if __name__=='__main__': main()