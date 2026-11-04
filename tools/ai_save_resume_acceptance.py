"""Check competitive combat and pending-plan saves on the exact frozen runtime.

Editor integration tests with the same game source/native as the named Release.
Actual packaged EXE checks and full-game strength remain separate evidence.
"""
import argparse, json
from pathlib import Path
import ai_competitive as ai
from ai_combat_acceptance import validate_project_sources

PENDING = ai.ROOT / 'tools/qa/ai_pending_competitive_save.gd'
COMBAT = 'tests/integration/test_adaptive_ai_save_resume.gd'


def run(project, release):
    source = ai.read_result(project / 'arena_runtime_manifest.json').get('source')
    if not isinstance(source, dict):
        raise ValueError('An explicitly frozen project is required')
    validate_project_sources(project, source)
    proof = ai.read_result(release.parent / 'build-provenance.json')
    if not proof.get('artifacts'):
        raise ValueError('Exact Release provenance is required')
    for name, sha in proof['runtime_source_hashes'].items():
        if name != 'prototype/tests/manual/verify_packaged_startup.gd' and source.get(name) != sha:
            raise ValueError('Frozen save/resume source differs from the Release: ' + name)
    if ai.digest(project / 'bin/ror_pathfinding.windows.template_release.x86_64.dll') != proof['artifacts']['bin/ror_pathfinding.windows.template_release.x86_64.dll']:
        raise ValueError('Native library differs from the Release')
    if any(ai.digest(release.parent / name) != sha for name, sha in proof['artifacts'].items()):
        raise ValueError('Actual Release artifact changed')
    evidence = {'source': source, 'release_artifacts': proof['artifacts'],
                'combat_test_sha256': ai.digest(project / COMBAT), 'pending_probe_sha256': ai.digest(PENDING),
                'combat_user_args': ['--competitive-ai', '--competitive', '--combat'],
                'driver_sha256': ai.digest(Path(__file__)), 'process_driver_sha256': ai.digest(Path(ai.__file__))}
    fingerprint = ai.fingerprint(evidence)
    directory = ai.QA / 'save-resume-acceptance' / fingerprint[:16]
    ai.atomic(directory / 'manifest.json', evidence)
    processes = {}
    for name, script, arguments in [('combat', COMBAT, evidence['combat_user_args']),
                                     ('pending', str(PENDING), [str(directory / 'pending.result.json')])]:
        process_path = directory / (name + '.process.json')
        process = ai.read_result(process_path)
        if process_path.exists():
            if process.get('fingerprint') != fingerprint or not process.get('passed'):
                raise RuntimeError('Preserve the incomplete save/resume attempt before an intentional rerun')
        else:
            process = ai.run_process(script, directory / (name + '.log'), 900, arguments, project=project)
            process = {'fingerprint': fingerprint, 'user_args': arguments, **process}
            ai.atomic(process_path, process)
        processes[name] = process
        if not process.get('passed'):
            raise RuntimeError('Competitive save/resume failed: ' + name)
    pending = ai.read_result(directory / 'pending.result.json')
    details = pending.get('details', {})
    if (not pending.get('passed') or pending.get('checks', 0) < 10
            or not all(details.get(k) is True for k in ['competitive', 'native', 'world_equal', 'ai_equal', 'commands_equal'])
            or details.get('recorded_commands', 0) < 1
            or not 0 <= details.get('source_tick', -1) < details.get('saved_tick', -1) < details.get('apply_tick', -1)):
        raise RuntimeError('Pending save must preserve a real command and all three tick boundaries')
    validate_project_sources(project, source)
    if ai.digest(PENDING) != evidence['pending_probe_sha256'] or ai.digest(project / COMBAT) != evidence['combat_test_sha256']:
        raise RuntimeError('A save/resume fixture changed during verification')
    if any(ai.digest(release.parent / name) != sha for name, sha in proof['artifacts'].items()):
        raise RuntimeError('Actual Release changed during verification')
    summary = {'passed': True, 'cases': 2, 'all_processes_passed': True,
               'release_artifacts': proof['artifacts'], 'pending': pending,
               'combat_user_args': evidence['combat_user_args'], 'directory': str(directory),
               'process_logs': {name: process['log'] for name, process in processes.items()},
               'scope': 'Competitive combat feedback and pending economic plan through real save/load; frozen game source and identical Release native DLL in the editor. Combat uses the normal competitive launch flag. Not an actual packaged EXE or full-game strength test.'}
    ai.atomic(directory / 'summary.json', summary)
    print(json.dumps(summary), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, required=True)
    parser.add_argument('--release-application', type=Path, required=True)
    args = parser.parse_args()
    run(args.project.resolve(), args.release_application.resolve())
