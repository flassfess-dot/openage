# Проверка многопоточной оптимизации — 2026-10-04

По новому указанию пользователя сначала выполнен полный suite без изменений кода во время прогона, затем исправлены обнаруженные падения и выполнен отдельный повтор.

| Прогон | Прошли | Упали |
|---|---:|---:|
| Все 347 тестов, 22:13–23:00 (Europe/Moscow) | 325 | 22 |
| Все 22 первоначально упавших теста после исправлений | 22 | 0 |
| Усиленный тест пакетных маршрутов и семь связанных новых unit-тестов после исправлений | 8 | 0 |

Второй полный suite не запускался: итог составлен из первого полного прогона и отдельного повторного прогона падений. Все девять добавленных unit-файлов прошли на исправленном коде.

## Причины и исправления

- В 19 тестах создания основной сцены Godot сообщал о недопустимом `z_index=20000` у надписи загрузки. Значение приведено к допустимому `4096`.
- Два из этих тестов отправляли клавиатурный/мышиный ввод после двух кадров, пока продолжалась подготовка навигации. Общий fixture `tests/support/match_ready.gd` теперь ожидает фактическую публикацию навигации с ограничением 30 секунд до интерактивных проверок.
- Пакетный поиск сохранял пути, но терял индивидуальные `navigation.path_query` observations и часть счётчиков. Частный probe принадлежит worker-планировщику; отделённые числовые samples/counters объединяются владельцем в порядке запросов. Tick accounting использует прошедшее время владельца. Добавлено покрытие числа запросов, cache hits и времени tick.
- После попадания части видов зданий в кэш оставшаяся единственная задача с одним рабочим всё равно направлялась в worker. Выбор режима теперь учитывает реальные незакэшированные запросы; в этом случае применяется исходный последовательный поиск без лишнего capture/context.
- `seal()` пытался добавить маркер в уже readonly корень без маркера и прерывал тест координатора. Такой корень копируется перед маркировкой; повторная фиксация зарегистрированного корня сохраняет идентичность, неподтверждённый маркер получает новый token. Регрессионные проверки расширены.
- PowerShell-оболочка не считала строки `ERROR: FAILED tests/…`. Исправлено распознавание префикса ошибки; первичный результат 325/22 получен из suite, а ошибочная строка оболочки «Failed: 0» не использована как результат.

Тест координатора после SCRIPT ERROR не дошёл до `quit()`; был завершён только его конкретный дочерний процесс, чтобы suite выполнил остальные тесты. В первичном результате он учтён как failed; после исправления завершился штатно с exit 0.

## Первоначально упавшие тесты

| Тест | Причина | Отдельный повтор |
|---|---|---|
| [test_build_palette_pipeline.gd](../../prototype/tests/integration/test_build_palette_pipeline.gd) | Слой загрузки и готовность ввода | PASS |
| [test_building_selection_rectangle.gd](../../prototype/tests/integration/test_building_selection_rectangle.gd) | Слой загрузки | PASS |
| [test_checkpoint_resume.gd](../../prototype/tests/integration/test_checkpoint_resume.gd) | Слой загрузки | PASS |
| [test_delete_and_martyrdom_routing.gd](../../prototype/tests/integration/test_delete_and_martyrdom_routing.gd) | Слой загрузки | PASS |
| [test_e3_controlled_skirmish.gd](../../prototype/tests/integration/test_e3_controlled_skirmish.gd) | Слой загрузки | PASS |
| [test_foreign_inspection.gd](../../prototype/tests/integration/test_foreign_inspection.gd) | Слой загрузки | PASS |
| [test_game_save_load_pipeline.gd](../../prototype/tests/integration/test_game_save_load_pipeline.gd) | Слой загрузки | PASS |
| [test_game_save_state_matrix.gd](../../prototype/tests/integration/test_game_save_state_matrix.gd) | Слой загрузки | PASS |
| [test_generated_skirmish_main_scene.gd](../../prototype/tests/integration/test_generated_skirmish_main_scene.gd) | Слой загрузки | PASS |
| [test_imported_campaign_main_scene.gd](../../prototype/tests/integration/test_imported_campaign_main_scene.gd) | Слой загрузки | PASS |
| [test_main_hud_scene.gd](../../prototype/tests/integration/test_main_hud_scene.gd) | Слой загрузки | PASS |
| [test_multiplayer_main_scene.gd](../../prototype/tests/integration/test_multiplayer_main_scene.gd) | Слой загрузки | PASS |
| [test_navigation_command_pipeline.gd](../../prototype/tests/integration/test_navigation_command_pipeline.gd) | Статистика пакетного поиска | PASS |
| [test_p14_replay_save_hash_matrix.gd](../../prototype/tests/integration/test_p14_replay_save_hash_matrix.gd) | Слой загрузки | PASS |
| [test_panned_static_projection.gd](../../prototype/tests/integration/test_panned_static_projection.gd) | Слой загрузки | PASS |
| [test_player_unit_order_controls.gd](../../prototype/tests/integration/test_player_unit_order_controls.gd) | Слой загрузки | PASS |
| [test_resign_spectator.gd](../../prototype/tests/integration/test_resign_spectator.gd) | Слой загрузки | PASS |
| [test_resource_inspection_selection.gd](../../prototype/tests/integration/test_resource_inspection_selection.gd) | Слой загрузки и готовность ввода | PASS |
| [test_wall_drag_main_scene.gd](../../prototype/tests/integration/test_wall_drag_main_scene.gd) | Слой загрузки | PASS |
| [test_ai_build_site_cache.gd](../../prototype/tests/unit/test_ai_build_site_cache.gd) | Режим поиска после cache hits | PASS |
| [test_isolated_task_coordinator.gd](../../prototype/tests/unit/test_isolated_task_coordinator.gd) | Фиксация readonly корня | PASS |
| [test_minimap_fog_chunks.gd](../../prototype/tests/unit/test_minimap_fog_chunks.gd) | Слой загрузки | PASS |

