"""Local, resumable AI execution evidence. No network or third-party packages."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import time
from contextlib import contextmanager
from concurrent.futures import ThreadPoolExecutor, as_completed
from ai_process_metrics import ProcessMetrics

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "prototype"
STATE = ROOT / "doc/ror-modern/AI_COMPETITIVE_EXECUTION_STATE_2026-10-29.json"
ENGINE = ROOT / ".tools/godot-4.7.2/Godot_v4.7.2-stable_win64.exe"
PACK = None
ARENA_TIMEOUT_SECONDS = 3600
RUN_ID = "competitive-20261030"
QA = PROJECT / "qa/ai-competitive" / RUN_ID
TEMP = ROOT / ".tmp/ai-competitive" / RUN_ID
FLAGS = getattr(subprocess, "CREATE_NO_WINDOW", 0)


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1048576), b""):
            h.update(block)
    return h.hexdigest()


def fingerprint(value) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False,
                                     separators=(",", ":")).encode()).hexdigest()


def atomic(path: Path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    pending = path.with_suffix(path.suffix + ".pending")
    pending.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    json.loads(pending.read_text(encoding="utf-8"))
    os.replace(pending, path)


def event(kind, **fields):
    QA.mkdir(parents=True, exist_ok=True)
    with (QA / "events.jsonl").open("a", encoding="utf-8") as f:
        f.write(json.dumps({"time_utc": time.time(), "kind": kind, **fields}, ensure_ascii=False) + "\n")


def source_hashes():
    paths = list((PROJECT / "scripts").glob("*.gd"))
    paths += [p for p in (PROJECT / "data/ai").rglob("*.json") if "manifests" not in p.parts]
    paths += list((PROJECT / "ai_baselines/v1").rglob("*.gd"))
    paths += list((PROJECT / "tools").glob("ai_*.gd"))
    paths += list((ROOT / "native/ror_pathfinding/src").glob("*"))
    paths += [PROJECT / "project.godot", PROJECT / "export_presets.cfg", PROJECT / "main.gd", PROJECT / "main.tscn",PROJECT/"ror_pathfinding.gdextension",ENGINE,Path(__file__),ROOT/"tools/ai_tune.py",ROOT/"tools/ai_process_metrics.py"]
    paths += list((PROJECT / "ai_baselines/v1").glob("*.json"))
    paths += [p for p in (PROJECT / "bin").glob("*.dll") if not p.name.startswith("~")]
    paths += [p for p in (PROJECT / "assets/generated").glob("*.json")
              if any(x in p.name for x in ("catalog", "manifest", "gamespec"))]
    return {p.relative_to(ROOT).as_posix(): digest(p) for p in sorted(set(paths)) if p.is_file()}


def preflight():
    QA.mkdir(parents=True, exist_ok=True)
    manifest_path = QA / "initial_manifest.json"
    if manifest_path.exists():
        print("Existing immutable initial manifest:", manifest_path, flush=True)
        return
    hashes = source_hashes()
    for relative in hashes:
        src, dst = ROOT / relative, TEMP / "source" / relative
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
    dirty = subprocess.check_output(["git", "status", "--porcelain=v1", "-uall"], cwd=ROOT).decode("utf-8", errors="replace")
    # Archive every dirty text source, including non-AI owners, before touching it.
    for line in dirty.splitlines():
        relative = line[3:].strip('"')
        src = ROOT / relative
        if src.is_file() and src.suffix in (".gd", ".md", ".json", ".cpp", ".h", ".ps1", ".godot", ".cfg", ".py"):
            dst = TEMP / "dirty" / relative
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
    versions={}
    for name,filename,constant in (("archive","game_save_archive.gd","FORMAT_VERSION"),
                                   ("checkpoint","game_checkpoint.gd","VERSION"),
                                   ("replay","replay_system.gd","FORMAT_VERSION")):
        text=(PROJECT/"scripts"/filename).read_text(encoding="utf-8")
        declared=re.search(r"^const\s+"+constant+r"\s*(?::\s*int\s*)?:?=\s*(\d+)\s*$",text,re.MULTILINE)
        if not declared: raise ValueError("Cannot identify the runtime version in "+filename)
        versions[name]=int(declared.group(1))
    manifest = {"schema_version": 1, "run_id": RUN_ID, "date": time.strftime("%Y-%m-%d"),
                "timezone": "Europe/Moscow", "hardware": platform.uname()._asdict(),
                "logical_cpus": os.cpu_count(), "engine_sha256": digest(ENGINE),
                "python": platform.python_version(), "initial_hashes": hashes,
                "source_bundle_sha256": fingerprint(hashes), "initial_dirty": dirty,
                "versions": versions}
    atomic(manifest_path, manifest)
    state = json.loads(STATE.read_text(encoding="utf-8"))
    state.update(execution_status="in_progress", run_id=RUN_ID, active_task="AI00-01")
    atomic(STATE, state)
    event("preflight", files=len(hashes), source_bundle=manifest["source_bundle_sha256"])
    print(json.dumps({"files_preserved": len(hashes), "manifest": str(manifest_path)}), flush=True)


def freeze():
    target = PROJECT / "ai_baselines/v1"
    manifest_path = target / "manifest.json"
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        for relative, expected in manifest["frozen_hashes"].items():
            if digest(PROJECT / relative) != expected:
                raise ValueError("Frozen baseline was modified: " + relative)
        print("Verified existing baseline", len(manifest["frozen_hashes"]), flush=True)
        return
    pending = ["scripts/ai_player.gd"]
    sources, shared = {}, {}
    rx = re.compile(r'(?:preload|load)\("res://([^"\n]+\.gd)"\)')
    while pending:
        relative = pending.pop()
        if relative in sources:
            continue
        text = (PROJECT / relative).read_text(encoding="utf-8-sig")
        sources[relative] = text
        for dependency in rx.findall(text):
            name = Path(dependency).name
            if name.startswith(("ai_", "source_ai_", "source_campaign_ai")):
                pending.append(dependency)
            else:
                shared[dependency] = digest(PROJECT / dependency)
    names = {}
    for text in sources.values():
        for name in re.findall(r"(?m)^class_name (\w+)", text):
            names[name] = "BaselineV1" + name
    transformed = {}
    for relative, text in sources.items():
        for source in sources:
            text = text.replace('"res://' + source + '"', '"res://ai_baselines/v1/' + source + '"')
        for name, replacement in names.items():
            text = re.sub(r"\b" + re.escape(name) + r"\b", replacement, text)
        out = target / relative
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(text, encoding="utf-8", newline="\n")
        transformed[out.relative_to(PROJECT).as_posix()] = digest(out)
    catalog = PROJECT / "data/ai/skirmish_policies.json"
    shutil.copy2(catalog, target / "skirmish_policies.json")
    transformed["ai_baselines/v1/skirmish_policies.json"] = digest(target / "skirmish_policies.json")
    atomic(manifest_path, {"schema_version": 1, "id": "baseline_v1", "run_id": RUN_ID,
                          "source_hashes": {k: hashlib.sha256(v.encode()).hexdigest() for k, v in sources.items()},
                          "frozen_hashes": transformed, "shared_dependencies": shared,
                          "allowed_shared_reason": "command ABI and authoritative engine rules; hashes define arena series"})
    event("baseline_frozen", modules=len(sources), fingerprint=fingerprint(transformed))
    print("Frozen modules:", len(sources), "shared contracts:", len(shared), flush=True)


def run_process(script: str, output: Path, timeout: float = 300, args=(), project=PROJECT, entrypoint="ai-arena"):
    output.parent.mkdir(parents=True, exist_ok=True)
    command = [str(ENGINE), "--headless", "--path", str(project), "--log-file", str(output),
               "--script", str(script) if Path(script).is_absolute() else "res://" + script]
    if PACK:
        if PACK!=ENGINE.with_suffix(".pck"): raise ValueError("Release runtime must use its own adjacent package")
        command=[str(ENGINE),"--headless","--log-file",str(output)]
        args=["--"+entrypoint,*(args or [])]
    if args:
        command += ["--", *args]
    started = time.monotonic()
    termination_error=None
    def terminate_child(process):
        # Termination itself can take time on Windows. Preserve a failed
        # process result instead of raising out of the whole resumable matrix.
        nonlocal termination_error
        killed=subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],capture_output=True,creationflags=FLAGS)
        try: process.wait(timeout=15)
        except subprocess.TimeoutExpired:
            try: process.kill(); process.wait(timeout=15)
            except (OSError,subprocess.TimeoutExpired) as exc:
                termination_error={"error":str(exc),"taskkill_exit":killed.returncode,
                    "taskkill_output":(killed.stdout+killed.stderr).decode(errors="replace")[-2000:]}
    with output.with_suffix(".stdout.log").open("w", encoding="utf-8") as log:
        process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, creationflags=FLAGS)
        with ProcessMetrics(process.pid) as usage:
            sampled=started-1; retained=started-30
            timed_out = False
            while process.poll() is None:
                now=time.monotonic()
                if now-sampled>=1:
                    usage.sample(retain=now-retained>=30); sampled=now
                    if now-retained>=30: retained=now
                if output.exists() and "SCRIPT ERROR:" in output.read_text(encoding="utf-8",errors="replace"):
                    terminate_child(process)
                    break
                if time.monotonic() - started > timeout:
                    timed_out = True
                    terminate_child(process)
                    break
                time.sleep(.1)
    text = output.read_text(encoding="utf-8", errors="replace") if output.exists() else "ERROR: Missing engine log"
    stdout=output.with_suffix(".stdout.log")
    if stdout.exists(): text+="\n"+stdout.read_text(encoding="utf-8",errors="replace")
    errors = list(dict.fromkeys(line for line in text.splitlines() if line.strip().startswith(("SCRIPT ERROR:", "ERROR:"))
              and "root certificate store" not in line))
    return {"script": script, "exit_code": process.returncode, "timeout": timed_out,
            "seconds": round(time.monotonic() - started, 3), "engine_errors": errors,
            "passed": process.returncode == 0 and not timed_out and not errors and termination_error is None,
            "termination_error":termination_error,
            "process_metrics":usage.report(),
            "log": output.relative_to(ROOT).as_posix()}


@contextmanager
def result_lock(path):
    path.parent.mkdir(parents=True,exist_ok=True)
    with path.with_suffix(".lock").open("a+b") as lock:
        lock.seek(0); lock.write(b"0"); lock.flush(); lock.seek(0)
        if os.name=="nt":
            import msvcrt
            msvcrt.locking(lock.fileno(),msvcrt.LK_LOCK,1)
        try: yield
        finally:
            if os.name=="nt":
                lock.seek(0); msvcrt.locking(lock.fileno(),msvcrt.LK_UNLCK,1)

def tests(scripts, timeout, user_args=None):
    source = fingerprint(source_hashes())
    result_path = QA / "tests/results.json"
    results = json.loads(result_path.read_text(encoding="utf-8")) if result_path.exists() else []
    for script in scripts:
        script = script.removeprefix("res://")
        test_path=PROJECT/script
        key = fingerprint({"source": source, "script": script,"test_sha256":digest(test_path) if test_path.exists() else "missing","runner":digest(Path(__file__)),"user_args":user_args or []})
        previous = next((x for x in results if x.get("key") == key and x.get("passed")), None)
        if previous:
            print("REUSE", script, flush=True)
            continue
        result = run_process(script, QA / "tests" / (Path(script).stem + "-" + key[:8] + "-" + str(time.time_ns()) + ".log"), timeout,user_args)
        result.update(key=key, source_sha256=source)
        with result_lock(result_path):
            results=json.loads(result_path.read_text(encoding="utf-8")) if result_path.exists() else []
            results.append(result)
            atomic(result_path, results)
        event("test", **result)
        print(json.dumps(result), flush=True)
    return all(next(x for x in reversed(results) if x["script"] == s.removeprefix("res://"))["passed"] for s in scripts)


def update(task_id, status, evidence, note):
    state = json.loads(STATE.read_text(encoding="utf-8"))
    if not any(t["id"] == task_id for s in state["stages"] for t in s["tasks"]):
        raise ValueError("Unknown task: " + task_id)
    for stage in state["stages"]:
        for task in stage["tasks"]:
            if task["id"] == task_id:
                for relative in evidence:
                    if not (ROOT / relative).exists():
                        raise ValueError("Evidence does not exist: " + relative)
                if status == "passed" and not evidence:
                    raise ValueError("Passed task needs evidence")
                task.update(status=status, evidence=evidence, next_action=note or None)
                state["active_task"] = task_id if status == "in_progress" else None
        statuses = [t["status"] for t in stage["tasks"]]
        stage["status"] = "passed" if all(x == "passed" for x in statuses) else "in_progress" if any(x != "pending" for x in statuses) else "pending"
        if stage["status"] == "passed": stage.update(functional_gate="passed", quality_gate="passed")
    state["completed_tasks"] = sum(t["status"] == "passed" for s in state["stages"] for t in s["tasks"])
    state["next_action"] = note
    atomic(STATE, state)
    event("task", task_id=task_id, status=status, evidence=evidence, note=note)


OPPONENTS = {
    "baseline": {},
    "rush": {"land_worker_target": 6, "worker_population_ratio": .35, "attack_ratio": .85,
             "minimum_attack_group_size": 2, "initial_attack_delay_ticks": 0},
    "ranged": {"opponent_role": "ranged", "minimum_attack_group_size": 5, "retreat_ratio": .95},
    "boom": {"land_worker_target": 14, "worker_population_ratio": .60,
             "initial_attack_delay_ticks": 1200, "economic_research_priority": 2.0},
    "turtle": {"construction_priorities": ["house", "barracks", "granary", "storage_pit", "tower", "archery_range", "farm", "town_center"],
               "building_limits": {"house": 8, "barracks": 1, "granary": 1, "storage_pit": 1, "tower": 4, "archery_range": 2, "farm": 12, "town_center": 3},
               "initial_attack_delay_ticks": 2400, "enemy_response_distance": 30.0},
    "raid": {"opponent_role": "raid", "minimum_attack_group_size": 2, "maximum_attack_group_size": 6, "attack_ratio": .9},
    "siege": {"opponent_role": "siege", "land_worker_target": 12, "minimum_attack_group_size": 6},
    "naval": {"opponent_role": "naval", "water_worker_target": 6, "minimum_naval_escort": 3},
}


def manifests():
    directory = PROJECT / "data/ai/arena/manifests"
    directory.mkdir(parents=True, exist_ok=True)
    for suite, count, seed_base in [("smoke",12,2000001),("dev",48,3000001),("validation",64,4000001),
                                     ("holdout",64,5000001),("challenge_holdout",32,6000001)]:
        path = directory / (suite + ".json")
        if path.exists():
            continue
        rows = []
        for index in range(count):
            map_type = ["grasslands", "narrows", "coastal", "islands"][index % 4]
            opponent = "baseline" if suite == "holdout" else list(OPPONENTS)[index % 8]
            if suite == "challenge_holdout": opponent = list(OPPONENTS)[1 + index % 7]
            if opponent == "naval": map_type = "islands" if index % 2 else "coastal"
            rows.append({"id": f"{suite}-{index:03}", "opponent": opponent,
                         "civilizations": [1 + index % 16, 1 + (index * 7 + 8) % 16],
                         "maximum_ticks": 72000 if map_type == "islands" else 36000,
                         "settings": {"seed": seed_base + index * 1009, "map_type_id": map_type,
                                      "map_size_id": "compact", "resource_preset_id": "high" if index%8==7 else "standard",
                                      "starting_age_id": "bronze" if index%8==6 else "stone",
                                      "ai_difficulty_id": "standard", "population_limit": [50,200,500][index%3]}})
        atomic(path, {"schema_version":1,"suite":suite,"rows":rows,"paired_positions":True})
    atomic(PROJECT / "data/ai/arena/opponents.json", {"schema_version":1,"algorithm_version":"baseline_v1","profiles":OPPONENTS})
    print("Frozen arena manifests ready", flush=True)


def arena(suite, subject, jobs, limit, ticks=None, overrides=None, project=PROJECT):
    manifest = json.loads((PROJECT / f"data/ai/arena/manifests/{suite}.json").read_text(encoding="utf-8"))
    snapshot_manifest = project / "arena_runtime_manifest.json"
    source = json.loads(snapshot_manifest.read_text(encoding="utf-8"))["source"] if snapshot_manifest.exists() else source_hashes()
    if PACK:
        source={"release_executable":digest(ENGINE),"release_package":digest(PACK),"runner":digest(Path(__file__)),
                "opponents":fingerprint(OPPONENTS),"native":digest(ENGINE.parent/"bin/ror_pathfinding.windows.template_release.x86_64.dll")}
    series = fingerprint({"source":source,"driver":digest(Path(__file__)),"subject":subject,"overrides":overrides or {},"manifest":manifest,"ticks_override":ticks,"timeout_seconds":ARENA_TIMEOUT_SECONDS})
    directory = QA / "arena" / series[:16]
    directory.mkdir(parents=True, exist_ok=True)
    atomic(directory / "series.json", {"series":series,"source":source,"suite":suite,"subject":subject,"overrides":overrides or {},"diagnostic_tick_limit":ticks})
    rows = manifest["rows"][:limit or None]
    map_source={key:value for key,value in source.items() if key.startswith(("prototype/scripts/random_map","prototype/scripts/skirmish","prototype/assets/generated/"))}
    map_revision=fingerprint(map_source or source)[:16]

    def paired(row):
        reports=[]
        # Two seats run sequentially so map materialisation is atomic and identical.
        for seat in (1,2):
            case_id = row["id"] + f"-seat{seat}"
            case = {"case_id":case_id,"base_id":row["id"],"series":series,"subject_team":seat,
                    "settings":row["settings"],"civilizations":row["civilizations"],"opponent":row["opponent"],
                    "opponent_policy":OPPONENTS[row["opponent"]],
                    "subject_policy":{"algorithm_version":subject,**(overrides or {})},
                    "maximum_ticks":ticks or row["maximum_ticks"],"wall_timeout_seconds":ARENA_TIMEOUT_SECONDS,"threaded":False,
                    "map_bundle":str(QA / "maps" / (row["id"]+"-"+map_revision+".dat"))}
            case["fingerprint"]=fingerprint(case)
            input_path = directory / (case_id+".input.json")
            output_path = directory / (case_id+".json")
            process_path=directory/(case_id+".process.json")
            if output_path.exists() and process_path.exists():
                old=read_result(output_path)
                old_process=read_result(process_path)
                if (old.get("fingerprint")==case["fingerprint"] and old.get("status") in ["WIN","LOSS","DRAW_TIME_LIMIT"]
                        and old_process.get("fingerprint")==case["fingerprint"] and old_process.get("passed")):
                    old["subject_civilization"]=case["civilizations"][0]
                    old["opponent_civilization"]=case["civilizations"][1]
                    reports.append(old); print("REUSE",case_id,old["status"],flush=True); continue
            # A crashed or interrupted attempt stays reviewable. A complete
            # gameplay report alone does not prove that engine shutdown passed.
            if output_path.exists() or process_path.exists():
                attempt=1
                while (directory/(case_id+f".attempt-{attempt}")).exists(): attempt+=1
                previous=directory/(case_id+f".attempt-{attempt}"); previous.mkdir()
                for previous_file in directory.glob(case_id+".*"):
                    if previous_file.is_file(): shutil.copy2(previous_file,previous/previous_file.name)
                output_path.unlink(missing_ok=True); process_path.unlink(missing_ok=True)
            atomic(input_path,case)
            (QA / "maps").mkdir(parents=True,exist_ok=True)
            process = run_process("tools/ai_arena.gd",directory/(case_id+".engine.log"),ARENA_TIMEOUT_SECONDS+15,
                                  ["--case="+str(input_path),"--output="+str(output_path)],project)
            atomic(process_path,{"fingerprint":case["fingerprint"],**process})
            if output_path.exists():
                report=read_result(output_path)
                if not report:
                    shutil.copy2(output_path,output_path.with_suffix(".invalid-result.txt"))
                    report={"case_id":case_id,"base_id":row["id"],"series":series,"fingerprint":case["fingerprint"],"status":"RESULT_ERROR","process":process}
                    atomic(output_path,report)
                if report.get("fingerprint")!=case["fingerprint"] or (not process["passed"] and report.get("status") in ("WIN","LOSS","DRAW_TIME_LIMIT")):
                    report.update(status="RUNTIME_ERROR",process=process)
                    atomic(output_path,report)
            else:
                report={"case_id":case_id,"base_id":row["id"],"series":series,"fingerprint":case["fingerprint"],
                        "status":"INFRA_TIMEOUT" if process["timeout"] else "CRASH","process":process}
                atomic(output_path,report)
            report["subject_civilization"]=case["civilizations"][0]
            report["opponent_civilization"]=case["civilizations"][1]
            atomic(output_path,report)
            reports.append(report)
            event("arena_case",case_id=case_id,status=report["status"],series=series)
            print("ARENA",case_id,report["status"],"tick",report.get("tick"),"seconds",report.get("wall_seconds"),flush=True)
        return reports

    reports=[]
    with ThreadPoolExecutor(max_workers=jobs) as executor:
        futures=[executor.submit(paired,row) for row in rows]
        for future in as_completed(futures):
            reports.extend(future.result())
            atomic(directory/"summary.json",summarize(reports))
    summary=summarize(reports)
    summary.update(series=series,directory=directory.relative_to(ROOT).as_posix(),diagnostic_tick_limit=ticks)
    atomic(directory/"summary.json",summary)
    print(json.dumps({"directory":str(directory),**summary}),flush=True)
    return summary


def read_result(path):
    try:
        result=json.loads(path.read_text(encoding="utf-8"))
        return result if isinstance(result,dict) else {}
    except (OSError,ValueError):
        return {}


def freeze_runtime():
    source=source_hashes()
    target = TEMP / ("baseline_runtime_" + fingerprint(source)[:12])
    if (target / "arena_runtime_manifest.json").exists():
        print(target, flush=True); return
    # Copy code, scenes, declarations and policy data. Asset/import caches are
    # read-only junctions created by the PowerShell bootstrap below.
    for relative in ("scripts", "tools", "tests", "data", "ai_baselines", "bin"):
        src = PROJECT / relative
        if src.exists(): shutil.copytree(src,target/relative,dirs_exist_ok=True)
    for name in ("project.godot","main.gd","main.tscn","export_presets.cfg","ror_pathfinding.gdextension"):
        if (PROJECT/name).exists(): shutil.copy2(PROJECT/name,target/name)
    (target/".godot").mkdir(parents=True,exist_ok=True)
    for name in ("global_script_class_cache.cfg","extension_list.cfg"):
        if (PROJECT/".godot"/name).exists(): shutil.copy2(PROJECT/".godot"/name,target/".godot"/name)
    if source_hashes()!=source:
        raise RuntimeError("Source changed while freezing; retry after the build or edit completes")
    atomic(target/"arena_runtime_manifest.json",{"source":source,"run_id":RUN_ID,"immutable":True})
    print(target,flush=True)


def summarize(reports):
    series={row["series"] for row in reports if "series" in row}
    if len(series)>1: raise ValueError("Incompatible arena series cannot be pooled")
    counts={}
    blocks={}
    for row in reports:
        status=row["status"]; counts[status]=counts.get(status,0)+1
        if status in ("WIN","LOSS","DRAW_TIME_LIMIT"):
            blocks.setdefault(row["base_id"],[]).append(1 if status=="WIN" else .5 if status=="DRAW_TIME_LIMIT" else 0)
    values=[sum(blocks[key])/len(blocks[key]) for key in sorted(blocks) if len(blocks[key])==2]
    import random
    rng=random.Random(20261030)
    bootstrap=sorted(sum(rng.choices(values,k=len(values)))/len(values) for _ in range(2000)) if values else []
    strata={}
    for field in ("opponent","map_type_id","population_limit","subject_civilization","resource_preset_id","starting_age_id"):
        groups={}
        for row in reports:
            value=row.get(field,row.get("settings",{}).get(field,"unknown"))
            groups.setdefault(str(value),[]).append(row)
        strata[field]={}
        for name in sorted(groups):
            rows=groups[name]
            scores=[1 if row["status"]=="WIN" else 0 if row["status"]=="LOSS" else .5 for row in rows if row["status"] in ("WIN","LOSS","DRAW_TIME_LIMIT")]
            strata[field][name]={"reports":len(rows),"score":sum(scores)/len(scores) if scores else None}
    return {"statistics_schema":2,"resampling_order":"sorted_base_id","reports":len(reports),"counts":dict(sorted(counts.items())),"paired_blocks":len(values),"strata":strata,
            "score":sum(values)/len(values) if values else None,
            "seed_block_95_percent":[bootstrap[49],bootstrap[1949]] if bootstrap else None,
            "errors":sum(n for key,n in counts.items() if key not in ("WIN","LOSS","DRAW_TIME_LIMIT"))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("preflight")
    sub.add_parser("freeze")
    sub.add_parser("manifests")
    sub.add_parser("freeze-runtime")
    a=sub.add_parser("arena")
    a.add_argument("--suite",choices=["smoke","dev","validation","holdout","challenge_holdout"],default="smoke")
    a.add_argument("--subject",default="competitive_v2")
    a.add_argument("--jobs",type=int,default=3)
    a.add_argument("--limit",type=int,default=0)
    a.add_argument("--ticks",type=int)
    a.add_argument("--project",type=Path,default=PROJECT)
    a.add_argument("--policy",type=Path)
    a.add_argument("--engine",type=Path)
    a.add_argument("--pack",type=Path)
    t = sub.add_parser("tests")
    t.add_argument("scripts", nargs="+")
    t.add_argument("--timeout", type=float, default=300)
    t.add_argument("--user-arg",action="append",default=[])
    u = sub.add_parser("task")
    u.add_argument("id")
    u.add_argument("--status", choices=["pending", "in_progress", "passed", "quality_gap", "blocked"], required=True)
    u.add_argument("--evidence", nargs="*", default=[])
    u.add_argument("--note", default="")
    args = parser.parse_args()
    if args.command == "preflight": preflight()
    if args.command == "freeze": freeze()
    if args.command == "manifests": manifests()
    if args.command == "freeze-runtime": freeze_runtime()
    if args.command == "arena":
        global ENGINE,PACK
        if args.engine: ENGINE=args.engine.resolve()
        if args.pack: PACK=args.pack.resolve()
        policy=json.loads(args.policy.read_text(encoding="utf-8")) if args.policy else None
        result=arena(args.suite,args.subject,args.jobs,args.limit,args.ticks,overrides=policy,project=args.project)
        if result["errors"]: raise SystemExit(1)
    if args.command == "tests" and not tests(args.scripts, args.timeout,args.user_arg): raise SystemExit(1)
    if args.command == "task": update(args.id, args.status, args.evidence, args.note)


if __name__ == "__main__":
    main()
