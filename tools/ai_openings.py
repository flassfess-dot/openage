"""Controlled, paired economy openings for all sixteen civilizations."""
import argparse,json,statistics,shutil,math
from concurrent.futures import ThreadPoolExecutor,as_completed
from pathlib import Path
import ai_competitive as ai

def completed_runtime(row,process,maximum_ticks):
    if process.get('timeout') or process.get('engine_errors') or process.get('termination_error'): return False
    if process.get('exit_code')==0 and row.get('passed') is True: return True
    # The probe deliberately exits1 when the age goal is missed. A complete
    # bounded policy failure is distinct from a crashed or incomplete runtime.
    return (process.get('exit_code') in (0,1) and row.get('passed') is False
            and row.get('tick')==maximum_ticks and not row.get('runtime_error'))

def parameters_match(active,expected):
    if isinstance(expected,dict): return isinstance(active,dict) and all(k in active and parameters_match(active[k],v) for k,v in expected.items())
    if isinstance(expected,list): return isinstance(active,list) and len(active)==len(expected) and all(parameters_match(a,b) for a,b in zip(active,expected))
    if isinstance(expected,(int,float)) and not isinstance(expected,bool): return isinstance(active,(int,float)) and not isinstance(active,bool) and math.isclose(active,expected,rel_tol=1e-9,abs_tol=1e-9)
    return active==expected

def work_measurement_valid(row):
    purity=row.get('observer_purity',{})
    measured=row.get('work_availability',{}).get('2',{})
    if not isinstance(purity,dict) or purity.get('passed') is not True or not isinstance(purity.get('checks'),int) or purity['checks']<3:return False
    names=('worker_ticks','available_ticks','idle_available_ticks','unknown_ticks','idle_unknown_ticks')
    if not isinstance(measured,dict) or any(not isinstance(measured.get(k),int) or isinstance(measured[k],bool) or measured[k]<0 for k in names):return False
    total,available,idle,unknown,idle_unknown=(measured[k] for k in names)
    if total<=0 or available+unknown!=total or idle>available or idle_unknown>unknown:return False
    expected={'conditional_idle_lower_bound':idle/max(1,available+unknown-idle_unknown),
              'conditional_idle_upper_bound':(idle+idle_unknown)/max(1,available+idle_unknown),
              'confirmed_worker_time_coverage':available/total}
    return parameters_match(measured,expected) and isinstance(row.get('final_world_hash'),str) and len(row['final_world_hash'])==64

def work_matrix_valid(rows):
    if not isinstance(rows,list) or len(rows)!=32:return False
    if not all(isinstance(row,dict) for row in rows):return False
    if {(row.get('algorithm'),row.get('civilization')) for row in rows}!={(algorithm,civ) for algorithm in ('baseline_v1','competitive_v2') for civ in range(1,17)}:return False
    return all(work_measurement_valid({'observer_purity':row.get('observer_purity',{}),
        'work_availability':{'2':row.get('measurement',{})},'final_world_hash':row.get('final_world_hash')}) for row in rows)

