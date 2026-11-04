import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import sys
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("ai_competitive", Path(__file__).resolve().parents[1]/"ai_competitive.py")
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
ai = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ai)

class EvidenceTests(unittest.TestCase):
    def test_shipping_strategy_sampling_rejects_stale_or_partial_evidence(self):
        import copy
        from ai_acceptance_checks import strategy_sampling_matches_release
        proof={'runtime_source_hashes':{'sampler':'v2'},'artifacts':{'exe':'final','package':'final','native':'final'}}
        sample={'version':2,'capacity':4096,'observed_distinct_inputs':150,'retained':150,'duplicates_skipped':4000,'thinning_stride':1,'first_decision_tick':0,'last_decision_tick':11920}
        rows=[{'name':name,'case':'dev-004-'+name,'status':'DRAW_TIME_LIMIT','tick':12000,'sampling':copy.deepcopy(sample),'process':{'passed':True,'exit_code':0,'timeout':False,'engine_errors':[]}} for name in ('seat1','seat2')]
        valid={'passed':True,'source':proof['runtime_source_hashes'],'artifacts':proof['artifacts'],'records':rows}
        self.assertTrue(strategy_sampling_matches_release(valid,proof))
        bad=copy.deepcopy(valid);bad['source']={'sampler':'old'}
        self.assertFalse(strategy_sampling_matches_release(bad,proof))
        bad=copy.deepcopy(valid);bad['artifacts']['native']='old'
        self.assertFalse(strategy_sampling_matches_release(bad,proof))
        bad=copy.deepcopy(valid);bad['records']=bad['records'][:1]
        self.assertFalse(strategy_sampling_matches_release(bad,proof))
        for field,value in [('version',1),('retained',4097),('retained',0),('observed_distinct_inputs',100),('duplicates_skipped',-1),('last_decision_tick',7300),('last_decision_tick',True)]:
            bad=copy.deepcopy(valid);bad['records'][0]['sampling'][field]=value
            self.assertFalse(strategy_sampling_matches_release(bad,proof),(field,value))
        bad=copy.deepcopy(valid);bad['records'][0]['process']['passed']=False
        self.assertFalse(strategy_sampling_matches_release(bad,proof))
        bad=copy.deepcopy(valid);bad['records'][0]['process']['exit_code']=False
        self.assertFalse(strategy_sampling_matches_release(bad,proof))
        bad=copy.deepcopy(valid);bad['records'][1]=copy.deepcopy(bad['records'][0])
        self.assertFalse(strategy_sampling_matches_release(bad,proof))

    def test_seed_block_statistics_ignore_completion_order(self):
        import random
        rows=[]
        for index in range(40):
            status='WIN' if index<12 else 'DRAW_TIME_LIMIT' if index<28 else 'LOSS'
            for seat in (1,2):rows.append({'base_id':f'b{index:03}','case_id':f'b{index:03}-seat{seat}','status':status,'opponent':str(index%3)})
        expected=ai.summarize(rows)
        self.assertEqual(expected['statistics_schema'],2)
        for seed in range(16):
            shuffled=rows.copy();random.Random(seed).shuffle(shuffled)
            self.assertEqual(ai.summarize(shuffled),expected)

    def gameplay_fixture(self, case_id='one', team=2):
        measured={'worker_ticks':100,'idle_worker_ticks':10,'tc_ticks':100,'tc_idle_ticks':30,
                  'producer_ticks':100,'population_blocked_ticks':2,'commands':100,'rejected':{'no_path':3},
                  'deposited':[10,20,0,0],'stock_integral':[100,0,0,0],
                  'lost_value':100.0,'killed_value':200.0,'converted_value':50.0}
        return {'case_id':case_id,'series':'series','status':'DRAW_TIME_LIMIT','tick':100,'subject_team':team,
                'measured':{str(team):measured,str(3-team):{**measured,'commands':10000}},
                'players':[{'team':team,'metrics':{'commands_accepted':5,'commands_rejected':3,'decisions':20}},
                           {'team':3-team,'metrics':{'commands_accepted':10000,'commands_rejected':0,'decisions':20}}]}

    def test_gameplay_metrics_use_authoritative_subject_and_weight_durations(self):
        import ai_gameplay_metrics as gameplay
        first=self.gameplay_fixture()
        second=self.gameplay_fixture('two',1)
        data=second['measured']['1']
        data.update(worker_ticks=900,idle_worker_ticks=0,tc_ticks=900,tc_idle_ticks=0,
                    producer_ticks=900,population_blocked_ticks=0,commands=900,rejected={'no_path':7},
                    stock_integral=[900,0,0,0],lost_value=0,killed_value=0,converted_value=0)
        result=gameplay.aggregate([first,second])
        self.assertEqual(result['commands']['accepted'],1000)
        self.assertEqual(result['policy_feedback']['accepted'],10)
        self.assertEqual(result['commands']['reasons'],{'no_path':10})
        self.assertAlmostEqual(result['commands']['raw_rejection_ratio'],10/1010)
        self.assertAlmostEqual(result['unconditional_idle']['worker_ratio'],.01)
        self.assertAlmostEqual(result['housing']['ratio'],.002)
        self.assertEqual(result['resources']['mean_stock'],[5,0,0,0])
        self.assertEqual(result['combat_value']['direct_death_exchange'],2)
        self.assertEqual(result['combat_value']['converted'],50)
        self.assertEqual(result['commands']['race_exclusions'],[])
        self.assertEqual(gameplay.aggregate([second,first]),result)

    def test_gameplay_metrics_reject_wrong_owner_and_impossible_counters(self):
        import ai_gameplay_metrics as gameplay
        import copy
        good=self.gameplay_fixture()
        with self.assertRaises(ValueError):gameplay.aggregate([good,good])
        with self.assertRaises(ValueError):gameplay.aggregate([])
        other=copy.deepcopy(good);other['series']='another'
        with self.assertRaises(ValueError):gameplay.aggregate([good,other])
        for field,value in [('idle_worker_ticks',101),('commands',True),('lost_value',float('nan')),
                            ('rejected',{'no_path':-1})]:
            row=copy.deepcopy(good);row['measured']['2'][field]=value
            with self.assertRaises(ValueError):gameplay.aggregate([row])
        row=copy.deepcopy(good);del row['measured']['2']
        with self.assertRaises(ValueError):gameplay.aggregate([row])
        row=copy.deepcopy(good);row['players'].pop(0)
        with self.assertRaises(ValueError):gameplay.aggregate([row])

    def test_gameplay_metrics_require_full_horizon_exact_release_and_policy(self):
        import ai_gameplay_metrics as gameplay
        release={'executable':'exe','package':'pack','native':'dll'}
        with tempfile.TemporaryDirectory(dir=ai.TEMP) as folder:
            directory=Path(folder)
            manifest={'series':'series','source':{'release_executable':'exe','release_package':'pack','native':'dll'},
                      'subject':'competitive_v2','overrides':{},'diagnostic_tick_limit':None}
            case={'case_id':'one','series':'series','maximum_ticks':36000}
            case['fingerprint']=ai.fingerprint(case)
            row=self.gameplay_fixture();row.update(tick=36000,wall_seconds=10,
                fingerprint=case['fingerprint'],runtime={'release':True,'native':True})
            process={'fingerprint':case['fingerprint'],'passed':True,'seconds':11,
                     'process_metrics':{'available':True,'cpu_seconds':10,'peak_private_bytes':1000}}
            summary={'series':'series','reports':1,'errors':0,'counts':{'DRAW_TIME_LIMIT':1}}
            for name,value in [('series.json',manifest),('summary.json',summary),('one.input.json',case),('one.json',row),('one.process.json',process)]:
                ai.atomic(directory/name,value)
            result=gameplay.qualified_series(directory,release,1,'competitive_v2',{})
            self.assertEqual(result['commands']['accepted'],100)
            with self.assertRaises(ValueError):gameplay.qualified_series(directory,release,2)
            with self.assertRaises(ValueError):gameplay.qualified_series(directory,{**release,'package':'old'},1)
            with self.assertRaises(ValueError):gameplay.qualified_series(directory,release,1,'baseline_v1')
            with self.assertRaises(ValueError):gameplay.qualified_series(directory,release,1,overrides={'attack_ratio':2})
            row['tick']=400;ai.atomic(directory/'one.json',row)
            with self.assertRaises(ValueError):gameplay.qualified_series(directory,release,1)
            row['tick']=36000;row['series']='other';ai.atomic(directory/'one.json',row)
            with self.assertRaises(ValueError):gameplay.qualified_series(directory,release,1)
            row['series']='series';case['maximum_ticks']=400
            case['fingerprint']=ai.fingerprint({k:v for k,v in case.items() if k!='fingerprint'})
            row.update(tick=400,fingerprint=case['fingerprint']);process['fingerprint']=case['fingerprint']
            for name,value in [('one.input.json',case),('one.json',row),('one.process.json',process)]:ai.atomic(directory/name,value)
            with self.assertRaises(ValueError):gameplay.qualified_series(directory,release,1)

    def test_parallel_tuning_keeps_one_global_game_limit(self):
        import ai_tune as tuning
        import threading,time
        lock=threading.Lock();barrier=threading.Barrier(3);counts={'active':0,'peak':0,'calls':0}
        def process(*args,**kwargs):
            with lock:
                counts['active']+=1;counts['calls']+=1;number=counts['calls']
                counts['peak']=max(counts['peak'],counts['active'])
            try:
                if number<=3:barrier.wait(5)
                time.sleep(.002)
                return {'passed':True}
            finally:
                with lock:counts['active']-=1
        def arena(*args,**kwargs):
            tuning.ai.run_process('first');tuning.ai.run_process('second')
            return {'errors':0,'score':.5,'directory':'synthetic'}
        candidates=[{'id':f'g0-c{i}','parameters':{'x':i},'status':'pending'} for i in range(8)]
        with tempfile.TemporaryDirectory(dir=ai.TEMP) as folder:
            with patch.object(tuning,'DIRECTORY',Path(folder)),patch.object(tuning.ai,'run_process',side_effect=process) as original,patch.object(tuning.ai,'arena',side_effect=arena):
                result=tuning.evaluate_generation(candidates,3,{'candidates':candidates})
                self.assertIs(tuning.ai.run_process,original)
        self.assertEqual(counts,{'active':0,'peak':3,'calls':16})
        self.assertEqual(len(result),8)
        self.assertTrue(all(c['status']=='evaluated' for c in result))

    def test_parallel_tuning_restores_process_runner_after_candidate_error(self):
        import ai_tune as tuning
        candidates=[{'id':'g0-c0','parameters':{},'status':'pending'}]
        with tempfile.TemporaryDirectory(dir=ai.TEMP) as folder:
            with patch.object(tuning,'DIRECTORY',Path(folder)),patch.object(tuning.ai,'arena',side_effect=RuntimeError('injected candidate error')):
                original=tuning.ai.run_process
                with self.assertRaises(RuntimeError):tuning.evaluate_generation(candidates,2,{'candidates':candidates})
                self.assertIs(tuning.ai.run_process,original)
                with self.assertRaises(ValueError):tuning.evaluate_generation(candidates,0,{'candidates':candidates})

    def test_conditional_idle_preserves_unknown_workers_and_requires_purity(self):
        import ai_openings as openings
        row={'observer_purity':{'passed':True,'checks':3},'final_world_hash':'a'*64,
             'work_availability':{'2':{'worker_ticks':100,'available_ticks':80,'idle_available_ticks':4,
                 'unknown_ticks':20,'idle_unknown_ticks':10,'conditional_idle_lower_bound':4/90,
                 'conditional_idle_upper_bound':14/90,'confirmed_worker_time_coverage':.8}}}
        self.assertTrue(openings.work_measurement_valid(row))
        row['work_availability']['2']['conditional_idle_upper_bound']=.05
        self.assertFalse(openings.work_measurement_valid(row))
        row['work_availability']['2']['conditional_idle_upper_bound']=14/90
        row['observer_purity']['passed']=False
        self.assertFalse(openings.work_measurement_valid(row))
        import copy
        row['observer_purity']['passed']=True
        matrix=[{'algorithm':algorithm,'civilization':civ,'observer_purity':copy.deepcopy(row['observer_purity']),
                 'measurement':copy.deepcopy(row['work_availability']['2']),'final_world_hash':row['final_world_hash']}
                for algorithm in ('baseline_v1','competitive_v2') for civ in range(1,17)]
        self.assertTrue(openings.work_matrix_valid(matrix))
        self.assertFalse(openings.work_matrix_valid(matrix[:-1]))
        matrix[-1]=matrix[0]
        self.assertFalse(openings.work_matrix_valid(matrix))

    def test_tuning_generations_refine_dev_winner_and_resume_without_validation_leak(self):
        import copy
        import ai_tune as tuning
        with tempfile.TemporaryDirectory(dir=ai.TEMP) as folder:
            directory=Path(folder)
            with patch.object(tuning,'DIRECTORY',directory),patch.object(tuning,'experiment_source',return_value={'test':'source'}):
                manifest=tuning.prepare()
                for candidate in manifest['candidates'][:8]:
                    candidate.update(status='evaluated',result={'score':.1,'errors':[]},validation={'score':1.0})
                manifest['candidates'][2].update(result={'score':.8,'errors':[]},validation={'score':0})
                original=copy.deepcopy(manifest['candidates'][8:16])
                tuning.adapt_generation(manifest,1,8)
                self.assertEqual(manifest['adaptive_generations']['1']['parent'],'g0-c2')
                self.assertEqual([c['parameters'] for c in manifest['candidates'][8:12]],[c['parameters'] for c in original[:4]])
                self.assertTrue(all(c.get('parameter_origin',{}).get('parent')=='g0-c2' for c in manifest['candidates'][12:16]))
                for candidate in manifest['candidates'][12:16]:
                    for key,(low,high) in tuning.RANGES.items():self.assertTrue(low<=candidate['parameters'][key]<=high)
                frozen=copy.deepcopy(manifest['candidates'][8:16])
                manifest['candidates'][2]['result']['score']=0
                manifest['candidates'][3]['result']['score']=1
                resumed=tuning.prepare()
                tuning.adapt_generation(resumed,1,8)
                self.assertEqual(resumed['candidates'][8:16],frozen)

    def test_learner_throughput_uses_full_counters_and_rejects_mixed_or_short_series(self):
        import ai_learner_throughput as throughput
        release={'executable':'e','package':'p','native':'n'}
        with tempfile.TemporaryDirectory(dir=ai.TEMP) as folder:
            root=Path(folder)
            manifest={'series':'s','diagnostic_tick_limit':None,'source':{'release_executable':'e','release_package':'p','native':'n'}}
            ai.atomic(root/'series.json',manifest)
            case={'series':'s'}
            case['fingerprint']=ai.fingerprint(case)
            summary={'series':'s','reports':1,'errors':0,'counts':{'DRAW_TIME_LIMIT':1}}
            ai.atomic(root/'summary.json',summary)
            ai.atomic(root/'dev-000-seat1.input.json',case)
            ai.atomic(root/'dev-000-seat1.json',{'case_id':'dev-000-seat1','fingerprint':case['fingerprint'],'status':'DRAW_TIME_LIMIT',
                'runtime':{'release':True,'native':True},'tick':36000,'wall_seconds':90,
                'players':[{'metrics':{'decisions':200}},{'metrics':{'decisions':100}}],'strategy_trace':[{}]})
            ai.atomic(root/'dev-000-seat1.process.json',{'fingerprint':case['fingerprint'],'passed':True,'seconds':100,
                'process_metrics':{'available':True,'cpu_seconds':80,'peak_private_bytes':1000}})
            result=throughput.summarize([root],release,4)
            self.assertEqual(result['decisions_per_process_second'],3)
            self.assertEqual(result['ticks_per_process_second'],360)
            self.assertEqual(result['parallel_capacity_estimate']['ticks_per_second'],1440)
            with self.assertRaises(ValueError):throughput.summarize([root],{**release,'package':'old'},4)
            with self.assertRaises(ValueError):throughput.summarize([root,root],release,4)
            for broken in [{},{**summary,'reports':2},{**summary,'series':'other'},
                           {**summary,'errors':1},{**summary,'counts':{'WIN':1}}]:
                ai.atomic(root/'summary.json',broken)
                with self.assertRaises(ValueError):throughput.summarize([root],release,4)
            ai.atomic(root/'summary.json',summary)
            ai.atomic(root/'dev-000-seat1.input.json',{**case,'changed_after_freeze':True})
            with self.assertRaises(ValueError):throughput.summarize([root],release,4)
            ai.atomic(root/'dev-000-seat1.input.json',case)
            ai.atomic(root/'series.json',{**manifest,'diagnostic_tick_limit':400})
            with self.assertRaises(ValueError):throughput.summarize([root],release,4)

    def test_final_acceptance_rejects_stale_or_incomplete_suite_boundary(self):
        import copy
        from ai_acceptance_checks import suite_boundary_matches_evidence,final_complete_suite_matches_release
        coverage={'discovered':2,'passed':2,'all_discovered_covered':True,'missing':[],'unresolved_failures':[],
                  'records':[{'script':'a.gd','passed':True},{'script':'b.gd','passed':True}]}
        boundary={'passed':True,'discovered':2,'coverage_sha256':'coverage','suite_stdout_sha256':'stdout'}
        check=lambda:suite_boundary_matches_evidence(coverage,boundary,'coverage','stdout',2)
        self.assertTrue(check())
        boundary['suite_stdout_sha256']='older-run';self.assertFalse(check())
        boundary['suite_stdout_sha256']='stdout';coverage['unresolved_failures']=['b.gd'];self.assertFalse(check())
        coverage['unresolved_failures']=[];coverage['records'][1]['script']='a.gd';self.assertFalse(check())
        proof={'runtime_source_hashes':{'script.gd':'selected'},'artifacts':{'exe':'e','pck':'p','bin/ror_pathfinding.windows.template_release.x86_64.dll':'final-native'}}
        tests={'tests/unit/test_a.gd':'a','tests/unit/test_b.gd':'b','tests/support/base.gd':'support'}
        complete={'passed':True,'inventory':2,'all_test_sources':tests,'source':proof['runtime_source_hashes'],'artifacts':proof['artifacts'],'native_sha256':'final-native'}
        self.assertTrue(final_complete_suite_matches_release(complete,proof,tests,2))
        stale=copy.deepcopy(complete);stale['source']['script.gd']='before-selection'
        self.assertFalse(final_complete_suite_matches_release(stale,proof,tests,2))
        stale=copy.deepcopy(complete);stale['native_sha256']='previous-native'
        self.assertFalse(final_complete_suite_matches_release(stale,proof,tests,2))
        partial=copy.deepcopy(complete);partial['inventory']=1
        self.assertFalse(final_complete_suite_matches_release(partial,proof,tests,2))
        self.assertFalse(final_complete_suite_matches_release(complete,proof,{**tests,'tests/support/base.gd':'edited'},2))

    def test_final_acceptance_rejects_foreign_or_editor_performance(self):
        import copy
        from ai_acceptance_checks import performance_matches_release
        release={'executable':'e','package':'p','native':'n'}
        manifest={'source':{'release_executable':'e','release_package':'p','native':'n'},'quick':False}
        rows=[]
        cases=[(t,s,a,b,False) for t in (2,4,8) for s in (96,192) for a in ('baseline_v1','competitive_v2') for b in (False,True)]
        cases.extend((8,192,a,True,True) for a in ('baseline_v1','competitive_v2'))
        for teams,side,algorithm,threaded,stress in cases:
            rows.append({'passed':True,'runtime':{'release':True},'native':True,'tick':100,'workload_passed':True,
                'case':dict(teams=teams,side=side,algorithm=algorithm,threaded=threaded,all_active=stress,units_per_team=500,ticks=100,cold_ticks=20),
                'workload':dict(gatherers=0 if stress else teams*100,marchers=teams*(484 if stress else 100),combatants=teams*16,idle=0 if stress else teams*284,moved_marchers=teams*50),
                'workload_events':dict(attack=10,damage=8,resource_gathered=0 if stress else 10),'world_hash':'w','ai_state_hash':'a'})
        summary={'reports':26,'all_equal':True,'all_processes_passed':True,'reports_detail':rows}
        self.assertTrue(performance_matches_release(manifest,summary,release))
        self.assertFalse(performance_matches_release(manifest,summary,{**release,'package':'old'}))
        rows[0]['runtime']['release']=False
        self.assertFalse(performance_matches_release(manifest,summary,release))
        rows[0]['runtime']['release']=True
        original=copy.deepcopy(rows)
        for field,value in [('workload_events',{'attack':0,'damage':0,'resource_gathered':10}),
                            ('workload',{}),('tick',99),('world_hash','different-sequential-state')]:
            rows[0][field]=value
            self.assertFalse(performance_matches_release(manifest,summary,release),field)
            rows[:]=copy.deepcopy(original)
        rows[1]=copy.deepcopy(rows[0])
        self.assertFalse(performance_matches_release(manifest,summary,release),'Duplicate configuration cannot replace the missing threaded case')

    def test_final_acceptance_rejects_earlier_build_or_foreign_calibration(self):
        from ai_acceptance_checks import final_evaluation_matches_release
        release={'executable':'0'*64,'package':'1'*64,'native':'2'*64}
        def step(count):return {'reports':count,'errors':0,'statistics_schema':2,'resampling_order':'sorted_base_id',
                                'paired_blocks':count//2,'counts':{'WIN':count},'score':1,'seed_block_95_percent':[1,1]}
        row={'complete':True,'release':release,'timeout_model':{'source_release':release,'samples':12,'timeout_seconds':300},'steps':{'holdout128':step(128),'challenge64':step(64)}}
        self.assertTrue(final_evaluation_matches_release(row,release))
        row['steps']['holdout128']['paired_blocks']=63
        self.assertFalse(final_evaluation_matches_release(row,release))
        row['steps']['holdout128']['paired_blocks']=64
        row['steps']['holdout128']['statistics_schema']=1
        self.assertFalse(final_evaluation_matches_release(row,release))
        row['steps']['holdout128']['statistics_schema']=2
        self.assertFalse(final_evaluation_matches_release(row,{**release,'package':'3'*64}))
        row['timeout_model']={**row['timeout_model'],'source_release':{**release,'native':'4'*64}}
        self.assertFalse(final_evaluation_matches_release(row,release))
        row['timeout_model']={'source_release':release,'samples':12,'timeout_seconds':True}
        self.assertFalse(final_evaluation_matches_release(row,release))

    def test_calibration_ignores_later_smoke_cases_in_reused_directory(self):
        import ai_evaluate_final as evaluation
        with tempfile.TemporaryDirectory(dir=ai.TEMP) as folder:
            root=Path(folder);project=root/'prototype';manifest=project/'data/ai/arena/manifests/smoke.json';manifest.parent.mkdir(parents=True)
            manifest.write_text(json.dumps({'rows':[{'id':f'smoke-{i:03}'} for i in range(12)]}))
            reports=root/'calibration';reports.mkdir()
            for i in range(12):
                for team in (1,2):
                    case=f'smoke-{i:03}-p{team}'
                    (reports/(case+'.json')).write_text(json.dumps({'case_id':case,'base_id':f'smoke-{i:03}','subject_team':team,'status':'DRAW_TIME_LIMIT','wall_seconds':10+i*2+team-1 if i<6 else 1000}))
            with patch.object(evaluation.ai,'ROOT',root),patch.object(evaluation.ai,'PROJECT',project):
                model=evaluation.calibration_model({'reports':12,'directory':'calibration'},2,{'package':'test'})
            self.assertEqual(model['samples'],12)
            self.assertEqual(model['p95_seconds'],21)
            self.assertEqual(model['timeout_seconds'],300)
            self.assertEqual(model['source_release'],{'package':'test'})

    def test_final_release_calibrates_before_holdout(self):
        import argparse
        import ai_evaluate_final as evaluation
        with tempfile.TemporaryDirectory(dir=ai.TEMP) as folder:
            root=Path(folder);project=root/'prototype';manifest=project/'data/ai/arena/manifests/smoke.json';manifest.parent.mkdir(parents=True)
            manifest.write_text(json.dumps({'rows':[{'id':f'smoke-{i:03}'} for i in range(12)]}))
            champion=root/'champion.json';champion.write_text('{}');calls=[]
            def arena(suite,subject,jobs,limit,**kwargs):
                calls.append((suite,subject,limit,evaluation.ai.ARENA_TIMEOUT_SECONDS))
                if suite=='smoke':
                    reports=root/'calibration';reports.mkdir()
                    for i in range(6):
                        for team in (1,2):
                            case=f'smoke-{i:03}-p{team}'
                            (reports/(case+'.json')).write_text(json.dumps({'case_id':case,'base_id':f'smoke-{i:03}','subject_team':team,'status':'DRAW_TIME_LIMIT','wall_seconds':10+i*2+team-1}))
                    return {'reports':12,'directory':'calibration','errors':[]}
                return {'reports':128 if suite=='holdout' else 64,'errors':[]}
            args=argparse.Namespace(engine=root/'final.exe',pack=root/'final.pck',jobs=2,phase='final',champion=champion,tuning_generations=3)
            with patch.object(evaluation.ai,'ROOT',root),patch.object(evaluation.ai,'PROJECT',project),patch.object(evaluation.ai,'QA',root/'qa'),patch.object(evaluation.ai,'ARENA_TIMEOUT_SECONDS',3600),patch.object(evaluation.ai,'arena',side_effect=arena),patch.object(evaluation,'pin_release',return_value={'executable':'e','package':'p','native':'n'}):
                evaluation.run(args)
            self.assertEqual([call[0] for call in calls],['smoke','holdout','challenge_holdout'])
            self.assertEqual(calls[0][1:3],('baseline_v1',6))
            self.assertEqual([call[3] for call in calls[1:]],[300,300])

    def role_rows(self):
        rows=[]
        for scenario in range(2):
            for micro in (False,True):
                own=[{'team':1,'hp':0.0} for _ in range(8)]
                enemy=[{'team':2,'hp':0.0} for _ in range(8)]
                if micro and scenario==0:
                    enemy[0]={'team':1,'hp':10.0}
                else:
                    enemy[0]['hp']=10.0
                    if micro:own[0]['hp']=10.0
                rows.append({'split':'fit','scenario':scenario,'micro':micro,'ticks':1200,
                             'own_value':1000,'enemy_value':1000,'own_lost':100 if scenario==0 else 900,
                             'enemy_lost':200 if scenario==0 else 100,'rejected':0,
                             'terminal_roster':{'own_initial':own,'enemy_initial':enemy},
                             'accepted_role_orders':{'screen_ranged_support':1,'protect_priest':2} if micro else {}})
        return rows

    def test_role_battle_outcome_uses_current_ownership(self):
        import ai_combat_acceptance as combat
        result=combat.summarize_roles(self.role_rows())
        cases=[row for row in result['cases'] if row['micro']]
        self.assertEqual(cases[0]['outcome'],'WIN')
        self.assertEqual(cases[1]['outcome'],'DRAW_TIME_LIMIT')
        self.assertAlmostEqual(result['micro_exchange'],.3)
        self.assertTrue(all(result['functional_roles_observed'].values()))

    def test_role_battle_summary_rejects_duplicate_or_missing_terminal_data(self):
        import ai_combat_acceptance as combat
        rows=self.role_rows();rows[-1]=dict(rows[0])
        with self.assertRaises(ValueError):combat.summarize_roles(rows)
        rows=self.role_rows();rows[0].pop('terminal_roster')
        with self.assertRaises(ValueError):combat.summarize_roles(rows)

    def test_component_runtime_rejects_modified_frozen_source(self):
        import ai_combat_acceptance as combat
        with tempfile.TemporaryDirectory(dir=ai.TEMP) as folder:
            project=Path(folder)
            script=project/'scripts/ai_micro_controller.gd';script.parent.mkdir()
            script.write_text('extends RefCounted\n',encoding='utf-8')
            source={'prototype/scripts/ai_micro_controller.gd':ai.digest(script)}
            combat.validate_project_sources(project,source)
            script.write_text('extends RefCounted\n# changed\n',encoding='utf-8')
            with self.assertRaises(ValueError):combat.validate_project_sources(project,source)

    def test_suite_footer_does_not_override_a_later_real_rerun(self):
        import datetime
        import os
        import ai_suite_coverage as coverage
        with tempfile.TemporaryDirectory(dir=ai.TEMP) as folder:
            root=Path(folder);project=root/'prototype'
            test=project/'tests/unit/test_example.gd';test.parent.mkdir(parents=True)
            test.write_text('extends SceneTree\n',encoding='utf-8')
            log=root/'suite.log'
            log.write_text('[2026-10-31 03:00:00] test-suite: FAILED tests/unit/test_example.gd\n'
                           '[2026-10-31 05:00:00] godot-summary: ERROR: FAILED tests/unit/test_example.gd\n',encoding='utf-8')
            evidence=root/'rerun.log';evidence.write_text('passed\n',encoding='utf-8')
            stamp=datetime.datetime(2026,10,31,4).timestamp();os.utime(evidence,(stamp,stamp))
            reruns=root/'reruns.json'
            reruns.write_text(json.dumps([{'script':'tests/unit/test_example.gd','passed':True,'log':'rerun.log'}]),encoding='utf-8')
            with patch.object(coverage.ai,'ROOT',root),patch.object(coverage.ai,'PROJECT',project):
                self.assertTrue(coverage.audit([log],reruns,root/'coverage.json'))
            report=json.loads((root/'coverage.json').read_text())
            self.assertEqual(report['passed'],1)
            self.assertEqual(len(report['historical_failed_events']),1)

    def combat_rows(self):
        rows=[]
        for split in ('fit','heldout'):
            for index in range(12):
                for micro in (False,True):
                    rows.append({'split':split,'scenario':index,'micro':micro,'kinds':['a','b'],'own_value':1000,'enemy_value':1000,
                        'own_lost':1 if index<6 else 100,'enemy_lost':(4 if micro else 2) if index<6 else 50,
                        'sign_correct':not micro,'horizon_mean_abs_retained_hp_error':.2,'issued':10 if micro else 0,'rejected':0})
        return rows

    def test_controlled_combat_aggregates_resource_losses_instead_of_case_ratios(self):
        import ai_combat_acceptance as combat
        result=combat.summarize(self.combat_rows())['heldout']
        self.assertAlmostEqual(result['micro_exchange_ratio'],324/312)
        self.assertEqual(result['forecast_sign_accuracy'],1)
        self.assertEqual(result['issued'],120)

    def test_controlled_forecast_shows_close_battles_instead_of_hiding_them(self):
        import ai_combat_acceptance as combat
        rows=self.combat_rows()
        for row in rows:
            if row['split']=='heldout' and row['scenario']==0 and not row['micro']:
                row.update(own_lost=600,enemy_lost=0,sign_correct=False)
        result=combat.summarize(rows)['heldout']
        self.assertEqual(result['close_battles'],11)
        self.assertEqual(result['decisive_battles'],1)
        self.assertEqual(result['forecast_sign_accuracy_close'],1)
        self.assertEqual(result['forecast_sign_accuracy_outside_close'],0)
        self.assertAlmostEqual(result['forecast_sign_accuracy'],11/12)

    def test_controlled_combat_rejects_duplicate_missing_or_unequal_forces(self):
        import ai_combat_acceptance as combat
        rows=self.combat_rows();rows[-1]=dict(rows[0])
        with self.assertRaises(ValueError):combat.summarize(rows)
        rows=self.combat_rows();rows[0]['enemy_value']=999
        with self.assertRaises(ValueError):combat.summarize(rows)

    def test_fingerprint_is_order_independent(self):
        self.assertEqual(ai.fingerprint({"b":2,"a":1}), ai.fingerprint({"a":1,"b":2}))

    def test_atomic_replaces_only_complete_json(self):
        with tempfile.TemporaryDirectory(dir=ai.TEMP) as folder:
            path=Path(folder)/"state.json"
            ai.atomic(path,{"step":1})
            path.with_suffix(".json.pending").write_text('{"partial":',encoding="utf-8")
            self.assertEqual(json.loads(path.read_text()),{"step":1})
            ai.atomic(path,{"step":2})
            self.assertEqual(json.loads(path.read_text()),{"step":2})

    def test_preflight_reads_format_versions_and_preserves_resume_state(self):
        with tempfile.TemporaryDirectory(dir=ai.TEMP) as folder:
            root=Path(folder); state=root/"state.json"; ai.atomic(state,{"active_task":"AI00-01"})
            hardware=ai.platform.uname()
            with patch.object(ai,"QA",root/"qa"),patch.object(ai,"TEMP",root/"temp"),patch.object(ai,"STATE",state),patch.object(ai,"source_hashes",return_value={}),patch.object(ai.platform,"uname",return_value=hardware),patch.object(ai.subprocess,"check_output",return_value=b""):
                ai.preflight()
                manifest=root/"qa/initial_manifest.json"; preserved=manifest.read_bytes()
                self.assertEqual(ai.read_result(manifest)["versions"],{"archive":8,"checkpoint":4,"replay":5})
                ai.atomic(state,{"active_task":"AI03-07"})
                ai.preflight()
                self.assertEqual(manifest.read_bytes(),preserved)
                self.assertEqual(ai.read_result(state)["active_task"],"AI03-07")

    def test_correlated_seats_form_one_block(self):
        rows=[{"status":"WIN","base_id":"a"},{"status":"LOSS","base_id":"a"},
              {"status":"DRAW_TIME_LIMIT","base_id":"b"},{"status":"DRAW_TIME_LIMIT","base_id":"b"},
              {"status":"CRASH","base_id":"c"}]
        result=ai.summarize(rows)
        self.assertEqual(result["paired_blocks"],2)
        self.assertEqual(result["score"],.5)
        self.assertEqual(result["errors"],1)

    def test_summary_reports_civilization_and_economic_settings_separately(self):
        rows=[{"status":"WIN","base_id":"a","subject_civilization":10,"settings":{"resource_preset_id":"standard","starting_age_id":"stone"}},
              {"status":"LOSS","base_id":"b","subject_civilization":15,"settings":{"resource_preset_id":"high","starting_age_id":"bronze"}}]
        strata=ai.summarize(rows)["strata"]
        self.assertEqual(strata["subject_civilization"]["10"]["score"],1)
        self.assertEqual(strata["subject_civilization"]["15"]["score"],0)
        self.assertEqual(strata["resource_preset_id"]["high"]["reports"],1)
        self.assertEqual(strata["starting_age_id"]["stone"]["reports"],1)

    def test_no_fake_success_without_evidence(self):
        with self.assertRaises(ValueError): ai.update("AI00-04","passed",[],"")
        with self.assertRaises(ValueError): ai.update("NONEXISTENT","passed",[],"")

    def test_resume_reuses_only_matching_success(self):
        with tempfile.TemporaryDirectory(dir=ai.TEMP) as folder:
            with patch.object(ai,"QA",Path(folder)), patch.object(ai,"source_hashes",return_value={"f":"v1"}), patch.object(ai,"event"):
                result={"script":"tests/mock.gd","passed":True,"exit_code":0,"engine_errors":[],"timeout":False}
                with patch.object(ai,"run_process",return_value=result) as run:
                    self.assertTrue(ai.tests(["tests/mock.gd"],1))
                    self.assertTrue(ai.tests(["tests/mock.gd"],1))
                    self.assertEqual(run.call_count,1)
                with patch.object(ai,"source_hashes",return_value={"f":"v2"}),patch.object(ai,"run_process",return_value=dict(result)) as run:
                    self.assertTrue(ai.tests(["tests/mock.gd"],1))
                    self.assertEqual(run.call_count,1)

    def test_ranker_uses_only_owned_complete_dev_demonstrations(self):
        import ai_tune as tuning
        with tempfile.TemporaryDirectory(dir=ai.TEMP) as folder:
            root=Path(folder); owned=root/"owned"; historical=root/"historical"
            owned.mkdir(); historical.mkdir()
            def report(directory,name,base,complete=True):
                row={"case_id":name,"base_id":base,"status":"WIN","series":"s","fingerprint":name,
                     "strategy_trace":[{"tick":40,"facts":{},"selected":"develop","candidates":[{"id":"develop","utility":1}]}]*5}
                ai.atomic(directory/(name+".json"),row)
                if complete: ai.atomic(directory/(name+".process.json"),{"passed":True,"fingerprint":name})
            report(owned,"accepted","dev-001")
            report(owned,"unseen","holdout-001")
            report(owned,"unfinished","dev-002",False)
            report(historical,"old-engine","dev-003")
            with patch.object(tuning,"DIRECTORY",root/"experiment"):
                rows=tuning.dataset([owned])
            self.assertEqual([r["case"] for r in rows],["accepted"])
            self.assertTrue(all(r["split"]=="dev" for r in rows))

    def test_release_provenance_rejects_changed_runtime_sources(self):
        import ai_build_manifest as provenance
        with tempfile.TemporaryDirectory(dir=ai.TEMP) as folder:
            state=Path(folder)/"build.json"
            with patch.object(provenance,"runtime_sources",return_value={"script":"before"}): provenance.begin(state)
            with patch.object(provenance,"runtime_sources",return_value={"script":"after"}):
                with self.assertRaises(RuntimeError): provenance.finish(state,Path(folder))

    def test_package_rejects_artifacts_changed_after_export(self):
        import package_ai_release as packaging
        with tempfile.TemporaryDirectory(dir=ai.TEMP) as folder:
            root=Path(folder); source=root/"source"; source.mkdir()
            (source/"game.pck").write_bytes(b"changed")
            ai.atomic(source/"build-provenance.json",{"runtime_source_hashes":{"s":"h"},"artifacts":{"game.pck":"old-hash"}})
            with self.assertRaises(ValueError): packaging.package(source,root/"package")
            self.assertFalse((root/"package").exists())

    def test_package_zip_checks_manifest_and_exact_extracted_contents(self):
        import contextlib,io
        import package_ai_release as packaging
        with tempfile.TemporaryDirectory(dir=ai.TEMP) as folder:
            root=Path(folder);source=root/'source';destination=root/'package'
            names=[packaging.APPLICATION,'Rise of Rome Prototype.pck',
                   'bin/ror_pathfinding.windows.template_release.x86_64.dll',
                   'legal/MIT/godot-cpp.md','README.md','Rise of Rome.ico']
            for name in names:
                target=source/name;target.parent.mkdir(parents=True,exist_ok=True)
                target.write_bytes(('fixture '+name).encode())
            ai.atomic(source/'build-provenance.json',{'runtime_source_hashes':{'fixture':'source'},
                      'git_revision':'1'*40,'artifacts':{name:ai.digest(source/name) for name in names[:3]}})
            with patch.object(packaging.ai,'ROOT',root),patch.object(packaging.subprocess,'check_output',side_effect=['2'*40,'']),contextlib.redirect_stdout(io.StringIO()) as output:
                packaging.package(source,destination,archive=True)
            unpacked=root/'package-extracted/package'
            manifest=ai.read_result(destination/'ai-release-manifest.json')
            manifest_bytes=(destination/'ai-release-manifest.json').read_bytes()
            expected_sha=ai.digest(destination/'ai-release-manifest.json')
            receipt=json.loads(output.getvalue().splitlines()[0])
            self.assertEqual(receipt['manifest_sha256'],expected_sha)
            self.assertEqual(receipt['zip_sha256'],ai.digest(root/'package.zip'))
            self.assertEqual(receipt['verified_files'],len(manifest['files'])+1)
            self.assertEqual(manifest['git_revision'],'2'*40)
            packaging.verify_extracted_package(unpacked,manifest['files'],expected_sha)
            changed={**manifest,'git_revision':'3'*40}
            ai.atomic(unpacked/'ai-release-manifest.json',changed)
            with self.assertRaisesRegex(RuntimeError,'ai-release-manifest.json'):
                packaging.verify_extracted_package(unpacked,manifest['files'],expected_sha)
            (unpacked/'ai-release-manifest.json').write_bytes(manifest_bytes)
            payload=unpacked/'Rise of Rome Prototype.pck';original=payload.read_bytes()
            payload.write_bytes(b'changed package')
            with self.assertRaisesRegex(RuntimeError,'Rise of Rome Prototype.pck'):
                packaging.verify_extracted_package(unpacked,manifest['files'],expected_sha)
            payload.write_bytes(original)
            (unpacked/'unexpected-save.json').write_text('{}')
            with self.assertRaisesRegex(RuntimeError,'inventory mismatch'):
                packaging.verify_extracted_package(unpacked,manifest['files'],expected_sha)
            (unpacked/'unexpected-save.json').unlink()
            (unpacked/'README.md').unlink()
            with self.assertRaisesRegex(RuntimeError,'inventory mismatch'):
                packaging.verify_extracted_package(unpacked,manifest['files'],expected_sha)

    def test_full_soak_requires_one_continuous_hour_and_resumes(self):
        import ai_soak as soak
        with tempfile.TemporaryDirectory(dir=ai.TEMP) as folder:
            root=Path(folder); requested=[]
            def execute(script,log,timeout,args,project):
                paths={arg.split("=",1)[0]:Path(arg.split("=",1)[1]) for arg in args}
                case=ai.read_result(paths["--case"]); requested.append(case["maximum_ticks"])
                self.assertEqual(case['settings']['victory_mode_id'],'score_60')
                self.assertTrue(case['continuous_full_hour'])
                ai.atomic(paths["--output"],{"case_id":case["case_id"],"fingerprint":case["fingerprint"],"status":"WIN","tick":case["maximum_ticks"]})
                return {"passed":True}
            with patch.object(soak.ai,"QA",root/"qa"),patch.object(soak.ai,"TEMP",root/"tmp"),patch.object(soak.ai,"source_hashes",return_value={"source":"fixed"}),patch.object(soak.ai,"run_process",side_effect=execute) as run:
                soak.run(72000,project=ai.PROJECT,full=True,scenario=0)
                self.assertEqual(requested,[72000])
                self.assertEqual(run.call_count,1)
                soak.run(72000,project=ai.PROJECT,full=True,scenario=0)
                self.assertEqual(run.call_count,1)
                summary=next((root/"qa/soak").glob("*/summary.json"))
                self.assertTrue(ai.read_result(summary)["all_processes_passed"])
                self.assertTrue(ai.read_result(summary)["continuous_full_hour"])

    def test_full_soak_rejects_early_wins_instead_of_resetting_memory(self):
        import ai_soak as soak
        with self.assertRaises(ValueError): soak.run(400,full=True)
        with self.assertRaises(ValueError): soak.run(400,scenario=6)
        case={'fingerprint':'fixed','maximum_ticks':72000,'continuous_full_hour':True}
        self.assertFalse(soak.valid_episode({'fingerprint':'fixed','status':'WIN','tick':25000},case))
        self.assertTrue(soak.valid_episode({'fingerprint':'fixed','status':'WIN','tick':72000},case))

    def test_release_provenance_excludes_only_transient_hot_reload_dll(self):
        import ai_build_manifest as provenance
        before={"prototype/bin/runtime.dll":"real","prototype/bin/~runtime.dll":"transient","prototype/scripts/main.gd":"code"}
        expected={"prototype/bin/runtime.dll":"real","prototype/scripts/main.gd":"code"}
        self.assertEqual(provenance.stable_sources(before),expected)
        changed={**expected,"prototype/bin/runtime.dll":"changed"}
        self.assertNotEqual(provenance.stable_sources(before),provenance.stable_sources(changed))

    def test_release_tuning_pins_artifacts_instead_of_unbuilt_working_tree(self):
        import ai_tune as tuning
        with patch.object(tuning.ai,"PACK",Path("frozen/game.pck")),patch.object(tuning.ai,"ENGINE",Path("frozen/game.exe")),patch.object(tuning.ai,"digest",side_effect=lambda p:p.name),patch.object(tuning.ai,"source_hashes",side_effect=AssertionError("unbuilt source must not enter Release league")):
            source=tuning.experiment_source()
            self.assertEqual(source["release_package"],"game.pck")
            self.assertEqual(source["release_executable"],"game.exe")
            self.assertIn("tuning_driver",source)

    def test_opening_goal_limit_is_not_an_engine_crash(self):
        import ai_openings as openings
        row={"passed":False,"tick":72000,"runtime_error":""}
        process={"exit_code":1,"timeout":False,"engine_errors":[],"termination_error":None}
        self.assertTrue(openings.completed_runtime(row,process,72000))
        self.assertFalse(openings.completed_runtime({"passed":False},process,72000))
        self.assertFalse(openings.completed_runtime(row,{**process,"engine_errors":["SCRIPT ERROR: invalid property"]},72000))
        self.assertFalse(openings.completed_runtime(row,{**process,"timeout":True},72000))

    def test_opening_resume_recovers_corrupt_report_and_process(self):
        import ai_openings as openings
        with tempfile.TemporaryDirectory(dir=ai.TEMP) as folder:
            root=Path(folder)
            configuration=ai.read_result(ai.PROJECT/'data/ai/competitive_parameters.json')
            expected={**configuration.get('runtime',{}),**configuration.get('difficulty',{}).get('standard',{})}
            def execute(script,log,timeout,args,project):
                values=dict(arg[2:].split("=",1) for arg in args)
                row={"algorithm":values["algorithm"],"civilization":int(values["civilization"]),"passed":True,"tick":100,
                     "metrics":{"idle_worker_ticks":0,"worker_ticks":1},"active_parameters":expected,
                     "observer_purity":{"checks":3,"passed":True},"final_world_hash":"a"*64,
                     "work_availability":{"2":{"worker_ticks":100,"available_ticks":100,"idle_available_ticks":0,
                         "unknown_ticks":0,"idle_unknown_ticks":0,"conditional_idle_lower_bound":0,
                         "conditional_idle_upper_bound":0,"confirmed_worker_time_coverage":1}}}
                ai.atomic(Path(values["output"]),row)
                return {"passed":True,"exit_code":0,"seconds":0.1}
            with patch.object(openings.ai,"QA",root/"qa"),patch.object(openings.ai,"TEMP",root/"tmp"),patch.object(openings.ai,"source_hashes",return_value={"fixture":"fixed"}),patch.object(openings.ai,"run_process",side_effect=execute) as run:
                openings.run(ai.PROJECT,1)
                self.assertEqual(run.call_count,32)
                report=next((root/"qa/openings").glob("*/baseline_v1-civ01.json"));report.write_text('{"partial":')
                process=next((root/"qa/openings").glob("*/competitive_v2-civ02.process.json"));process.write_text('{"partial":')
                parameters=next((root/"qa/openings").glob("*/competitive_v2-civ03.json"))
                wrong=ai.read_result(parameters);wrong['active_parameters']={};ai.atomic(parameters,wrong)
                openings.run(ai.PROJECT,1)
                self.assertEqual(run.call_count,35)
                self.assertTrue(list(report.parent.glob("*.attempt-1")))
                observation=next((root/"qa/openings").glob("*/competitive_v2-civ04.json"))
                wrong=ai.read_result(observation);wrong['work_availability']['2']['conditional_idle_upper_bound']=.5;ai.atomic(observation,wrong)
                openings.run(ai.PROJECT,1)
                self.assertEqual(run.call_count,36)

    def test_performance_resume_recovers_corrupt_reports_without_stale_success(self):
        import ai_performance as performance
        with tempfile.TemporaryDirectory(dir=ai.TEMP) as folder:
            root=Path(folder)
            def execute(script,log,timeout,args,project,**kwargs):
                values={arg.split("=",1)[0]:Path(arg.split("=",1)[1]) for arg in args}
                case=ai.read_result(values["--case"])
                configuration=ai.read_result(ai.PROJECT/'data/ai/competitive_parameters.json')
                expected={**configuration['runtime'],**configuration['difficulty']['standard']}
                ai.atomic(values["--output"],{"case":case,"fingerprint":case["fingerprint"],"passed":True,"world_hash":"same","ai_state_hash":"same","phases":[],"active_parameters":[expected]*case['teams']})
                return {"passed":True}
            with patch.object(performance.ai,"QA",root/"qa"),patch.object(performance.ai,"TEMP",root/"tmp"),patch.object(performance.ai,"source_hashes",return_value={"fixture":"fixed"}),patch.object(performance.ai,"run_process",side_effect=execute) as run:
                performance.run(True,ai.PROJECT)
                self.assertEqual(run.call_count,4)
                report=next((root/"qa/performance").glob("*/case-00.json"));report.write_text('{"partial":')
                process=next((root/"qa/performance").glob("*/case-01.process.json"));process.write_text('{"partial":')
                wrong=next((root/"qa/performance").glob("*/case-02.json"))
                invalid=ai.read_result(wrong);invalid['active_parameters']=None;ai.atomic(wrong,invalid)
                performance.run(True,ai.PROJECT)
                self.assertEqual(run.call_count,7)
                self.assertEqual(len(list(report.parent.glob("*.attempt-1"))),3)

    def test_soak_resume_recovers_corrupt_results_and_rejects_invalid_ticks(self):
        import ai_soak as soak
        expected={"fingerprint":"case","maximum_ticks":100}
        for tick in (None,"100",0,-1,101,True):
            self.assertFalse(soak.valid_episode({"fingerprint":"case","status":"WIN","tick":tick},expected))
        with tempfile.TemporaryDirectory(dir=ai.TEMP) as folder:
            root=Path(folder)
            def execute(script,log,timeout,args,project):
                values={arg.split("=",1)[0]:Path(arg.split("=",1)[1]) for arg in args}
                case=ai.read_result(values["--case"])
                ai.atomic(values["--output"],{"case_id":case["case_id"],"fingerprint":case["fingerprint"],"status":"DRAW_TIME_LIMIT","tick":case["maximum_ticks"]})
                return {"passed":True}
            with patch.object(soak.ai,"QA",root/"qa"),patch.object(soak.ai,"TEMP",root/"tmp"),patch.object(soak.ai,"source_hashes",return_value={"fixture":"fixed"}),patch.object(soak.ai,"run_process",side_effect=execute) as run:
                soak.run(100,project=ai.PROJECT)
                self.assertEqual(run.call_count,4)
                report=next((root/"qa/soak").glob("*/soak-4p-coastal.json"));report.write_text('{"partial":')
                process=next((root/"qa/soak").glob("*/soak-4p-islands.process.json"));process.write_text('{"partial":')
                soak.run(100,project=ai.PROJECT)
                self.assertEqual(run.call_count,6)
                self.assertEqual(len(list(report.parent.glob("*.attempt-1"))),2)

    def test_cohorts_are_disjoint(self):
        sets=[]
        for name,count in [("smoke",12),("dev",48),("validation",64),("holdout",64),("challenge_holdout",32)]:
            manifest=json.loads((ai.PROJECT/f"data/ai/arena/manifests/{name}.json").read_text())
            self.assertEqual(len(manifest["rows"]),count)
            seeds={row["settings"]["seed"] for row in manifest["rows"]}
            self.assertEqual(len(seeds),count)
            for previous in sets: self.assertFalse(seeds & previous)
            sets.append(seeds)

    def test_tuning_does_not_select_a_champion_after_validation_failure(self):
        import ai_tune as tuning
        with tempfile.TemporaryDirectory(dir=ai.TEMP) as folder:
            directory=Path(folder)
            incumbent={"id":"g0-c0","generation":0,"parameters":{}}
            dev={"errors":0,"score":.5,"directory":"dev-fixture"}
            invalid={"errors":1,"score":.5,"directory":"validation-fixture"}
            with patch.object(tuning,"DIRECTORY",directory),patch.object(tuning,"prepare",return_value={"candidates":[incumbent]}),patch.object(tuning,"dataset",return_value=[]),patch.object(tuning,"ranker",return_value={"fit_rows":0}),patch.object(tuning.ai,"arena",side_effect=[dev,invalid]):
                with self.assertRaises(RuntimeError): tuning.run(1,1,1)
            self.assertTrue((directory/"validation_failure.json").exists())
            self.assertFalse((directory/"champion.policy.json").exists())
            self.assertFalse((directory/"league.json").exists())

    def test_arena_resume_requires_completed_process_and_valid_json(self):
        with tempfile.TemporaryDirectory(dir=ai.TEMP) as folder:
            directory=Path(folder)
            def completed(_script,_log,_timeout,args,_project):
                case=json.loads(Path(next(x[7:] for x in args if x.startswith('--case='))).read_text())
                output=Path(next(x[9:] for x in args if x.startswith('--output=')))
                ai.atomic(output,{k:case[k] for k in ('case_id','base_id','series','fingerprint')}|{'status':'WIN'})
                return {'passed':True,'timeout':False,'exit_code':0}
            with patch.object(ai,'QA',directory),patch.object(ai,'source_hashes',return_value={'fixture':'v1'}),patch.object(ai,'event'),patch.object(ai,'run_process',side_effect=completed) as run:
                ai.arena('smoke','baseline_v1',1,1)
                self.assertEqual(run.call_count,2)
                ai.arena('smoke','baseline_v1',1,1)
                self.assertEqual(run.call_count,2)
                process=next(directory.glob('arena/*/*seat1.process.json'))
                process.unlink()
                report=next(directory.glob('arena/*/*seat2.json'))
                report.write_text('{"partial":',encoding='utf-8')
                ai.arena('smoke','baseline_v1',1,1)
                self.assertEqual(run.call_count,4)
                self.assertEqual(len(list(directory.glob('arena/*/*.attempt-1'))),2)

if __name__=="__main__": unittest.main()
