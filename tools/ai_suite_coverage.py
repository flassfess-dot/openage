"""Audit suite coverage across an interrupted boundary and explicit reruns.

This never represents multiple runs as a single clean suite invocation.
"""
import argparse,datetime,json,re
from pathlib import Path
import ai_competitive as ai

def audit(logs,reruns,output):
    expected=sorted(p.relative_to(ai.PROJECT).as_posix() for folder in ('unit','integration','scenarios','golden')
                    for p in (ai.PROJECT/'tests'/folder).glob('test_*.gd'))
    records={}; history=[]
    for file in logs:
        for line in file.read_text(encoding='utf-8-sig',errors='replace').splitlines():
            # The PowerShell wrapper repeats old failures at suite completion.
            # Those summaries are not new executions after an isolated rerun.
            if 'godot-summary:' in line:
                continue
            match=re.search(r'\b(PASSED|FAILED) (tests/[^\s]+\.gd)',line)
            if match:
                stamp=re.search(r'\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)\]',line)
                completed=datetime.datetime.strptime(stamp[1],'%Y-%m-%d %H:%M:%S').timestamp() if stamp else file.stat().st_mtime
                row={'script':match[2],'passed':match[1]=='PASSED','evidence':str(file.relative_to(ai.ROOT)),'completed_unix':completed}
                records[match[2]]=row; history.append(row)
    # The process wrapper checks both stdout and the separate engine log, an
    # exit status, timeout, source fingerprint and the individual test hash.
    for row in json.loads(reruns.read_text(encoding='utf-8')):
        if row.get('passed') and row.get('script') in expected:
            evidence=ai.ROOT/row['log']
            if not evidence.exists(): continue
            if evidence.stat().st_mtime>=records.get(row['script'],{}).get('completed_unix',0):
                records[row['script']]={'script':row['script'],'passed':True,'evidence':row['log'],
                                    'source_sha256':row.get('source_sha256'),'key':row.get('key'),'completed_unix':evidence.stat().st_mtime}
    missing=[name for name in expected if name not in records]
    failed=[name for name in expected if name in records and not records[name]['passed']]
    report={'schema_version':1,'scope':'Resumed suite boundary plus explicit isolated reruns; not one uninterrupted clean run',
            'discovered':len(expected),'passed':sum(name in records and records[name]['passed'] for name in expected),
            'missing':missing,'unresolved_failures':failed,'historical_failed_events':[r for r in history if not r['passed']],
            'all_discovered_covered':not missing and not failed,'records':[records[name] for name in expected if name in records]}
    ai.atomic(output,report)
    print(json.dumps({k:v for k,v in report.items() if k!='records'},ensure_ascii=False),flush=True)
    return report['all_discovered_covered']

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('--logs',type=Path,nargs='+',required=True)
    parser.add_argument('--reruns',type=Path,default=ai.QA/'tests/results.json')
    parser.add_argument('--output',type=Path,default=ai.QA/'suite_coverage.json')
    args=parser.parse_args()
    if not audit([p.resolve() for p in args.logs],args.reruns,args.output): raise SystemExit(1)
