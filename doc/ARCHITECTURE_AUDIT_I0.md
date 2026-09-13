# I0 — аудит архитектуры и baseline

Дата: 2026-09-11  
План: `doc/DEVELOPMENT_ROADMAP_ROR_PARITY.md`  
Область: `prototype`, импортированные каталоги и пользовательская сборка

## 1. Итог

I0 подтвердил, что проект имеет значительный функциональный фундамент, но прежние отметки «проверено» нельзя трактовать как соответствие Rise of Rome. Текущая реализация в основном находится между `FOUNDATION` и частичным `INTEGRATED`. Ни один крупный игровой блок пока не имеет достаточных доказательств `PARITY` или `HARDENED`.

Следующая работа должна начинаться с I1, а не с расширения UI или точечных графических исправлений.

## 2. Воспроизводимый baseline

- Godot: `4.7.2.stable.official.ed1daf0bf`.
- Полный набор: `66 passed, 0 failed`.
- Состав: 62 unit, 2 scenarios, 2 golden, 0 integration.
- Основная сцена проходит короткий headless smoke-run без engine errors.
- `simulation_world.gd`: 2193 строки.
- `main.gd`: 972 строки.
- `game_controller.gd`: 396 строк.
- Кеш содержит 941 graphics, 3580 objects, 234 sounds и 10 languages.
- Отчёт кеша: 130 errors и 1506 warnings: 63 missing SLP, 33 missing audio, 34 unknown IDs, 1464 missing name/icon, 42 suspicious values.

Команда baseline:

```powershell
.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path prototype --script res://tests/test_suite.gd
```

## 3. Матрица фактической готовности

| Подсистема | Текущий уровень | Доказательство | Главный пробел |
|---|---|---|---|
| Fixed tick и базовый мир | `FOUNDATION`, частично `INTEGRATED` | Frame-rate test, единый `advance()` | Нет явного сериализуемого состояния и полного порядка систем |
| Команды и replay | `FOUNDATION` | Очередь, JSON round-trip, частичный state hash | Нет issuer/sequence/result/events; same-tick order и snapshot неполны |
| Данные и кеш | `FOUNDATION`, частично `INTEGRATED` | Версии и хеши источников | Валидация содержит 130 ошибок; runtime остаётся жёстко привязан к demo-набору |
| Выделение и context command | `FOUNDATION` | Узкие resolver/pointer tests | Нет полного integration-пути и структурированного feedback |
| Навигация | `FOUNDATION`, частично `INTEGRATED` | Path/reservation/stress tests | Нет длительной проверки живой игры и контракта с групповым состоянием |
| Действия/facing/анимация | `FOUNDATION` | Формулы и catalog tests | Нет L3-калибровки семантического направления и action-facing |
| Бой | `FOUNDATION` | Melee/projectile unit tests | Нет perception/stance/acquisition и полного боевого сценария |
| Формации | `FOUNDATION`, частично `INTEGRATED` | Геометрия, assignment, два сценария | Нет жизненного цикла `TRAVEL/ENGAGED/REGROUP`; тест закрепляет преждевременный возврат в слот |
| Экономика/стройка/технологии | `FOUNDATION` | Узкие циклы и формулы | Нет связного экономического L2-сценария и UI-команд полного цикла |
| Terrain/render | `FOUNDATION` | Stable sort и terrain hash | Golden фиксирует текущий результат, но не доказывает соответствие оригиналу |
| UI/audio | Частичный `FOUNDATION` | Прототипный HUD и несколько звуков | Нет событийного presentation и полного управления |
| Карты/сценарии/AI | `MISSING` либо ранний прототип | Victory rules отдельно | Нет полноценного матча и AI через команды |
| Сохранения/release hardening | `MISSING` | Есть packaging prototype | Нет сериализации полного состояния, миграций и soak tests |

## 4. Критические архитектурные наблюдения

### I1: владение состоянием и детерминизм

1. `SimulationWorld` одновременно реализует создание сущностей, движение, бой, экономику, производство, технологии, туман, победу и доступ к данным. Его нужно декомпозировать постепенно через контракты систем, без большой одномоментной переписи.
2. Сущности представлены изменяемыми `Dictionary`; их ссылки возвращаются через `get_units()` и напрямую меняются `GameController`, formation helpers и `main.gd`.
3. `main.gd` хранит ссылки на массивы мира и записывает `selected` прямо в словарь юнита. Selection следует перенести в presentation/player-control state.
4. `RenderWorld` читает живой `SimulationWorld`, а не read-only snapshot.
5. Верхнеуровневые поля сущности и `components` содержат дублируемые значения, синхронизируемые вручную. До декомпозиции нужно определить единственный источник истины для каждого поля.
6. Formation groups хранятся в `GameController`, меняют словари юнитов и не входят в replay snapshot/hash.
7. Replay snapshot не включает полный мир: formation groups, fog, approach/reservation state, часть очередей и внутреннее RNG-состояние.
8. Живая очередь сохраняет insertion order, но recorder сортирует команды одного тика по type; replay способен выполнить тот же набор в другом порядке.
9. `command_id` вычисляется из tick и числа юнитов, поэтому не уникален. В команде нет issuer и стабильного sequence.
10. Неизвестные команды молча игнорируются; нет результата принятия/отказа и доменных событий.

