"""Validate compact final evidence without accepting an earlier build's games."""
import math

def suite_boundary_matches_evidence(coverage,boundary,coverage_sha256,stdout_sha256,inventory):
    """A passing historical summary cannot qualify a newer, unfinished suite."""
    if not isinstance(coverage,dict) or not isinstance(boundary,dict):return False
    if boundary.get('passed') is not True or boundary.get('discovered')!=inventory:return False
    if boundary.get('coverage_sha256')!=coverage_sha256 or boundary.get('suite_stdout_sha256')!=stdout_sha256:return False
    if coverage.get('discovered')!=inventory or coverage.get('passed')!=inventory or coverage.get('all_discovered_covered') is not True:return False
    if coverage.get('missing')!=[] or coverage.get('unresolved_failures')!=[]:return False
    records=coverage.get('records')
    return (isinstance(records,list) and len(records)==inventory
            and all(isinstance(row,dict) and row.get('passed') is True and isinstance(row.get('script'),str) for row in records)
            and len({row['script'] for row in records})==inventory)

def final_complete_suite_matches_release(qualification,proof,all_test_sources,inventory):
    """A final build needs a complete run bound to its own source and native."""
    if not all(isinstance(value,dict) for value in (qualification,proof,all_test_sources)):return False
    if type(inventory) is not int or inventory<=0:return False
    if qualification.get('passed') is not True or qualification.get('inventory')!=inventory:return False
    if not all_test_sources or qualification.get('all_test_sources')!=all_test_sources:return False
    if not proof.get('runtime_source_hashes') or qualification.get('source')!=proof['runtime_source_hashes']:return False
    artifacts=proof.get('artifacts',{})
    if not isinstance(artifacts,dict):return False
    native=artifacts.get('bin/ror_pathfinding.windows.template_release.x86_64.dll')
    return bool(native and qualification.get('native_sha256')==native and qualification.get('artifacts')==artifacts)


def performance_matches_release(manifest,summary,release):
    """Require actual mixed work on every declared configuration of the Release."""
    if not isinstance(manifest,dict) or not isinstance(summary,dict):return False
    expected={'release_executable':release.get('executable'),'release_package':release.get('package'),'native':release.get('native')}
    if not all(expected.values()) or manifest.get('source')!=expected or manifest.get('quick') is not False:return False
    if summary.get('reports')!=26 or summary.get('all_equal') is not True or summary.get('all_processes_passed') is not True:return False
    rows=summary.get('reports_detail')
    if not isinstance(rows,list) or len(rows)!=26:return False
    expected_cases={(teams,side,algorithm,threaded,False)
                    for teams in (2,4,8) for side in (96,192)
                    for algorithm in ('baseline_v1','competitive_v2') for threaded in (False,True)}
    expected_cases.update((8,192,algorithm,True,True) for algorithm in ('baseline_v1','competitive_v2'))
    actual={}
    for row in rows:
        if not isinstance(row,dict) or row.get('passed') is not True or row.get('runtime',{}).get('release') is not True or row.get('native') is not True:return False
        case=row.get('case',{});work=row.get('workload',{});events=row.get('workload_events',{})
        if not all(isinstance(value,dict) for value in (case,work,events)):return False
        if type(case.get('teams')) is not int or type(case.get('side')) is not int or type(case.get('threaded')) is not bool or type(case.get('all_active')) is not bool:return False
        key=(case['teams'],case['side'],case.get('algorithm'),case['threaded'],case['all_active'])
        if key not in expected_cases or key in actual:return False
        if case.get('units_per_team')!=500 or case.get('ticks')!=100 or case.get('cold_ticks')!=20 or row.get('tick')!=100 or row.get('workload_passed') is not True:return False
        teams=case['teams'];stress=case['all_active']
        planned={'gatherers':0 if stress else 100*teams,'marchers':(484 if stress else 100)*teams,
                 'combatants':16*teams,'idle':0 if stress else 284*teams}
        if any(type(work.get(name)) is not int or work[name]!=value for name,value in planned.items()):return False
        moved=work.get('moved_marchers')
        if type(moved) is not int or not 0<moved<=planned['marchers']:return False
        for name in (('attack','damage') if stress else ('attack','damage','resource_gathered')):
            if type(events.get(name)) is not int or events[name]<=0:return False
        if not row.get('world_hash') or row.get('ai_state_hash') is None:return False
        actual[key]=row
    if set(actual)!=expected_cases:return False
    # Check the actual paired state hashes, as well as the driver's summary flag.
    for key,row in actual.items():
        teams,side,algorithm,threaded,stress=key
        if not threaded:
            peer=actual[(teams,side,algorithm,True,stress)]
            if any(row[name]!=peer[name] for name in ('world_hash','ai_state_hash','workload_events','workload')):return False
    return True

