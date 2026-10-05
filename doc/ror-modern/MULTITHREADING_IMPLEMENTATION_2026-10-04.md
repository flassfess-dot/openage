# Реализация многопоточной оптимизации

Дата: 2026-10-04. Первоначально реализованы этапы 1–9; после игровых регрессий этап 4 по умолчанию отключён и требует переработки. По последующему указанию пользователя выполнены полный suite (325/22), исправления и отдельный повтор всех падений со связанными проверками (30/0), см. [тестовый отчёт](MULTITHREADING_TEST_RESULTS_2026-10-04.md). Replay/save hashes совпали в проверенных сценариях. Основания приоритетов остаются в [плане](MULTITHREADING_OPTIMIZATION_PLAN.md), [E6 baseline](PERFORMANCE_BASELINE_E6.md) и существующих обзорах. Новые baseline не собирались; прирост FPS не заявляется. Последующая диагностика игровых регрессий и ограниченные визуальные проверки описаны в конце документа.

## Этапы и границы публикации

| Этап | Реализация | Владелец и барьер |
|---|---|---|
| 0 | Использованы существующие отчёты; новые измерения пропущены по указанию пользователя. Добавлены диагностические времена capture, worker и wait; отделены этапы navigation и demand filter в наблюдении ИИ. | Probe изменяется только владельцем; новые показатели не являются результатом замера. |
| 1 | `isolated_task_data.gd`, `isolated_task_coordinator.gd`: проверка вложенного DTO, копирование, рекурсивная фиксация topology, envelope, generation/revisions, bounded submit/collect/invalidate/shutdown. | Вход и результат без Object/Resource/Callable/RID/Signal. Executor и его частный планировщик остаются за пределами DTO. Результат читается после `wait_for_task_completion`. |
| 2 | `build_site_task.gd` и `SimulationWorld.get_cached_local_build_sites`: независимые виды зданий и последовательные группы рабочих с отдельными планировщиками. | Preferred → ID рабочих → row-major кольца; good sites объединяются перед gap fallback. Strict preferred не дробится. Demand filter и остановка на первой подходящей строительной цели сохранены. Слияние site caches выполняет мир до решения ИИ. |
| 3 | `ai_planning_task.gd`, `main.gd::queue_ai_commands`: частный AiPlayer с копией observer snapshot, настроек и canonical state. | Наблюдение и память fog обновляются в порядке игроков. Несколько due players планируются параллельно; один остаётся последовательным. Состояние и proposals применяются в порядке ai_players, до прежнего fixed tick. Sequence/replay назначает контроллер. |
| 4 | `presentation_publication.gd`: опциональные detached слоты без повторной проекции уже подготовленных DTO. По умолчанию выключено после воспроизведения игровых регрессий; стандартный путь использует прежний retained snapshot. | Полный переданный контракт сохраняется, прежние опубликованные словари отделены. Повторное копирование overview/исследованного леса оказалось дорогим; текущий вариант этапа 4 не считается подтверждённой оптимизацией. |
| 5 | `navigation_loading.gd`, `navigation_preparation_task.gd`: подготовка world и learned grids, native masks, исходных surface labels и native clearance labels. | Пока идёт подготовка, активные ticks и игровой ввод остановлены, отображается «Подготовка карты…». Ревизии всех результатов проверяются, затем весь набор публикуется. Устаревший набор переснимается. Learned grid сохраняет оптимистическую проходимость неизвестных клеток. |
| 6 | `Pathfinder.find_paths_batch`, `NavigationService.request_paths`: частные A* contexts с общими immutable native masks/connectivity. Пакетный путь подключён к обычному массовому move. | Отмена прежних задач и endpoint reservations последовательны; поиск выполняется между подготовкой и применением. Request IDs и результаты применяются по исходному порядку. Переносятся только новые записи route cache. У границы вытеснения кэша используется последовательный путь. Зависимые formation/attack/gather/transport назначения сохранены. |
| 7 | `native_movement_task.gd`, `Pathfinder.prepare_native_movement_batch`: numeric native calculation для обычных move, по конфигурациям и крупным группам. | Общий native snapshot не меняется до завершения всех задач. C++ scratch соседей — thread_local. Перед использованием velocity повторно сверяются target, speed, cohesion, delta и revision. Integration, arrival, repath, facing, reservations, экономика и посадка выполняются в исходном цикле. |
| 8 | `threaded_texture_queue.gd`, `unit_presentation_registry.gd`: дедупликация загрузки по реальному пути через ResourceLoader; публикация base/composite состояния после готовности всех кадров. | `load_threaded_get` вызывается после LOADED. Общие пути удерживаются до публикации всех использующих их запросов. Initial match prewarm сохранён синхронным; новые состояния во время игры используют уже готовый idle fallback. Animation clock и симуляция не ждут I/O. |
| 9 | `background_save_queue.gd`, `background_save_task.gd`: отделённый world/controller/AI/replay/view capture, затем упаковка checkpoint и запись в worker. | Capture/hash выполняются на главном потоке на завершённом tick. Записи FIFO, включая один и тот же слот; используются исходные temp/backup/rename правила. Успех сообщается после записи. Load/reset/exit завершают очередь. Публичный `save_game_to_path` для прямых инструментальных вызовов остаётся синхронным. |

