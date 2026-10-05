# План многопоточной оптимизации Rise of Rome

Дата: 2026-10-04. Статус: этапы 1–9 реализованы; полный suite дал 325 passed / 22 failed, после исправлений отдельный повтор всех 22 падений и восьми связанных проверок дал 30 passed / 0 failed. [Результаты проверки](MULTITHREADING_TEST_RESULTS_2026-10-04.md). Новые эталоны и парные performance-замеры не собирались. Подробная передача: [реализация 2026-10-04](MULTITHREADING_IMPLEMENTATION_2026-10-04.md).

Документ предназначен для агента, который будет внедрять многопоточность в Godot-прототипе из prototype/. Цель — уменьшить периодические задержки главного потока и улучшить масштабирование активного матча, сохранив игровые правила, частоту симуляции, порядок команд, туман войны, сохранения и воспроизводимость повторов. libopenage/ является отдельным движком и не является основной целью этого плана.

Первая очередь — подготовка данных ИИ, планирование ИИ и подготовка данных отображения. Первичную подготовку навигации и загрузку анимаций можно улучшать отдельными пакетами. Пакетный поиск путей и расчёты движения имеют более высокий риск и следуют после подготовки безопасных границ данных и подтверждения нагрузки на больших армиях.

В описаниях этапов пути scripts/ и tests/ отсчитываются от prototype/, а native/, tools/ и doc/ — от корня репозитория.

## Основания и ограничения измерений

Изучены [исторический обзор производительности](PERFORMANCE_REVIEW_2026-09-28.md), [обзор периодических подвисаний](PERIODIC_STUTTER_REVIEW_2026-09-28.md), [архитектура исправлений тяжёлого сохранения](STUTTER_ARCHITECTURE.md), [кампания измерений E6](PERFORMANCE_BASELINE_E6.md) и текущие исходники. Не следует повторно реализовывать уже выполненные исправления.

Наиболее свежий использованный профиль — prototype/qa/heavy-save-analysis/measurement-orders-release-ai.json от 2026-10-04. Матч восстанавливается с такта 103578 на карте 400×400: 127 юнитов, включая животных, 70 зданий, 9016 ресурсов, три игрока, лимит населения 500. После 40 начальных обновлений измерены 1000 обновлений с активным ИИ. orders-release-validation.json сообщает debug=false, editor=false и успешную загрузку точного сохранения. Эти QA-файлы исключены из Git и могут отсутствовать у следующего агента.

| Метрика | Выборок | Среднее, мс | p95, мс | Максимум, мс |
|---|---:|---:|---:|---:|
| controller.fixed_tick | 1000 | 17,132 | 44,413 | 83,910 |
| presentation.ai.snapshot | 100 | 21,944 | 31,844 | 34,820 |
| presentation.ai.snapshot.build_sites | 100 | 13,967 | 21,673 | 28,524 |
| presentation.ai.snapshot.buildings | 100 | 6,538 | 9,869 | 14,668 |
| presentation.ai.plan | 100 | 7,511 | 11,914 | 16,898 |
| presentation.sync.snapshot | 1000 | 8,922 | 10,842 | 18,931 |
| presentation.local.snapshot.resources | 1000 | 4,063 | 5,307 | 12,436 |
| presentation.local.snapshot.buildings | 1000 | 3,623 | 4,547 | 9,308 |
| navigation.path_query | 505 | 0,451 | 1,705 | 10,590 |
| simulation.movement.local_calculation | 1000 | 0,212 | 0,297 | 1,558 |

Это CPU-измерения, а не FPS. Подготовка ИИ измеряется только в такты решений, а не в каждый такт. Вложенные метрики и их процентили нельзя складывать. Этап presentation.ai.snapshot.build_sites сейчас включает также состояние игрока и навигационные знания между двумя отметками времени в ai_observation_store.gd. Все 21,673 мс нельзя приписывать собственно поиску площадок. Таймер simulation.movement.neighbor_query также включает работу до непосредственного запроса соседей, в том числе получение планировщика знаний.

В measurement-orders-release-cold.json первые 40 обновлений содержали пик 1568,728 мс; максимальное построение native mask — 508,747 мс. Четыре вызова подготовки ИИ в этом коротком окне дали максимум 1019,881 мс, её этап build_sites — 985,125 мс. Это свидетельство холодных задержек, а не надёжная оценка стационарного p95. Максимумы нельзя суммировать: они могут относиться к разным вызовам и вложенным этапам.

Перенос задачи в фон освобождает главный поток, но сам по себе не уменьшает суммарную работу CPU. Ускорение вычисления возникает при независимой параллельной обработке или устранении лишней работы. Прирост FPS требует видимого сравнительного прогона.

## Порядок и зависимости этапов

