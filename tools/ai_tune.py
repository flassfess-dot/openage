"""Bounded CPU policy search and deterministic linear ranking experiment.

Prepare is read-only toward gameplay defaults. --run executes real paired arena
matches. Holdout is deliberately absent from both fitting and selection.
"""
from __future__ import annotations
import argparse, json, random, sys
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor,as_completed
from threading import BoundedSemaphore
import ai_competitive as ai

RANGES={"attack_ratio":(1.05,1.5),"retreat_ratio":(.55,.9),
        "worker_population_ratio":(.35,.52),"forecast_seconds":(30.,60.),
        "plan_inertia":(4.,20.),"micro_repeat_ticks":(12,40),
        "maximum_economic_danger":(4.,10.),"minimum_naval_escort":(1,4)}
DIRECTORY=ai.QA/"tuning"

def experiment_source():
    if ai.PACK:
        return {"release_executable":ai.digest(ai.ENGINE),"release_package":ai.digest(ai.PACK),
                "native":ai.digest(ai.ENGINE.parent/"bin/ror_pathfinding.windows.template_release.x86_64.dll"),
                "tuning_driver":ai.digest(Path(__file__)),"process_driver":ai.digest(Path(ai.__file__))}
    return ai.source_hashes()

def prepare():
    path=DIRECTORY/"manifest.json"
    if path.exists():
        previous=json.loads(path.read_text(encoding="utf-8"))
        if previous["source"]!=experiment_source(): raise ValueError("Source changed; use a new experiment directory")
        return previous
    rng=random.Random(20261030)
    candidates=[]
    for generation in range(3):
        for number in range(8):
            parameters={key:rng.randint(low,high) if isinstance(low,int) else round(rng.uniform(low,high),4)
                        for key,(low,high) in RANGES.items()}
            if generation==0 and number==0: parameters={}
            identifier=f"g{generation}-c{number}"
            value={"id":identifier,"generation":generation,"parameters":parameters,"status":"pending"}
            candidates.append(value)
            ai.atomic(DIRECTORY/(identifier+".policy.json"),parameters)
    manifest={"schema_version":1,"seed":20261030,"ranges":RANGES,"candidates":candidates,
              "limits":{"dev_matches":384,"validation_matches":96},"source":experiment_source(),
              "human_data":"none","promotion":"requires independent validation, correctness and resource-budget gates"}
    ai.atomic(path,manifest)
    return manifest

def adapt_generation(manifest,generation,candidate_count):
    """Keep exploration and refine a prior dev winner; never read validation."""
    if generation==0:return
    saved=manifest.setdefault('adaptive_generations',{})
    if str(generation) in saved:return
    previous=[c for c in manifest['candidates'] if c['generation']<generation and c.get('status')=='evaluated'
              and c.get('parameters') and not c.get('result',{}).get('errors')]
    if not previous:return
    parent=max(previous,key=lambda c:((c['result'].get('score') or 0),c['id']))
    rng=random.Random(manifest['seed']+generation*1009)
    refined=[]
    for candidate in manifest['candidates']:
        number=int(candidate['id'].split('-c')[1])
        if candidate['generation']!=generation or number<candidate_count//2 or number>=candidate_count:continue
        if candidate.get('status')!='pending':raise ValueError('Cannot adapt an already evaluated generation')
        parameters={}
        for key,(low,high) in RANGES.items():
            radius=(high-low)*(.25/generation)
            value=max(low,min(high,parent['parameters'][key]+rng.uniform(-radius,radius)))
            parameters[key]=int(round(value)) if isinstance(low,int) else round(value,4)
        candidate.update(initial_random_parameters=candidate['parameters'],parameters=parameters,
                         parameter_origin={'parent':parent['id'],'split':'dev','generation':generation})
        ai.atomic(DIRECTORY/(candidate['id']+'.policy.json'),parameters)
        refined.append(candidate['id'])
    saved[str(generation)]={'parent':parent['id'],'parent_dev_score':parent['result'].get('score'),
        'refined':refined,'exploration':'First half retain seeded uniform proposals',
        'selection':'Best previously evaluated nonempty proposal on dev; unchanged incumbent remains a finalist'}
    ai.atomic(DIRECTORY/'manifest.json',manifest)

def features(candidate,facts):
    clamp=lambda x,lo,hi:max(lo,min(hi,x))
    return [1.,clamp(candidate.get("utility",0)/100,-2,2),clamp(facts.get("danger",0)/20,0,2),
            clamp(facts.get("army",0)/100,0,5),clamp(facts.get("workers",0)/100,0,5),
            (facts.get("age",100)-100)/3,clamp(facts.get("known",0)/100,0,10),
            float(candidate.get("id") in ("survive","develop"))]

