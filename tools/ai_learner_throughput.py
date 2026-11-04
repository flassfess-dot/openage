"""Measure full-game environment throughput from explicitly selected Release series.

This does not run training or inspect hidden information for policy features.
Parallel capacity and future RL duration are labelled estimates, not observed
scheduler throughput. Short diagnostics and mixed builds are rejected.
"""
import argparse,math,statistics
from collections import Counter
from pathlib import Path
import ai_competitive as ai

def summarize(directories,release,jobs):
    if not 1<=jobs<=8:raise ValueError('Expected 1..8 environment processes')
    expected={'release_executable':release['executable'],'release_package':release['package'],'native':release['native']}
    cases=[];seen=set();evidence=[]
    for directory in directories:
        manifest=ai.read_result(directory/'series.json')
        if manifest.get('diagnostic_tick_limit') is not None or not manifest.get('series'):raise ValueError('Full-game series required')
        if any(manifest.get('source',{}).get(key)!=value for key,value in expected.items()):raise ValueError('Series belongs to another Release')
        inputs=sorted(directory.glob('*.input.json'))
        summary=ai.read_result(directory/'summary.json')
        if (not inputs or summary.get('series')!=manifest['series'] or summary.get('errors')!=0
                or not isinstance(summary.get('reports'),int) or isinstance(summary.get('reports'),bool)
                or summary['reports']!=len(inputs)):
            raise ValueError('A completed series summary matching all declared inputs is required')
        evidence.append({'path':str(directory),'series':manifest['series'],'manifest_sha256':ai.digest(directory/'series.json'),
                         'summary_sha256':ai.digest(directory/'summary.json'),'completed_cases':len(inputs)})
        outcomes=Counter()
        for input_path in inputs:
            case=ai.read_result(input_path);name=input_path.name.removesuffix('.input.json')
            row=ai.read_result(directory/(name+'.json'));process=ai.read_result(directory/(name+'.process.json'))
            identity=(manifest['series'],name)
            if identity in seen:raise ValueError('Duplicate series/case')
            seen.add(identity)
            if case.get('series')!=manifest['series'] or row.get('case_id')!=name or row.get('fingerprint')!=case.get('fingerprint') or process.get('fingerprint')!=case.get('fingerprint'):raise ValueError('Missing or mismatched case evidence')
            if case.get('fingerprint')!=ai.fingerprint({key:value for key,value in case.items() if key!='fingerprint'}):raise ValueError('Input changed after its fingerprint was frozen')
            if row.get('status') not in ('WIN','LOSS','DRAW_TIME_LIMIT') or process.get('passed') is not True:raise ValueError('Incomplete or failed game; retain failure before estimating throughput')
            outcomes[row['status']]+=1
            if row.get('runtime',{}).get('release') is not True or row.get('runtime',{}).get('native') is not True:raise ValueError('Native Release required')
            values=[row.get('tick'),row.get('wall_seconds'),process.get('seconds')]
            if any(not isinstance(value,(int,float)) or isinstance(value,bool) or not math.isfinite(value) or value<=0 for value in values):raise ValueError('Invalid game timing')
            players=row.get('players',[])
            if not players or any(not isinstance(p.get('metrics',{}).get('decisions'),int) or p['metrics']['decisions']<0 for p in players):raise ValueError('Complete decision counters required')
            usage=process.get('process_metrics',{})
            cpu=usage.get('cpu_seconds');memory=usage.get('peak_private_bytes')
            if (not usage.get('available') or not isinstance(cpu,(int,float)) or isinstance(cpu,bool)
                    or not math.isfinite(cpu) or cpu<0 or not isinstance(memory,int) or isinstance(memory,bool) or memory<=0):raise ValueError('Measured finite CPU and positive peak private memory required')
            cases.append({'case':name,'series':manifest['series'],'ticks':int(row['tick']),
                'decisions_all_players':sum(p['metrics']['decisions'] for p in players),
                'process_seconds':process['seconds'],'simulation_seconds':row['wall_seconds'],
                'cpu_seconds':usage['cpu_seconds'],'peak_private_bytes':usage.get('peak_private_bytes'),
                'setup_and_shutdown_seconds':max(0,process['seconds']-row['wall_seconds'])})
        if dict(outcomes)!=summary.get('counts'):
            raise ValueError('Completed outcomes differ from the declared series summary')
    if not cases:raise ValueError('No full games')
    ticks=sum(r['ticks'] for r in cases);seconds=sum(r['process_seconds'] for r in cases)
    rate=ticks/seconds;capacity=jobs*rate
    return {'schema_version':1,'source_release':release,'games':len(cases),'ticks':ticks,
        'decisions_all_players':sum(r['decisions_all_players'] for r in cases),
        'ticks_per_process_second':rate,'decisions_per_process_second':sum(r['decisions_all_players'] for r in cases)/seconds,
        'simulation_ticks_per_second':ticks/sum(r['simulation_seconds'] for r in cases),
        'process_wall_seconds':{'median':statistics.median(r['process_seconds'] for r in cases),'max':max(r['process_seconds'] for r in cases)},
        'peak_private_bytes':max(r['peak_private_bytes'] for r in cases),
        'cpu_core_equivalents_per_process':sum(r['cpu_seconds'] for r in cases)/seconds,
        'parallel_capacity_estimate':{'processes':jobs,'ticks_per_second':capacity,'days_per_100million_ticks':100_000_000/capacity/86400,
            'assumption':'Ideal scaling at the observed per-process service rate; not measured aggregate wall throughput or a guarantee of RL convergence'},
        'scope':'Full rules and terminal games; process time includes setup/shutdown, simulation time excludes them. Setup includes map/catalog/load and is not isolated map-generation time. Cold/warm layer costs belong to the separate formal performance matrix. Decision counts are full strategy observations, not trace sample counts or external commands.',
        'series':evidence,'cases':cases}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--series',type=Path,nargs='+',required=True);parser.add_argument('--application',type=Path,required=True)
    parser.add_argument('--jobs',type=int,required=True);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();app=args.application.resolve()
    release={'executable':ai.digest(app),'package':ai.digest(app.with_suffix('.pck')),'native':ai.digest(app.parent/'bin/ror_pathfinding.windows.template_release.x86_64.dll')}
    report=summarize([p.resolve() for p in args.series],release,args.jobs);ai.atomic(args.output,report)
    print({key:value for key,value in report.items() if key not in ('cases','series')},flush=True)
