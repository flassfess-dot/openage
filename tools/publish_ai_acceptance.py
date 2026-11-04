"""Publish compact acceptance evidence; --final refuses incomplete finite phases.

Run after tools/ai_evaluate_final.py and the champion performance/soak checks.
Detailed local worlds and logs remain outside Git.
"""
import argparse,sys,json,re,datetime
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
import ai_competitive as ai
from ai_acceptance_checks import final_evaluation_matches_release, suite_boundary_matches_evidence, performance_matches_release, final_complete_suite_matches_release, strategy_sampling_matches_release
from ai_openings import work_matrix_valid
from ai_gameplay_metrics import qualified_series as gameplay_series
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--final',action='store_true')
parser.add_argument('--output',type=Path,default=ROOT/'doc/ror-modern/AI_COMPETITIVE_ACCEPTANCE.json')
args=parser.parse_args()
Q=ai.QA;final=args.final

def read(p):return ai.read_result(p)
def ref(p):return {'path':p.relative_to(ROOT).as_posix(),'sha256':ai.digest(p)}
def last_json(p):
 if not p.exists():return {}
 for line in reversed(p.read_text(encoding='utf-8-sig',errors='replace').splitlines()):
  try:r=json.loads(line)
  except ValueError:continue
  if isinstance(r,dict):return r
 return {}
def relative_path(value):
 p=Path(value)
 return p.relative_to(ROOT).as_posix() if p.is_absolute() else p.as_posix()
checkpoint=read(Q/'champion_pipeline_checkpoint.json')
if final and not checkpoint.get('stage','').startswith('all finite gameplay phases finished;'):raise RuntimeError('Required finite phases are not finished')
app=Path(checkpoint['application']) if checkpoint.get('application') else Path(read(Q/'current_release.json')['application'])
proof=read(app.parent/'build-provenance.json')
if any(ai.digest(app.parent/name)!=value for name,value in proof['artifacts'].items()):raise RuntimeError('Actual artifact changed after build')
coverage=read(Q/'suite_coverage.json')
boundary=read(Q/'fresh_suite_boundary.json')
suite_stdout=ROOT/str(boundary.get('suite_stdout',str((Q/'final-full-suite.stdout.log').relative_to(ROOT))))
if not suite_stdout.resolve().is_relative_to(Q.resolve()):raise RuntimeError('Full suite evidence must remain in the local QA directory')
test_closure=read(Q/'test_source_closure.after-complete-suite.json')
complete_path=Q/'quality-r20/full-suite/qualification.json'
complete=read(complete_path)
if final:
 test_sources={p.relative_to(ai.PROJECT).as_posix():ai.digest(p) for category in ('golden','integration','scenarios','unit') for p in sorted((ai.PROJECT/'tests'/category).glob('test_*.gd'))}
 all_test_sources={p.relative_to(ai.PROJECT).as_posix():ai.digest(p) for p in sorted((ai.PROJECT/'tests').rglob('*.gd'))}
 inventory=len(test_sources)
 if inventory<513 or not test_closure.get('passed') or test_closure.get('inventory')!=inventory or test_closure.get('test_source_sha256')!=ai.fingerprint(test_sources):raise RuntimeError('The full suite test-source closure is missing or changed')
 if not final_complete_suite_matches_release(complete,proof,all_test_sources,inventory):raise RuntimeError('A fresh complete final-source suite on the actual final native is required')
 complete_dir=complete_path.parent
 for field,name in [('before_sha256','before.json'),('full_suite_result_sha256','result.json'),('suite_stdout_sha256','suite.stdout.log'),('coverage_sha256','coverage.json')]:
  if complete.get(field)!=ai.digest(complete_dir/name):raise RuntimeError('Final complete suite evidence changed: '+name)
 full_result=read(complete_dir/'result.json')
 if not full_result.get('passed') or not full_result.get('unchanged_source_and_tests') or full_result.get('process',{}).get('exit_code')!=0:raise RuntimeError('The fresh final suite process did not pass')
 if suite_stdout.resolve()!=(complete_dir/'suite.stdout.log').resolve() or boundary.get('runtime_source_hashes')!=proof['runtime_source_hashes'] or test_closure.get('runtime_source_hashes')!=proof['runtime_source_hashes']:raise RuntimeError('Complete suite belongs to an earlier source or invocation')
 if not suite_boundary_matches_evidence(coverage,boundary,ai.digest(Q/'suite_coverage.json'),ai.digest(suite_stdout),inventory):raise RuntimeError('Full suite coverage is incomplete or differs from the audited fresh boundary')