def run(project,jobs,target_age=101):
    frozen=project/'arena_runtime_manifest.json'
    source=json.loads(frozen.read_text())['source'] if frozen.exists() else ai.source_hashes()
    script=ai.ROOT/'tools/qa/ai_economy_opening.gd'
    observer=ai.ROOT/'tools/qa/ai_work_availability.gd'
    configuration=ai.read_result(project/'data/ai/competitive_parameters.json')
    expected={**configuration.get('runtime',{}),**configuration.get('difficulty',{}).get('standard',{})}
    maximum_ticks=72000 if target_age>101 else 36000
    key=ai.fingerprint({'source':source,'driver':ai.digest(Path(__file__)),'process_driver':ai.digest(Path(ai.__file__)),'probe':ai.digest(script),'work_observer':ai.digest(observer),'seed':41721,'maximum_ticks':maximum_ticks,'target_age':target_age})
    directory=ai.QA/'openings'/key[:16]; directory.mkdir(parents=True,exist_ok=True)
    pinned=ai.TEMP/'opening-probes'/key; pinned.mkdir(parents=True,exist_ok=True)
    probe=pinned/'probe.gd'
    if probe.exists() and ai.digest(probe)!=ai.digest(script): raise ValueError('Immutable opening probe changed')
    if not probe.exists(): shutil.copy2(script,probe)
    observer_copy=pinned/observer.name
    if observer_copy.exists() and ai.digest(observer_copy)!=ai.digest(observer): raise ValueError('Immutable work observer changed')
    if not observer_copy.exists(): shutil.copy2(observer,observer_copy)
    ai.atomic(directory/'manifest.json',{'fingerprint':key,'source':source,'civilizations':list(range(1,17)),
        'algorithms':['baseline_v1','competitive_v2'],'seed':41721,'maximum_ticks':maximum_ticks,'target_age':target_age,
        'opponent':'identical passive durable opponent; no score/human-rating claim','work_observer_sha256':ai.digest(observer)})
    def case(algorithm,civilization):
        name=f'{algorithm}-civ{civilization:02}'
        path=directory/(name+'.json'); process_path=directory/(name+'.process.json')
        if path.exists() and process_path.exists():
            previous=ai.read_result(process_path)
            old=ai.read_result(path)
            if old.get('algorithm')==algorithm and old.get('civilization')==civilization and completed_runtime(old,previous,maximum_ticks) and work_measurement_valid(old) and (algorithm!='competitive_v2' or parameters_match(old.get('active_parameters',{}),expected)):
                old['runtime_valid']=True; return old
        # Preserve interrupted attempts and prevent a stale complete row from
        # being mistaken for output of a later process that never wrote one.
        stale=[p for p in directory.glob(name+'.*') if '.attempt-' not in p.name]
        if stale:
            attempt=1
            while any((directory/(p.name+'.attempt-'+str(attempt))).exists() for p in stale): attempt+=1
            for previous_path in stale: previous_path.rename(directory/(previous_path.name+'.attempt-'+str(attempt)))
        args=['--algorithm='+algorithm,'--civilization='+str(civilization),'--max-ticks='+str(maximum_ticks),'--target-age='+str(target_age),'--output='+str(path)]
        process=ai.run_process(str(probe),directory/(name+'.log'),3615 if target_age>101 else 1200,args,project)
        ai.atomic(process_path,process)
        row=ai.read_result(path) or {'algorithm':algorithm,'civilization':civilization,'passed':False}
        row['runtime_valid']=completed_runtime(row,process,maximum_ticks)
        if not work_measurement_valid(row):
            row['runtime_valid']=False
            row['measurement_error']='Conditional work observer evidence is incomplete or changed authoritative state'
        if algorithm=='competitive_v2' and not parameters_match(row.get('active_parameters',{}),expected):
            row['runtime_valid']=False
            row['parameter_error']='Actual controlled policy differs from the frozen project runtime parameters'
        print(json.dumps({'case':name,'passed':row.get('passed'),'runtime_valid':row['runtime_valid'],'tick':row.get('tick'),'seconds':process['seconds']}),flush=True)
        return row
    rows=[]
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        futures=[pool.submit(case,algorithm,civ) for civ in range(1,17) for algorithm in ('baseline_v1','competitive_v2')]
        for future in as_completed(futures): rows.append(future.result())
    pairs=[]
    for civ in range(1,17):
        a=next(r for r in rows if r['civilization']==civ and r['algorithm']=='baseline_v1')
        b=next(r for r in rows if r['civilization']==civ and r['algorithm']=='competitive_v2')
        if a.get('passed') and b.get('passed') and a.get('runtime_valid',True) and b.get('runtime_valid',True):
            pairs.append({'civilization':civ,'baseline_tick':a['tick'],'candidate_tick':b['tick'],'improvement':1-b['tick']/a['tick'],
                'idle_worker_ratio':b['metrics']['idle_worker_ticks']/max(1,b['metrics']['worker_ticks'])})
    report={'fingerprint':key,'reports':len(rows),'valid_pairs':len(pairs),'pairs':pairs,
        'median_improvement':statistics.median(r['improvement'] for r in pairs) if pairs else None,
        'median_idle_worker_ratio':statistics.median(r['idle_worker_ratio'] for r in pairs) if pairs else None,
        'candidate_goal_successes':sum(r.get('passed',False) and r.get('runtime_valid',False) for r in rows if r['algorithm']=='competitive_v2'),
        'baseline_goal_successes':sum(r.get('passed',False) and r.get('runtime_valid',False) for r in rows if r['algorithm']=='baseline_v1'),
        'runtime_failures':[{'algorithm':r['algorithm'],'civilization':r['civilization']} for r in rows if not r.get('runtime_valid',False)],
        'failed_cases':[{'algorithm':r['algorithm'],'civilization':r['civilization']} for r in rows if not r.get('passed') or not r.get('runtime_valid',True)]}
    report['conditional_worker_idle']=[{'algorithm':r['algorithm'],'civilization':r['civilization'],
        'observer_purity':r.get('observer_purity',{}),'measurement':r.get('work_availability',{}).get('2',{}),
        'final_world_hash':r.get('final_world_hash')} for r in rows]
    ai.atomic(directory/'summary.json',report);print(json.dumps(report),flush=True)
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--project',type=Path,default=ai.PROJECT);parser.add_argument('--jobs',type=int,default=3)
    parser.add_argument('--target-age',type=int,choices=(101,102),default=101)
    args=parser.parse_args();run(args.project.resolve(),args.jobs,args.target_age)
