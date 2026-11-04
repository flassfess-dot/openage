"""Bind a Release artifact to unchanged AI/runtime sources during export."""
import argparse,json,subprocess,time
from pathlib import Path
import ai_competitive as ai

def stable_sources(sources):
    # Godot creates/removes hot-reload copies while importing an extension.
    # The actual library named by .gdextension is still included and checked.
    return {k:v for k,v in sources.items() if not (k.startswith("prototype/bin/") and Path(k).name.startswith("~"))}

def runtime_sources():
    sources=stable_sources({k:v for k,v in ai.source_hashes().items() if k.startswith(("prototype/","native/"))})
    verifier="prototype/tests/manual/verify_packaged_startup.gd"
    sources[verifier]=ai.digest(ai.ROOT/verifier)
    diagnostic="prototype/tests/manual/profile_saved_match_frames.gd"
    sources[diagnostic]=ai.digest(ai.ROOT/diagnostic)
    return sources

def begin(path):
    ai.atomic(path,{"schema_version":1,"started_utc":time.time(),"runtime_source_hashes":runtime_sources()})

def finish(path,directory):
    manifest=ai.read_result(path)
    if not manifest or stable_sources(manifest["runtime_source_hashes"])!=runtime_sources():
        raise RuntimeError("AI/runtime source changed during Release export; rebuild before packaging")
    excluded=sorted(set(manifest["runtime_source_hashes"])-set(stable_sources(manifest["runtime_source_hashes"])))
    manifest["runtime_source_hashes"]=stable_sources(manifest["runtime_source_hashes"])
    manifest["excluded_transient_hot_reload_files"]=excluded
    names=("Rise of Rome Prototype.exe","Rise of Rome Prototype.pck","bin/ror_pathfinding.windows.template_release.x86_64.dll")
    manifest.update(completed_utc=time.time(),git_revision=subprocess.check_output(["git","rev-parse","HEAD"],cwd=ai.ROOT,text=True).strip(),
                    artifacts={name:ai.digest(directory/name) for name in names},
                    scope="AI/runtime code, catalogs, native and startup verifier sources frozen during export; complete binary artifacts hashed separately")
    ai.atomic(directory/"build-provenance.json",manifest)

if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__); p.add_argument("mode",choices=("begin","finish")); p.add_argument("--state",type=Path,required=True);p.add_argument("--directory",type=Path)
    a=p.parse_args()
    if a.mode=="begin": begin(a.state)
    else: finish(a.state,a.directory)