| Этап | Результат | Зависимость | Приоритет |
|---|---|---|---|
| 0 | Актуальный baseline и отдельные измерения владельцев нагрузки | Нет | Обязательный |
| 1 | Изолированные данные задач и управляемый жизненный цикл | 0 | Обязательный |
| 2 | Параллельная подготовка данных ИИ и площадок | 1 | Первый |
| 3 | Планирование разных ИИ в независимых задачах | 1 и контракт снимка из 2 | Первый |
| 4 | Подготовка отображения из опубликованных данных | 1 | Второй |
| 5 | Предварительная подготовка навигации при загрузке | 1 | Высокий для стартовых задержек |
| 6 | Пакетные независимые запросы маршрутов | 1 и изоляция рабочих буферов ядра | После нового профиля |
| 7 | Пакетные расчёты локального движения | 1 и изоляция рабочих буферов ядра | Для больших армий |
| 8 | Фоновая загрузка анимаций | 0 и отдельный контракт загрузчика | Для разовых рывков |
| 9 | Фоновая упаковка и запись сохранения | 1 | Дополнительный |

Начинать с 0 и 1, затем 2 и 3. Этап 4 требует отдельного пакета из-за смены владения данными. Этапы 5 и 8 не обязаны ждать завершения 4. Для 6 и 7 сначала оценить актуальную стоимость и память: в исследованной партии local calculation занимает менее 0,3 мс p95. Не включать все переключатели сразу, пока не измерен вклад каждого этапа.

Этап 0: по указанию пользователя использованы существующие эталоны, новые замеры пропущены. Этапы 1–9 реализованы; по следующему указанию пользователя выполнены полный suite и отдельный повтор исправленных падений, см. [тестовый отчёт](MULTITHREADING_TEST_RESULTS_2026-10-04.md). Проверки детерминизма подтверждены в пределах пройденных сценариев. Парные performance-замеры и визуальные критерии остаются отдельными неподтверждёнными gates; ускорение не заявляется. Подробности и границы реализации: [передача результатов](MULTITHREADING_IMPLEMENTATION_2026-10-04.md). Сам план не меняет общую очередь [дорожной карты проекта](../DEVELOPMENT_ROADMAP_ROR_PARITY.md).

## Общие правила реализации

1. Авторитетное состояние мира имеет одного владельца. Worker получает собственные неизменяемые входные данные и пишет только собственный результат. Он не вызывает методы живого SimulationWorld, GameController, общего Pathfinder, SceneTree, HUD или общего performance probe.
2. Вход содержит только необходимые скаляры, ID, векторы, числовые массивы и отделённые структуры. duplicate(true) не доказывает изоляцию, если внутри остались Object, Resource, Callable или общие retained-проекции. Проверять вложенное содержимое и владение.
3. Минимальный конверт задачи: тип, монотонный request ID, generation матча, source tick, назначенный apply tick, team/domain/restriction при необходимости и ревизии зависимостей. Результат содержит тот же конверт, данные, статус и локальные метрики. Scheduling-поля не входят в canonical state.
4. Generation меняется при замене или загрузке матча. Результат другого поколения не публикуется. Для навигации проверяются топология, радиус, домен и ограничение; для отображения — поколение, ревизия и актуальность камеры.
5. Авторитетные результаты применяются в прежнем логическом порядке, а не по очередности завершения потоков. Сохраняются порядок игроков, команд и EntityId, tie-break, порядок floating-point операций и состояние RNG.
6. Асинхронная готовность не определяет такт решения ИИ или движения. Первая реализация использует параллельный расчёт с барьером в прежнем месте применения. Расчёт наперёд требует отдельного доказательства совпадения входа. Нельзя молча сдвигать команду на следующий такт или пропускать её из-за занятости CPU.
7. Очередь задач ограничена. Для презентации разрешено заменить ещё не начавшийся устаревший запрос новым. Авторитетные запросы нельзя терять или переупорядочивать. Не ждать worker, удерживая блокировку общей очереди.
8. WorkerThreadPool уже обслуживает terrain refinement. Размер пакета и лимит задач выбирать по измерениям. Не создавать поток на юнита и не занимать весь пул мелкими заданиями. Буферы переиспользовать, когда доказан выигрыш.
9. Сначала сохранить последовательный эталон и fallback. Ошибка запуска или невалидный результат задачи приводят к исходному расчёту в том же месте и такте. Ошибка worker не означает игровой no_path или отсутствие решения.
10. Все задачи завершаются и освобождаются при выходе, смене карты, загрузке и reconfigure. Устаревшая задача может продолжать исполняться, но её результат отбрасывается; отмена результата не отменяет обязанность завершить и освободить задачу.
11. Частота 20 Гц, cadence игровых проверок, коллизии и fog остаются прежними. Перенос игровых правил в C++ не входит в этот план. Нативная реализация алгоритма и многопоточность — отдельные изменения.