python_log=(Q/'python-tests-final.stdout.log').read_text(encoding='utf-8-sig')
python_count=int(re.findall(r'Ran (\d+) tests',python_log)[-1])
if python_log.strip().splitlines()[-1]!='OK':raise RuntimeError('Python suite not passed')
report={'schema_version':1,'status':'FINITE_PHASES_FINISHED_REVIEW_QUALITY_GAPS' if final else 'IN_PROGRESS',
 'generated_local':str(datetime.datetime.now()),'performance_hardware':read(Q/'performance_hardware.json'),'human_strength':'HUMAN_UNMEASURED',
 'source':{'runtime_fingerprint':ai.fingerprint(proof['runtime_source_hashes']),'artifact_hashes':proof['artifacts'],'build_provenance':ref(app.parent/'build-provenance.json')},
 'tests':{'godot':{k:coverage[k] for k in ['scope','discovered','passed','missing','unresolved_failures','all_discovered_covered']},'coverage':ref(Q/'suite_coverage.json'),'python_passed':python_count,'python_log':ref(Q/'python-tests-final.stdout.log'),'powershell_log':ref(Q/'final-build-helpers.stdout.log'),'cache':read(Q/'final-cache-validation.json').get('summary',{})},
 'combat':read(Q/'forecast_calibration.json'),'urgent_defense':read(Q/'urgent_defense.json'),'urgent_before':read(Q/'urgent_defense.before-fix.json'),'bronze_retry_regression':read(Q/'bronze_retry_regression.json'),
 'micro_reachability':read(Q/'micro_reachability_benchmark.json'),
 'micro_battle_parity':read(Q/'micro_cache_combat_parity.json'),
 'traffic_heap':read(Q/'traffic_heap_benchmark.json'),
 'controlled_openings':{},'evaluation':[],'performance':{},'rendered_performance':{},'soaks':[],'packaged_checks':{},
 'compatibility':{'archive':8,'checkpoint':4,'replay':5,'read_contract':4,'previous_archive7':'explicitly unsupported; no migration; original user save preserved'},
 'scope':'Compact evidence; raw worlds, replays, private user save, machine usernames and per-unit observations are excluded. Detailed local files remain under prototype/qa/ai-competitive/competitive-20261030.'}
if complete:
 report['tests']['fresh_final_complete_suite']={'passed':complete.get('passed'),'scripts':complete.get('inventory'),'python_tests':complete.get('python_tests'),'powershell_checks':complete.get('powershell_checks'),'cache_summary':complete.get('cache_summary'),'evidence':ref(complete_path),'scope':complete.get('scope')}
sampling_path=Q/'arena-trace-sampling-r22/shipping-final/qualification.json'
sampling=read(sampling_path)
if final and not strategy_sampling_matches_release(sampling,proof):raise RuntimeError('Exact final shipping strategy-sampling verification is required')
if sampling:
 if final:
  if sampling.get('verification_driver_sha256')!=ai.digest(ai.TEMP/'verify_shipping_trace_sampling_r22.py'):raise RuntimeError('Shipping sampling verification procedure changed')
  for row in sampling['records']:
   if row.get('report_sha256')!=ai.digest(sampling_path.parent/(row['name']+'.json')) or row.get('input_sha256')!=ai.digest(sampling_path.parent/(row['name']+'.input.json')):raise RuntimeError('Shipping sampling evidence changed')
 report['strategy_sampling']={'evidence':ref(sampling_path),'passed':sampling.get('passed'),'records':[{key:row.get(key) for key in ['case','status','tick','sampling']} for row in sampling.get('records',[])],'scope':sampling.get('scope'),'legacy_tuning_data':'R19 retains its original bounded prefix traces; the new collector does not retroactively change demonstrations or fitness.'}
impact_path=Q/'quality-r20/current-native-impacts/qualification.json'
impact=read(impact_path)
if impact:
 matched=(impact.get('passed') is True and impact.get('artifacts')==proof['artifacts']
          and impact.get('source')==proof['runtime_source_hashes']
          and len(impact.get('results',[]))==23
          and all(row.get('passed') is True for row in impact.get('results',[])))
 if final and not matched:raise RuntimeError('Post-selection gameplay impacts must match the exact final native and parameters')
 report['tests']['post_selection_impacts']={'passed':matched,'scripts':len(impact.get('results',[])),
  'evidence':ref(impact_path),'scope':impact.get('scope')}
