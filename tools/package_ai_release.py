"""Copy a clean, relocatable local AI Release and verify its ZIP round trip."""
import argparse,json,shutil,subprocess,zipfile
import re
from pathlib import Path
import ai_competitive as ai

APPLICATION='Rise of Rome Prototype.exe'

def verify_extracted_package(unpacked,files,manifest_sha256):
    expected={**files,'ai-release-manifest.json':manifest_sha256}
    actual={p.relative_to(unpacked).as_posix() for p in unpacked.rglob('*') if p.is_file()}
    if actual!=set(expected): raise RuntimeError('Extracted file inventory mismatch')
    for name,sha256 in expected.items():
        if ai.digest(unpacked/name)!=sha256: raise RuntimeError('Extracted hash mismatch: '+name)

def package(source,destination,archive=False):
    source=source.resolve(); destination=destination.resolve()
    if destination.exists(): raise ValueError('Use a new package directory; existing releases are immutable')
    required=[APPLICATION,'Rise of Rome Prototype.pck','bin/ror_pathfinding.windows.template_release.x86_64.dll',
              'legal/MIT/godot-cpp.md','README.md','Rise of Rome.ico']
    provenance=ai.read_result(source/'build-provenance.json')
    if not provenance or not provenance.get('runtime_source_hashes'): raise ValueError('A build-provenance.json from the verified build pipeline is required')
    if any(ai.digest(source/name)!=value for name,value in provenance['artifacts'].items()): raise ValueError('Build provenance does not match actual Release artifacts')
    required.append('build-provenance.json')
    before={name:ai.digest(source/name) for name in required}
    destination.mkdir(parents=True)
    for name in required:
        target=destination/name; target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(source/name,target)
    if before!={name:ai.digest(source/name) for name in required}: raise RuntimeError('Build changed while packaging')
    (destination/'Play Competitive AI.cmd').write_text(
        '@echo off\ncd /d "%~dp0"\nstart "" "Rise of Rome Prototype.exe" -- --competitive-ai\n',encoding='ascii')
    (destination/'AI-README.txt').write_text(
        'Запуск нового ИИ: Play Competitive AI.cmd\n'
        'Создайте случайную карту и выберите сложность ИИ в обычном меню.\n'
        'Обычный EXE сохраняет прежний вариант ИИ, пока новая политика не пройдёт критерии качества.\n'
        'Человеческий рейтинг не измерен. Результаты и ограничения: AI-RESULTS.md.\n'
        'Старые сохранения формата 7 не поддерживаются; начните новую партию.\n'
        'Сохранения и настройки хранятся в обычном каталоге данных приложения Godot.\n',encoding='utf-8-sig')
    report=ai.ROOT/'doc/ror-modern/AI_COMPETITIVE_RESULTS.md'
    if report.exists(): shutil.copy2(report,destination/'AI-RESULTS.md')
    revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ai.ROOT,text=True).strip()
    dirty=bool(subprocess.check_output(['git','status','--porcelain','--untracked-files=normal'],cwd=ai.ROOT,text=True).strip())
    files={p.relative_to(destination).as_posix():ai.digest(p) for p in sorted(destination.rglob('*')) if p.is_file()}
    manifest={'schema_version':1,'git_revision':revision,'source_dirty':dirty,'runtime_source_hashes':provenance['runtime_source_hashes'],'build_git_revision':provenance['git_revision'],
              'files':files,'launch':'Play Competitive AI.cmd','human_strength':'HUMAN_UNMEASURED',
              'scope':'Local package; graphical input and FPS verification are reported separately'}
    ai.atomic(destination/'ai-release-manifest.json',manifest)
    manifest_sha256=ai.digest(destination/'ai-release-manifest.json')
    if archive:
        zip_path=destination.with_suffix('.zip')
        if zip_path.exists(): raise ValueError('ZIP already exists')
        with zipfile.ZipFile(zip_path,'w',zipfile.ZIP_DEFLATED,compresslevel=3) as out:
            for file in sorted(destination.rglob('*')):
                if file.is_file(): out.write(file,destination.name+'/'+file.relative_to(destination).as_posix())
        extracted=destination.parent/(destination.name+'-extracted')
        if extracted.exists(): raise ValueError('Extraction directory already exists')
        with zipfile.ZipFile(zip_path) as inp:
            if inp.testzip() is not None: raise RuntimeError('ZIP CRC failed')
            inp.extractall(extracted)
        unpacked=extracted/destination.name
        verify_extracted_package(unpacked,files,manifest_sha256)
        print(json.dumps({'zip':str(zip_path),'zip_sha256':ai.digest(zip_path),
              'extracted_application':str(unpacked/APPLICATION),'manifest_sha256':manifest_sha256,
              'verified_files':len(files)+1},ensure_ascii=False),flush=True)
    print(json.dumps({'package':str(destination),'manifest':str(destination/'ai-release-manifest.json')},ensure_ascii=False),flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path)
    parser.add_argument('--destination',type=Path,required=True); parser.add_argument('--zip',action='store_true')
    args=parser.parse_args()
    if args.source is None:
        dist = ai.ROOT / 'dist'
        marker = dist / 'current-release.txt'
        slot = marker.read_text(encoding='utf-8-sig').strip() if marker.exists() else 'primary'
        if slot == 'primary':
            parent = dist
        elif slot == 'alternate':
            parent = dist / 'releases'
        elif re.fullmatch(r'slot-[1-9][0-9]*', slot):
            parent = dist / 'releases' / slot
        else:
            parser.error(f'Unknown release slot in {marker}')
        args.source = parent / 'Rise of Rome Prototype'
    package(args.source,args.destination,args.zip)