### I2: данные

1. Версионирование кеша и независимая инвалидация реализованы хорошо.
2. Тест валидации проверяет структуру отчёта и число обработанных записей, но не требует отсутствия error issues.
3. Runtime-каталог вручную перечисляет demo-графику villager/clubman/archer, corpse IDs, work/carry IDs, town center, tree и berries.
4. `SimulationWorld` содержит специальные проверки `kind == villager/tree/berries/town_center` и зеркальные поля food/wood для team 1.
5. 130 ошибок источников должны быть классифицированы как ожидаемые отсутствующие ресурсы, ошибка извлечения либо реальный пробел установки. До этого I2 не получает `PARITY`.

### I3–I7: управление, движение, бой и формации

1. Обработчик ввода, picking, создание команд, camera, HUD, audio и draw собраны в `main.gd`.
2. Есть pixel-level texture picking юнитов, но нет общего picking для всех entity kinds и единого результата команды.
3. Контекстные команды не создают accepted/rejected events; presentation заранее показывает успех.
4. Автоматическое обнаружение цели реализовано отдельно только для demo enemy logic.
5. Formation test явно требует мгновенного возврата к `formation_home` после смерти одной цели. Это подтверждает старый контракт, который должен быть заменён I6/I7.
6. Formation group живёт вне авторитетного состояния и имеет только упрощённое состояние `moving`.
7. Направление математически тестируется, но нет поведенческого L3-теста, доказывающего соответствие семантике кадров SLP.

### I8–I13: полнота игры и presentation

1. Экономика и технологии представлены множеством хороших узких тестов, но нет цельного Stone Age сценария.
2. AI отсутствует; `update_enemy_orders()` является demo-автоматикой, а не архитектурой AI.
3. Overlap golden проверяет подпись sort order с fake frame info, а не эталонное изображение.
4. Terrain golden сравнивает хеш собственного текущего рендера. Он полезен против регрессии, но может закреплять визуально неверный результат.
5. Главная сцена жёстко создаёт демонстрационную карту, состав сторон, ресурсы и управление тренировкой clubman.
6. Полного формата карты, случайной генерации, сценариев, AI, сохранения и загрузки пока нет.

## 5. Интерпретация существующих тестов

66/66 — хороший regression baseline. Это не показатель «66 частей игры соответствуют RoR».

- 62 теста изолируют функции или короткие циклы.
- 2 scenario tests проверяют геометрию/устойчивость ограниченного числа случаев.
- 2 golden tests не сравнивают живой кадр игры с эталоном RoR.
- Каталог `tests/integration` заявлен раннером, но отсутствует.
- Нет теста полного пути пользовательской команды до presentation feedback.
- Нет длительного матча, полного экономического цикла и боя с autonomous acquisition.

## 6. Владельцы известных симптомов

| Симптом | Владелец | Когда исправлять |
|---|---|---|
| Клик не даёт ожидаемого приказа | I3 picking/command result | После базового event/result contract I1 |
| Ходьба боком, удар спиной | I4/I5 facing contract | После отделения движения и action state |
| Нет самостоятельной атаки | I6 perception/stance | После стабильных команд и locomotion |
| Формация важнее боя | I6/I7 group lifecycle | После combat acquisition |
| Перекрытия | I4/I6 reservation/contact | В пространственном и боевом контрактах |
| Артефакты terrain/слоёв | I9 render pipeline | После стабилизации simulation snapshots |

## 7. Первый незакрытый этап: I1

I1 выполняется небольшими совместимыми блоками:

### I1-001. Детерминированный command envelope

- Добавить issuer и монотонный sequence ID.
- Сохранять одинаковый порядок команд одного тика в live и replay.
- Сериализовать sequence и не использовать коллидирующий вычисляемый ID.
- Добавить тест порядка конфликтующих команд одного тика.

### I1-002. Command result и simulation event stream

- Возвращать accepted/rejected с кодом причины.
- Не показывать presentation-успех до результата симуляции.
- Ввести минимальные события command accepted/rejected и task changed.
- Затем расширять событиями боя, экономики и производства.

### I1-003. Полный canonical snapshot/hash

- Включить formation groups, очереди, reservations, fog/visibility, objectives и RNG state.
- Установить стабильную сериализацию коллекций.
- Разделить snapshot для replay/save и облегчённый presentation snapshot.

