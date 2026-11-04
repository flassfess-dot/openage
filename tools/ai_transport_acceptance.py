"""Verify two physical transport waves on frozen game sources and Release DLL.

This is a controlled component test in the editor. Full policy/strength, action
budgets, ordinary matches and actual EXE checks are verified separately.
"""
import argparse, json
from pathlib import Path
import ai_competitive as ai
from ai_combat_acceptance import validate_project_sources

SCRIPT = ai.ROOT / 'tools/qa/ai_transport_two_waves.gd'


def run(project, release=None):
    source = ai.read_result(project / 'arena_runtime_manifest.json').get('source')
    if not isinstance(source, dict):
        raise ValueError('An explicitly frozen runtime project is required')
    validate_project_sources(project, source)
    proof = ai.read_result(release.parent / 'build-provenance.json') if release else {}
    if release:
        if not proof.get('artifacts'):
            raise ValueError('Release provenance is required')
        for name, sha in proof['runtime_source_hashes'].items():
            if name != 'prototype/tests/manual/verify_packaged_startup.gd' and source.get(name) != sha:
                raise ValueError('Frozen transport component differs from the Release source: ' + name)
        if ai.digest(project / 'bin/ror_pathfinding.windows.template_release.x86_64.dll') != proof['artifacts']['bin/ror_pathfinding.windows.template_release.x86_64.dll']:
            raise ValueError('Frozen project and Release must use the same native library')
        if any(ai.digest(release.parent / name) != sha for name, sha in proof['artifacts'].items()):
            raise ValueError('Actual Release artifact changed')
    evidence = {'source': source, 'probe_sha256': ai.digest(SCRIPT), 'driver_sha256': ai.digest(Path(__file__)),
                'process_driver_sha256': ai.digest(Path(ai.__file__)), 'release_artifacts': proof.get('artifacts')}
    fingerprint = ai.fingerprint(evidence)
    directory = ai.QA / 'transport-acceptance' / fingerprint[:16]
    ai.atomic(directory / 'manifest.json', evidence)
    def execute(name, flags):
        output = directory / (name + '.json')
        process_path = directory / (name + '.process.json')
        process = ai.read_result(process_path)
        if output.exists() or process_path.exists():
            if process.get('fingerprint') != fingerprint or not process.get('passed'):
                raise RuntimeError('Preserve the incomplete transport attempt before an intentional rerun')
        else:
            process = ai.run_process(str(SCRIPT), directory / (name + '.engine.log'), 900,
                                     [str(output), *flags], project=project)
            process = {'fingerprint': fingerprint, **process}
            ai.atomic(process_path, process)
        row = ai.read_result(output)
        ticks = row.get('wave_landing_ticks', [])
        valid = (process.get('passed') and row.get('passed') and row.get('competitive') is True
                 and row.get('runtime', {}).get('native') is True
                 and len(ticks) == 2 and 0 < ticks[0] < ticks[1] <= 4000
                 and row.get('returning_for_troops_observed') is True
                 and row.get('command_trace_complete') is True
                 and row.get('reboarded_arrived_troops') == 0 and row.get('cargo') == []
                 and row.get('accepted_types', {}).get('board', 0) >= 2
                 and row.get('accepted_types', {}).get('unload', 0) >= 2)
        if not valid:
            raise RuntimeError('Two-wave transport component or no-reboarding criterion failed: ' + name)
        return row, output

    row, output = execute('result', [])
    ticks = row.get('wave_landing_ticks', [])
    checkpoints = {}
    parity_fields = ('tick', 'wave_landing_ticks', 'returning_for_troops_observed',
                     'accepted_types', 'rejected_reasons', 'trace', 'waves', 'cargo',
                     'world_hash', 'reboarded_arrived_troops', 'canonical_ai_state',
                     'public_command_count', 'command_trace_complete')
    for mode in ('boarding', 'transit'):
        restored, restored_path = execute('checkpoint-' + mode, ['--checkpoint-' + mode])
        checkpoint = restored.get('transport_checkpoint', {})
        valid = (checkpoint.get('mode') == mode and checkpoint.get('world_exact') is True
                 and checkpoint.get('canonical_ai_exact') is True
                 and isinstance(checkpoint.get('tick'), int) and 0 < checkpoint['tick'] < ticks[-1]
                 and (checkpoint.get('approaching_passenger') is True if mode == 'boarding'
                      else checkpoint.get('cargo_count') == 2))
        equal = all(restored.get(key) == row.get(key) for key in parity_fields)
        if not valid or not equal:
            raise RuntimeError('Saved transport did not continue with identical commands/world/AI: ' + mode)
        checkpoints[mode] = {'passed': True, 'checkpoint': checkpoint,
                             'exact_final_world_commands_ai': equal,
                             'result_sha256': ai.digest(restored_path)}
    validate_project_sources(project, source)
    if ai.digest(SCRIPT) != evidence['probe_sha256']:
        raise RuntimeError('Transport probe changed during the check')
    if release and any(ai.digest(release.parent / name) != sha for name, sha in proof['artifacts'].items()):
        raise RuntimeError('Actual Release changed during the check')
    summary = {'passed': True, 'process_passed': True, 'cases': 3, 'wave_landing_ticks': ticks,
               'accepted_types': row['accepted_types'], 'reboarded_arrived_troops': 0,
               'checkpoint_continuations': checkpoints,
               'release_artifacts': proof.get('artifacts'), 'directory': str(directory),
               'probe_sha256': evidence['probe_sha256'], 'result_sha256': ai.digest(output),
               'scope': 'Controlled competitive transport component, exact frozen game source and native DLL. Real-file world/expedition checkpoints during boarding and loaded transit must retain both landing ticks, all generated commands, final world and canonical AI state. Authored scouted fixture and explicit transport goal; no independently running full strategic AI, APM, modern-map generalization, strength or actual packaged EXE claim.'}
    ai.atomic(directory / 'summary.json', summary)
    print(json.dumps(summary), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, required=True)
    parser.add_argument('--release-application', type=Path)
    args = parser.parse_args()
    run(args.project.resolve(), args.release_application.resolve() if args.release_application else None)