if final and not impact:raise RuntimeError('Fresh final-native affected gameplay checks missing')
frames_path=Q/'user-half-second-freeze-20261101/release-r20-frame-verification.json'
frames=read(frames_path)
if frames:
 matched=(frames.get('completed') is True and frames.get('artifacts')==proof['artifacts']
          and len(frames.get('runs',[]))==2)
 if final and not matched:raise RuntimeError('Actual user-save frame pair must match the exact final Release')
 report['actual_user_save_frames']={'completed':matched,'runs':frames.get('runs',[]),
  'evidence':ref(frames_path),'scope':frames.get('scope'),
  'limitation':'Frame tails require separate review; completed measurements do not imply zero spikes or measured human strength.'}
if final and not frames:raise RuntimeError('Final actual user-save static/camera and isolated-autosave measurements missing')
if test_closure:
 report['tests']['test_source_closure']={'inventory':test_closure.get('inventory'),'sha256':test_closure.get('test_source_sha256'),
  'invocation_snapshot_sha256':test_closure.get('invocation_snapshot_sha256'),'fixture_corrections':test_closure.get('fixture_corrections',{}),
  'scope':test_closure.get('scope'),'evidence':ref(Q/'test_source_closure.after-complete-suite.json')}
delivery_repair=read(Q/'dropoff-reservation-r10/qualification.json')
if delivery_repair:
 report['delivery_reservation_repair']={'passed':delivery_repair.get('passed'),
  'pre_fix_regression_reproduced':delivery_repair.get('before',{}).get('passed') is False,
  'impact_tests':len(delivery_repair.get('results',[])),
  'all_impacts_passed':all(row.get('passed') for row in delivery_repair.get('results',[])),
  'actual_stranded_boat_recovered':delivery_repair.get('actual_boat_recovered'),
  'scope':'Implicit delivery retains its depot owner; completion/interruption frees the berth; retries reclaim only the same carrier stale reservation. Does not establish the full-game command-rejection target.',
  'evidence':ref(Q/'dropoff-reservation-r10/qualification.json')}
navigation_repair=read(Q/'navigation-privacy-r11/qualification.json')
if navigation_repair:
 report['navigation_privacy_repair']={'passed':navigation_repair.get('passed'),
  'counterfactual_leak_reproduced':read(Q/'hidden-navigation-counterfactual/result-v2.json').get('noninterference_passed') is False,
  'impact_tests':len(navigation_repair.get('results',[])),
  'all_impacts_passed':all(row.get('passed') for row in navigation_repair.get('results',[])),
  'kernel_measurements':navigation_repair.get('kernel_measurements',[]),
  'scope':'Team legal terrain/occupancy and its change journal drive full and budgeted navigation. Hidden changes stay remembered across checkpoints. Native surface BFS matches reference labels and serialization. Private kernel timings are not final graphical FPS; exact final suite and Release checks are reported separately.',
  'evidence':ref(Q/'navigation-privacy-r11/qualification.json')}
egress=read(Q/'navigation-egress-r12-final-impacts/qualification.json')
if egress:
 delivery=read(Q/'traffic-clearance-r12-v5/qualification.json')
 placement=read(Q/'original-construction-access-r12-local-index/result.json')
 report['construction_and_traffic_repair']={
  'impact_tests':len(egress.get('results',[])),
  'all_impacts_passed':egress.get('passed') is True and all(row.get('passed') for row in egress.get('results',[])),
  'original_closing_sites_rejected':placement.get('passed') is True and len(placement.get('results',[]))==2,
  'real_cargo_deposited':delivery.get('passed') is True and delivery.get('deposited') is True and delivery.get('remaining')==0,
  'delivery_ticks':delivery.get('advanced_ticks'),
  'public_clearance_orders':len(delivery.get('clearance_commands',[])),
  'isolated_planning_cost':read(Q/'navigation-egress-r12-planning-cost-early-gates/result.json'),
  'scope':'Known construction access is preserved with bounded local cell extraction. Idle own units yield through public moves; held/active/foreign orders are preserved. Actual cargo credit qualified on the reconstructed stalled state. Planning-kernel timings are not graphical FPS or full E6 acceptance.',
  'evidence':ref(Q/'navigation-egress-r12-final-impacts/qualification.json')}
