"""Aggregate authoritative subject metrics from explicitly qualified full games.

This reads evaluator output after play. Privileged match facts never become
policy features. Unconditional full-game idle is not the peaceful-work criterion.
"""
import math
from collections import Counter
from pathlib import Path

import ai_competitive as ai
import ai_learner_throughput as throughput


def counter(value, name):
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        raise ValueError('Invalid authoritative counter: ' + name)
    return value


def amount(value, name):
    if (not isinstance(value, (int, float)) or isinstance(value, bool)
            or not math.isfinite(value) or value < 0):
        raise ValueError('Invalid authoritative amount: ' + name)
    return value


def ratio(numerator, denominator):
    return numerator / denominator if denominator > 0 else None


def aggregate(reports):
    if not reports:
        raise ValueError('Full-game subject reports required')
    if len({report.get('series') for report in reports}) != 1:
        raise ValueError('Different game series cannot be pooled')
    totals = Counter()
    reasons = Counter()
    deposited = [0] * 4
    stock_integral = [0] * 4
    per_game = []
    seen = set()
    for report in sorted(reports, key=lambda row: (str(row.get('series')), str(row.get('case_id')))):
        identity = (report.get('series'), report.get('case_id'))
        if not all(identity) or identity in seen:
            raise ValueError('Missing or duplicate game identity')
        seen.add(identity)
        if report.get('status') not in ('WIN', 'LOSS', 'DRAW_TIME_LIMIT'):
            raise ValueError('Incomplete game cannot qualify gameplay metrics')
        ticks = counter(report.get('tick'), 'tick')
        if ticks == 0:
            raise ValueError('Zero-length game')
        team = report.get('subject_team')
        if not isinstance(team, int) or isinstance(team, bool) or team <= 0:
            raise ValueError('Invalid subject team')
        measured = report.get('measured', {})
        data = measured.get(str(team), measured.get(team))
        if not isinstance(data, dict):
            raise ValueError('Authoritative subject measurements missing')
        players = [p for p in report.get('players', []) if p.get('team') == team]
        if len(players) != 1:
            raise ValueError('Expected exactly one subject policy record')
        values = {}
        for name in ('worker_ticks', 'idle_worker_ticks', 'tc_ticks', 'tc_idle_ticks',
                     'producer_ticks', 'population_blocked_ticks', 'commands'):
            values[name] = counter(data.get(name), name)
            totals[name] += values[name]
        for numerator, denominator in (('idle_worker_ticks', 'worker_ticks'),
                                       ('tc_idle_ticks', 'tc_ticks'),
                                       ('population_blocked_ticks', 'producer_ticks')):
            if values[numerator] > values[denominator]:
                raise ValueError('Impossible idle/blocked duration')
        rejected = data.get('rejected')
        if not isinstance(rejected, dict):
            raise ValueError('Authoritative rejection reasons missing')
        for reason, count in rejected.items():
            if not isinstance(reason, str) or not reason:
                raise ValueError('Invalid rejection reason')
            reasons[reason] += counter(count, 'rejected.' + reason)
        for name, target in (('deposited', deposited), ('stock_integral', stock_integral)):
            values_array = data.get(name)
            if not isinstance(values_array, list) or len(values_array) != 4:
                raise ValueError('Expected four resource categories: ' + name)
            for index, value in enumerate(values_array):
                target[index] += amount(value, name)
        for name in ('lost_value', 'killed_value', 'converted_value'):
            totals[name] += amount(data.get(name), name)
        totals['ticks'] += ticks
        feedback = players[0].get('metrics', {})
        for name in ('commands_accepted', 'commands_rejected'):
            totals['feedback_' + name] += counter(feedback.get(name), name)
        accepted = values['commands']
        failures = sum(rejected.values())
        per_game.append({'case_id': report['case_id'],
                         'accepted': accepted, 'rejected': failures,
                         'raw_rejection_ratio': ratio(failures, accepted + failures),
                         'unconditional_worker_idle': ratio(values['idle_worker_ticks'], values['worker_ticks']),
                         'unconditional_tc_idle': ratio(values['tc_idle_ticks'], values['tc_ticks']),
                         'population_blocked': ratio(values['population_blocked_ticks'], values['producer_ticks'])})
    failures = sum(reasons.values())
    raw_rate = ratio(failures, totals['commands'] + failures)
    return {'schema_version': 1, 'games': len(reports), 'ticks': totals['ticks'],
            'commands': {'accepted': totals['commands'], 'rejected': failures,
                         'raw_rejection_ratio': raw_rate,
                         'reasons': dict(sorted(reasons.items())),
                         'raw_upper_bound_below_one_percent': raw_rate is not None and raw_rate < .01,
                         'race_exclusions': [],
                         'scope': 'All authoritative refusals retained. Raw rate bounds unexpected refusals from above; target-death and occupancy races are not silently inferred or excluded.'},
            'policy_feedback': {'accepted': totals['feedback_commands_accepted'],
                                'rejected': totals['feedback_commands_rejected'],
                                'scope': 'Planner feedback may omit direct legacy-controller commands; it is not the denominator of the authoritative command rate.'},
            'unconditional_idle': {'worker_ticks': totals['worker_ticks'],
                                   'idle_worker_ticks': totals['idle_worker_ticks'],
                                   'worker_ratio': ratio(totals['idle_worker_ticks'], totals['worker_ticks']),
                                   'tc_ticks': totals['tc_ticks'], 'tc_idle_ticks': totals['tc_idle_ticks'],
                                   'tc_ratio': ratio(totals['tc_idle_ticks'], totals['tc_ticks']),
                                   'scope': 'Time-weighted full-game evaluator counters; idle task only. Does not establish the peaceful available-work <=5% criterion.'},
            'housing': {'producer_ticks': totals['producer_ticks'],
                        'population_blocked_ticks': totals['population_blocked_ticks'],
                        'ratio': ratio(totals['population_blocked_ticks'], totals['producer_ticks']),
                        'scope': 'Unconditional full-game production occupancy; peaceful controls are reported separately.'},
            'resources': {'deposited': deposited,
                          'mean_stock': [value / totals['ticks'] for value in stock_integral],
                          'order': ['food', 'wood', 'stone', 'gold']},
            'combat_value': {'lost': totals['lost_value'], 'killed': totals['killed_value'],
                             'converted': totals['converted_value'],
                             'direct_death_exchange': ratio(totals['killed_value'], totals['lost_value']),
                             'scope': 'Recorded deaths and conversions shown separately. Healing does not create kills; this is not the paired micro improvement experiment.'},
            'per_game': sorted(per_game, key=lambda row: row['case_id'])}