def dataset(directories=None):
    # The current league owns its demonstrations. Scanning all historical QA
    # would silently mix earlier engines, short diagnostics and abandoned runs.
    if directories is None:
        saved=ai.read_result(DIRECTORY/"manifest.json")
        directories=[ai.ROOT/c["result"]["directory"] for c in saved.get("candidates",[]) if "result" in c]
    files=sorted({p for directory in directories for p in Path(directory).glob("*.json")})
    result=[]
    for file in files:
        if file.name.endswith(("input.json","progress.json","original-report.json")) or file.name in ("summary.json","series.json","validity.json"): continue
        validity=file.parent/"validity.json"
        summary=file.parent/"summary.json"
        if validity.exists() and not json.loads(validity.read_text()).get("valid_for_acceptance",False): continue
        if summary.exists() and json.loads(summary.read_text()).get("valid_for_acceptance") is False: continue
        report=ai.read_result(file)
        process=ai.read_result(file.with_suffix(".process.json"))
        if not process.get("passed") or process.get("fingerprint")!=report.get("fingerprint"): continue
        if report.get("status") not in ("WIN","LOSS","DRAW_TIME_LIMIT"): continue
        if not str(report.get("base_id","")).startswith(("dev-","validation-")): continue
        # Pending preparation frames may repeat the same policy sample. Keep
        # independent samples across the recorded game and bound fit memory.
        unique=[]; seen=set()
        for decision in report.get("strategy_trace",[]):
            key=ai.fingerprint(decision)
            if key not in seen: seen.add(key); unique.append(decision)
        unique.sort(key=lambda row:row["tick"])
        if len(unique)>128:
            unique=[unique[round(i*(len(unique)-1)/127)] for i in range(128)]
        for decision in unique:
            for candidate in decision.get("candidates",[]):
                result.append({"case":report["case_id"],"series":report["series"],"fingerprint":report["fingerprint"],
                    "split":"validation" if report["base_id"].startswith("validation-") else "dev",
                    "tick":decision["tick"],"features":features(candidate,decision.get("facts",{})),"candidate":candidate["id"],
                    "selected":candidate["id"]==decision.get("selected"),"outcome":report["status"],
                    "provenance":"bot_demonstration; legal strategy facts from fixed-tick policy; terminal label is evaluator-only"})
    ai.atomic(DIRECTORY/"dataset.json",{"schema_version":1,"rows":result,"human_demonstrations":0,"sampling":{"deduplicated":True,"max_decisions_per_case":128,"rule":"uniform quantiles of distinct records sorted by tick, including endpoints"}})
    return result

def ranker(rows):
    train=[r for r in rows if r["split"]=="dev"]
    validation=[r for r in rows if r["split"]=="validation"]
    # The manual score is the safe fallback. No learned model is promoted when
    # independent data are absent or contain just one correlated seed block.
    weights=[0.,100.,0.,0.,0.,0.,0.,0.]
    for epoch in range(20):
        for row in train:
            target=100. if row["selected"] else 0.
            error=sum(a*b for a,b in zip(weights,row["features"]))-target
            for i,x in enumerate(row["features"]): weights[i]=max(-1000,min(1000,weights[i]-.005*(error*x+.01*weights[i])))
    model={"version":1,"weights":weights,"provenance":"bot_imitation; no human rating or reinforcement-learning claim",
           "fit_rows":len(train),"validation_rows":len(validation),"enabled":False,
           "promotion_status":"EXPERIMENT_ONLY; paired validation improvement required"}
    ai.atomic(DIRECTORY/"ranker_experiment.json",model)
    return model

def dev_maps_ready():
    # Policies share maps. Warm them before concurrent candidates so two
    # engine processes never materialize the same .pending map simultaneously.
    if ai.PACK:
        source={'release_executable':ai.digest(ai.ENGINE),'release_package':ai.digest(ai.PACK),
                'runner':ai.digest(Path(ai.__file__)),'opponents':ai.fingerprint(ai.OPPONENTS),
                'native':ai.digest(ai.ENGINE.parent/'bin/ror_pathfinding.windows.template_release.x86_64.dll')}
    else:source=ai.source_hashes()
    map_source={key:value for key,value in source.items() if key.startswith(('prototype/scripts/random_map','prototype/scripts/skirmish','prototype/assets/generated/'))}
    revision=ai.fingerprint(map_source or source)[:16]
    rows=ai.read_result(ai.PROJECT/'data/ai/arena/manifests/dev.json').get('rows',[])[:8]
    return len(rows)==8 and all((ai.QA/'maps'/(row['id']+'-'+revision+'.dat')).is_file() for row in rows)

def evaluate_generation(candidates,jobs,manifest):
    """Share one engine-process limit across independently scored candidates."""
    if not isinstance(jobs,int) or isinstance(jobs,bool) or not 1<=jobs<=8:raise ValueError('Expected 1..8 game processes')
    if not candidates:return []
    original=ai.run_process
    slots=BoundedSemaphore(jobs)
    def bounded_process(*args,**kwargs):
        # Waiting for an environment slot is outside the game's watchdog.
        with slots:return original(*args,**kwargs)
    for candidate in candidates:candidate['status']='running'
    manifest['execution']={'maximum_game_processes':jobs,'candidate_parallelism':len(candidates),
        'map_materialization':'shared dev bundles verified before concurrent policies',
        'scope':'Scheduling only; fixed ticks, cases, policies and match limits unchanged'}
    ai.atomic(DIRECTORY/'manifest.json',manifest)
    ai.run_process=bounded_process
    try:
        with ThreadPoolExecutor(max_workers=min(8,len(candidates))) as pool:
            futures={pool.submit(ai.arena,'dev','competitive_v2',jobs,8,overrides=c['parameters']):c for c in candidates}
            for future in as_completed(futures):
                candidate=futures[future];result=future.result()
                candidate.update(status='evaluated',result=result)
                ai.atomic(DIRECTORY/'manifest.json',manifest)
                print('TUNING CANDIDATE COMPLETE',candidate['id'],result.get('score'),flush=True)
                if result['errors']:raise RuntimeError('Candidate failed correctness; inspect evidence before continuing')
    finally:
        ai.run_process=original
    return candidates