### I1-004. Граница presentation

- Перенести selection из словарей сущностей в player-control state.
- Перевести RenderWorld и HUD на snapshot/read model.
- Не возвращать наружу изменяемые авторитетные коллекции после появления необходимых query API.

### I1-005. Постепенная декомпозиция SimulationWorld

- Сначала выделить system interfaces и явный порядок tick.
- Переносить combat/economy/production/fog по одной системе с parity-тестом.
- Не делать массовый rewrite 2193 строк за один шаг.

## 8. Решение I0

I0 считается завершённым как аудит и baseline. Существующий код не удаляется и не объявляется бесполезным: он является рабочей основой. Прежние статусы трекера трактуются как наличие foundation, пока отдельный интеграционный или parity-сценарий не докажет более высокий уровень.

## 9. Выполнение I1 после аудита (обновлено 2026-09-12)

- `I1-001` завершена: команды получают назначаемые один раз `issuer_id` и монотонный `sequence_id`; live и replay используют одинаковую сортировку, формат replay v2 мигрирует записи v1.
- `I1-002` завершена на уровне симуляционного контракта: есть accepted/rejected result с кодом причины и единый нумерованный поток `command accepted/rejected`, `task changed`, `attack`, `hit`, `damage`, `death`, `entity_created`, `build_complete`, `research_complete`. Подключение всех визуальных подтверждений к событиям остаётся задачей I3/I10.
- `I1-003` завершена: canonical snapshot/hash включает очередь команд, formation groups, reservations, fog, objectives, technology state и RNG; отдельный presentation snapshot фильтрует видимость и копирует данные.
- `I1-004` завершена для selection, renderer, HUD и миникарты: они больше не изменяют и не получают живые коллекции мира. Переходный spatial query для picking остаётся до I3.
- `I1-005a` завершена: порядок активного и завершённого тика вынесен в именованный `SimulationTickPipeline`; владение FogOfWar, его tick и visibility queries перенесены в `SimulationVisibilitySystem`, совместимый фасад мира сохранён. Побайтовый parity-тест сравнивает новую систему с прежней семантикой.
- `I1-005b` завершена: ресурсы/population принадлежат `SimulationEconomySystem`; очереди обучения и исследований, reservation/refund/spawn и completion state принадлежат `SimulationProductionSystem`.
- `I1-005c` завершена: разрешение attack frame, melee damage и projectile lifecycle принадлежат `SimulationCombatSystem`. Системы держат слабую ссылку на мир, поэтому циклов владения RefCounted нет.
- Новый baseline после I2: 68 unit, 2 integration, 2 scenario и 2 golden теста; всего `74 passed, 0 failed`.

## 10. Выполнение I2 (2026-09-12)

- Введён декларативный `runtime-archetypes.json` и детерминированный генератор `build_runtime_catalog.py`; готовый `runtime-catalog.json` загружается при обычном запуске без конвертации.
- `RoRDataRepository` является границей полного source cache и симуляции. Alias прототипа, стабильный internal ID, source unit ID RoR и presentation ID больше не смешиваются.
- Симуляция получает stats/source record/behavior tags через repository; прямые проверки worker/drop site заменены компонентами и тегами, старый gamespec остаётся только совместимым адаптером.
- Explorer 127 подключён как `scout` одной записью манифеста и создаётся headless-тестом без изменения центрального игрового цикла.
- Validator v3 проверяет отсутствующие ссылки, graphic/technology cycles, уникальность ID и runtime source records. Ложные errors для projectile dead-unit links и однокадровых статических SLP устранены семантически.
- Текущий gate: `0 errors, 181 warnings`. Warning означает пробел исходной пользовательской установки или presentation metadata и содержит impact; это не маскируется как целостность cache.

Точная следующая задача: `I3-001 — вынести PickingService и закрыть интеграционный путь pointer → hit stack → intent → command result → feedback`.

## 10. Последующая сверка I3 (2026-09-12)

- Пункты исходного аудита 4.3.1–4.3.3 устранены: `main.gd` больше не декодирует физические клавиши/кнопки и не выполняет picking; эти обязанности принадлежат `InputAdapter` и `PickingService`.
- Selection и context resolution независимы; hit stack поддерживает юниты, здания/фундаменты, составные части и ресурсы.
- `CommandFeedbackRouter` потребляет авторитетные accepted/rejected events. Звук и marker не появляются заранее.
- Наведение и клик используют один hit stack; логическая сущность подсвечивается, а курсор показывает семантику действия.
- Сквозной тест существует и проверяет как успех, так и invalidation цели до тика.
- Demo enemy logic всё ещё вызывает внутреннее назначение атаки. Его перевод на общий perception/query/command pipeline принадлежит I6 и блокирует уровень `PARITY`, но не следующий архитектурный этап I4.
