# First Punic War vertical

## Статус

Кампания `First Punic War.cpx` опубликована единым пакетом уровня `INTEGRATED`: все три миссии имеют постоянные fixed-source matches, доступны из launcher и проходят bootstrap, source-win и local-defeat evidence. Это не заявление о пиксельном или AI-поведении уровня `PARITY`.

| Миссия | Source objects | Runtime entities | Presentation-only | Условия | Launcher |
| --- | ---: | ---: | ---: | ---: | --- |
| Struggle for Sicily | 3388 | 2688 | 700 | 2 | ready |
| Battle of Mylae | 2605 | 1818 | 785 | 2 | ready |
| Battle of Tunes | 8894 | 6872 | 2017 | 2 | ready |

## Общие контракты

- Guard Tower 69, Tree Stump 131 и Artifact 159 нормализованы общими archetype-правилами.
- Artifact остаётся обычной мобильной сущностью с сериализуемой связью с victory-objective. Ближайший допустимый юнит захватывает его через общий fixed-tick lifecycle; нейтральная, своя и вражеская палитры разделены.
- Правый клик по нейтральному Artifact означает подход к объекту, а не атаку. Artifact исключён из боевых целей.
- `DestroyMultiple` нормализован как подсчёт уничтоженных точных source scenario IDs; `BringToArea` проверяет точный объект и исходную область.
- Guard Tower использует существующий tower pipeline. Source-specific scenery выбирает presentation variant по source unit ID, не создавая отдельных runtime-классов.
- AI-профиль с `Random` и пустым build list запускается через общий безопасный source-random fallback, сохраняя явный parity gap для недоказанного исходного выбора.

## Ресурсы и честная граница соответствия

Импортированы source graphics 323 в обеих player-палитрах, 572, 833, 928 и 929. В установленном каталоге graphic 930 указывает на отсутствующий SLP 799, поэтому его экземпляры используют явно записанный semantic fallback `tree`; это учитывается как `source_asset_fallback_gap`, а не скрывается под готовностью launcher.

Остаются parity gaps:

- AI semantics: 1 / 2 / 2 профиля по миссиям;
- graphic 930 fallback instances: 3 / 75 / 194;
- точная визуальная и временная калибровка по executable captures.

## Воспроизведение

`tools/ror_import/convert_campaign_manifest.ps1` строит все постоянные matches из source campaign manifest. `tools/import-assets.ps1` вызывает его для обеих опубликованных кампаний после построения каталогов; запуск игры конвертацию не выполняет. `tools/ror_import/audit_first_punic_war.ps1` независимо пересобирает временные matches и обновляет machine gap matrix.

Доказательства находятся в `test_imported_first_punic_war_matches.gd`, `test_artifact_capture_pipeline.gd` и `test_fpw_vertical.gd`.

Итоговый boundary gate: 186 тестов пройдено, 0 провалено; cache validation — 0 ошибок и 181 известное source-owned предупреждение. Windows PCK имеет размер 246 916 672 байта и SHA-256 `01fdb59a4da2601f942e5a2cd97f3b62f03ed25bb6c38c46d3e816874c04149b`. Упакованный `campaign_battle_of_mylae` запущен автономно и завершил smoke с кодом 0 без runtime/script errors.