Нативный модуль получил `create_search_context`, `connectivity_labels` и `install_connectivity`. Mask использует copy-on-write при topology patch; компоненты разделяются как const vectors, а costs/parents/seen/frontier принадлежат отдельному context. Порядок A*, smoothing и numeric movement алгоритмы не заменялись.

## Переключатели и ограничения

В `prototype/project.godot`, секция `[ror_threading]`: `enabled`, `ai_observation`, `ai_planning`, `presentation`, `navigation_prepare`, `navigation_paths`, `movement`, `animation_loading`, `save`. Все включены, кроме `presentation`: этап 4 отключён после выявленной регрессии; подробности в конце документа. Для возврата к последовательной реализации — `enabled=false` или пользовательский аргумент `--ror-sequential` после разделителя `--`. Отдельные флаги позволяют отключать подсистемы независимо. Scheduling/generation/task IDs не включены в canonical state.

- Координатор: до 8 незабранных задач на экземпляр; обычные ordered waves — до 4 задач с учётом количества CPU. Уже существующие terrain tasks используют тот же Godot pool.
- Immutable DTO registry: до 12 корней; доверие проверяется по идентичности readonly корня, а не только по маркеру. Вложенные циклы и чрезмерная глубина отклоняются.
- Topology копируется при изменении grid/revision и повторно используется между пакетами. Native contexts создаются только для необходимых domain/restriction.
- Базовые A* массивы на группу ограничены расчётным бюджетом 64 MiB, учитывающим количество конфигураций; превышение даёт последовательный fallback. Frontier, topology DTO и до 16 connectivity radii на kernel требуют дополнительной памяти; это не общий лимит RSS.
- Пакетные routes: от 4 запросов, при доступном native kernel и запасе route cache. При отсутствующей DLL сохранён исходный GDScript расчёт.
- Movement: от 64 подходящих ordinary move; formation/shared motion, open envelopes и arrival из пакета исключены.
- Опциональная publication держит два detached снимка. Рабочая игра использует прежний retained render cache с retirement удалённых ID.
- Animation: до 8 active loads, 512 queued paths и 32 pending states. Состояния не загружаются для всех типов заранее. Глубина отдельного состояния ограничена каталогом ресурсов.
- Save: одна активная запись и одна ожидающая; переполнение возвращает понятную ошибку. При выходе незавершённые записи дожидаются завершения.

Submit failure/некорректный authoritative result вызывает последовательный расчёт в прежнем месте. Invalid generation/revision не публикуется. Invalidate не отменяет уже исполняющийся Callable: shutdown/reconfigure обязательно забирают Task IDs. ResourceLoader не предоставляет отмену начатой загрузки; registry drain дожидается ready/failure и освобождает результаты.

## Написанные тесты

В `prototype/tests/unit/` добавлены девять файлов, включаемых существующим автоматическим обнаружением suite:

