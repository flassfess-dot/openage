"""Fresh complete tests on the selected final source and actual standard native."""
import argparse,json,re,shutil,subprocess,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import ai_competitive as ai
import ai_build_manifest as provenance
import ai_suite_coverage as coverage
from ai_combat_acceptance import validate_project_sources

def execute(args,log,timeout):
    assert not log.exists(), 'Preserve previous test evidence: '+str(log)
    started=time.monotonic()
    with log.open('w',encoding='utf-8') as stream:
        child=subprocess.Popen(args,cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT,creationflags=ai.FLAGS)
        try: code=child.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            subprocess.run(['taskkill','/PID',str(child.pid),'/T','/F'],capture_output=True,creationflags=ai.FLAGS)
            child.wait(timeout=30)
            ai.atomic(log.with_suffix('.timeout.json'),dict(pid=child.pid,seconds=timeout,scope='Only the owned test process tree.'))
            code=-1
    return dict(command=args,exit_code=code,seconds=round(time.monotonic()-started,3),stdout=log.relative_to(ROOT).as_posix(),stdout_sha256=ai.digest(log))

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--application',type=Path,required=True)
    parser.add_argument('--project',type=Path,default=ai.PROJECT)
    parser.add_argument('--output-directory',type=Path,default=ai.QA/'quality-r20/full-suite')
    args=parser.parse_args()
    exe=args.application.resolve();project=args.project.resolve()
    q=args.output_directory.resolve()
    if not q.is_relative_to(ai.QA.resolve()):raise ValueError('Complete test evidence must remain under the current QA directory')
    proof=ai.read_result(exe.parent/'build-provenance.json');source=proof['runtime_source_hashes']
    assert provenance.runtime_sources()==source, 'Final source differs before complete test run'
    assert all(ai.digest(exe.parent/name)==sha for name,sha in proof['artifacts'].items())
    native=ai.PROJECT/'bin/ror_pathfinding.windows.template_release.x86_64.dll'
    assert ai.digest(native)==proof['artifacts']['bin/ror_pathfinding.windows.template_release.x86_64.dll']
    extension=(ai.PROJECT/'ror_pathfinding.gdextension').read_text(encoding='utf-8')
    assert 'windows.debug.x86_64 = "res://bin/ror_pathfinding.windows.template_release.x86_64.dll"' in extension
    assert 'windows.release.x86_64 = "res://bin/ror_pathfinding.windows.template_release.x86_64.dll"' in extension
    frozen=ai.read_result(project/'arena_runtime_manifest.json')
    if frozen:validate_project_sources(project,frozen['source'])
    elif project!=ai.PROJECT.resolve():raise ValueError('A separate frozen project requires its source manifest')
    tests={p.relative_to(ai.PROJECT).as_posix():ai.digest(p) for p in sorted((ai.PROJECT/'tests').rglob('*.gd'))}
    inventory=sorted(p.relative_to(ai.PROJECT).as_posix() for category in ('golden','integration','scenarios','unit') for p in (ai.PROJECT/'tests'/category).glob('test_*.gd'))
    assert len(inventory)>=513, 'The complete inventory must not silently shrink'
    driver=ROOT/'tools/ror-run-tests.ps1'
    tool_paths=list((ROOT/'tools').rglob('*.py'))+[ROOT/'tools/tests/test-ror-build-common.ps1',ROOT/'tools/ror-build-common.ps1']
    tool_sources={p.relative_to(ROOT).as_posix():ai.digest(p) for p in sorted(tool_paths)}
    before=dict(runtime_source=source,all_test_sources=tests,inventory=inventory,tool_sources=tool_sources,driver_sha256=ai.digest(driver),verification_driver_sha256=ai.digest(Path(__file__)),artifacts=proof['artifacts'],native_sha256=ai.digest(native),engine_sha256=ai.digest(ai.ENGINE))
    q.mkdir(parents=True,exist_ok=False)
    ai.atomic(q/'before.json',before)
    prior=q/'prior-global-metadata';prior.mkdir()
    prior_hashes={}
    for name in ['suite_coverage.json','fresh_suite_boundary.json','test_source_closure.after-complete-suite.json','python-tests-final.stdout.log','final-build-helpers.stdout.log','final-cache-validation.json','final-cache.stdout.log']:
        path=ai.QA/name
        if path.exists():shutil.copy2(path,prior/name);prior_hashes[name]=ai.digest(prior/name)
    if (ai.PROJECT/'qa/test-logs').exists():shutil.copytree(ai.PROJECT/'qa/test-logs',q/'prior-engine-logs')
    print('FINAL COMPLETE SUITE START',len(inventory),'source-bound standard native',flush=True)
    suite=execute([shutil.which('pwsh'),'-NoProfile','-ExecutionPolicy','Bypass','-File',str(driver)],q/'suite.stdout.log',28800)
    ai.atomic(q/'no-reruns.json',[])
    complete=coverage.audit([q/'suite.stdout.log'],q/'no-reruns.json',q/'coverage.json')
    report=ai.read_result(q/'coverage.json')
    unchanged=provenance.runtime_sources()==source and tests=={p.relative_to(ai.PROJECT).as_posix():ai.digest(p) for p in sorted((ai.PROJECT/'tests').rglob('*.gd'))}
    unchanged=unchanged and ai.digest(driver)==before['driver_sha256'] and ai.digest(native)==before['native_sha256']
    unchanged=unchanged and all(ai.digest(exe.parent/name)==sha for name,sha in proof['artifacts'].items())
    passed=suite['exit_code']==0 and complete and unchanged and report['passed']==len(inventory) and not report['historical_failed_events']
    result=dict(passed=passed,process=suite,unchanged_source_and_tests=unchanged,inventory=len(inventory),coverage_sha256=ai.digest(q/'coverage.json'),release_artifacts=proof['artifacts'],scope='One fresh complete final-source invocation, no cached R19 tests or isolated reruns counted as this run. Editor test engine loads the exact final standard Release native DLL; actual shipping EXE checks remain separate.')
    ai.atomic(q/'result.json',result)
    if not passed:
        ai.atomic(q/'qualification.json',dict(passed=False,source=source,artifacts=proof['artifacts'],full_suite_result_sha256=ai.digest(q/'result.json')))
        raise RuntimeError('Final complete suite failed; all failures and engine logs retained: '+str(q))
    print('FINAL COMPLETE SUITE PASSED',len(inventory),flush=True)
    checks=[]
    checks.append(execute([sys.executable,'-m','unittest','discover','-s','tools/tests','-p','test*.py'],q/'python.stdout.log',600))
    checks.append(execute([shutil.which('pwsh'),'-NoProfile','-ExecutionPolicy','Bypass','-File','tools/tests/test-ror-build-common.ps1'],q/'powershell.stdout.log',600))
    checks.append(execute([sys.executable,'tools/ror_import/validate_cache.py','--cache-dir',str(ai.PROJECT/'assets/generated'),'--json-output',str(q/'cache-validation.json'),'--markdown-output',str(q/'cache-validation.md')],q/'cache.stdout.log',600))
    python_text=(q/'python.stdout.log').read_text(encoding='utf-8-sig',errors='replace')
    python_counts=re.findall(r'Ran (\d+) tests',python_text)
    powershell_text=(q/'powershell.stdout.log').read_text(encoding='utf-8-sig',errors='replace')
    ps_counts=re.findall(r'Build common: (\d+) checks passed',powershell_text)
    cache=ai.read_result(q/'cache-validation.json')
    tools_passed=all(row['exit_code']==0 for row in checks) and python_counts and int(python_counts[-1])>=42 and python_text.strip().splitlines()[-1]=='OK'
    tools_passed=bool(tools_passed and ps_counts and int(ps_counts[-1])>=15 and cache.get('summary',{}).get('errors')==0)
    unchanged=provenance.runtime_sources()==source and tests=={p.relative_to(ai.PROJECT).as_posix():ai.digest(p) for p in sorted((ai.PROJECT/'tests').rglob('*.gd'))}
    unchanged=unchanged and all(ai.digest(exe.parent/name)==sha for name,sha in proof['artifacts'].items()) and ai.digest(native)==before['native_sha256']
    unchanged=unchanged and all(ai.digest(ROOT/name)==sha for name,sha in tool_sources.items())
    unchanged=unchanged and ai.digest(driver)==before['driver_sha256'] and ai.digest(Path(__file__))==before['verification_driver_sha256'] and ai.digest(ai.ENGINE)==before['engine_sha256']
    passed=tools_passed and unchanged
    qualification=dict(passed=passed,source=source,artifacts=proof['artifacts'],inventory=len(inventory),all_test_sources=tests,native_sha256=ai.digest(native),before_sha256=ai.digest(q/'before.json'),full_suite_result_sha256=ai.digest(q/'result.json'),suite_stdout=(q/'suite.stdout.log').relative_to(ROOT).as_posix(),suite_stdout_sha256=ai.digest(q/'suite.stdout.log'),coverage_sha256=ai.digest(q/'coverage.json'),python_tests=int(python_counts[-1]) if python_counts else 0,powershell_checks=int(ps_counts[-1]) if ps_counts else 0,cache_summary=cache.get('summary'),tool_processes=checks,prior_global_metadata_sha256=prior_hashes,scope=result['scope'])
    ai.atomic(q/'qualification.json',qualification)
    if not passed:raise RuntimeError('Final tool tests/cache/source boundary failed; inspect preserved complete suite and tool logs')
    report['scope']=result['scope']
    ai.atomic(ai.QA/'suite_coverage.json',report)
    selected={name:tests[name] for name in inventory}
    ai.atomic(ai.QA/'fresh_suite_boundary.json',dict(passed=True,discovered=len(inventory),runtime_source_hashes=source,coverage_sha256=ai.digest(ai.QA/'suite_coverage.json'),suite_stdout=(q/'suite.stdout.log').relative_to(ROOT).as_posix(),suite_stdout_sha256=ai.digest(q/'suite.stdout.log'),test_source_sha256=ai.fingerprint(selected),scope=result['scope']))
    ai.atomic(ai.QA/'test_source_closure.after-complete-suite.json',dict(passed=True,inventory=len(inventory),test_source_sha256=ai.fingerprint(selected),all_test_source_sha256=ai.fingerprint(tests),runtime_source_hashes=source,suite_result_sha256=ai.digest(q/'result.json'),invocation_snapshot_sha256=ai.digest(q/'before.json'),scope=result['scope']))
    for source_name,target_name in [('python.stdout.log','python-tests-final.stdout.log'),('powershell.stdout.log','final-build-helpers.stdout.log'),('cache-validation.json','final-cache-validation.json'),('cache.stdout.log','final-cache.stdout.log')]:shutil.copy2(q/source_name,ai.QA/target_name)
    print('FINAL COMPLETE TEST BOUNDARY PASSED',json.dumps(dict(godot=len(inventory),python=qualification['python_tests'],powershell=qualification['powershell_checks'],cache=qualification['cache_summary'])),flush=True)

if __name__=='__main__':main()