for age in (101,102):
 paths=[Q/('champion-openings-age'+str(age)+'.stdout.log'),Q/('defense-core-openings-age'+str(age)+'.stdout.log'),Q/('micro-core-openings-age'+str(age)+'.stdout.log')]
 if final:paths=paths[:1]
 for path in paths:
  row=last_json(path)
  if row.get('reports')==32:
   if final and not work_matrix_valid(row.get('conditional_worker_idle')):raise RuntimeError('All32 exact-source conditional-idle observations and purity checks are required')
   report['controlled_openings'][str(age)]={'summary':row,'evidence':ref(path)};break
 if final and str(age) not in report['controlled_openings']:raise RuntimeError('Controlled openings incomplete')
transport_gate=Q/'transport-target-filter-r20b/qualification.json'
transport_cleanup=read(transport_gate)
if transport_cleanup:
 before_transport=transport_cleanup.get('records',{}).get('before-competitive',{}).get('result',{})
 after_transport=transport_cleanup.get('records',{}).get('after-competitive',{}).get('result',{})
 promotion=read(Q/'transport_target_filter_promotion.json')
 promoted=(promotion.get('passed') is True
           and promotion.get('qualification_sha256')==ai.digest(transport_gate)
           and promotion.get('after_sha256')==transport_cleanup.get('after_transport_sha256')
           and promotion.get('after_sha256')==proof['runtime_source_hashes'].get('prototype/scripts/ai_transport_planner.gd'))
 if final and (not transport_cleanup.get('passed') or not transport_cleanup.get('legacy_exact_parity')
               or len(transport_cleanup.get('linked_results',[]))!=5
               or not all(row.get('passed') for row in transport_cleanup['linked_results']) or not promoted):raise RuntimeError('The revised transport filter and five unchanged linked contracts must match the final promoted source')
 report['transport_reinforcement_cleanup']={'private_qualification_passed':transport_cleanup.get('passed'),
  'legacy_exact_parity':transport_cleanup.get('legacy_exact_parity'),
  'final_source_matches_qualified_filter':promoted,
  'unchanged_linked_contracts_passed':sum(row.get('passed') is True for row in transport_cleanup.get('linked_results',[])),
  'before':{key:before_transport.get(key) for key in ['tick','wave_landing_ticks','accepted_types','reboarded_arrived_troops']},
  'after':{key:after_transport.get(key) for key in ['tick','wave_landing_ticks','accepted_types','reboarded_arrived_troops']},
  'promotion':promotion,'evidence':ref(transport_gate),
  'scope':'Revised target-land filter qualified on R19 after rejecting the unknown-goal regression. Two exact-source before cases reused, two revised after cases and five unchanged linked contracts passed. All final selected-package scenarios and unseen cohorts follow promotion; this is separate from parameter tuning.'}
if final and not transport_cleanup:raise RuntimeError('Revised transport qualification missing')
transport=last_json(Q/'champion-transport-two-waves.stdout.log')
if final and (not transport.get('passed') or not transport.get('process_passed') or transport.get('release_artifacts')!=proof['artifacts'] or transport.get('reboarded_arrived_troops')!=0):raise RuntimeError('Exact-champion two-wave transport component not verified')
if final and (transport.get('cases')!=3 or set(transport.get('checkpoint_continuations',{}))!={'boarding','transit'} or not all(row.get('passed') is True and row.get('exact_final_world_commands_ai') is True for row in transport.get('checkpoint_continuations',{}).values())):raise RuntimeError('Final champion must preserve both transport waves after boarding and loaded-transit checkpoints')
if transport:report['final_transport_component']=transport
team_economy=last_json(Q/'champion-team-economy.stdout.log')
if final and (not team_economy.get('passed') or team_economy.get('cases')!=6
              or not team_economy.get('process_passed') or team_economy.get('release_artifacts')!=proof['artifacts']
              or team_economy.get('probe_sha256')!=ai.digest(ROOT/'tools/qa/ai_team_economy_runtime.gd')):raise RuntimeError('Allied paid repair and completed trade must match the final source/native in2v2/4v4 live/save/replay')