## Подтверждённое покрытие

Golden-тесты прошли; golden files не обновлялись. Проверки навигации, сценарии ИИ, матрица профилей/стартов/сверхбольших карт прошли. В первом suite прошла проверка карт в тогдашней упакованной сборке. После исправлений отдельно прошла P14 replay/save hash matrix: queued orders, combat, logistics, fog, victory и четыре generated-map профиля. Это подтверждение проверенных сценариев, а не всех визуальных и performance критериев плана.

Новые эталоны производительности и парные Release-замеры ускорения не собирались. Числовой прирост FPS не заявляется.

Локальные журналы и машиночитаемые результаты (QA исключена из Git):

- `prototype/qa/dev-scripts/test-run-20261004-221315.log` — полный suite.
- `prototype/qa/threading-initial-test-results.json` — исходные 325/22 и список падений.
- `prototype/qa/threading-failed-rerun-results.json` и `threading-failed-rerun-console.log` — 22 исправленных теста и усиленный path-batch test.
- `prototype/qa/threading-impact-results.json` — семь связанных новых тестов.
- `prototype/qa/threading-failed-rerun/` — отдельные engine logs.
- `prototype/qa/threading-fixes-compilation.log` — компиляция изменённых скриптов.
- `prototype/qa/threading-fixed-release-build.log` — обновлённая сборка после исправлений.

## Обновлённая сборка после исправлений

Windows Release-экспорт завершён 2026-10-04 в 23:20 (Europe/Moscow), exit 0. Запуск готового EXE штатным launcher-параметром `--match=prototype_skirmish`, headless, `--quit-after 300`: exit 0, SCRIPT/engine errors 0. Новые замеры производительности не выполнялись.

| Файл | Размер, байт | SHA-256 |
|---|---:|---|
| Rise of Rome Prototype.exe | 109127680 | `4a9eaded8955ef789ab02651ed9d2dde80328fbb342bd2a6db4db33e86305668` |
| Rise of Rome Prototype.pck | 275724264 | `f3e27674bd7f8f623cccc4e3c3d40d638091841fed740e8a9898cdfc84c366d4` |
| ror_pathfinding.windows.template_release.x86_64.dll | 686592 | `b8752911c1ea0c1e405aa1640e2fa06614ed30dc3773343d56281de91653d2e4` |

DLL в корне distribution, в `bin/` и в исходном `prototype/bin/` совпадают. Итоговые артефакты находятся в `dist/Rise of Rome Prototype/`. Проверка пакета: `prototype/qa/threading-fixed-packaged-smoke.log`; машиночитаемые размеры/хеши: `prototype/qa/threading-fixed-release-artifacts.json`.

## Игровые регрессии: строительство, лес и задержки (2026-10-04/05)