def qualified_series(directory, release, expected_games, subject=None, overrides=None):
    """Reuse full-game/process/build checks, then validate the full tick horizon."""
    directory = Path(directory)
    verified = throughput.summarize([directory], release, 1)
    if verified['games'] != expected_games:
        raise ValueError('Incomplete gameplay metric cohort')
    manifest = ai.read_result(directory / 'series.json')
    series = manifest['series']
    if subject is not None and manifest.get('subject') != subject:
        raise ValueError('Gameplay metric series uses another subject algorithm')
    if overrides is not None and manifest.get('overrides') != overrides:
        raise ValueError('Gameplay metric series uses another policy')
    reports = []
    for entry in verified['cases']:
        name = entry['case']
        case = ai.read_result(directory / (name + '.input.json'))
        report = ai.read_result(directory / (name + '.json'))
        identity = {key: value for key, value in case.items() if key != 'fingerprint'}
        if ai.fingerprint(identity) != case.get('fingerprint') or report.get('series') != series:
            raise ValueError('Game identity changed after execution')
        maximum = case.get('maximum_ticks')
        if not isinstance(maximum, int) or isinstance(maximum, bool) or maximum < 36000:
            raise ValueError('Shortened full-game horizon')
        tick = report.get('tick')
        if (not isinstance(tick, int) or isinstance(tick, bool) or tick > maximum
                or (report['status'] == 'DRAW_TIME_LIMIT' and tick != maximum)):
            raise ValueError('Terminal result does not match its full-game horizon')
        reports.append(report)
    result = aggregate(reports)
    result['source_release'] = release
    result['series'] = series
    result['evidence'] = {'directory': directory.relative_to(ai.ROOT).as_posix(),
                          'manifest_sha256': ai.digest(directory / 'series.json')}
    return result
