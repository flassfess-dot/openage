# Контракт сохранения игры

## Дополнение 16.10.2026 — густые карты 400×400

Текущий код использует архив версии 7 и checkpoint версии 3; ниже сохранены исторические этапы контракта. Форматы в этом исправлении не менялись. Проверка новой генерации обнаружила корректный снимок мира 400×400 объёмом 387 261 340 байт до сжатия (файл архива около 6,9 МБ). Прежний предел распаковки 256 МиБ приводил к отказу загрузки сохранения, которое игра только что успешно записала.

Предел `RoRGameCheckpoint.MAX_BYTES` увеличен до 1 ГиБ с запасом для поддерживаемых густых лесов и развитого матча. Он остаётся конечным; проверки версии, размера распакованного содержимого, SHA-256 и структуры состояния сохранены. Новые проверки охватывают отказ размера выше предела, повреждённый digest и сериализацию настоящего восьмиигрокового мира 400×400. Проверка через меню использует ранее отклонённый архив и подтверждает продолжение симуляции. Журналы текущей работы находятся в `prototype/qa/natural-landscape-20261016/`.

Актуальные исходники: 10 октября 2026 года. Архив версии 5, checkpoint версии 2, replay версии 4, состояние незавершённой очереди ИИ версии 2. Пользователь явно отказался от обратной совместимости ради оптимизации: старые форматы отклоняются, миграций нет. Последняя правка загрузчика требует повторного экспорта Release.

## Источник восстановления

Сохранение фиксирует продолжимый матч на завершённом фиксированном такте. Авторитетный мир, RNG, очереди, команды на будущее, формации, производство, снаряды, изученная навигация и законная память наблюдений входят в отделённый checkpoint. Сцена, нативные объекты, подписки и производные кэши не сериализуются.

Replay сохраняет историю команд и продолжение записи. Загрузка текущего архива восстанавливает checkpoint напрямую; воспроизведение всей партии от такта 0 и сравнение полного canonical-хеша живого мира из загрузчика удалены.

## Состав архива

- format_version = 6 и обязательные schema_features, включая incremental_runtime_v2 и world_checkpoint.
- metadata — имя слота, время записи и сведения о настройках матча.
- match_path и match_fingerprint — идентичность определения матча; само определение и карта входят в checkpoint.
- tick — завершённый фиксированный такт.
- state_sha256 — SHA-256 несжатых бинарных данных checkpoint; совпадает с checkpoint.sha256.
- checkpoint — версия 2, размер несжатого содержимого, SHA-256 и Base64 сжатых данных ZSTD.
- replay — текущий журнал версии 4 с обязательными issuer_id, sequence_id, issued_tick и execute_tick.
- ai_states — продолжимое состояние ожидаемых игроков ИИ.
- controller_state — скорость, пауза и очередь незавершённых решений ИИ.
- view_state — камера, масштаб, выделение, группы управления и история звуковых событий.

Checkpoint содержит обязательную observation_memory с последними законно увиденными зданиями и ресурсами каждого наблюдателя. Эта память принадлежит миру и восстанавливается независимо от камеры и интерфейса. Скрытое изменение живого объекта не заменяет сохранённую память.

Активность, пространственные и боевые индексы, версии сущностей и курсоры чтения восстанавливаются из текущих фактов новой эпохи. Историческое расписание wildlife и открытые условия движения сохраняются явно там, где они влияют на поведение. Старые поля переключаемого пилота и периодических compatibility-обходов не входят в текущий checkpoint.

## Запись

RoRMatchLifecycleService один раз захватывает отделённый checkpoint в главном потоке. RoRBackgroundSaveTask сериализует Variant, вычисляет SHA-256, сжимает данные и кодирует архив. Второго полного canonical-хеша и повторного глубокого захвата живого мира нет. Проверка полноты checkpoint выполняется текущим загрузчиком.

Запись использует временный файл и резервную копию .bak; замена основного файла транзакционная. Стандартный быстрый слот — user://saves/quicksave.json; именованные слоты — user://saves/named. Старые версии не предлагаются как доступные текущие слоты; их файлы не удаляются.

## Загрузка

1. Отклонить любую версию архива, кроме 5, и неполные обязательные разделы. Принять только replay 4 и checkpoint 2.
2. Распаковать checkpoint, проверить размер, SHA-256 и обязательную текущую структуру, включая память наблюдений и runtime-состояние.
3. Проверить идентичность определения матча и создать отдельные SimulationWorld и GameController.
4. Восстановить авторитетные данные, законную память, RNG, будущие команды и продолжение истории записи. Создать производные индексы новой эпохи.
5. Восстановить состояния всех ожидаемых ИИ, незавершённую очередь решений и историю звуков. Отсутствующая или несовместимая секция завершает загрузку ошибкой.
6. Только после успешного восстановления опубликовать новый мир, завершить владельцев прежнего матча и применить состояние интерфейса.