if team_economy:report['final_team_economy_component']=team_economy
combat=last_json(Q/'champion-runtime-combat-standard.stdout.log')
if combat:
 if final and (combat.get('cases')!=48 or not combat.get('process_passed') or not combat.get('actual_parameters_verified') or combat.get('release_artifacts')!=proof['artifacts']):raise RuntimeError('Final-policy standard controlled combat not verified')
 report['final_standard_combat']=combat
if final and not combat:raise RuntimeError('Final standard-difficulty controlled combat48 missing')
roles=last_json(Q/'champion-runtime-role-combat.stdout.log')
if roles:
 if final and (roles.get('cases')!=4 or not roles.get('role_fixtures') or not roles.get('process_passed') or not roles.get('actual_parameters_verified') or roles.get('release_artifacts')!=proof['artifacts'] or not all(roles.get('results',{}).get('functional_roles_observed',{}).values()) or set(roles.get('results',{}).get('functional_roles_observed',{}))!={'melee_screen','priest_protection'}):raise RuntimeError('Final-policy mixed role integration not verified')
 report['final_standard_roles']=roles
if final and not roles:raise RuntimeError('Final mixed-role functional component checks missing')
saves=last_json(Q/'champion-save-resume-explicit.stdout.log')
if final and (not saves.get('passed') or saves.get('cases')!=2 or not saves.get('all_processes_passed') or saves.get('release_artifacts')!=proof['artifacts'] or saves.get('pending',{}).get('details',{}).get('recorded_commands',0)<1):raise RuntimeError('Explicit competitive combat and pending-plan saves must match the final champion')
if saves:report['explicit_competitive_save_resume']=saves
early=read(Q/'champion_early_opening_diversity.json')
early_release={'release_executable':proof['artifacts']['Rise of Rome Prototype.exe'],'release_package':proof['artifacts']['Rise of Rome Prototype.pck'],'native':proof['artifacts']['bin/ror_pathfinding.windows.template_release.x86_64.dll']}
if final and (not early.get('passed') or early.get('reports')!=40 or early.get('ticks_per_case')!=400 or early.get('release')!=early_release or early.get('policy_sha256')!=ai.digest(Q/'champion.policy.json') or len(early.get('exact_input_repeats',[]))!=2 or not all(r.get('passed') for r in early.get('exact_input_repeats',[]))):raise RuntimeError('Forty actual early dev decisions and two exact-input repeats are required on the final champion')
if early:
 report['early_decision_diversity']={key:value for key,value in early.items() if key not in ['records','exact_input_repeats']}
 report['early_decision_diversity']['exact_input_repeats_passed']=sum(r.get('passed') is True for r in early.get('exact_input_repeats',[]))
 report['early_decision_diversity']['evidence']=ref(Q/'champion_early_opening_diversity.json')
release_packages={ai.digest(app.with_suffix('.pck'))}
current=read(Q/'current_release.json')
if current:release_packages.add(ai.digest(Path(current['pack'])))
for path in sorted((Q/'evaluation').glob('*/state.json')):
 row=read(path)
 if row.get('release',{}).get('package') not in release_packages:continue
 report['evaluation'].append({'evidence':ref(path),'release':row['release'],'complete':row.get('evaluation_complete',False),'timeout_model':read(path.parent/'timeout_model.json'),'steps':{key:value['result'] for key,value in row.get('steps',{}).items()}})
expected_final_release={'executable':proof['artifacts']['Rise of Rome Prototype.exe'],'package':proof['artifacts']['Rise of Rome Prototype.pck'],'native':proof['artifacts']['bin/ror_pathfinding.windows.template_release.x86_64.dll']}
if final and not any(final_evaluation_matches_release(r,expected_final_release) for r in report['evaluation']):raise RuntimeError('Final128+64 arena or exact champion calibration not completed')
if final:
 final_evaluation=next(r for r in report['evaluation'] if final_evaluation_matches_release(r,expected_final_release))
 selected_policy=read(Q/'champion.policy.json')
 report['full_game_metrics']={}
 for step,count in [('holdout128',128),('challenge64',64)]:
  directory=ROOT/final_evaluation['steps'][step]['directory']
  if not directory.resolve().is_relative_to((Q/'arena').resolve()):raise RuntimeError('Final gameplay evidence must remain in the local arena directory')
  measured=gameplay_series(directory,expected_final_release,count,'competitive_v2',selected_policy)
  report['full_game_metrics'][step]={key:value for key,value in measured.items() if key!='per_game'}