- `test_isolated_task_coordinator.gd`: изоляция, forged seal/readonly nesting/cycle, обратное завершение, fallback, stale generation/revision, overflow, reconfigure/shutdown.
- `test_threaded_build_sites.gd`: сравнение ordered sites с исходным методом, берег, несколько рабочих, strict preferred/gap, мобильные препятствия и fog.
- `test_threaded_ai_planning.gd`: proposals, tick/state, cadence, отключённый и побеждённый игрок.
- `test_presentation_publication.gd`: выбранные command options, отделённые entities/fog/overview, удаление ID, повторное использование retained слотов без изменения старого кадра.
- `test_threaded_navigation_preparation.gd`: mask/surface labels, optimistic unknown cells, stale revision.
- `test_threaded_path_batches.gd`: исходные ordered paths, выключенный режим и COW context при patch владельца.
- `test_threaded_movement_batches.gd`: обычное движение 80 юнитов и обход результата после смены цели.
- `test_threaded_animation_loading.gd`: duplicate request, общие frame paths, composite publication, missing state и shutdown.
- `test_background_save_queue.gd`: FIFO одного слота, захват до дальнейших изменений мира, overflow, DTO rejection и чтение архива.

При первой сборке в 22:09 тесты ещё не запускались по первоначальному указанию пользователя; использовалась только компиляция `--check-only`. Затем по новому указанию пользователя выполнены все 347 тестов и отдельный повтор выявленных падений. Все девять новых unit-файлов прошли на исправленном коде. В `test_threaded_path_batches` добавлены проверки переноса observations/counters/cache hits, в `test_isolated_task_coordinator` — readonly root и повторной фиксации. Golden files не обновлялись. Подробности: [результаты тестирования](MULTITHREADING_TEST_RESULTS_2026-10-04.md).

## Сборка и границы подтверждения

Сборка выполняется `tools/build-game.ps1`: CMake/MinGW native DLL, Godot import и Windows Release export. Этот скрипт не запускает тесты. Движок — Godot 4.7.2 `ed1daf0bf`; godot-cpp — pinned `507ed9d840c01a3c5b2a39af8bb4000bfac30bf5`, API 4.7, float64.

Итоговый EXE/PCK/DLL находятся в `dist/Rise of Rome Prototype/`. Результат сборки и SHA-256 записаны ниже. Локальные журналы компиляции/сборки находятся в `prototype/qa/threading-*.log` и исключены из Git.

Тестовые критерии подтверждены в пределах [пройденного покрытия](MULTITHREADING_TEST_RESULTS_2026-10-04.md), включая replay/save continuation и canonical hashes. Визуальные критерии и существующие paired Release workloads по отдельным переключателям остаются вне выполненного прогона. Числовых заявлений об ускорении этого пакета нет.

Первая сборка завершена успешно 2026-10-04 в 22:09 (Europe/Moscow), код выхода 0. Godot import и Windows Release export выполнены. После неё полный suite включал проверку карт в этой упакованной игре. Ниже сохранены размеры и хеши первой сборки; итог пересборки после исправлений записан в тестовый отчёт.

| Файл | Размер, байт | SHA-256 |
|---|---:|---|
| Rise of Rome Prototype.exe | 109127680 | `4a9eaded8955ef789ab02651ed9d2dde80328fbb342bd2a6db4db33e86305668` |
| Rise of Rome Prototype.pck | 275721172 | `393bfab80f7883f4a928c68452be2e6ab19426432a47905b38665fa15dfade87` |
| ror_pathfinding.windows.template_release.x86_64.dll | 686592 | `fd2f330cd2c4b689f41d8399ab6d1b120f054250cd96ce13cd23159bd6cf308e` |

DLL в корне distribution, в `bin/` и в исходном `prototype/bin/` совпадают. Изменённые игровые скрипты и девять новых тестовых файлов скомпилированы без SCRIPT/Parse/Compile errors в режиме `--check-only`. C++ build выдаёт warning из заголовка godot-cpp о неподдерживаемом диагностическом pragma MinGW; target успешно собран.