Использовать официальные ограничения [thread-safe APIs Godot](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html), [WorkerThreadPool](https://docs.godotengine.org/en/stable/classes/class_workerthreadpool.html) и [background loading](https://docs.godotengine.org/en/stable/tutorials/io/background_loading.html). Работу с GPU и активными узлами оставить владельцу отображения. CPU-задачи возвращают массивы; создание и обновление текстур, установка mesh и UI выполняются после публикации. Общие изменения контейнеров требуют отдельного протокола синхронизации.

## Этап 0 Обновить измерения и эталон поведения

**Статус 2026-10-04:** существующие эталоны приняты по указанию пользователя; новые измерения и проверки не выполнялись.

**Задача.** Получить baseline именно той рабочей версии, которую агент будет менять. Сохранённые профили обосновывают приоритет, но не заменяют новое парное сравнение.

**Точки входа.** В prototype/: scripts/performance_probe.gd; main.gd::queue_ai_commands и sync_world_state; scripts/ai_observation_store.gd::observe; scripts/simulation_movement_system.gd::move_unit; tests/manual/benchmark_e6_runtime.gd, benchmark_e6_visible.gd, benchmark_large_random_match.gd, benchmark_long_random_match.gd.

**Реализация.** Зафиксировать версию движка, наличие и версию DLL, Release/debug/editor-флаги, исходное состояние checkout, карту/seed, команды, скорость игры, разрешение и видимую область. Сохранить baseline до изменений, не сбрасывая чужие незакоммиченные правки. Если тяжёлое сохранение недоступно, подготовить воспроизводимую фикстуру и явно отметить отличие.

Разделить текущий build_sites timer на navigation, demand_filter, candidate_scan, static_validation, dynamic_validation, reachability и обслуживание кэша. Отдельно измерить capture/copy входа, запуск задачи, CPU worker, ожидание, проверку результата и публикацию. Для движения выделить получение планировщика, revision checks, соседей и native calculation. Worker возвращает числа владельцу probe, не пишет в общий probe одновременно с другими задачами.

Для стационарного сценария использовать одинаковый прогрев и минимум 1000 измеряемых тактов; для редкого решения ИИ собрать не менее 100 вызовов. Короткий stress-прогон подходит для разработки, но не для вывода о длительных задержках. Cold load измерять отдельно. Итоговое сравнение делать в нескольких парных прогонах на одной машине; увеличивать число повторов только при заметном разбросе.

**Проверки.** test_performance_observability, test_deterministic_replay и test_checkpoint_resume. Сохранить последовательность команд и canonical state в контрольных тактах. Headless CPU и видимый кадр измерять раздельно.

**Завершение.** Есть исходный отчёт, фикстура и повторяемая команда запуска; реальные владельцы нагрузки отделены от вложенных таймеров. Установлены игровые и графические ожидания следующих этапов.

## Этап 1 Подготовить общий механизм изолированных задач

**Статус 2026-10-04:** реализовано; выполнены полный suite и отдельный повтор исправленных падений. Покрытие: [тестовый отчёт](MULTITHREADING_TEST_RESULTS_2026-10-04.md). Парные performance-замеры и визуальные критерии не подтверждены. См. [передачу реализации](MULTITHREADING_IMPLEMENTATION_2026-10-04.md).

**Задача.** Дать последующим этапам безопасный submit, collect, invalidate и shutdown без преждевременного переноса всего мира в отдельный поток.

**Точки входа.** scripts/native_terrain_mesh.gd::run и scripts/terrain_canvas.gd::_start_queued_refinement, _process, _finish_refinement — существующий образец detached numeric input и публикации. scripts/skirmish_generation_job.gd — существующий Thread генерации. Их поведение сохранить.

**Реализация.** Ввести небольшой координатор либо общий контракт нескольких узких координаторов. Конкретные имена новых файлов выбирает реализующий агент. Определить DTO и конверт из общих правил. Разделить задачи с барьером симуляции и презентационные задачи с допустимой поздней публикацией. Добавить выключаемые переключатели подсистем и последовательные fallback-пути.

Результаты писать в заранее выделенные индивидуальные слоты, объединять после завершения группы в заданном порядке. Не использовать один общий append из всех worker. Task ID Godot, generation матча и revision входа — разные поля. При отмене не считать, что уже исполняющийся Callable физически остановлен.

**Проверки.** Новые тесты координатора: обратный порядок завершения, выключенный worker, ошибка задачи, переполнение очереди, смена generation, reconfigure, shutdown, отсутствие незавершённых задач и deadlock. Сохранить test_async_terrain_mesh, test_terrain_prefetch и deterministic replay.

**Завершение.** Проходит lifecycle-набор; последовательный режим сохраняет baseline; переключатели не меняют игровой hash; память и очередь ограничены. Измерены расходы координатора до его использования в горячих циклах.

## Этап 2 Распараллелить подготовку данных ИИ и площадок

**Статус 2026-10-04:** реализовано; выполнены полный suite и отдельный повтор исправленных падений. Покрытие: [тестовый отчёт](MULTITHREADING_TEST_RESULTS_2026-10-04.md). Парные performance-замеры и визуальные критерии не подтверждены. См. [передачу реализации](MULTITHREADING_IMPLEMENTATION_2026-10-04.md).

**Задача.** Сократить дорогую подготовку перед решением ИИ. Этот этап должен работать и с последовательным планировщиком.

**Точки изменения.** scripts/ai_observation_store.gd::observe и _build_sites; scripts/ai_navigation_knowledge.gd::snapshot; scripts/simulation_world.gd::get_local_build_sites, get_cached_local_build_sites и _build_site_query_dependencies; scripts/simulation_building_placement_system.gd::cached_map_supports_foundation и reachable_builder_ids; scripts/simulation_snapshot.gd::requested_build_sites.

**Вход и выход.** Вход содержит observer visibility и память, позиции и ID доступных рабочих, числовую занятость и проходимость, footprint/placement profiles, запрошенные виды зданий и правила preferred sites. ИИ не получает сведения о скрытом мире сверх действующего observer-контракта. Выход — упорядоченные площадки по виду здания, подготовленные navigation data и локальные счётчики.

**Реализация.** Сначала перенести последовательный расчёт на DTO и доказать эквивалентность. Затем разбить проверки кандидатов на пакеты или независимые виды зданий. У кандидата есть стабильный порядковый индекс, воспроизводящий preferred sites, workers по ID и row-major ring scan. Слияние, de-duplication, maximum_per_kind, strict preferred kinds и fallback по structure gap выполняются по этому порядку. Ранняя готовность более позднего пакета не меняет выбор.

Сохранить demand filter и положительные/отрицательные кэши. site_map_cache, local_build_site_cache, ai_navigation_knowledge.entries, retained-проекции и last_build_failure остаются у одного владельца. Worker возвращает данные или дельту кэша, но не изменяет общие структуры. Не копировать мир для каждого кандидата: вход готовится один раз на решение.

Reachability использует изолированный планировщик или готовую связность; общий world.pathfinder в worker недопустим. Штатная авторитетная проверка Build сохраняется перед фактическим размещением. Первая версия использует вход и результат одного такта с барьером до collect_commands.

**Проверки.** test_ai_build_site_demand, test_ai_build_site_cache, test_ai_coastal_search, test_build_site_batch_queries, test_building_placement_regressions, test_ai_resource_projection, test_ai_navigation_failures. Имена существующих тестов проверять поиском в prototype/tests/; здесь расширение .gd опущено.

Добавить сравнение ordered results для пустого поиска, дока на берегу, нескольких рабочих, технологии, движения препятствия, удаления дерева, fog/revision changes и обратного завершения пакетов. Проверить отсутствие утечки скрытых сведений; сравнить принятые/отклонённые команды, состояние мира и ИИ.

**Завершение.** Выходы и игровой hash совпадают с эталоном. Полный путь capture → worker → wait → publish показывает сокращение решения или блокировки главного потока выше межпрогонного разброса. Ускорение только worker timer при более дорогом копировании не принимается.

## Этап 3 Планировать разных ИИ в независимых задачах

**Статус 2026-10-04:** реализовано; выполнены полный suite и отдельный повтор исправленных падений. Покрытие: [тестовый отчёт](MULTITHREADING_TEST_RESULTS_2026-10-04.md). Парные performance-замеры и визуальные критерии не подтверждены. См. [передачу реализации](MULTITHREADING_IMPLEMENTATION_2026-10-04.md).

**Задача.** Сократить последовательную волну решений нескольких игроков.

**Точки изменения.** main.gd::queue_ai_commands; scripts/ai_player.gd::needs_decision, collect_commands, canonical_state и restore_state; ai_economic_planner.gd, ai_support_planner.gd, ai_strategic_planner.gd, ai_tactical_planner.gd, ai_transport_planner.gd, source_campaign_ai_planner.gd; scripts/game_controller.gd::_run_fixed_tick и enqueue_command.

**Вход и выход.** Вход — отделённый observer snapshot, private state ИИ и назначенный decision tick. Выход — ordered command proposals и новое состояние ИИ: decision index, экономические/военные фазы, failed targets, source groups. Одновременно не запускать два решения одного игрока. collect_commands изменяет AiPlayer: изолировать только входной snapshot недостаточно.

**Реализация.** Сохранить needs_decision, интервалы и детерминированное разнесение первых решений. Выдать задаче отдельный планировщик или явно отделённое состояние. Внутри игрока сохранить navigation recovery → support/economy → tribute → transport/tactics, резервы рабочих/военных и бюджет. Делить эти зависимые этапы на потоки без доказательства нельзя.

Собирать due players в прежнем порядке ai_players и команды игрока в прежнем порядке. enqueue_command, sequence ID и replay recording выполняет владелец контроллера. У задач должен быть тот же логический момент наблюдения, что у baseline. Проверить порядок обновления world memory при наблюдении разных игроков. Retained-projection caches нельзя отдавать worker напрямую.

Первый вариант использует барьер до соответствующего fixed tick. При одном due player перенос может не ускорить tick: измерить wait и перекрытие. Отделение постоянного владельца симуляции от renderer возможно позднее отдельным пакетом; его нельзя заменить применением команды «когда готова».

**Проверки.** test_ai_player, test_ai_periodic_work, test_ai_command_pipeline, test_generated_skirmish_deterministic_outcome, test_ai_vs_ai_match, test_mixed_domain_ai_match, source campaign AI impact-набор, test_deterministic_replay и test_checkpoint_resume.

Добавить одинаковые commands/ticks/sequence IDs/AI state при одном и нескольких worker, обратное завершение, выключенный или побеждённый ИИ, ошибки, одновременные due decisions, загрузку и конец матча. Не строить baseline после отключения и одновременного возобновления просроченных ИИ: это искусственно синхронизирует их фазы.

**Завершение.** Совпадают authoritative trace и контрольные hashes. Уменьшается полное время волны нескольких решений; нет регрессии обычной партии и p95/p99 кадра. Если выигрыша на выбранной нагрузке нет, режим остаётся выключенным до подходящего measured workload.

## Этап 4 Подготовить отображение из опубликованных данных

**Статус 2026-10-04:** реализовано; выполнены полный suite и отдельный повтор исправленных падений. Покрытие: [тестовый отчёт](MULTITHREADING_TEST_RESULTS_2026-10-04.md). Парные performance-замеры и визуальные критерии не подтверждены. См. [передачу реализации](MULTITHREADING_IMPLEMENTATION_2026-10-04.md).

**Задача.** Убрать часть CPU-подготовки отображения из tick-кадра и создать безопасную границу между миром и рендером.

**Точки изменения.** main.gd::update_units, sync_world_state, current_world_drawables; scripts/simulation_snapshot.gd::presentation; scripts/render_entity_projection_cache.gd; scripts/render_world.gd::create_world_drawables и refresh_world_drawables; scripts/environment_presentation_field.gd; scripts/minimap_terrain_raster.gd.

**Реализация.** borrow_visible_render_entities и borrow_overview_entities сейчас допустимы только при последовательной работе на одном потоке. Перед worker заменить соответствующие ссылки компактными собственными записями. Использовать publication buffer, а не deep-copy всего мира каждый кадр. Начать с измеренных ресурсов и зданий; сохранить bounds, retained caches и инкрементальные revisions.

Симуляция публикует завершённый tick. Worker строит CPU-проекции, видимые ID, depth keys и numeric geometry. Главный поток читает только завершённый результат. Минимум два буфера с явным владением; буфер нельзя переиспользовать, пока его читает worker или потребитель. Два массива без протокола владения не исключают гонку.

Отделить данные мира от камеры. Новая камера может перепроецировать существующий snapshot. Camera-dependent результат проверяет generation/bounds и не устанавливается после нового запроса камеры. Selection, hover, HUD-команды, hit testing и production state должны опираться на согласованный опубликованный tick. Допустимую задержку представления определить и измерить отдельно от игрового решения.

Texture/frame lookup с возможной загрузкой, ImageTexture upload, ArrayMesh installation, UI и draw оставить главному потоку. Фоновая миникарта получает отделённые numeric terrain/fog samples, а не Callable к живой сцене. Presentation-запросы можно объединять с сохранением последнего. Gameplay visibility рассчитывается в штатном месте.

**Проверки.** test_simulation_snapshot, test_panned_static_projection, test_minimap_projection, test_unit_presentation_registry, building/naval presentation golden, fog boundary и render/projection impact-набор. Покрыть pan одновременно с publication, удаление/посадку юнитов, смену selection, быстрые minimap clicks, revisions, паузу и загрузку.

**Завершение.** Authoritative hash прежний; просмотрены кадры, выбор согласован с отображением, статики не «скользят». Видимый Release показывает сокращение tick-frame p95/p99 с учётом capture/publication. Память буферов ограничена в длительном матче.

## Этап 5 Подготовить навигацию до первого активного такта

**Статус 2026-10-04:** реализовано; выполнены полный suite и отдельный повтор исправленных падений. Покрытие: [тестовый отчёт](MULTITHREADING_TEST_RESULTS_2026-10-04.md). Парные performance-замеры и визуальные критерии не подтверждены. См. [передачу реализации](MULTITHREADING_IMPLEMENTATION_2026-10-04.md).

**Задача.** Уменьшить cold stalls после запуска и восстановления карты.

**Точки изменения.** scripts/navigation_grid.gd::native_walkability_mask и _build_surface_components; scripts/pathfinder.gd::prepare_native_kernels_for_units и _native_kernel_for; scripts/ai_navigation_knowledge.gd::snapshot; main.gd bootstrap/load; scripts/game_checkpoint.gd::restore.

**Реализация.** Во время загрузки снять numeric topology и список реально нужных domain/restriction/clearance configurations для world и learned navigation игроков. На изолированных данных подготовить маски и связность; независимые конфигурации считать параллельно. Публиковать готовый набор атомарно до первого active tick.

Номера компонент, порядок обхода, diagonals и blocked-origin escape совпадают с соответствующим текущим алгоритмом; не смешивать world и native connectivity contracts. При восстановлении использовать точную карту и learned-state сохранения. Не заменять знания игрока проходимостью скрытого мира.

Loading UI остаётся отзывчивым; worker не трогает SceneTree/GPU. Topology change инвалидирует результат; частичную маску не публиковать. Конфигурация, впервые появившаяся позднее, сохраняет корректный sync fallback и отдельное измерение.

**Проверки.** test_navigation_components, test_incremental_navigation_masks, test_sparse_navigation_masks, test_navigation_knowledge, test_water_navigation, native parity impact-набор, test_checkpoint_resume и test_game_save_load_pipeline. Включить острова, проходы, радиусы кораблей, patch и истёкший journal.

**Завершение.** После загрузки нет первого-tick построения уже известных конфигураций; уменьшены максимумы начальных updates. Измерены также полное время до готовности, отзывчивость UI и пиковая память. Перенос паузы в неизмеряемый участок загрузки не считается завершением.

## Этап 6 Выполнять независимые маршруты пакетами

**Статус 2026-10-04:** реализовано; выполнены полный suite и отдельный повтор исправленных падений. Покрытие: [тестовый отчёт](MULTITHREADING_TEST_RESULTS_2026-10-04.md). Парные performance-замеры и визуальные критерии не подтверждены. См. [передачу реализации](MULTITHREADING_IMPLEMENTATION_2026-10-04.md).

**Задача.** Сократить волны A* при массовом приказе и возврате работников. Нынешний p95 отдельного запроса сам по себе не доказывает приоритет этого этапа.

**Точки изменения.** scripts/pathfinder.gd::find_path, find_cell_path, _find_native_cell_path, _native_kernel_for; scripts/navigation_service.gd; scripts/simulation_movement_system.gd::assign_unit_destination; scripts/destination_reservations.gd; native/ror_pathfinding/src/ror_path_kernel.hpp и .cpp.

**Реализация.** Разделить immutable mask/connectivity data и mutable search context. Сейчас общие costs_, parents_, seen_generation_, frontier_, search_generation_, last_expanded_nodes_, last_path_was_direct_ и lazy components_by_radius_ исключают одновременный поиск на одном экземпляре. Каждый worker имеет собственный search context. Lazy connectivity готовится до группы или получает отдельный безопасный протокол. Mutex на весь поиск защищает от гонок, но сериализует работу.

Разделить назначение на последовательную подготовку endpoint/reservations, параллельный поиск и последовательное применение. ID запросов, nearest endpoint, слоты и конфликты назначает прежний владелец. Сохранить A* direction order, diagonal rule, heuristic/tie-break и smoothing. Route caches и counters обновляются после сбора, в прежнем порядке. Ограничить число/размер buffers: карта на каждый worker заметно увеличивает память.

Сначала использовать запросы одного стабильного этапа и барьер перед потребителем пути. Если между запросами меняется grid или endpoint dependency, такой поднабор остаётся последовательным. Семантика ожидания пути через несколько ticks этим планом не вводится.

**Проверки.** test_navigation_service, test_navigation_cache_coherence, test_navigation_command_pipeline, test_navigation_stress, test_destination_reservations, formation/gather/transport impact-набор и deterministic replay. Добавить concurrent direct/unreachable/long paths, разные радиусы/домены, topology patch во время задачи и обратный порядок завершения.

**Завершение.** Raw/smoothed paths, command trace и hash совпадают. На волне запросов уменьшается полное время назначения, маленькая команда не регрессирует, memory cap измерен. Изолированный быстрый A* при выросших capture/reservation/wait не считается успехом.

## Этап 7 Считать локальное движение пакетами

**Статус 2026-10-04:** реализовано; выполнены полный suite и отдельный повтор исправленных падений. Покрытие: [тестовый отчёт](MULTITHREADING_TEST_RESULTS_2026-10-04.md). Парные performance-замеры и визуальные критерии не подтверждены. См. [передачу реализации](MULTITHREADING_IMPLEMENTATION_2026-10-04.md).

**Задача.** Улучшить масштабирование плотных активных армий. Для малой партии сохранить последовательный порог, если scheduling дороже расчёта.

**Точки изменения.** scripts/pathfinder.gd::prepare_native_movement_snapshot и calculate_native_movement; scripts/simulation_world.gd::update_units; scripts/simulation_movement_system.gd::move_unit; native/ror_pathfinding/src/ror_path_kernel.cpp::calculate_movement.

**Вход и выход.** Основа — существующий per-tick snapshot позиций, радиусов, приоритетов и здоровья. Добавить отделённые target, speed/cohesion scale и delta для готовых запросов. Выход — velocity proposal, native state и число кандидатов по unit ID. Worker не пишет позиции, orders и reservations.

**Реализация.** movement_candidates_ изменяется каждым вызовом и становится private scratch worker. Shared movement buckets/mask заморожены на время группы. Сохранить сортировку соседей по ID и порядок арифметики. configure/update_walkable не могут выполняться параллельно с читателями.

Выделять только независимую numeric calculation после определения фактического движения. Нельзя заранее считать любое движение всех юнитов в начале tick: предыдущие задачи могут изменить цель, здоровье, приказ и топологию. Начать с доказанного независимого поднабора ordinary native movement. Shared formation translation, open envelopes и GDScript fallback сохраняются до отдельного доказательства.

После барьера применить результаты в исходном порядке active units. Position integration, map clamp, facing, arrival, waypoint, stuck recovery, repath, economy transitions, boarding/unloading и reservations остаются последовательными. Весь update_units нельзя превращать в параллельный foreach.

**Проверки.** test_local_movement, test_formation_interaction, native/movement snapshot impact-набор, test_stuck_recovery, test_destination_reservations, water navigation, gather/return, transport и formation lifecycle, deterministic replay. Покрыть смерть/смену приказа до apply, mixed domains и обратное завершение.

**Завершение.** Velocity/state/positions и canonical итоги совпадают с эталоном. Выигрыш доказан на больших all-active workloads; расходы в малой партии обходятся порогом. Floating-point отличие не принимать автоматически под предлогом многопоточности.

## Этап 8 Загружать новые анимации заранее в фоне

**Статус 2026-10-04:** реализовано; выполнены полный suite и отдельный повтор исправленных падений. Покрытие: [тестовый отчёт](MULTITHREADING_TEST_RESULTS_2026-10-04.md). Парные performance-замеры и визуальные критерии не подтверждены. См. [передачу реализации](MULTITHREADING_IMPLEMENTATION_2026-10-04.md).

**Задача.** Сократить разовые паузы первого появления состояния анимации без изменения simulation timing.

**Точки изменения.** scripts/unit_presentation_registry.gd::ensure_loaded, _load_team, _load_composite_parts, prewarm_units; scripts/resource_catalog.gd::prewarm_match_entities и unit_frame_info. Другие registries добавлять только после измерения.

**Реализация.** _load_team синхронно вызывает load() для PNG состояния. Ввести очередь ResourceLoader.load_threaded_request по реальному пути и de-duplication. Проверять load_threaded_get_status; get выполняется только после готовности, иначе снова блокирует. Ограничить requests, память и глубину prewarm; не грузить все состояния всех типов сразу.

Сохранить ключи civilization/team, enemy/neutral fallback, hotspots, graphic IDs, directions, mirroring, descriptors и composite parts. Публиковать состояние целиком после готовности частей. Временный visual fallback определить и проверить явно; animation clock, звук, атака и смерть не ждут I/O. Для полного визуального совпадения первого кадра prewarm выполняется заранее, а не путём пропуска кадра по готовности.

**Проверки.** test_unit_presentation_registry, test_resource_loading_policy, test_long_session_performance, animation direction/catalog и naval composite golden. Добавить duplicate request, error/missing resource, partial composite, смену матча и отсутствие blocking get на draw-пути. Проверить PCK и экспортированный runtime.

**Завершение.** В сценарии первого появления уменьшены stalls; память ограничена; fallback сохраняет facing/composite/lifecycle. Результат отделяется от FPS прогретого матча.

## Этап 9 Упаковывать сохранение после отделённого захвата

**Статус 2026-10-04:** реализовано; выполнены полный suite и отдельный повтор исправленных падений. Покрытие: [тестовый отчёт](MULTITHREADING_TEST_RESULTS_2026-10-04.md). Парные performance-замеры и визуальные критерии не подтверждены. См. [передачу реализации](MULTITHREADING_IMPLEMENTATION_2026-10-04.md).

**Задача.** Дополнительная отзывчивость при сохранении. Обычные игровые такты этот этап не ускоряет.

**Точки изменения.** main.gd::save_game_to_path; scripts/game_checkpoint.gd::capture и pack; scripts/game_save_archive.gd::create и write; scripts/replay_system.gd.

**Реализация.** На границе завершённого tick захватить согласованные world/controller/AI/replay/view данные. Убедиться, что capture не разделяет изменяемые массивы и Object с продолжающейся симуляцией. После передачи исключительного владения worker выполняет serialization, SHA-256, ZSTD, base64 и запись временного файла.

Успех показывается после завершения записи и штатной атомарной установки результата. Сохранить версии, checksum и backup/overwrite rules. Несколько saves одного слота имеют последовательный порядок. При закрытии завершить запись или сохранить прежний валидный архив. Не захватывать hash одного tick и checkpoint другого. Capture/hashing живого мира нельзя переносить в worker без изоляции.

**Проверки.** test_game_save_archive, test_game_save_state_matrix, test_game_save_load_pipeline, test_checkpoint_resume и test_p14_replay_save_hash_matrix. Добавить save при продолжающейся симуляции, ошибку записи, два запроса слота и выход во время записи.

**Завершение.** Архив восстанавливает состояние и continuation нужного tick; прежний файл доступен при ошибке; уменьшена блокировка UI с учётом capture. Если capture остаётся основным владельцем, измерить и описать его отдельно.

## Участки вне первой очереди

- terrain_canvas.gd уже отправляет полную детализацию в WorkerThreadPool, проверяет generation/revision/bounds и устанавливает результат в главном потоке. skirmish_generation_job.gd уже использует Thread генерации карты. Не предлагать их как новую многопоточность.
- combat_awareness_system.gd::collect_commands увеличивает assigned[target_id] после каждого выбора, влияя на следующее решение. Независимый параллельный выбор целей изменит поведение. Допустима подготовка candidate sets с последовательным финальным выбором после отдельного профиля.
- Vision footprint уже нативный; свежий simulation.fog.vision_cells — около 0,27 мс p95. Gameplay overlap counts, alliances, explored history и revisions не являются первыми кандидатами. Presentation fog/minimap rasterization оценивается внутри этапа 4 отдельно от gameplay fog.
- Перенос всей симуляции в один постоянный поток возможен после этапа 4, но требует устранения прямых обращений ввода, презентации, сохранений и сети к миру. Это отдельный архитектурный пакет, а не вызов advance_frame из worker. Само выделение потока не ускоряет tick.

## Проверка производительности и выпуск

Внутри этапа запускать адресные unit/integration/scenario проверки владельцев и прямых потребителей. Новый тест проверяет гонку, порядок, lifecycle или игровой контракт, а не повторяет реализацию. Полный suite, cache validation и Windows export выполняются на границе крупного пакета; сквозная смена simulation/data contract требует полного impact gate.

Ниже примеры существующих команд из корня репозитория. Они предназначены для будущей реализации и не выполнялись при сохранении плана. На другой машине сначала проверить путь движка и DLL.

~~~powershell
# Один адресный тест.
& '.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path prototype --script res://tests/unit/test_ai_build_site_cache.gd

# CPU workload. Эталон запускать с теми же параметрами.
& '.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path prototype --script res://tests/manual/benchmark_e6_runtime.gd -- --case=threading-mixed-2p --workload=mixed_match --players=2 --units-per-player=500 --map-side=400 --warmup-ticks=100 --sample-ticks=1000 --output=res://qa/performance/threading-mixed-2p.json

# Большая карта с реальным рендером и скачками камеры.
& '.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' --path prototype --script res://tests/manual/benchmark_large_random_match.gd -- --rendered --ticks=1400 --output=res://qa/performance/threading-large-visible.json

# Smoke. Baseline не перезаписывать без парного сравнения.
powershell -ExecutionPolicy Bypass -File tools/ror-performance-smoke.ps1

# Полный suite на границе пакета.
& '.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path prototype --script res://tests/test_suite.gd
~~~

mixed_match проверяет активные системы, но не заменяет измерение стратегических решений реальных AI players. Для этапов 2 и 3 воспроизводить тяжёлое сохранение или main-scene матч с включённым ИИ. Для 6 и 7 сравнивать formation_march, individual_crossing, combat_contact, gather_economy и mixed_match на 2/4/8 игроках по 500 юнитов после устранения подтверждённого blocker. Полный многоминутный matrix не запускать на каждое малое изменение.

Release проверяется согласованной парой EXE/PCK и её DLL из bin, из каталога пакета. Подтвердить native availability, debug=false и editor=false. Проверка PCK другим executable может незаметно включить GDScript fallback. Headless успех не доказывает графический результат: нужен visible run с просмотром кадров, camera pan, minimap jumps, selection и первым появлением анимаций.

Сохранять mean/p50/p95/p99/max, число кадров/updates выше 16,67/33,33/50 мс, CPU worker time, main-thread wait, capture/copy, очередь, stale/rejected tasks, static/peak memory и игровые hashes. Учитывать скорость: 20 Гц при 1× даёт 50 мс реального времени на tick, при 1,5× — около 33,33 мс, при 2× — 25 мс. Цель 60 FPS относится к полному кадру 16,67 мс.

Исторические цели E6: simulation p95 менее 50 мс при 1×, comfort p95 не более 35 мс на реалистичной mixed нагрузке и отдельный visible 60 FPS gate. Это цели проверки, а не обещанные результаты плана. Если цель не достигнута, записать остаточный measured owner, не снижать правила и не объявлять FPS по CPU timer.

## Передача результатов следующему агенту

После каждого этапа обновить его статус здесь и добавить запись в doc/WORK_TRACKER.md. Передать:

1. Изменённые файлы, контракт входа/выхода и точное место барьера/публикации.
2. Переключатели и способ вернуться к последовательной реализации.
3. Фикстуру, команды/параметры, версии движка/DLL и парные измерения с пределами применимости.
4. Сравнение command trace, canonical world/controller/AI state и continuation после save/load. Несовпадения разрешаются и объясняются, а не скрываются заменой golden hash.
5. Пройденные тесты, отдельно воспроизведённые прежние сбои, ошибки worker и оставшиеся ограничения.
6. Пределы памяти/очереди, shutdown/reconfigure и следующий измеренный владелец нагрузки.

Raw QA-файлы не являются единственным итогом: компактные показатели и воспроизводимый сценарий сохранять в отслеживаемой документации, поскольку prototype/qa/ исключён из Git. Статус «завершён» присваивается только после критериев этапа.
