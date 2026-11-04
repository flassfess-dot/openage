"""Finite paired performance matrix using the real fixed-tick AI runtime.

The standalone GDScript stays outside the exported project. No command or AI
decision is chosen using elapsed time. Cold/warm CPU timings include capture,
owner work, worker work, waiting, navigation and the authoritative simulation.
"""
import argparse,json,sys,shutil
from pathlib import Path
import ai_competitive as ai
from ai_openings import parameters_match

SCRIPT=ai.ROOT/'tools/qa/ai_runtime_performance.gd'

def run(quick=False,project=ai.PROJECT):
    parameter_path=project/'data/ai/competitive_parameters.json'
    configuration=ai.read_result(parameter_path)
    expected={**configuration.get('runtime',{}),**configuration.get('difficulty',{}).get('standard',{})}
    if not expected: raise ValueError('Missing competitive runtime parameters')
    frozen=project/'arena_runtime_manifest.json'
    source=json.loads(frozen.read_text())['source'] if frozen.exists() else ai.source_hashes()
    if ai.PACK:
        proof=ai.read_result(ai.ENGINE.parent/'build-provenance.json')
        if proof.get('runtime_source_hashes',{}).get('prototype/data/ai/competitive_parameters.json')!=ai.digest(parameter_path):
            raise ValueError('Performance parameter configuration differs from the measured Release')
        source={'release_executable':ai.digest(ai.ENGINE),'release_package':ai.digest(ai.PACK),
            'native':ai.digest(ai.ENGINE.parent/'bin/ror_pathfinding.windows.template_release.x86_64.dll')}
    evidence={'source':source,'script':ai.digest(SCRIPT),'driver':ai.digest(Path(__file__)),
        'process_driver':ai.digest(Path(ai.__file__)),'parameter_matcher':ai.digest(ai.ROOT/'tools/ai_openings.py'),
        'quick':quick,'expected_competitive_parameters':expected}
    directory=ai.QA/'performance'/ai.fingerprint(evidence)[:16]
    ai.atomic(directory/'manifest.json',evidence)
    pinned=ai.TEMP/'performance-probes'/ai.fingerprint(evidence)
    pinned.mkdir(parents=True,exist_ok=True)
    harness=pinned/'probe.gd'
    if harness.exists() and ai.digest(harness)!=ai.digest(SCRIPT): raise ValueError('Immutable performance harness changed')
    if not harness.exists(): shutil.copy2(SCRIPT,harness)
    cases=[]
    for teams in ([2] if quick else [2,4,8]):
        for side in ([48] if quick else [96,192]):
            for algorithm in ['baseline_v1','competitive_v2']:
                for threaded in [False,True]:
                    cases.append(dict(teams=teams,side=side,algorithm=algorithm,threaded=threaded,
                        units_per_team=50 if quick else 500,ticks=12 if quick else 100,cold_ticks=4 if quick else 20,
                        all_active=False,timeout_seconds=1800))
    if not quick:
        for algorithm in ['baseline_v1','competitive_v2']:
            cases.append(dict(teams=8,side=192,algorithm=algorithm,threaded=True,units_per_team=500,
                ticks=100,cold_ticks=20,all_active=True,timeout_seconds=1800))
    reports=[]
    for index,case in enumerate(cases):
        case['fingerprint']=ai.fingerprint({'evidence':evidence,'case':case})
        output=directory/f'case-{index:02}.json'
        process_path=directory/f'case-{index:02}.process.json'
        if output.exists() and process_path.exists():
            row=ai.read_result(output)
            process=ai.read_result(process_path)
            active=row.get('active_parameters',[])
            policy_valid=case['algorithm']!='competitive_v2' or (isinstance(active,list) and len(active)==case['teams'] and all(parameters_match(p,expected) for p in active))
            if row.get('fingerprint')==case['fingerprint'] and row.get('passed') and process.get('passed') and policy_valid:
                reports.append(row); print('REUSE PERFORMANCE',index,flush=True); continue
        if output.exists() or process_path.exists():
            attempt=1
            while (directory/f'case-{index:02}.attempt-{attempt}').exists(): attempt+=1
            previous=directory/f'case-{index:02}.attempt-{attempt}'; previous.mkdir()
            for old in directory.glob(f'case-{index:02}.*'):
                if old.is_file(): old.rename(previous/old.name)
        case_path=directory/f'case-{index:02}.input.json'; ai.atomic(case_path,case)
        process=ai.run_process(str(harness),directory/f'case-{index:02}.log',1815,
            ['--case='+str(case_path),'--output='+str(output)],project,entrypoint='ai-performance')
        ai.atomic(process_path,process)
        row=ai.read_result(output) or {'case':case,'passed':False}
        if row.get('fingerprint')!=case['fingerprint']: row['passed']=False
        active=row.get('active_parameters',[])
        if case['algorithm']=='competitive_v2' and (not isinstance(active,list) or len(active)!=case['teams'] or not all(parameters_match(p,expected) for p in active)):
            row['passed']=False;row['parameter_error']='Actual performance policies differ from the frozen Release parameters'
        row['process_valid']=process['passed']; reports.append(row)
        print(json.dumps({'case':index,**case,'passed':row.get('passed'),'process':process}),flush=True)
        ai.atomic(directory/'partial.json',reports)
        if not process['passed'] or not row.get('passed'):
            raise RuntimeError('Performance fixture failed; inspect the engine log before continuing')
    equality=[]; deltas=[]
    def key(row,omit): return tuple((k,row['case'][k]) for k in ('teams','side','algorithm','threaded','all_active') if k!=omit)
    for row in reports:
        if not row['case']['threaded']:
            peer=next(r for r in reports if r['case']['threaded'] and key(r,'threaded')==key(row,'threaded'))
            equality.append({'configuration':dict(key(row,'threaded')),'world_equal':row['world_hash']==peer['world_hash'],
                'ai_equal':row['ai_state_hash']==peer['ai_state_hash']})
        if row['case']['algorithm']=='competitive_v2':
            previous=next(r for r in reports if r['case']['algorithm']=='baseline_v1' and key(r,'algorithm')==key(row,'algorithm'))
            for phase,old_phase in zip(row['phases'],previous['phases']):
                measurements={}
                for metric in ('controller.fixed_tick','controller.world_advance','diagnostic.ai.owner_queue','diagnostic.runtime.apply_gate_wait','ai.worker.action'):
                    current=phase['profile']['metrics_microseconds'].get(metric)
                    baseline=old_phase['profile']['metrics_microseconds'].get(metric)
                    if current and baseline:
                        measurements[metric]={'baseline_p95_us':baseline['p95'],'candidate_p95_us':current['p95'],
                            'p95_ratio':current['p95']/max(1,baseline['p95'])}
                span=row['case']['cold_ticks'] if phase['phase']=='cold' else row['case']['ticks']-row['case']['cold_ticks']
                for metric in ('presentation.ai.owner_total','ai.worker.action','ai.worker.validation','diagnostic.runtime.apply_gate_wait'):
                    current=phase['profile']['metrics_microseconds'].get(metric)
                    baseline=old_phase['profile']['metrics_microseconds'].get(metric)
                    if current and baseline:
                        before=baseline['mean']*baseline['count']/span; after=current['mean']*current['count']/span
                        measurements[metric+'.per_tick']={'baseline_mean_us':before,'candidate_mean_us':after,'ratio':after/max(1,before)}
                deltas.append({'configuration':dict(key(row,'algorithm')),'phase':phase['phase'],'measurements':measurements,
                    'gate_yield_ratio':{'baseline':old_phase.get('gate_yields',0)/max(1,old_phase.get('gate_calls',0)),
                                        'candidate':phase.get('gate_yields',0)/max(1,phase.get('gate_calls',0))}})
    summary={'diagnostic_only':quick,'reports':len(reports),'all_processes_passed':all(r.get('process_valid',True) for r in reports),
        'sequential_threaded_equality':equality,'all_equal':all(r['world_equal'] and r['ai_equal'] for r in equality),
        'deltas':deltas,'reports_detail':reports,'scope':'fixed 100-tick mixed workload; cold20/warm80; separate all-active stress; no graphical FPS or long-soak claim'}
    ai.atomic(directory/'summary.json',summary)
    print(json.dumps({'directory':str(directory),'reports':len(reports),'all_equal':summary['all_equal']}),flush=True)
    if not summary['all_equal']: raise RuntimeError('Sequential/threaded runtime state differs')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('--quick',action='store_true')
    parser.add_argument('--project',type=Path,default=ai.PROJECT);parser.add_argument('--engine',type=Path);parser.add_argument('--pack',type=Path)
    args=parser.parse_args()
    if args.engine: ai.ENGINE=args.engine.resolve()
    if args.pack: ai.PACK=args.pack.resolve()
    run(args.quick,args.project.resolve())