Обновлённая сборка после исправлений завершена 2026-10-04 в 23:20 (Europe/Moscow), exit 0. PCK: 275724264 байт, SHA-256 `f3e27674bd7f8f623cccc4e3c3d40d638091841fed740e8a9898cdfc84c366d4`; DLL: 686592 байт, SHA-256 `b8752911c1ea0c1e405aa1640e2fa06614ed30dc3773343d56281de91653d2e4`. Штатный packaged skirmish запуск на 300 кадров прошёл с exit 0 без SCRIPT/engine errors. Полные сведения: [тестовый отчёт и актуальная сборка](MULTITHREADING_TEST_RESULTS_2026-10-04.md).

## Исправление игровых регрессий после оптимизации

2026-10-04, после сообщения пользователя о нарастающих задержках, готовых горящих фундаментах и обеднённом ландшафте.

Причины воспроизведены отдельно от полного suite:

- Вторичная проекция уже компактного building DTO определяла здание как юнит: в таком DTO отсутствует production_queue. Терялись state и construction_stage, а низкий HP фундамента включал damage overlay готового здания.
- Поля environment_asset/environment_variant/tree_condition терялись и в retained render cache, используемом памятью ресурсов, и в новой publication. Прямой тест _compact_render_entity эту игровую цепочку не покрывал.
- Новая publication заново копировала подготовленные entities, fog, overview и исследованные ресурсы миникарты. Стоимость росла с исследованной областью. Этап 4 по умолчанию отключён (ror_threading/presentation=false); рабочая игра использует прежний retained snapshot. Остальные переключатели сохранены. Опциональная publication теперь переносит полный DTO без повторной классификации/обрезки.

Диагностика sync_world_state на одной карте 400×400, seed 41721, два игрока, по 30 обновлений на вариант: p50 нового пути до исправления 12,311 мс в начале и 28,524 мс после полного открытия, прежнего пути 3,796 и 2,235 мс соответственно. p95 при открытой карте 72,473 против 3,278 мс; первый полный перенос известного леса дал 4235,691 мс. Это CPU-время подготовки снимка в исходном проекте, не FPS и не новый performance baseline. Последовательность вариантов и первичное заполнение кэшей ограничивают прямое сравнение максимумов.

Повторно пройдены 16 отдельных файлов: presentation publication, новый gameplay render contract, resources, building registry/golden, simulation snapshot, generated environment landscape, coordinator, environment pack, long-session contracts, tree lifecycle, random-map ecology/landscape, worker regressions, panned static projection, core building age pipeline. Новый интеграционный тест до исправления выявил 12 ошибок контракта, после — 0. Golden files не изменялись. Полный suite второй раз не запускался; теперь автоматическое обнаружение включает 348 файлов.

Generated-environment test дополнен проверкой реальной цепочки generation → bootstrap → retained fog memory → gameplay snapshot → publication в обоих режимах и при повторном использовании слотов: точное количество/координаты деревьев, их species/variant/condition и конечный asset/frame. Физические бюджеты и алгоритмы генератора не менялись.

Дополнительно выполнены четыре минуты ускоренной реальной coastal-партии (4800 ticks): 77–78 юнитов, память 509,17 → 511,79 MiB; p95 snapshot по минутам 2,913 / 1,288 / 1,929 / 2,635 мс. Проверка ограничена этой партией и не подтверждает производительность всех карт/популяций. Оконные захваты реальной игры проверены для grasslands/highlands/islands и четырёх construction stages/complete.

Локальные результаты: prototype/qa/diagnose_presentation_cost.log, presentation-render-contract-before.log, regression-*.log, threading-regressions-long-match.json, threading-regression-visuals/, threading-regressions-release-build.log. QA исключена из Git. Итог обновлённой сборки приведён ниже.

## Итоговая сборка после игровых регрессий — 2026-10-05

Windows Release собран успешно (exit 0). Итоговый пакет: 275727820 байт, SHA-256 7f540a78ab23f240e1249785478c2f48d9f06f6e9d942063991aec3eb0bb7a1f. EXE: 109127680 байт, SHA-256 4a9eaded8955ef789ab02651ed9d2dde80328fbb342bd2a6db4db33e86305668. Нативная DLL: 686592 байт, SHA-256 de2f80cf963866ebcd15a650c074897b3d532476a27be80148f7cf01df3de87d; исходная, корневая distribution и bin-копии совпадают.

