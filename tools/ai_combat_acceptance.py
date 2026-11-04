"""Repeat equal-cost component battles with the final runtime difficulty.

Uses the editor against the frozen champion sources and identical Release DLL.
This is separate from complete-game strength and actual packaged EXE checks.
"""
import argparse,json,math,shutil
from pathlib import Path
import ai_competitive as ai
from ai_openings import parameters_match

SCRIPT=ai.ROOT/'tools/qa/ai_combat_runtime.gd'

def validate_project_sources(project,source):
    if 'prototype/scripts/ai_micro_controller.gd' not in source:
        raise ValueError('Frozen runtime does not identify its micro controller')
    for name,value in source.items():
        if name.startswith('prototype/'):
            relative=Path(name.removeprefix('prototype/'))
            if '..' in relative.parts:raise ValueError('Invalid frozen project path')
            path=project/relative
        elif name.startswith('native/'):
            path=ai.ROOT/name
        else:
            continue
        if not path.is_file() or ai.digest(path)!=value:
            raise ValueError('Frozen controlled battle file changed: '+name)

def summarize(rows):
    if len(rows)!=48 or {(r.get('split'),r.get('scenario'),r.get('micro')) for r in rows}!={(s,i,m) for s in ('fit','heldout') for i in range(12) for m in (False,True)}:
        raise ValueError('Expected all 48 distinct controlled battles')
    for row in rows:
        if row.get('own_value',0)<=0 or row.get('enemy_value',0)<=0 or not math.isclose(row['own_value'],row['enemy_value']):
            raise ValueError('Controlled forces must have identical positive resource cost')
    result={}
    for split in ('fit','heldout'):
        baseline=[r for r in rows if r['split']==split and not r['micro']]
        micro=[r for r in rows if r['split']==split and r['micro']]
        def exchange(group):return sum(r['enemy_lost'] for r in group)/max(1,sum(r['own_lost'] for r in group))
        def close(row):return abs((row['own_value']-row['own_lost'])-(row['enemy_value']-row['enemy_lost']))<.10*(row['own_value']+row['enemy_value'])
        close_cases=[r for r in baseline if close(r)]
        decisive=[r for r in baseline if not close(r)]
        before=exchange(baseline);after=exchange(micro)
        result[split]={'cases':len(baseline),'forecast_sign_accuracy':sum(r['sign_correct'] for r in baseline)/len(baseline),
            'close_battles':len(close_cases),'forecast_sign_accuracy_close':sum(r['sign_correct'] for r in close_cases)/len(close_cases) if close_cases else None,
            'decisive_battles':len(decisive),'forecast_sign_accuracy_outside_close':sum(r['sign_correct'] for r in decisive)/len(decisive) if decisive else None,
            'close_definition':'Absolute difference of retained roster resource cost <10% of total initial cost; both accuracy denominators shown separately',
            'matched16s_retained_hp_MAE':sum(r['horizon_mean_abs_retained_hp_error'] for r in baseline)/len(baseline),
            'baseline_exchange':before,'micro_exchange':after,'micro_exchange_ratio':after/before if before else None,
            'issued':sum(r['issued'] for r in micro),'rejected':sum(r['rejected'] for r in micro),
            'rejection_reasons':{reason:sum(r.get('rejection_reasons',{}).get(reason,0) for r in micro) for reason in sorted({k for r in micro for k in r.get('rejection_reasons',{})})},
            'scenarios':[{'scenario':b['scenario'],'kinds':b['kinds'],'baseline_own_lost':b['own_lost'],'baseline_enemy_lost':b['enemy_lost'],
                          'micro_own_lost':next(r for r in micro if r['scenario']==b['scenario'])['own_lost'],
                          'micro_enemy_lost':next(r for r in micro if r['scenario']==b['scenario'])['enemy_lost']} for b in baseline]}
    return result

def summarize_roles(rows):
    if len(rows)!=4 or {(r.get('split'),r.get('scenario'),r.get('micro')) for r in rows}!={('fit',i,m) for i in range(2) for m in (False,True)}:
        raise ValueError('Expected four distinct fit-only mixed role battles')
    cases=[];role_orders={}
    for row in rows:
        if row.get('own_value',0)<=0 or not math.isclose(row['own_value'],row.get('enemy_value',0)):
            raise ValueError('Mixed forces must have identical positive resource cost')
        terminal=row.get('terminal_roster',{})
        actors=terminal.get('own_initial',[])+terminal.get('enemy_initial',[])
        if len(terminal.get('own_initial',[]))!=8 or len(terminal.get('enemy_initial',[]))!=8:
            raise ValueError('Missing terminal rosters for the mixed fixture')
        own=any(a.get('team')==1 and a.get('hp',0)>0 for a in actors)
        enemy=any(a.get('team')==2 and a.get('hp',0)>0 for a in actors)
        outcome='WIN' if own and not enemy else 'LOSS' if enemy and not own else 'DRAW_TIME_LIMIT' if own and enemy else 'SIMULTANEOUS_ELIMINATION'
        cases.append({'scenario':row['scenario'],'micro':row['micro'],'outcome':outcome,'ticks':row['ticks'],
                      'own_lost':row['own_lost'],'enemy_lost':row['enemy_lost'],'rejected':row['rejected'],
                      'accepted_role_orders':row.get('accepted_role_orders',{})})
        if row['micro']:
            for reason,count in row.get('accepted_role_orders',{}).items():
                if not isinstance(count,(int,float)) or count<0 or int(count)!=count:raise ValueError('Invalid role order counter')
                role_orders[reason]=role_orders.get(reason,0)+int(count)
    before=[r for r in rows if not r['micro']];after=[r for r in rows if r['micro']]
    def exchange(group):return sum(r['enemy_lost'] for r in group)/max(1,sum(r['own_lost'] for r in group))
    baseline=exchange(before);micro=exchange(after)
    observed={'melee_screen':sum(role_orders.get(k,0) for k in ('screen_ranged_support','retain_screen'))>0,
              'priest_protection':sum(role_orders.get(k,0) for k in ('behind_cover','protect_priest'))>0}
    return {'cases':cases,'accepted_role_orders':role_orders,'functional_roles_observed':observed,
            'baseline_exchange':baseline,'micro_exchange':micro,'micro_exchange_ratio':micro/baseline if baseline else None,
            'rejected':sum(r['rejected'] for r in after),
            'scope':'Fit-only functional integration checks; not unseen strength or human rating'}