def strategy_sampling_matches_release(qualification,proof):
    """Bind actual shipping observer checks to the final source and artifacts."""
    if not isinstance(qualification,dict) or qualification.get('passed') is not True:return False
    if not proof.get('runtime_source_hashes') or qualification.get('source')!=proof['runtime_source_hashes']:return False
    if not proof.get('artifacts') or qualification.get('artifacts')!=proof['artifacts']:return False
    rows=qualification.get('records')
    if not isinstance(rows,list) or len(rows)!=2:return False
    names=set();cases=set()
    for row in rows:
        if not isinstance(row,dict):return False
        name=row.get('name');case=row.get('case');tick=row.get('tick')
        if name not in ('seat1','seat2') or name in names or not isinstance(case,str) or not case.endswith('-'+name) or case in cases:return False
        names.add(name);cases.add(case)
        if type(tick) is not int or not 0<tick<=12000 or row.get('status') not in ('WIN','LOSS','DRAW_TIME_LIMIT'):return False
        if row['status']=='DRAW_TIME_LIMIT' and tick!=12000:return False
        process=row.get('process',{})
        if not isinstance(process,dict) or process.get('passed') is not True or type(process.get('exit_code')) is not int or process['exit_code']!=0 or process.get('timeout') is not False or process.get('engine_errors')!=[]:return False
        sample=row.get('sampling',{})
        if not isinstance(sample,dict) or sample.get('version')!=2 or sample.get('capacity')!=4096:return False
        if any(type(sample.get(key)) is not int for key in ('observed_distinct_inputs','retained','duplicates_skipped','thinning_stride','first_decision_tick','last_decision_tick')):return False
        if not 0<sample['retained']<=min(4096,sample['observed_distinct_inputs']) or sample['duplicates_skipped']<0 or sample['thinning_stride']<1:return False
        if not 0<=sample['first_decision_tick']<=sample['last_decision_tick'] or sample['last_decision_tick']<tick-240:return False
    return names=={'seat1','seat2'}


def final_evaluation_matches_release(row,release):
    if not isinstance(row,dict) or set(release)!={'executable','package','native'} or not all(release.values()):return False
    if row.get('complete') is not True or row.get('release')!=release:return False
    model=row.get('timeout_model',{});steps=row.get('steps',{})
    if not isinstance(model,dict) or not isinstance(steps,dict):return False
    timeout=model.get('timeout_seconds')
    if model.get('source_release')!=release or model.get('samples')!=12 or not isinstance(timeout,int) or isinstance(timeout,bool) or not 300<=timeout<=3600:return False
    for name,count in [('holdout128',128),('challenge64',64)]:
        result=steps.get(name,{})
        if not isinstance(result,dict) or result.get('reports')!=count or result.get('errors'):return False
        if result.get('statistics_schema')!=2 or result.get('resampling_order')!='sorted_base_id' or result.get('paired_blocks')!=count//2:return False
        counts=result.get('counts',{})
        if not isinstance(counts,dict) or set(counts)-{'WIN','LOSS','DRAW_TIME_LIMIT'}:return False
        if any(not isinstance(value,int) or isinstance(value,bool) or value<0 for value in counts.values()) or sum(counts.values())!=count:return False
        score=result.get('score');interval=result.get('seed_block_95_percent')
        if not isinstance(score,(int,float)) or isinstance(score,bool) or not math.isfinite(score) or not 0<=score<=1:return False
        if not isinstance(interval,list) or len(interval)!=2 or any(not isinstance(value,(int,float)) or isinstance(value,bool) or not math.isfinite(value) or not 0<=value<=1 for value in interval) or interval[0]>interval[1]:return False
    return True