После пользовательского сообщения проведены отдельные воспроизводящие проверки. Новый test_presentation_render_contract сначала упал с 12 ошибками; после исправления прошёл. Исправлены повторная классификация компактных building DTO и потеря environment_asset/environment_variant/tree_condition в retained resource memory. Дополнен generated environment test проверкой количества, координат и точного asset/frame всех деревьев через реальный gameplay snapshot, с publication и без неё.

В новой publication больше нет повторной обрезки полей. По умолчанию presentation=false: подготовка кадра возвращается к retained snapshot, без повторного копирования всего исследованного леса/overview и worker-validation. Отключение затрагивает только этап 4. Остальные подсистемы продолжают работать.

Целевой набор: **16 passed / 0 failed**. Все журналы regression-*.log проверены на SCRIPT/Parse/Compile/ERROR (0). Набор: test_presentation_publication, test_presentation_render_contract, test_resources, test_building_presentation_registry, test_building_presentation_golden, test_simulation_snapshot, test_generated_environment_landscape, test_isolated_task_coordinator, test_environment_pack, test_long_session_performance, test_tree_lifecycle_budget, test_random_map_ecology, test_random_map_landscape, test_worker_regressions, test_panned_static_projection, test_core_building_age_pipeline. Второй полный suite не запускался. Новый интеграционный файл автоматически включён в desktop Run Tests: всего **348** обнаруживаемых тестов.

