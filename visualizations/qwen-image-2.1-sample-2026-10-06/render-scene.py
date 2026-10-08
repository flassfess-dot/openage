from pathlib import Path
import json, subprocess, time
ROOT=Path(__file__).resolve().parent
GODOT=Path('D:/Develop/Rise of Rome/.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe')
started=time.monotonic()
command=[str(GODOT),'--path',str(ROOT),'--script','assemble-scene.gd','--position','-10000,-10000']
with (ROOT/'assembly.log').open('w',encoding='utf-8') as log:
 result=subprocess.run(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW,timeout=180)
if result.returncode: raise RuntimeError('Godot assembly failed, see assembly.log')
if not (ROOT/'assembled-scene.png').is_file(): raise RuntimeError('No scene capture produced')
print(json.dumps({'status':'complete','renderer':'Godot 4.7.2','elapsed_seconds':round(time.monotonic()-started,2),'capture':'assembled-scene.png'}))