perf=last_json(Q/'champion-performance26.stdout.log')
if perf:
 directory=Path(perf['directory']);s=read(directory/'summary.json')
 if final and not performance_matches_release(read(directory/'manifest.json'),s,expected_final_release):raise RuntimeError('Performance reports must use the exact final native Release')
 report['performance']={k:v for k,v in s.items() if k!='reports_detail'}
 report['performance']['evidence']=ref(directory/'summary.json')
 report['performance']['cases']=[]
 for row in s.get('reports_detail',[]):
  report['performance']['cases'].append({'case':row['case'],'passed':row['passed'],'world_hash':row['world_hash'],'ai_state_hash':row['ai_state_hash'],'workload':row.get('workload'),'workload_events':row.get('workload_events'),'phases':[{'phase':phase['phase'],'metrics':phase['profile'].get('metrics_microseconds',{})} for phase in row['phases']]})
if final and (report['performance'].get('reports')!=26 or not report['performance'].get('all_equal') or not report['performance'].get('all_processes_passed')):raise RuntimeError('Formal performance incomplete or invalid')
for algorithm in ['legacy_adaptive_v1','competitive_v2']:
 path=Q/('champion-rendered-load-'+algorithm)/'report.json';row=read(path)
 if row.get('passed'):
  receipt=read(path.parent/'verified-artifacts.json')
  matched={k:v.lower() for k,v in receipt.get('artifacts',{}).items()}==proof['artifacts']
  workload=row.get('rendered_load',{})
  if final and (not row.get('release') or not matched or workload.get('algorithm_versions')!=[algorithm] or workload.get('owner_started_samples',0)<1):raise RuntimeError('Rendered load proof must use the exact final Release and ordinary simulation owner')
  report['rendered_performance'][algorithm]={k:v for k,v in workload.items() if k!='screenshot'}
  report['rendered_performance'][algorithm]['evidence']=ref(path)
  report['rendered_performance'][algorithm]['artifact_identity_verified']=matched
 if final and algorithm not in report['rendered_performance']:raise RuntimeError('Both actual rendered workloads are required')
for index in range(7):
 path=Q/('champion-full-soak-'+str(index)+'.stdout.log');s=last_json(path)
 if not s:continue
 directory=Path(s['directory']);episodes=[]
 for row_path in sorted(directory.glob('*.json')):
  row=read(row_path)
  if row.get('status') not in ('WIN','LOSS','DRAW_TIME_LIMIT') or 'tick' not in row:continue
  process=read(row_path.with_suffix('.process.json'))
  episodes.append({'case':row['case_id'],'status':row['status'],'ticks':row['tick'],'seconds':process.get('seconds'),'process_passed':process.get('passed'),'process_metrics':process.get('process_metrics',{})})
 report['soaks'].append({'scenario':index,'summary':s,'episodes':episodes,'ticks':sum(row['ticks'] for row in episodes),'max_continuous_ticks':max((row['ticks'] for row in episodes),default=0),'evidence':ref(directory/'summary.json')})
if final and (len(report['soaks'])!=7 or any(row['max_continuous_ticks']<72000 or not row['summary'].get('continuous_full_hour') or not row['summary']['all_processes_passed'] for row in report['soaks'])):raise RuntimeError('Full-hour scenarios incomplete')
for label in ['land','islands','render-land','render-islands']:
 for prefix in ['champion-release-','defense-core-release-','micro-core-release-']:
  path=Q/(prefix+label)/'report.json';r=read(path)
  receipt=read(path.parent/'verified-artifacts.json')
  matched={k:v.lower() for k,v in receipt.get('artifacts',{}).items()}==proof['artifacts']
  if r.get('passed') and r.get('release') and (matched or not final):
   # Keep schema-independent proof; full report contains machine paths.
   report['packaged_checks'][label]={'passed':True,'artifact_identity_verified':matched,'evidence':ref(path),'algorithm_version':r.get('algorithm_version'),'activated_policy_parameters':r.get('activated_policy_parameters'),'render_wait_ms':{stage['stage']:stage.get('render_wait_ms') for stage in r.get('stages',[])}};break
 if final and label not in report['packaged_checks']:raise RuntimeError('Actual EXE scenario incomplete')
output=args.output.resolve();ai.atomic(output,report)
print(json.dumps({'output':str(output),'status':report['status'],'games':[(r['complete'],list(r['steps'])) for r in report['evaluation']],'controls':list(report['controlled_openings'])}),flush=True)