Меню один раз читает и валидирует архив, затем передаёт его владельцу восстановления.
`match_path` служит идентификатором: загрузка карты из внешнего файла по этому пути
не выполняется. Определение матча и карта восстанавливаются из checkpoint, включая
случайные карты с виртуальным исходным путём. Повторного чтения архива в этом пути нет.

Несовместимый или неполный архив не изменяет текущий матч. Для старой версии интерфейс сообщает о несовместимости и предлагает начать новую игру; попытки загрузки через старую схему отсутствуют.

## Незавершённые решения ИИ

Порции одного захвата читают закреплённый source_tick и сохраняют фиксированный apply_tick. Пока захват не отделён, очередь и авторитетный checkpoint остаются на том же исходном такте. После загрузки незавершённая подготовка повторяется с этого источника; уже отделённые входы сохраняются бинарным Variant с точными типами и проверяются относительно состояния ИИ. Производные курсоры порций не сохраняются.

Смена матча отменяет решения и освобождает закрепления и производные кэши. Worker получает только отделённые неизменяемые данные.

## Статус приёмки

По указанию пользователя агент не запускал тесты, профили, компиляцию DLL и экспорт в этой итерации. Пользовательский экспорт 10 октября завершился, но автоматическая проверка пакета обнаружила устаревшее требование внешнего файла карты при загрузке нового сохранения. Этот путь исправлен в исходниках; повторная сборка и проверка после исправления не запускались. Подготовлен test_current_checkpoint_archive.gd для отказа старым форматам и текущего digest; test_incremental_runtime_generation.gd охватывает отмену и восстановление незавершённого захвата. Прежние результаты тестов относятся к предыдущему пакету и не подтверждают этот контракт.

[Полная исходная реализация и её ограничения](INCREMENTAL_SIMULATION_IMPLEMENTATION_2026-10-10.md). [План и отложенная приёмка](INCREMENTAL_SIMULATION_OPTIMIZATION_PLAN_2026-10-09.md).


## Adaptive AI state — 2026-10-11

Archive version 6 adds the required `adaptive_ai_v1` feature. Checkpoint payload version 2, replay version 4 and pending decision queue version 2 remain unchanged. As with the existing archive policy, older archive versions are rejected; there is no automatic migration.

Each AI state contains versioned strategic knowledge, observation timestamps, confidence inputs, income samples, spending feedback, retry cooldowns, worker rotation, telemetry, scout visits and transport missions. Persistent skirmish operations serialize the existing attack-group state plus their phase, movement region and last order tick. Enemy observations are retained only from the legal observer snapshot. Derived threat caches are rebuilt and never serialized.

Own pending proposals retain their issuer, sequence, command tick and detached feedback metadata. Saving copies already completed results for these exact proposals into `controller_state.ai_feedback_results`. Loading validates sequence ownership, uniqueness and applied tick before restoring those results. It does not inspect results issued by other players. An unfinished command remains in the normal checkpoint command queue.

Feedback is consumed only when the AI decision queue is inactive. Saving never drains feedback or changes a live/captured AI state. This preserves the exact `input.state` equality required at the source/apply barrier. Planner feedback metadata is removed before controller enqueue and replay recording, so it does not become gameplay command parameters or affect pending-command hashes.

The initial 2026-10-11 validation was static only. Runtime validation on 2026-10-12 exposed JSON numeric-type loss in nested AI state; the archive now uses one `__exact_variant_v1` descriptor per AI dictionary, containing a base64 binary Variant without object deserialization. Payloads are bounded to 64 MiB. This preserves nested integer values, float values, dictionary key types and typed arrays before a pending plan compares its input state. Normal replay parameters and hash encoding keep their existing representation.


The follow-up includes `test_ai_adaptive_strategy.gd` for exact JSON state restoration and feedback counted once, and `test_adaptive_ai_save_resume.gd` for a generated skirmish saved after accepted AI commands but before feedback consumption. The latter loads through the normal game boundary and compares the continued world hash, complete AI state and public command history. The completed run results are recorded in `prototype/qa/ai-validation-20261012-final/results.json`; no Release export or native DLL build was performed.

The completed targeted validation passed 49 tests with no actionable Godot errors. Subsequent scout fixes were checked with affected reruns, including ordinary-resource progression, inland/naval exploration, deterministic outcomes and adaptive save/resume. The consolidated result is `prototype/qa/ai-validation-20261012-summary.json`.
