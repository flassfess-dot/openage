"""Physical allied repair/trade with save continuation and public-command replay.

Controlled AI components in the editor, with exact frozen game source and native
library. This does not measure full-policy strength or packaged graphical FPS.
"""
import argparse,json
from pathlib import Path
import ai_competitive as ai
from ai_combat_acceptance import validate_project_sources

SCRIPT=ai.ROOT/'tools/qa/ai_team_economy_runtime.gd'


def run(project,release=None):
    source=ai.read_result(project/'arena_runtime_manifest.json').get('source')
    if not isinstance(source,dict):raise ValueError('An explicitly frozen runtime is required')
    validate_project_sources(project,source)
    proof=ai.read_result(release.parent/'build-provenance.json') if release else {}
    if release:
        if not proof.get('artifacts'):raise ValueError('Actual Release provenance required')
        if any(source.get(name)!=value for name,value in proof['runtime_source_hashes'].items()):raise ValueError('Team economy source differs from the final Release')
        if ai.digest(project/'bin/ror_pathfinding.windows.template_release.x86_64.dll')!=proof['artifacts']['bin/ror_pathfinding.windows.template_release.x86_64.dll']:raise ValueError('Native library differs')
        if any(ai.digest(release.parent/name)!=value for name,value in proof['artifacts'].items()):raise ValueError('Actual Release artifact changed')
    evidence=dict(source=source,probe_sha256=ai.digest(SCRIPT),driver_sha256=ai.digest(Path(__file__)),
                  process_driver_sha256=ai.digest(Path(ai.__file__)),release_artifacts=proof.get('artifacts'))
    fingerprint=ai.fingerprint(evidence)
    directory=ai.QA/'team-economy-acceptance'/fingerprint[:16]
    manifest=directory/'manifest.json'
    if manifest.exists() and ai.read_result(manifest)!=evidence:raise RuntimeError('Existing immutable evidence differs')
    ai.atomic(manifest,evidence)
    output=directory/'report.json';process_path=directory/'process.json'
    if output.exists() or process_path.exists():
        process=ai.read_result(process_path)
        if process.get('fingerprint')!=fingerprint or not process.get('passed'):raise RuntimeError('Preserve failed attempt before retrying')
    else:
        process=ai.run_process(str(SCRIPT),directory/'engine.log',900,['--output='+str(output)],project)
        process={'fingerprint':fingerprint,**process};ai.atomic(process_path,process)
    report=ai.read_result(output);rows=report.get('results',[])
    if not process.get('passed') or not report.get('passed') or not report.get('runtime',{}).get('native'):raise RuntimeError('Team economy component failed; inspect '+str(directory))
    if len(rows)!=6 or {(r.get('teams'),r.get('mode')) for r in rows}!={(count,mode) for count in (4,8) for mode in ('live','saved','replay')}:raise RuntimeError('Six distinct component executions required')
    compact=[]
    for count in (4,8):
        live=next(r for r in rows if r['teams']==count and r['mode']=='live')
        for row in [r for r in rows if r['teams']==count]:
            if row.get('tick')!=1200 or any(row.get(key,0)<=0 for key in ('repaired_hp','repair_wood','trips','gold')):raise RuntimeError('Actual paid repair and completed trade required')
            if row.get('world_hash')!=live.get('world_hash') or row.get('commands')!=live.get('commands'):raise RuntimeError('Save/replay differs from live world or complete public commands')
            if row['mode']=='saved' and (not row.get('checkpoint',{}).get('exact_world_ai') or row['checkpoint'].get('repair_progress',0)<=0 or row['checkpoint'].get('trade_task')!='trade'):raise RuntimeError('Checkpoint must preserve actual in-progress allied repair and trade')
            compact.append({key:row[key] for key in ('teams','mode','tick','repaired_hp','repair_wood','trips','gold','world_hash','checkpoint')})
    validate_project_sources(project,source)
    if ai.digest(SCRIPT)!=evidence['probe_sha256']:raise RuntimeError('Probe changed during execution')
    if release and any(ai.digest(release.parent/name)!=value for name,value in proof['artifacts'].items()):raise RuntimeError('Actual Release changed during execution')
    summary=dict(passed=True,cases=6,process_passed=True,release_artifacts=proof.get('artifacts'),
                 directory=str(directory),probe_sha256=evidence['probe_sha256'],report_sha256=ai.digest(output),
                 results=compact,scope=report['scope'])
    ai.atomic(directory/'summary.json',summary)
    print(json.dumps(summary),flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project',type=Path,required=True)
    parser.add_argument('--release-application',type=Path)
    args=parser.parse_args()
    run(args.project.resolve(),args.release_application.resolve() if args.release_application else None)