def run(generations,jobs,candidate_count=8):
    if generations not in (1,2,3) or not 1<=candidate_count<=8 or not 1<=jobs<=8:raise ValueError('Invalid finite tuning limits')
    manifest=prepare(); evaluated=[]
    for generation in range(generations):
        adapt_generation(manifest,generation,candidate_count)
        candidates=[c for c in manifest['candidates'] if c['generation']==generation and int(c['id'].split('-c')[1])<candidate_count]
        if candidates and not dev_maps_ready():
            candidate=candidates.pop(0)
            result=ai.arena('dev','competitive_v2',jobs,8,overrides=candidate['parameters'])
            candidate.update(status='evaluated',result=result);evaluated.append(candidate)
            ai.atomic(DIRECTORY/"manifest.json",manifest)
            if result["errors"]: raise RuntimeError("Candidate failed correctness; inspect evidence before continuing")
            if candidates and not dev_maps_ready():raise RuntimeError('Shared dev maps were not materialized; concurrent policies remain disabled')
        # Equal parameter proposals must not race over the same result files.
        unique={};duplicates=[]
        for candidate in candidates:
            key=ai.fingerprint(candidate['parameters'])
            if key in unique:duplicates.append((candidate,unique[key]))
            else:unique[key]=candidate
        evaluated.extend(evaluate_generation(list(unique.values()),jobs,manifest))
        for candidate,original in duplicates:
            candidate.update(status='evaluated',result=original['result'],reused_proposal=original['id']);evaluated.append(candidate)
        ai.atomic(DIRECTORY/'manifest.json',manifest)
    incumbent=next(c for c in evaluated if c['id']=='g0-c0')
    manual=sorted([c for c in evaluated if c is not incumbent],key=lambda c:(c["result"].get("score") or 0,c["id"]),reverse=True)[:1]
    directories=[ai.ROOT/c["result"]["directory"] for c in evaluated]
    fitted=ranker(dataset(directories))
    learned={"id":"ranker-fit1","parameters":{"ranker_enabled":True,"ranker_model":fitted},"status":"experiment"}
    finalists=[incumbent]+manual+([learned] if fitted["fit_rows"] else [])
    for candidate in finalists:
        candidate["validation"]=ai.arena("validation","competitive_v2",jobs,16,overrides=candidate["parameters"])
        ai.atomic(DIRECTORY/"manifest.json",manifest)
        if candidate["validation"]["errors"]:
            ai.atomic(DIRECTORY/"validation_failure.json",{"candidate":candidate["id"],"result":candidate["validation"],
                "reason":"Functional validation failure; no champion may be frozen or evaluated on holdout"})
            raise RuntimeError("Validation failed correctness; inspect evidence before selecting a champion")
    best=incumbent
    for candidate in finalists[1:]:
        if not candidate['validation']['errors'] and (candidate['validation'].get('score') or 0)>(best['validation'].get('score') or 0)+.05: best=candidate
    ai.atomic(DIRECTORY/"champion.policy.json",best['parameters'])
    ai.atomic(DIRECTORY/"league.json",{"baseline":"baseline_v1","finalists":finalists,"experimental_champion":best['id'],"promoted":None,
        "reason":"Selected on independent validation; default-policy promotion additionally requires final correctness/strength gates"})
    dataset(directories+[ai.ROOT/c["validation"]["directory"] for c in finalists])

if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument("--run",action="store_true")
    parser.add_argument("--generations",type=int,choices=(1,2,3),default=1); parser.add_argument("--jobs",type=int,default=3)
    parser.add_argument("--dataset",action="store_true")
    parser.add_argument("--directory",type=Path)
    parser.add_argument("--engine",type=Path); parser.add_argument("--pack",type=Path)
    parser.add_argument("--candidates",type=int,choices=range(1,9),default=8)
    args=parser.parse_args()
    if args.directory: DIRECTORY=args.directory.resolve()
    if args.engine: ai.ENGINE=args.engine.resolve()
    if args.pack: ai.PACK=args.pack.resolve()
    if args.run: run(args.generations,args.jobs,args.candidates)
    elif args.dataset: print(json.dumps(ranker(dataset()),ensure_ascii=False))
    else: print(json.dumps({"directory":str(DIRECTORY),"candidates":len(prepare()["candidates"])}))