def run(project,difficulty='standard',release=None,role_fixtures=False):
    frozen=project/'arena_runtime_manifest.json'
    if release and not frozen.exists():raise ValueError('Release component checks require a frozen runtime manifest')
    source=ai.read_result(frozen)['source'] if frozen.exists() else ai.source_hashes()
    if frozen.exists():validate_project_sources(project,source)
    configuration=ai.read_result(project/'data/ai/competitive_parameters.json')
    expected={**configuration.get('runtime',{}),**configuration.get('difficulty',{}).get(difficulty,{})}
    if not expected:raise ValueError('Missing runtime policy')
    provenance=ai.read_result(release.parent/'build-provenance.json') if release else {}
    if release:
        if not provenance or any(ai.digest(release.parent/name)!=value for name,value in provenance['artifacts'].items()):raise ValueError('Champion artifacts changed after their recorded build')
        native='bin/ror_pathfinding.windows.template_release.x86_64.dll'
        if ai.digest(project/native)!=provenance.get('artifacts',{}).get(native):raise ValueError('Controlled battle DLL differs from champion Release')
        for name,value in source.items():
            if name.startswith(('prototype/','native/')) and provenance.get('runtime_source_hashes',{}).get(name)!=value:
                raise ValueError('Frozen controlled battle source differs from champion: '+name)
    evidence={'source':source,'harness':ai.digest(SCRIPT),'driver':ai.digest(Path(__file__)),'process_driver':ai.digest(Path(ai.__file__)),
        'difficulty':difficulty,'expected_parameters':expected,'release_artifacts':provenance.get('artifacts',{}),'role_fixtures':role_fixtures,
        'scope':('4 fit-only mixed role module battles' if role_fixtures else '48 controlled module battles')+'; editor with frozen champion sources and identical Release native DLL; not full-game or human strength'}
    key=ai.fingerprint(evidence);folder=ai.QA/('role-acceptance' if role_fixtures else 'combat-acceptance')/key[:16];ai.atomic(folder/'manifest.json',evidence)
    pinned=ai.TEMP/'combat-probes'/key;pinned.mkdir(parents=True,exist_ok=True);probe=pinned/'probe.gd'
    if probe.exists() and ai.digest(probe)!=ai.digest(SCRIPT):raise ValueError('Immutable combat probe changed')
    if not probe.exists():shutil.copy2(SCRIPT,probe)
    output=folder/'result.json';process_path=folder/'process.json';row=ai.read_result(output);process=ai.read_result(process_path)
    if not process.get('passed') or not parameters_match(row.get('active_policy',{}),expected):
        if output.exists():output.replace(folder/('result.previous-'+str(output.stat().st_mtime_ns)+'.json'))
        arguments=['--equal-cost','--difficulty='+difficulty,'--output='+str(output)]
        if role_fixtures:arguments+=['--role-fixtures']
        process=ai.run_process(str(probe),folder/'runtime.log',1800,arguments,project)
        ai.atomic(process_path,process);row=ai.read_result(output)
    if not process.get('passed') or not row.get('runtime',{}).get('native') or not parameters_match(row.get('active_policy',{}),expected):
        raise RuntimeError('Final-policy controlled combat runtime or parameter check failed')
    if frozen.exists():validate_project_sources(project,source)
    results=summarize_roles(row.get('rows',[])) if role_fixtures else summarize(row.get('rows',[]))
    if role_fixtures and not all(results['functional_roles_observed'].values()):raise RuntimeError('Mixed fixture did not exercise the required role commands')
    summary={'fingerprint':key,'difficulty':difficulty,'cases':len(row.get('rows',[])),'results':results,'role_fixtures':role_fixtures,
        'process_passed':True,'actual_parameters_verified':True,'release_artifacts':evidence['release_artifacts'],'scope':evidence['scope'],'directory':str(folder)}
    ai.atomic(folder/'summary.json',summary);print(json.dumps(summary),flush=True);return summary

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--project',type=Path,default=ai.PROJECT)
    parser.add_argument('--difficulty',choices=('easy','standard','hard'),default='standard');parser.add_argument('--release-application',type=Path)
    parser.add_argument('--role-fixtures',action='store_true')
    args=parser.parse_args();run(args.project.resolve(),args.difficulty,args.release_application.resolve() if args.release_application else None,args.role_fixtures)