Штатный Release EXE: prototype_skirmish, headless, 600 кадров — exit 0, ошибок 0. Дополнительно из готового PCK с Godot 4.7.2 выполнены test_presentation_render_contract и test_generated_environment_landscape — 2 passed / 0 failed, ошибок загрузки native extension 0. Для --main-pack задан --path каталога distribution; запуск движка из каталога репозитория без этого параметра сначала не нашёл относительную native DLL. Прямой запуск integration script через Release EXE из корня репозитория не завершился и остановлен; это не засчитано как прохождение. Чистые окончательные проверки PCK находятся в packaged-regression-*-fixed.log.

Файлы: dist/Rise of Rome Prototype/. Журналы: prototype/qa/threading-regressions-release-build.log, threading-regressions-packaged-smoke.log, packaged-regression-test_presentation_render_contract-fixed.log, packaged-regression-test_generated_environment_landscape-fixed.log. Размеры/хеши: prototype/qa/threading-regressions-release-artifacts.json. Целевые проверки исходного проекта: 16 passed / 0 failed; отдельные проверки пакета: 2 passed / 0 failed. Новые performance baseline не создавались.

## Периодические фризы — 2026-10-05

Пользователь сообщил о фризах всей игры примерно раз в две секунды с начала матча. Диагностика нашла две независимые причины.

1. FIFO-реестр readonly DTO в isolated_task_data.gd забывал часто используемую топологию после 12 новых transient snapshots. Последующие submit на главном потоке снова рекурсивно проверяли всю карту: около 750–800 мс на одну группу рабочих. В Birth of Rome с шестью source_campaign_v1 противниками решения повторяются через 40 ticks; суммарный build-site участок занимал 2–5 секунд. Реестр стал LRU: подтверждённый корень продвигается при каждом использовании, лимит 12 и проверка точной identity сохранены. Чужие маркеры, Object/Callable и циклы по-прежнему отклоняются.
2. Изменение материала клетки после вырубки дерева увеличивало terrain_revision и сбрасывало весь world fog mask, slope cache и terrain mesh, в том числе для деревьев за экраном. В оконном прогоне после первой починки это давало повторные mask updates 548–591 мс и camera/terrain updates 315–337 мс. Эти пики продолжались после отключения ИИ. Fog/edge geometry теперь зависит от версии высот; материал земли не пересоздаёт туман. Версия высот меняется также при checkpoint restore.

Дополнительно source campaign observation запрашивает только жилищную потребность и первое незавершённое building entry, если есть принимающий эту команду idle land builder. Незавершённые unit/research entries блокируют последующие здания как прежде. Общие housing/target-count helpers используются и фильтром, и исходным планировщиком. Порядок source build order, координаты выбранных площадок, wall/gate geometry и команды проверены сравнением с нефильтрованным snapshot. Один фактический вид здания рассчитывается последовательно с ранним выходом; нет захвата полной карты и спекулятивных групп рабочих. Несколько независимых видов сохраняют worker-путь.

SimulationWorld хранит нерасходуемый журнал последних 256 изменений материала для независимых потребителей. TerrainCanvas сохраняет mesh при изменениях вне его bounds с соседним поясом. Внутри видимой области legacy renderer пересчитывает только изменённые tiles и их восемь соседей; numeric native cache инвалидирует только изменённые material samples. Оба кэша ограничены текущей областью. Новые partial meshes совпадают с fresh full build по всем массивам геометрии. При неизвестном/переполненном журнале или изменении высот выполняется полный refresh; устаревшие async результаты не публикуются.

Подробные результаты, границы диагностики и актуальная сборка — в [тестовом отчёте](MULTITHREADING_TEST_RESULTS_2026-10-04.md#периодические-фризы--2026-10-05).

Обновлённая Windows Release-сборка завершена 2026-10-05 в 21:39, exit 0. Шесть проверок нового PCK и штатный EXE smoke на 600 кадров прошли без ошибок. Точные размеры/хеши и журналы приведены в тестовом отчёте; готовая игра находится в dist/Rise of Rome Prototype/.