Короткая диагностика CPU-копирования на карте 400×400 и четыре минуты ускоренной real-main coastal-партии подтвердили причину и отсутствие прежнего резкого роста в проверенном сценарии. Новые baseline не создавались. Оконные захваты grasslands/highlands/islands и foundation stages 0–3/complete просмотрены. Полные условия, пределы подтверждения и результаты в [описании реализации](MULTITHREADING_IMPLEMENTATION_2026-10-04.md#исправление-игровых-регрессий-после-оптимизации).

Локальные файлы QA: diagnose_presentation_cost.log, presentation-render-contract-before.log, regression-*.log, threading-regressions-long-match.json, threading-regression-visuals/, threading-regressions-release-build.log. Golden files не обновлялись.

## Итоговая сборка после игровых регрессий — 2026-10-05

Windows Release собран успешно (exit 0). Итоговый пакет: 275727820 байт, SHA-256 7f540a78ab23f240e1249785478c2f48d9f06f6e9d942063991aec3eb0bb7a1f. EXE: 109127680 байт, SHA-256 4a9eaded8955ef789ab02651ed9d2dde80328fbb342bd2a6db4db33e86305668. Нативная DLL: 686592 байт, SHA-256 de2f80cf963866ebcd15a650c074897b3d532476a27be80148f7cf01df3de87d; исходная, корневая distribution и bin-копии совпадают.

Штатный Release EXE: prototype_skirmish, headless, 600 кадров — exit 0, ошибок 0. Дополнительно из готового PCK с Godot 4.7.2 выполнены test_presentation_render_contract и test_generated_environment_landscape — 2 passed / 0 failed, ошибок загрузки native extension 0. Для --main-pack задан --path каталога distribution; запуск движка из каталога репозитория без этого параметра сначала не нашёл относительную native DLL. Прямой запуск integration script через Release EXE из корня репозитория не завершился и остановлен; это не засчитано как прохождение. Чистые окончательные проверки PCK находятся в packaged-regression-*-fixed.log.

Файлы: dist/Rise of Rome Prototype/. Журналы: prototype/qa/threading-regressions-release-build.log, threading-regressions-packaged-smoke.log, packaged-regression-test_presentation_render_contract-fixed.log, packaged-regression-test_generated_environment_landscape-fixed.log. Размеры/хеши: prototype/qa/threading-regressions-release-artifacts.json. Целевые проверки исходного проекта: 16 passed / 0 failed; отдельные проверки пакета: 2 passed / 0 failed. Новые performance baseline не создавались.

## Периодические фризы — 2026-10-05

Причины: вытеснение активной navigation topology из FIFO sealed-root registry перед задачами ИИ и полное сбрасывание fog/terrain presentation при локальной смене ground material от вырубки дерева. Исправления: LRU immutable identity registry; source construction demand filter; serial early exit для одного вида стройплощадки; независимая версия геометрии высот; bounded surface delta history и локальная invalidation terrain caches.

Новый test_detached_topology_registry до исправления выявлял 25 нарушений удержания активной карты, после — 0. Добавлены test_source_campaign_build_site_demand и test_terrain_change_invalidation; усилен test_threaded_build_sites. Покрыты source lineage/target counts, queues/research, housing/reserved/half population points, busy/dead/enemy/water workers, unavailable/failed priorities, wall gates и drop-site distance, оба observation paths, native и legacy exact geometry, ограниченность кэшей, offscreen updates, slope-mask reuse и full-refresh fallback. Native incremental capture повторно читает ровно одну изменённую клетку; legacy пересчитывает ровно девять tiles. Golden files не обновлялись.

Два последовательных impact-набора: **43 выполнения / 40 разных файлов / 0 failed / 0 engine errors**. Включены fog/elevation/terrain golden, native/async/prefetch, source campaign planners и семь pipelines, build-site caches, detached/coordinator/path/movement tasks, snapshot/render/environment, deterministic replay, checkpoint resume и save-load pipeline. Полный suite повторно не запускался. Desktop runner автоматически обнаруживает **351** тестовый файл.

Диагностика исходного проекта (не новый performance baseline):

| Workload | До исправления | После исправления |
|---|---:|---:|
| Grasslands, два игрока, 800 fixed ticks: максимум process + world drawables на AI decision | 115,308 мс | 31,279 мс |
| Тот же конкретный tick 622 с новым building/topology | 115,308 мс | 26,555 мс |
| Birth of Rome, шесть ИИ, 240 fixed ticks: AI-decision p50 / p95 / max | 2423,855 / 3456,017 / 5333,259 мс | 22,959 / 54,094 / 73,939 мс |
| Оконный Birth of Rome после первой AI-починки: recurring fog mask / terrain | 548–591 / 315–337 мс | Эти повторные пересборки отсутствуют |

Оконные прогоны: 1500 кадров, viewport 1280×720, нормальная обработка main scene, ИИ отключается на кадре 1100. После всех исправлений AI-decision frame p95 56,085 мс; ordinary frame p95 37,705 мс. Максимум 154,955 мс приходится на первичное заполнение presentation caches в tick 4; после первых 40 ticks повторных пауз >100 мс не зарегистрировано. Это ограниченная диагностика конкретных source-project партий, без заявления о постоянных 60 FPS или полном отсутствии любых пиков на всех картах. Два headless grasslands контроля без ИИ также выполнены.

Локальные артефакты QA: periodic-freeze-before/final.log, periodic-campaign-before/after/final.log, periodic-campaign-submit-before.log, periodic-campaign-live-final.log (после AI-починки, до fog/terrain-починки), periodic-campaign-live-complete.log (после всех исправлений), detached-topology-before/after.log, periodic-targeted-results.json, periodic-terrain-results.json и объединённый periodic-all-targeted-results.json. QA не добавляется в Git. Сборка и проверки готового пакета успешно завершены; итог ниже.

### Итоговая сборка после исправления периодических фризов

Windows Release export завершён 2026-10-05 в 21:39 (Europe/Moscow), exit 0. Готовый PCK: **275751352** байт, SHA-256 `674b6668e8ec324f81a9f98ffa2d3da477548634e44f79d910446da185ef7eda`. EXE: 109127680 байт, SHA-256 `4a9eaded8955ef789ab02651ed9d2dde80328fbb342bd2a6db4db33e86305668`. Нативная DLL: 686592 байт, SHA-256 `70c2c875cc51be9aeabbd6a9b1bafb211edc718d77a209af84e12941ae9e3afc`; prototype/bin, distribution root и distribution/bin идентичны.

Из нового PCK с Godot 4.7.2 и корректным --path distribution выполнены шесть файлов: detached topology registry, source campaign build-site demand, terrain change invalidation, threaded build sites, gameplay presentation render contract и generated environment landscape. **6 passed / 0 failed / 0 engine errors**. Штатный Release EXE, prototype_skirmish, --headless, 600 кадров: exit 0, ошибок 0.

Сборка: dist/Rise of Rome Prototype/. Локальные журналы и метаданные: prototype/qa/periodic-release-build.log, periodic-release-artifacts.json, periodic-packaged-results.json, periodic-packaged-*.log, periodic-packaged-smoke.log. Итог исходного проекта: 40 разных целевых файлов (43 выполнения), все прошли; полный suite повторно не запускался.
