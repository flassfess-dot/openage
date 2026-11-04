"""Resume a finite Release evaluation without mixing builds or tuning holdout.

An agent still handles a failed functional gate. Quality misses are recorded;
they never silently promote a policy. All long games retain the frozen limits.
"""
import argparse,json,math,time
from pathlib import Path
import ai_competitive as ai
import ai_tune as tuning

def pin_release(engine,pack):
    if pack!=engine.with_suffix('.pck'): raise ValueError('Use the adjacent Release PCK')
    ai.ENGINE=engine; ai.PACK=pack
    return {'executable':ai.digest(engine),'package':ai.digest(pack),
        'native':ai.digest(engine.parent/'bin/ror_pathfinding.windows.template_release.x86_64.dll')}

def calibration_model(calibration,jobs,release):
    rows=ai.read_result(ai.PROJECT/'data/ai/arena/manifests/smoke.json').get('rows',[])[:6]
    expected={row['id'] for row in rows}
    if len(expected)!=6 or calibration.get('reports')!=12:raise ValueError('Twelve paired calibration games are required')
    samples={};case_ids=[]
    for path in (ai.ROOT/calibration['directory']).glob('smoke-*.json'):
        row=ai.read_result(path)
        if row.get('base_id') not in expected or row.get('case_id')!=path.stem or row.get('status') not in ('WIN','LOSS','DRAW_TIME_LIMIT'):continue
        key=(row['base_id'],row.get('subject_team'))
        value=row.get('wall_seconds')
        if key in samples:raise ValueError('Duplicate calibration position')
        if not isinstance(value,(int,float)) or isinstance(value,bool) or not math.isfinite(value) or value<=0:raise ValueError('Invalid calibration runtime')
        samples[key]=float(value);case_ids.append(row['case_id'])
    if set(samples)!={(base,team) for base in expected for team in (1,2)}:raise ValueError('Twelve complete calibration positions are required')
    # Twelve process runtimes; the nearest-rank p95 is their maximum. Later
    # smoke games in a reused arena directory must not enlarge this sample.
    p95=sorted(samples.values())[math.ceil(.95*len(samples))-1]
    return {'map_size_id':'compact','samples':12,'sample_case_ids':sorted(case_ids),'p95_seconds':p95,
            'timeout_seconds':min(3600,max(300,math.ceil(3*p95))),'jobs':jobs,'source_release':release,
            'source':'same exact Release, full games; six frozen smoke pairs; nearest-rank p95'}

def run(args):
    release=pin_release(args.engine.resolve(),args.pack.resolve())
    directory=ai.QA/'evaluation'/ai.fingerprint({'release':release,'driver':ai.digest(Path(__file__)),'arena':ai.digest(Path(ai.__file__))})[:16]
    state_path=directory/'state.json'
    state=json.loads(state_path.read_text()) if state_path.exists() else {'schema_version':1,'release':release,'steps':{},'human_strength':'HUMAN_UNMEASURED'}
    if state['release']!=release: raise ValueError('Evaluation build changed')
    ai.atomic(state_path,state)
    def check_build():
        if pin_release(args.engine.resolve(),args.pack.resolve())!=release: raise RuntimeError('Release changed during evaluation')
    def step(name,action):
        if name in state['steps']:
            print('REUSE EVALUATION STEP',name,flush=True); return state['steps'][name]['result']
        check_build(); print('EVALUATION STEP',name,flush=True)
        result=action()
        if isinstance(result,dict) and result.get('errors'): raise RuntimeError('Functional arena failures in '+name)
        check_build(); state['steps'][name]={'completed_utc':time.time(),'result':result}; ai.atomic(state_path,state)
        return result
    print('EVALUATION_DIRECTORY',directory,flush=True)
    model_path=directory/'timeout_model.json'
    if model_path.exists() and 'calibration12' in state['steps']:
        model=ai.read_result(model_path)
        if model.get('source_release')!=release or model.get('samples')!=12 or not 300<=int(model.get('timeout_seconds',0))<=3600:raise ValueError('Invalid calibration provenance or limits')
    else:
        calibration=step('calibration12',lambda:ai.arena('smoke','baseline_v1',args.jobs,6))
        model=calibration_model(calibration,args.jobs,release);ai.atomic(model_path,model)
    ai.ARENA_TIMEOUT_SECONDS=int(model['timeout_seconds'])
    if args.phase in ('all','baseline'):
        step('candidate_smoke24',lambda:ai.arena('smoke','competitive_v2',args.jobs,0))
        step('baseline_smoke24',lambda:ai.arena('smoke','baseline_v1',args.jobs,0))
        step('baseline_dev96',lambda:ai.arena('dev','baseline_v1',args.jobs,0))
    if args.phase in ('all','tuning'):
        tuning.DIRECTORY=directory/'tuning'
        def tune():
            tuning.run(args.tuning_generations,args.jobs,8)
            return json.loads((tuning.DIRECTORY/'league.json').read_text())
        league=step('tuning'+str(128*args.tuning_generations)+'dev_max96validation',tune)
        selected=json.loads((tuning.DIRECTORY/'champion.policy.json').read_text())
        step('ablation_micro16',lambda:ai.arena('dev','competitive_v2',args.jobs,8,overrides={**selected,'micro_enabled':False}))
        step('ablation_rollout16',lambda:ai.arena('dev','competitive_v2',args.jobs,8,overrides={**selected,'combat_rollouts':False}))
        ai.atomic(directory/'selected_champion.json',{'release':release,'parameters':selected,'selection':league['experimental_champion'],'tuning_generations':args.tuning_generations,
            'promotion':'not promoted; freeze packaged parameters before final holdout','human_strength':'HUMAN_UNMEASURED'})
        if selected and args.phase=='all':
            print('SELECTED_PARAMETERS_REQUIRE_PACKAGE_FREEZE',directory/'selected_champion.json',flush=True)
            # This is a concrete source/build boundary, not a permission prompt.
            # Repackage the chosen runtime parameters, then run --phase final.
            return
    if args.phase in ('all','final'):
        if not args.champion and args.phase=='final': raise ValueError('--champion must explicitly freeze the final policy')
        selected=json.loads(args.champion.read_text()) if args.champion else {}
        step('holdout128',lambda:ai.arena('holdout','competitive_v2',args.jobs,0,overrides=selected))
        step('challenge64',lambda:ai.arena('challenge_holdout','competitive_v2',args.jobs,0,overrides=selected))
        state['evaluation_complete']=True; ai.atomic(state_path,state)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine',type=Path,required=True);parser.add_argument('--pack',type=Path,required=True)
    parser.add_argument('--jobs',type=int,choices=range(1,9),default=3)
    parser.add_argument('--phase',choices=('all','baseline','tuning','final'),default='all')
    parser.add_argument('--champion',type=Path)
    parser.add_argument('--tuning-generations',type=int,choices=(1,2,3),default=3)
    run(parser.parse_args())
