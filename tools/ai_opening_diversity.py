"""Check actual early decisions on twenty dev seeds in the selected Release.

Forty 400-tick diagnostics and two exact-input replays. These are neither full
strength games nor evidence that style selection considers map/civilization.
"""
import argparse, collections, json
from pathlib import Path
import ai_competitive as ai
from ai_openings import parameters_match


def check(application, policy_path, jobs, output):
    application = application.resolve()
    if not policy_path.is_file():
        raise ValueError('An explicit frozen champion policy is required')
    selected = json.loads(policy_path.read_text(encoding='utf-8'))
    if not isinstance(selected, dict):
        raise ValueError('The frozen policy must be a JSON object')
    policy_sha256 = ai.digest(policy_path)
    ai.ENGINE = application
    ai.PACK = application.with_suffix('.pck')
    release = {'release_executable': ai.digest(application),
               'release_package': ai.digest(ai.PACK),
               'native': ai.digest(application.parent / 'bin/ror_pathfinding.windows.template_release.x86_64.dll')}
    summary = ai.arena('dev', 'competitive_v2', jobs, 20, ticks=400, overrides=selected)
    if summary.get('reports') != 40 or summary.get('errors'):
        raise RuntimeError('All forty early-decision processes are required')
    directory = ai.ROOT / summary['directory']
    series = ai.read_result(directory / 'series.json')
    if any(series.get('source', {}).get(k) != v for k, v in release.items()):
        raise RuntimeError('Early decisions belong to another Release')
    manifest = ai.read_result(ai.PROJECT / 'data/ai/arena/manifests/dev.json')
    expected = {row['id'] + '-seat' + str(seat)
                for row in manifest['rows'][:20] for seat in (1, 2)}
    records = []
    for name in sorted(expected):
        case = ai.read_result(directory / (name + '.input.json'))
        row = ai.read_result(directory / (name + '.json'))
        process = ai.read_result(directory / (name + '.process.json'))
        canonical = {k: v for k, v in case.items() if k != 'fingerprint'}
        if (case.get('fingerprint') != ai.fingerprint(canonical)
                or case.get('series') != series['series']
                or row.get('fingerprint') != case['fingerprint']
                or process.get('fingerprint') != case['fingerprint']
                or not process.get('passed') or row.get('tick') != 400
                or row.get('status') != 'DRAW_TIME_LIMIT'
                or not row.get('runtime', {}).get('release')
                or not row.get('runtime', {}).get('native')):
            raise RuntimeError('Incomplete or mismatched early-decision evidence: ' + name)
        subject = [p for p in row.get('players', []) if p.get('team') == case['subject_team']]
        if (len(subject) != 1
                or subject[0].get('policy', {}).get('algorithm_version') != 'competitive_v2'
                or not parameters_match(subject[0].get('policy', {}), selected)):
            raise RuntimeError('Subject policy differs from the selected champion')
        macro = subject[0].get('metrics', {}).get('macro_plan', {})
        replay_path = Path(row['replay'])
        if not replay_path.resolve().is_relative_to(directory.resolve()):
            raise RuntimeError('Replay must remain in the declared series')
        replay = ai.read_result(replay_path)
        if replay.get('format_version') != 5 or not isinstance(replay.get('commands'), list):
            raise RuntimeError('Versioned public command replay is required')
        commands = [c for c in replay.get('commands', []) if c.get('issuer_id') == case['subject_team']]
        families = [[c.get('type'), c.get('params', {}).get('building_type'),
                     c.get('params', {}).get('unit_type'), c.get('params', {}).get('technology_id')]
                    for c in commands[:16]]
        records.append({'case': name, 'seed': row.get('seed'), 'subject_team': case['subject_team'],
                        'style': macro.get('style'), 'macro_plan': macro,
                        'decision_count': subject[0].get('metrics', {}).get('decisions', 0),
                        'issued_commands': len(commands), 'first_command_families': families,
                        'command_family_signature': ai.fingerprint(families),
                        'replay_sha256': ai.digest(replay_path),
                        'result_sha256': ai.digest(directory / (name + '.json'))})
    repeats = []
    repeat_directory = directory / 'early-decision-repeats'
    repeat_directory.mkdir(exist_ok=True)
    first_base = manifest['rows'][0]['id']
    for seat in (1, 2):
        name = first_base + '-seat' + str(seat)
        case_path = directory / (name + '.input.json')
        target = repeat_directory / (name + '.json')
        process_path = repeat_directory / (name + '.process.json')
        case = ai.read_result(case_path)
        # Execute independently of the original arena result. Resume only a
        # completed repeat with its own matching input/process evidence.
        if target.exists() or process_path.exists():
            process = ai.read_result(process_path)
            if not process.get('passed') or process.get('fingerprint') != case['fingerprint']:
                raise RuntimeError('Preserve incomplete repeat evidence before an intentional rerun')
        else:
            process = ai.run_process('tools/ai_arena.gd', repeat_directory / (name + '.engine.log'),
                                     300, ['--case=' + str(case_path), '--output=' + str(target)])
            process = {'fingerprint': case['fingerprint'], **process}
            ai.atomic(process_path, process)
        original = ai.read_result(directory / (name + '.json'))
        repeated = ai.read_result(target)
        before = ai.read_result(Path(original['replay']))
        after = ai.read_result(Path(repeated['replay'])) if repeated.get('replay') else {}
        equal = (process.get('passed') and repeated.get('fingerprint') == original['fingerprint']
                 and repeated.get('status') == 'DRAW_TIME_LIMIT'
                 and repeated.get('runtime', {}).get('release') and repeated.get('runtime', {}).get('native')
                 and repeated.get('tick') == 400 and repeated.get('final_hash') == original['final_hash']
                 and after.get('format_version') == before.get('format_version') == 5
                 and isinstance(after.get('commands'), list)
                 and after.get('commands') == before.get('commands'))
        repeats.append({'case': name, 'passed': bool(equal), 'process': process,
                        'repeated_result_sha256': ai.digest(target) if target.exists() else None})
        if not equal:
            raise RuntimeError('Identical input changed world state or command order')
    current_release = {'release_executable': ai.digest(application), 'release_package': ai.digest(ai.PACK),
                       'native': ai.digest(application.parent / 'bin/ror_pathfinding.windows.template_release.x86_64.dll')}
    if release != current_release or policy_sha256 != ai.digest(policy_path):
        raise RuntimeError('Release or selected policy changed during the diagnostics')
    styles = dict(sorted(collections.Counter(str(r['style']) for r in records).items()))
    result = {'passed': True, 'release': release, 'policy_sha256': policy_sha256,
              'series': str(directory.relative_to(ai.ROOT)), 'series_manifest_sha256': ai.digest(directory / 'series.json'),
              'reports': 40, 'ticks_per_case': 400, 'styles': styles,
              'all_four_styles_observed': set(styles) == {'pressure', 'fast_age', 'growth', 'naval'},
              'unique_coordinate_free_command_sequences': len({r['command_family_signature'] for r in records}),
              'all_subjects_issued_commands': all(r['issued_commands'] > 0 for r in records),
              'exact_input_repeats': repeats, 'records': records,
              'scope': 'Real first twenty dev seeds, both seats, actual 400-tick selected Release and public command replays. Two identical-input executions verify deterministic commands and world hash. No strength, complete opening, or context-sensitive style-selection claim.'}
    ai.atomic(output, result)
    print({k: v for k, v in result.items() if k not in ('records', 'exact_input_repeats')}, flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--application', type=Path, required=True)
    parser.add_argument('--policy', type=Path, required=True)
    parser.add_argument('--jobs', type=int, choices=range(1, 9), default=6)
    parser.add_argument('--output', type=Path, required=True)
    arguments = parser.parse_args()
    check(arguments.application, arguments.policy, arguments.jobs, arguments.output)
