"""Finite multiplayer soak, separate from all training and strength cohorts."""
import argparse,json,shutil
from pathlib import Path
import ai_competitive as ai

def valid_episode(row,case):
    ticks=row.get('tick')
    return (row.get('fingerprint')==case['fingerprint'] and row.get('status') in ('WIN','LOSS','DRAW_TIME_LIMIT')
            and isinstance(ticks,int) and not isinstance(ticks,bool) and 0<ticks<=case['maximum_ticks']
            and (not case.get('continuous_full_hour') or ticks==case['maximum_ticks']))

def run(ticks,policy_path=None,project=ai.PROJECT,full=False,scenario=None):
    if ticks<=0 or (full and ticks!=72000): raise ValueError('A full-hour soak requires exactly 72000 ticks')
    if scenario is not None and scenario not in range(7 if full else 4): raise ValueError('Scenario is outside the selected matrix')
    script=ai.ROOT/'tools/qa/ai_team_soak.gd'
    policy=json.loads(policy_path.read_text()) if policy_path else {}
    frozen=project/'arena_runtime_manifest.json'
    source=json.loads(frozen.read_text())['source'] if frozen.exists() else ai.source_hashes()
    evidence={'source':source,'script':ai.digest(script),'driver':ai.digest(Path(__file__)),
        'ticks':ticks,'policy':policy,'full_hour_matrix':full,'continuous_full_hour':full,'scenario':scenario,'purpose':'multiplayer stability; not strength, fitting or graphical FPS'}
    series=ai.fingerprint(evidence); directory=ai.QA/'soak'/series[:16]
    ai.atomic(directory/'manifest.json',evidence)
    pinned=ai.TEMP/'soak-probes'/series; pinned.mkdir(parents=True,exist_ok=True)
    probe=pinned/'probe.gd'
    if probe.exists() and ai.digest(probe)!=ai.digest(script): raise ValueError('Immutable soak probe changed')
    if not probe.exists(): shutil.copy2(script,probe)
    rows=[]
    matrix=((i,p,m) for i,(p,m) in enumerate([(2,'grasslands'),(2,'coastal'),(2,'islands'),(8,'grasslands'),(8,'coastal'),(8,'islands'),(8,'narrows')])) if full else ((1,4,'coastal'),(0,4,'grasslands'),(2,4,'islands'),(3,8,'islands'))
    for index,players,map_type in matrix:
        if scenario is not None and index!=scenario: continue
        total_ticks=0
        for episode in range(1):
            if total_ticks>=ticks: break
            name=f'soak-{players}p-{map_type}'+(f'-episode{episode:02}' if full else '')
            case={'schema_version':1,'case_id':name,'base_id':name,'series':series,'subject_team':1,
                'player_count':players,'civilizations':list(range(1,players+1)),
                'settings':{'seed':(8100001 if full else 7000001)+index*1009+episode*104729,'map_type_id':map_type,'map_size_id':'large' if players==8 else 'standard',
                    'population_limit':50,'resource_preset_id':'very_high','starting_age_id':'bronze','ai_difficulty_id':'standard','allied_victory_enabled':True,
                    'victory_mode_id':'score_60' if full else 'conquest'},
                'subject_policy':{'algorithm_version':'competitive_v2',**policy},'opponent':'all_competitive_team_soak',
                'maximum_ticks':ticks,'continuous_full_hour':full,'wall_timeout_seconds':21600 if full else 3600,'threaded':True,
                'map_bundle':str(directory/(name+'.map.dat'))}
            case['fingerprint']=ai.fingerprint(case)
            output=directory/(name+'.json'); process_path=directory/(name+'.process.json')
            if output.exists() and process_path.exists():
                row=ai.read_result(output); process=ai.read_result(process_path)
                if valid_episode(row,case) and process.get('passed'):
                    rows.append(row); total_ticks+=int(row['tick']); print('REUSE SOAK',name,flush=True); continue
            if output.exists() or process_path.exists():
                attempt=1
                while (directory/(name+f'.attempt-{attempt}')).exists(): attempt+=1
                previous=directory/(name+f'.attempt-{attempt}'); previous.mkdir()
                for old in directory.glob(name+'.*'):
                    if old.is_file(): old.rename(previous/old.name)
            input_path=directory/(name+'.input.json'); ai.atomic(input_path,case)
            process=ai.run_process(str(probe),directory/(name+'.log'),21615 if full else 3615,['--case='+str(input_path),'--output='+str(output)],project)
            ai.atomic(process_path,process)
            row=ai.read_result(output) or {'case_id':name,'status':'PROCESS_ERROR'}
            result_valid=valid_episode(row,case)
            row['process_valid']=process['passed'] and result_valid; rows.append(row)
            if result_valid: total_ticks+=row['tick']
            print(json.dumps({'case':name,'status':row.get('status'),'tick':row.get('tick'),'process':process}),flush=True)
            ai.atomic(directory/'partial.json',rows)
            if not row['process_valid']: raise RuntimeError('Team soak runtime or result failed; inspect case and progress before resuming')
        if full and total_ticks<ticks: raise RuntimeError('Full-hour soak did not complete a continuous hour in one world')
    summary={'cases':len(rows),'all_processes_passed':all(r.get('process_valid',True) for r in rows),
        'counts':{status:sum(r['status']==status for r in rows) for status in sorted({r['status'] for r in rows})},
        'diagnostic_short_run':not full,'full_hour_matrix':full,'continuous_full_hour':full,'directory':str(directory),'strength_claim':None}
    ai.atomic(directory/'summary.json',summary); print(json.dumps(summary),flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--ticks',type=int,default=12000);parser.add_argument('--policy',type=Path)
    parser.add_argument('--project',type=Path,default=ai.PROJECT);parser.add_argument('--full',action='store_true');parser.add_argument('--scenario',type=int,choices=range(7))
    args=parser.parse_args();run(72000 if args.full else args.ticks,args.policy,args.project.resolve(),args.full,args.scenario)
