# Архитектурный план развития до уровня Rise of Rome

Статус: основной план следующих итераций  
Актуален с: 2026-09-12  
Связанные документы: `doc/DEVELOPMENT_PLAN.md`, `doc/WORK_TRACKER.md`

## 1. Цель и границы

Довести новый движок до полноценной игры уровня Age of Empires: The Rise of Rome по правилам, данным, управлению, содержанию, интерфейсу, аудиовизуальной обратной связи и устойчивости. Внутренняя архитектура должна оставаться современной и расширяемой.

Расширенные формации, изменение формы и направление строя входят в основную игру, а не в отдельный режим. Старый поиск пути и другие ограничения оригинального движка копировать не требуется. Внешнее поведение должно быть знакомым игроку RoR и не разрушать баланс, управление и темп игры.

Замеченные дефекты не образуют очередь срочных заплаток. Они указывают на незавершённые архитектурные контракты и исправляются во владеющих ими итерациях.

## 2. Статусы готовности

Для каждой подсистемы отдельно отмечаются:

1. `FOUNDATION` — существует базовая реализация и API.
2. `INTEGRATED` — корректно работают связи с соседними системами.
3. `PARITY` — контрольные сценарии соответствуют ожидаемому поведению RoR.
4. `HARDENED` — пройдены пограничные, длительные и производительные проверки.

Наличие классов или прохождение узких модульных тестов не означает `PARITY`.

## 3. Обязательные архитектурные правила

### Авторитетная симуляция

- Состояние меняется только на фиксированных тиках.
- Ввод игрока, AI и replay создают одинаковые игровые команды.
- Рендер, UI и анимация не определяют здоровье, урон, задачи, путь или стоимость.
- RNG централизован и получает известный seed.
- Порядок систем и сортировки стабилен.
- Одинаковое состояние и поток команд дают одинаковый хеш результата.

### Направление зависимостей

```text
ресурсы -> нормализованные каталоги -> симуляция -> снимки/события -> presentation
ввод/AI/replay -> команды -----------> симуляция
```

Godot-сцена отображает снимок и отправляет команды, но не хранит единственную авторитетную копию игровых правил.

### Данные и ресурсы

- Юниты, здания, технологии, цивилизации, снаряды, графика и звук описываются каталогами со стабильными ID.
- Различия задаются данными, компонентами и стратегиями, а не ветвлениями по имени юнита.
- Импорт оригинальных ресурсов отделён от runtime.
- Кеш имеет версию схемы, версию конвертера и хеш источника.
- Неизменившиеся ресурсы не конвертируются при каждом запуске.

### Контракты систем

- Команда выражает намерение; task planner создаёт действия.
- Навигация строит путь; locomotion создаёт фактическую скорость; симуляция меняет позицию.
- Presentation получает facing и состояние из симуляции, но не управляет исходом действия.
- Формация организует группу, но не подменяет индивидуальный бой и навигацию.
- Бой создаёт события атаки, попадания, урона и смерти.

### Расширяемые формации

- Группа имеет стабильный ID, anchor, orientation, policy, параметры и участников.
- Генерация слотов отделена от назначения юнитов на слоты.
- Геометрия строя подключается через registry/policy.
- Движение, развёртывание, бой, сбор и восстановление — разные состояния.
- Новая форма не требует изменений рендера, боевой системы и обработчика мыши.

### Наблюдаемость

Отладочный режим показывает принятую команду, задачу, цель, путь, stance, группу, слот и причину смены состояния. Симуляционный дефект сохраняется как seed, tick и минимальный поток команд.

## 4. Уровни проверки

- `L0`: чистые функции и контракты.
- `L1`: интеграция команды, задачи, пути, боя и событий.
- `L2`: headless-сценарий с фиксированными seed и командами.
- `L3`: запись поведения и эталонные кадры presentation.
- `L4`: большие группы, долгий матч, сохранения и производительность.

Итерация не закрывается без L1 и соответствующего L2. Для рендера и UI обязателен L3; для выпуска — L4.

## 5. Очерёдность

```text
I0 аудит
 -> I1 симуляция/команды/события
 -> I2 данные и кеш ресурсов
 -> I3 управление и picking
 -> I4 пространство, путь и движение
 -> I5 действия, facing и animation contract
 -> I6 восприятие и бой
 -> I7 жизненный цикл формаций
 -> I8 экономика и развитие
 -> I9 рендер мира
 -> I10 UI, звук и ощущение управления
 -> I11 карты, AI и правила матча
 -> I12 волны контента и parity
 -> I13 сохранения, оптимизация и выпуск
```

Если аудит доказывает, что часть этапа уже выполнена, работа не повторяется: добавляются недостающие интеграционные доказательства и закрывается первый невыполненный выходной критерий.

## I0. Аудит и новый baseline

**Цель:** честно сопоставить текущую реализацию с планом, не переписывая рабочие части.

1. Сопоставить файлы, системы и тесты с I0–I13.
2. Поставить каждой подсистеме четыре независимых статуса готовности.
3. Найти места, где один Godot-класс смешивает ввод, правила и рисование.
4. Зафиксировать порядок одного тика и источники недетерминизма.
5. Найти жёстко заданные unit kind, ID, стоимость, графику и правила.
6. Зафиксировать baseline тестов и запуска сборки.
7. Создать реестр дефектов с владельцем-итерацией.
8. Подготовить сценарии: выбор/движение; сбор; строительство; производство; бой 1x1; бой групп с формациями.
9. Обновить `doc/WORK_TRACKER.md` фактами и точной следующей задачей.

**Выход:** следующий агент однозначно видит владельца каждого состояния и первый незакрытый контракт.

## I1. Граница симуляции, команды, события и снимки

**Цель:** закрепить фундамент, не зависящий от кадра, UI и анимации.

1. Определить сериализуемый `SimulationState` и стабильные entity ID.
2. Зафиксировать fixed tick и порядок систем.
3. Сделать команды неизменяемыми: issuer, tick, type, payload.
4. Разделить принятие команды и выполнение задачи.
5. Ввести события: command accepted/rejected, task changed, attack, hit, damage, death, create, build complete, research complete.
6. Создать read-only snapshot для рендера и UI.
7. Удалять прямые изменения симуляции из presentation через переходные адаптеры.
8. Централизовать RNG и устойчивую сортировку запросов.
9. Определить паузу, скорость и единичный шаг.
10. Добавить headless replay и хеш состояния.

**Выход:** сценарий дважды выполняется без графики с одинаковым результатом; отключение рендера не меняет игру.

**Статус 2026-09-12:** I1 завершена на уровне `INTEGRATED`. I1-001…I1-004 закрепили immutable command envelope, результаты/события, canonical и presentation snapshots. I1-005 физически выделила `SimulationVisibilitySystem`, `SimulationEconomySystem`, `SimulationProductionSystem` и `SimulationCombatSystem`; мир сохранил совместимые фасады, а порядок тика задаёт `SimulationTickPipeline`.

**Доказательство:** replay/canonical hash, presentation boundary, parity fog, economy ownership, production completion event и combat event проходят в полном baseline. Статус не повышается до `PARITY`, пока нет эталонного полного матча RoR.

## I2. Нормализованные данные и конвейер ресурсов

**Цель:** получить единственный расширяемый источник истины для содержимого RoR.

1. Версионировать схемы каталогов.
2. Нормализовать юниты, здания, ресурсы, технологии, цивилизации, команды, снаряды, графику и звук.
3. Разделить source ID оригинала, внутренний ID и presentation ID.
4. Валидировать отсутствующие ссылки, циклы зависимостей и несовместимые данные.
5. Переносить константы из кода через совместимые адаптеры.
6. Закрепить pipeline `оригинал -> нормализованный кеш -> runtime`.
7. Хранить в кеше схему, версию конвертера и хеш источников.
8. Перестраивать кеш только при реальном изменении.
9. Создать отчёт покрытия данных и ресурсов.
10. Подготовить полный набор данных для первого вертикального среза.

**Выход:** новый тип контрольного среза добавляется через данные/стратегию без правки центрального цикла; повторной конвертации при обычном запуске нет.

**Статус 2026-09-12:** I2 завершена на уровне `INTEGRATED`. `runtime-catalog.json` генерируется из полного object/graphics/sound/localization cache и декларативного `runtime-archetypes.json`; схема, importer version и хеши всех входов входят в cache key. `RoRDataRepository` разделяет alias, internal ID, исходный RoR unit ID и presentation ID. Новый тип `scout` (Explorer 127) входит в headless-симуляцию только через запись манифеста, без ветки в центральном цикле.

**Доказательство:** validation schema v3 проверяет ссылки, graphic/technology cycles и runtime ID-пространства. Отчёт даёт 0 структурных ошибок; 181 warning классифицирован как пробелы принадлежащей пользователю установки: 63 SLP, 33 WAV и 85 name/icon records. Покрытие учитывает стартовые сущности, технологические разблокировки, upgrades, projectiles и lifecycle links. Повторный запуск генератора даёт cache hit, обычный launcher импорт не вызывает.

**Следующий шаг I2 выполнен:** I3-001…I3-004 создали общий путь ввода, picking, семантики и событийной обратной связи.

## I3. Семантика команд, picking и обратная связь

**Цель:** отделить физический ввод от игровых намерений и сделать управление надёжным.

1. Выделить `InputAdapter` и независимый `PickingService`.
2. Picking учитывает камеру, проекцию, footprint, hotspot и порядок рисования.
3. Разделить selection resolution и context command resolution.
4. Описать таблицу команд для земли, союзника, врага, ресурса, здания и фундамента.
5. Исключить молчаливую замену ожидаемой команды другой командой.
6. Реализовать click, box select, модификаторы и control groups.
7. Описать move, attack, attack-move, gather, return, build, repair, train, research и stop.
8. Возвращать результат принятия и причину отказа.
9. Подключить курсор, command marker, подтверждение и краткий статус через события.
10. Тестировать масштаб, камеру, перекрытие и разные направления спрайта.

**Выход:** пользователь видит объект под курсором, отправленную команду и результат; мышь, AI и replay используют одну семантику приказов.

**Статус 2026-09-12:** I3 завершена на уровне `INTEGRATED` для пользовательского управления. `InputAdapter` отделяет физические события от жестов, `PickingService` строит hit stack по фактическому render order и общим alpha/footprint правилам, `ContextResolver` исключает молчаливую подмену неподходящей команды, а `CommandFeedbackRouter` показывает marker/звук только после авторитетного `command_accepted`. Наведение использует тот же hit stack и отображает select/attack/gather/repair/unavailable.

**Доказательство:** `test_pointer_command_feedback.gd` проходит путь от ПКМ до события presentation и отдельно проверяет исчезновение цели между picking и fixed tick. Полная матрица и границы отложенных команд записаны в `doc/ror-modern/COMMAND_SEMANTICS.md`. Общий pipeline для будущего AI остаётся частью I6, поэтому статус не повышается до `PARITY`.

**Следующий шаг:** I4-001 — аудитировать уже существующие navigation/local movement/reservation/recovery реализации против контрактов I4 и выделить первый недостающий интеграционный сценарий, не повторяя закрытые N-001…N-008.

## I4. Пространство, навигация и locomotion

**Цель:** устойчивое современное движение одиночных юнитов и групп.

1. Зафиксировать единицы мира, footprint, радиус контакта, высоту и проходимость.
2. Разделить глобальный путь и локальное движение.
3. Ввести детерминированные path requests/results.
4. Добавить резервирование конечных позиций.
5. Реализовать локальное избегание без недетерминированной физики.
6. Различать desired velocity, actual velocity, movement facing и action facing.
7. Обрабатывать остановку, replan, недостижимую цель и recovery из застревания.
8. Использовать групповой коридор, а не один жёсткий путь для всех.
9. Проходить узкие места со сжатием и последующим восстановлением.
10. Проверить здания, лес, берег, разные footprint, скопления и большие группы.

**Выход:** юниты доходят до достижимых целей, не занимают одну точку, не колеблются бесконечно и воспроизводимо проходят узкие места.

**Статус 2026-09-12:** I4 завершена на уровне `INTEGRATED`. Существующие N-001…N-008 уже давали footprint, глобальный A*, локальное избегание, reservations, recovery и formation corridor. I4-001 добавила явный детерминированный `NavigationService` request/result envelope с correlation ID, grid revision и `resolved/unreachable`. I4-002 провела команду через GameController до прибытия и закрепила `command_rejected/no_path`, если маршрут не получил ни один участник. `movement_facing`, `desired_facing` и `action_facing` разделены в authoritative state и диагностике.

**Доказательство:** `test_navigation_command_pipeline.gd` является L1, `test_navigation_stress.gd` и formation scenario matrix — L2. Полный контракт записан в `doc/ror-modern/NAVIGATION_CONTRACT.md`. Статус `PARITY` требует контентных карт/сценариев RoR и измеряемого эталона ощущения движения, поэтому пока не заявляется.

**Следующий шаг:** I5-001 — аудитировать animation/facing pipeline на реальных SLP, ввести явный action-state contract и эталонную таблицу соответствия world direction → source direction/mirror/frame order.

## I5. Действия, facing и контракт анимации

**Цель:** согласовать симуляционное действие, направление и presentation, не позволяя аниматору управлять правилами.

1. Описать состояния idle, move, approach, gather, carry, build, repair, windup, attack, recover, die и decay.
2. Определить допустимые переходы и правила прерывания.
3. Ввести отдельные movement facing, desired facing и action facing.
4. Установить единую систему мировых углов и нулевое направление.
5. Создать калибровочную таблицу `world direction -> SLP direction -> mirror`.
6. Фиксировать action facing на цели во время удара; formation и avoidance не должны разворачивать атаку.
7. Разделить simulation timing и визуальные frame markers: presentation синхронизируется, но не решает, нанесён ли урон.
8. Валидировать clip length, action frame, frame order, hotspot и fallback-графику.
9. Создать тестовую сцену всех состояний во всех направлениях.
10. Проверить смену цели, отмену приказа, смерть и потерю пути.

**Выход:** действие правильно выполняется без графики, а рендер однозначно показывает его правильным клипом и направлением.

**Статус 2026-09-12:** I5 завершена на уровне `INTEGRATED`. Единый `FacingConvention` откалиброван по реальным кадрам Clubman: исправлено перепутанное восток/запад, зафиксирована таблица восьми logical directions к пяти source blocks и mirror. `movement_facing`, `desired_facing` и `action_facing` раздельны; action facing удерживается на цели. Переход windup/recover больше не запускает один attack clip задом наперёд, а новый цикл атаки имеет явный restart.

**Доказательство:** `test_facing_convention.gd` и `test_animation_direction_pipeline.gd`; полный контракт — `doc/ror-modern/ANIMATION_FACING_CONTRACT.md`. `PARITY` требует L3-эталонов всех классов RoR-анимации.

## I6. Восприятие, выбор цели и полноценный бой

**Цель:** перейти от приказа на конкретный entity ID к устойчивому боевому поведению RTS.

1. Ввести perception query с дальностью обзора, принадлежностью, видимостью и доступностью.
2. Добавить stance: aggressive, defensive, stand ground и passive/no-attack.
3. Разделить acquisition range, attack range, chase/leash range и помощь союзникам.
4. Детерминированно оценивать угрозу, расстояние, достижимость, класс и число уже назначенных атакующих.
5. Дать игроку и AI общий сервис обнаружения целей.
6. Реализовать attack-move, реакцию на урон и цепочку целей после смерти текущей.
7. Ввести melee contact positions и распределение атакующих вокруг цели.
8. Реализовать дальний бой, снаряды, попадание/промах и эффекты по данным RoR.
9. Вынести атаку, броню, бонусы, cooldown и скорость снаряда в каталоги.
10. Обрабатывать потерю видимости, недоступность цели и возврат к предыдущей задаче.
11. Проверить 1x1, Nx1, группа на группу, melee против ranged и последовательные цели.

**Выход:** отряд действует согласно stance, сам вступает в достижимый бой, меняет цели и завершает контакт без клика по каждому противнику.

**Статус 2026-09-12:** I6 завершена на уровне `INTEGRATED`. `PerceptionService` фильтрует дальность, союз, видимость и достижимость и стабильно ранжирует цели; `CombatAwarenessSystem` создаёт команды для обеих сторон вместо прямого enemy-only управления. Работают aggressive/defensive/stand_ground/passive, retaliation и помощь союзнику, acquisition/chase/leash, attack-move, цепочка целей и возврат к прерванному движению. Юниты, здания и фундаменты используют один attack target contract; разрушение здания освобождает карту и создаёт death event. Melee contact, ranged projectiles, armor/attack/cooldown уже используют нормализованные исходные данные.

**Доказательство:** `test_perception_service.gd`, `test_combat_awareness_system.gd`, `test_autonomous_combat_pipeline.gd`, а также прежние melee/projectile/formation scenarios. Контракт — `doc/ror-modern/COMBAT_BEHAVIOR_CONTRACT.md`. Численные параметры RoR и L3/L4 длинных боёв оставлены критерием `PARITY`, а не выданы за завершённые.

**Следующий шаг:** I7-001 — выделить формальную state machine жизненного цикла группы (`ASSEMBLE/TRAVEL/DEPLOY/ENGAGED/REGROUP/REFORM/DISBAND`) поверх существующих FormationGroup/Corridor/Cohesion, начав с перехода `TRAVEL -> ENGAGED`, который освобождает жёсткие слоты.

## I7. Жизненный цикл группы и инновационные формации

**Цель:** формации улучшают управление войском, не подавляя индивидуальный бой.

1. Закрепить group model: ID, anchor, orientation, policy, spacing, ranks, members, state.
2. Ввести `ASSEMBLE`, `TRAVEL`, `DEPLOY`, `ENGAGED`, `REGROUP`, `REFORM`, `DISBAND`.
3. В `TRAVEL` поддерживать слоты с допуском, а не идеальную геометрию каждый тик.
4. В `DEPLOY` выбирать фронт по направлению приказа или угрозы.
5. В `ENGAGED` освобождать жёсткие слоты, сохраняя anchor, фронт и допустимую область рассеивания.
6. Передавать контактные позиции боевой системе; formation planner не рассчитывает исход боя.
7. Ввести hysteresis между боем и перестроением.
8. После боя проходить `REGROUP`, новое назначение слотов и `REFORM`.
9. Сохранять выбранные форму, плотность и направление.
10. Assignment учитывает тип, скорость, footprint и прежний слот.
11. Подключать линию, колонну, каре, клин и новые формы через registry policies.
12. Реализовать пользовательское направление и preview до подтверждения.
13. Проверить потери, пополнение, смешанные скорости, узкие места, окружение и отступление.

**Выход:** строй устойчив в пути, естественно переходит в бой, не мешает выбору целей и воспроизводимо восстанавливается после контакта.

**Статус 2026-09-12:** I7 завершена на уровне `INTEGRATED`. `FormationLifecycle` формализует `ASSEMBLE/TRAVEL/DEPLOY/ENGAGED/REGROUP/REFORM/DISBAND`; переходы версионируются и видны как simulation events. В походе слоты мягкие, в `ENGAGED` освобождены, в `REFORM` кратко жёсткие. Существующие geometry registry, assignment с сохранением прежних слотов, corridor compression, contact positions и direction drag включены в единый lifecycle. Выбранный front хранится отдельно от направления текущей угрозы.

**Доказательство:** `test_formation_lifecycle.gd`, `test_formation_combat_lifecycle.gd`, membership и scenario matrix 2…100 участников. Контракт — `doc/ror-modern/FORMATION_LIFECYCLE_CONTRACT.md`.

**Следующий шаг:** I8-001 — gap-аудит уже существующих S-007…S-011 и один end-to-end Stone Age economic loop через команды и события, без прямого изменения ресурсов тестом.

## I8. Экономика, строительство и развитие

**Цель:** собрать основной игровой цикл RoR поверх устойчивой симуляции и данных.

1. Формализовать ресурсы, вместимость, переносимый груз и точки сдачи.
2. Реализовать worker pipeline: approach, work, carry, return, resume, retarget.
3. Учесть истощение, потерю доступа, несколько работников и очередь к месту работы.
4. Реализовать размещение, footprint, фундамент, строительство несколькими юнитами, отмену и уничтожение.
5. Реализовать производство, стоимость, population, spawn placement и blocked spawn.
6. Реализовать исследования, эпохи, зависимости и цивилизационные модификаторы.
7. Привести числовые правила к данным RoR.
8. Добавить экономические события для UI и AI.
9. Проверить Stone Age loop от рабочих до первого военного отряда.
10. Расширить сценарий до перехода эпохи и смешанной армии.

**Выход:** экономический цикл проходится в headless-сценарии и обычной игре без отладочного изменения состояния.

**Статус 2026-09-12:** I8 завершена на уровне `INTEGRATED`. Экономика использует четыре source resource ID, физический gather/carry/deposit и явный `ReturnResourcesCommand`; точки сдачи и подхода распределяются по безопасному периметру без взаимной блокировки работников. Runtime-каталог расширен Town Center/Barracks/House/Granary/Storage Pit/Archery Range. Явное производство проверяет source train location и object availability, а завершение здания активирует его hidden technology connector. Population разделена на global match limit и housing capacity из source storage data; завершение/уничтожение provider добавляет/снимает вклад один раз.

**Доказательство:** `test_stone_age_economy_loop.gd` проходит сбор недостающей древесины, строительство Barracks и производство Clubman только через команды/events. `test_tool_age_progression.gd` проходит high-resource match от сбора через Barracks/Granary и Tool Age research до Archery Range и смешанного Clubman/Bowman отряда. L1 дополнительно закрепляют production locations/unlocks, specialized drop sites, population providers и explicit return. Контракт — `doc/ror-modern/ECONOMY_PROGRESSION_CONTRACT.md`.

**Граница статуса:** полный tech tree/content, точная build-availability matrix, UI выбранных зданий и длительная численная калибровка остаются критериями I10/I12; старый HUD train без producer ID пока обслуживает один явно помеченный compatibility adapter.

**Следующий шаг:** I9-001 — создать data-driven building presentation registry и L3 golden scene для Town Center/Barracks/House/Granary/Storage Pit/Archery Range, одновременно устранив двойные composite layers, неверные hotspots и texel bleed terrain.

## I9. Визуальное соответствие мира

**Цель:** после стабилизации игровых контрактов правильно представить оригинальные ресурсы.

1. Зафиксировать изометрическую проекцию, elevation и pixel snapping.
2. Проверить импорт, фильтрацию, alpha, player color и края текстур.
3. Устранить швы terrain и утечки соседних texel.
4. Поддержать переходы terrain, берега, elevation, cliffs, декор и animated terrain по данным.
5. Ввести стабильный sort key для overlays, shadows, objects, units, projectiles и effects.
6. Откалибровать hotspot, anchor, footprint и shadow классов объектов.
7. Исключить одновременное рисование взаимоисключающих base/delta/composite-слоёв.
8. Реализовать fog/unexplored mask независимо от швов тайлов.
9. Добавить damage/death/decay, стройку, снаряды и эффекты.
10. Создать эталонные кадры фиксированных сцен, разрешений и масштабов.
11. Документировать только осознанные визуальные отличия.

**Выход:** в контрольных кадрах нет швов, неверного зеркалирования, скачков глубины, двойных слоёв и смещённых hotspot.

**Статус 2026-09-12:** I9 завершена на уровне `INTEGRATED`. `RoRBuildingPresentationRegistry` заменил единственную жёстко заданную картинку Town Center на выбор graphics/deltas по runtime, object и graphics catalogs. Поддержаны разные здания, player palette, construction stages, технологическая смена `display_graphic_id`, римская expansion architecture, взаимоисключающий damage overlay и исходные building death/rubble sequences. Разрушенное здание освобождает путь немедленно, но удаляется после видимой анимации.

Terrain переведён на исходную логическую решётку `64 x 32`; bitmap `65 x 33` трактуется как изображение с общим граничным texel, поэтому устранены чередующиеся швы и смещение склонов. L3 закреплён отдельными terrain/building golden scenes, а overlap scene продолжает проверять стабильную глубину. Контракт: `doc/ror-modern/WORLD_PRESENTATION_CONTRACT.md`.

**Доказательство:** `95 passed, 0 failed`; основной проект и экспортированный EXE проходят headless smoke-run; cache validation — `0 errors, 181 warnings`. Статус не повышается до `PARITY`, пока I12 не расширит импорт/эталоны на полный roster, cliffs, декор и эффекты.

**Следующий шаг:** I10-001 — выделить read-only `HudViewModel`, который строит панели, команды, очередь и причины недоступности только из presentation snapshot и авторитетных command results.

## I10. Интерфейс, управление, звук и ощущение игры

**Цель:** сделать правила понятными пользователю и приблизить темп взаимодействия к RoR.

1. Воссоздать структуру HUD, панели объекта, ресурсов, команд, очередей и сообщений.
2. Получать доступность команд и причины блокировки из симуляции, не дублируя правила.
3. Реализовать курсоры, markers, selection feedback и health/status display.
4. Реализовать миникарту, сигналы и управление камерой.
5. Настроить hotkeys, control groups, очередь команд и модификаторы выбора.
6. Подключить реплики, подтверждения, предупреждения, бой, экономику, UI и музыку.
7. Ввести presentation event router с ограничением повторяющихся звуков.
8. Проверить разные разрешения, масштаб UI и оконный/полноэкранный режим.
9. Убрать обязательные debug-панели из пользовательского пути, сохранив переключаемую диагностику.

**Выход:** контрольный матч проводится без консоли и знания внутреннего состояния; вся обратная связь доступна в UI и звуке.

**Статус (2026-09-12): `INTEGRATED`.** `RoRHudViewModel` строит ресурсы, население, эпоху, выбор, formation/building command palette, причины недоступности и очередь исключительно из presentation snapshot и нормализованных каталогов. Train, research и cancel проходят через единый command/result/event pipeline. Миникарта использует обратимую world-space проекцию, fog и контур камеры, поддерживает click/drag recenter. Реальная геометрия HUD проверена в основной сцене и на изменённом control canvas; итоговый L3-кадр сохранён как `prototype/qa/golden/hud-main-1280x720.png`.

`RoRPresentationAudioRouter` подключает исходные selection/command/train WAV и звуки unit/building death через цепочку animation graphic → sound ID, выбирает варианты детерминированно и ограничивает повторения по категориям. Невидимые domain events не раскрываются звуком. Контракт: `doc/ror-modern/USER_INTERFACE_AUDIO_CONTRACT.md`.

**Доказательство:** `100 passed, 0 failed`; cache validation — `0 errors, 181 warnings`; основная сцена, экспорт и готовый Windows EXE проходят headless smoke-run. Статус не повышается до `PARITY`, пока I12 не закроет полный набор оригинальных icons/commands/menus/sound bindings и попарные UI-эталоны.

**Следующий шаг:** I11-001 — выделить декларативный `MatchDefinition`/`MapDefinition` и загрузчик стартового состояния, убрав жёстко заданный demo setup из `main.gd`; затем seeded random map и AI command producers.

## I11. Карта, игровой AI, сценарии и правила матча

**Цель:** перейти от демонстрационной сцены к полноценному матчу.

1. Завершить модель карты, игроков, Gaia, ресурсов и стартовых условий.
2. Загружать поддерживаемые карты/сценарии через адаптер данных.
3. Реализовать random map generation с воспроизводимым seed.
4. Дать AI те же публичные команды и допустимые знания, что предусмотрены правилами.
5. Разделить стратегический, экономический и тактический уровни AI.
6. Не давать AI скрытую информацию без явного правила сложности.
7. Реализовать diplomacy, ownership, команды игроков, defeat и resign.
8. Реализовать условия победы RoR и необходимый объём сценарных триггеров.
9. Добавить паузу, скорость, перезапуск и завершение матча.
10. Создать полные smoke-матчи AI против AI.

**Выход:** игра начинает, проводит и завершает полноценный матч без заранее написанного боевого скрипта.

**Статус (2026-09-12): `INTEGRATED`.** `RoRMatchDefinition` валидирует внешнее описание карты, игроков, стартовых условий, сущностей, дипломатии и victory rules. `RoRRandomMapGenerator` детерминированно строит terrain, vertex elevations и resource clusters по seed. `RoRMatchBootstrap` применяет всё описание к миру; `main.gd` больше не содержит ручной армии/ресурсов и использует фактический размер/seed карты.

`RoRPlayerRegistry` хранит controller/civilization, symmetric diplomacy и статусы active/resigned/defeated/victorious. Resign проходит immutable command → result → event → replay; после терминального статуса управление отклоняется. AI разделён на strategic/economic/tactical planners и видит только собственный fog-filtered presentation snapshot. Экономика использует authoritative production options, тактика — общие attack/attack-move/formation commands.

L2 `test_ai_vs_ai_match.gd` запускает две стороны без боевого скрипта: обе принимают решения, получают accepted events и завершают воспроизводимый conquest match. Pause/speed/restart/finish доступны в обычном input path; Shift+R отправляет resign. Контракт: `doc/ror-modern/MATCH_MAP_AI_CONTRACT.md`.

**Доказательство:** `108 passed, 0 failed`; основная сцена проходит headless smoke-run. Статус не `PARITY`: random maps, economic build planner, naval AI, difficulty, дипломатический UI и расширенные scenario triggers закрываются вертикальными волнами I12.

**Следующий шаг:** I12-001 — сформировать машинно-проверяемую матрицу первой законченной Stone Age content wave и расширить runtime archetypes/commands только по обнаруженным пробелам.

## I12. Волны контента и систематическое соответствие RoR

**Цель:** расширять покрытие вертикальными волнами, не добавляя весь контент одновременно.

**Статус 2026-09-13: выполняется; I12-019 source-driven vertical `INTEGRATED`, I12-019G measurement gate начат, I12-020A…K завершены, I12-020L фаза 2B-8a завершена.** I12-001…I12-018 закрыли проверяемую римскую наземную вертикаль и её source-driven UI/audio. I12-019A добавила Dock/Fish/Fisherman/Fishing Boat; I12-019B — Trade/Transport production, composite presentation и сериализуемый cargo/board/unload lifecycle; I12-019C — Scout Ship/War Galley/Trireme и Catapult Trireme/Juggernaught через общий combat/projectile pipeline; I12-019D — повторяемый Dock-to-Dock trade lifecycle; I12-019E — Whale 370, source-valid Dock zones и mixed-domain AI. I12-019F добавила DAT damage thresholds, death/impact effects, доступные naval sounds, fog-safe event presentation, обе палитры/composite RGBA golden и full-roster navigation/combat stress. I12-019G закрепила идентичность эталонного executable/DAT и машинно-проверяемый контракт будущих наблюдений, не выдавая незаписанный executable за доказательство. I12-020A каталогизировала сценарии и кампании, I12-020B…E построили первую кампанийную вертикаль, I12-020F — общую gap matrix, I12-020G…K последовательно закрыли и опубликовали остальные пять миссий. I12-020L теперь системно уменьшает только AI-semantic gaps без сценарных исключений.

**Текущий gate:** launcher выбирает прототип и все шесть миссий `Расцвета Рима`; briefing/objectives/result UI читает только presentation state. Для каждой миссии object/condition/trigger/AI-normalization/asset/settings launcher gaps равны нулю, bootstrap и воспроизводимые исходы проверены. Матрица: 6 published, 6 launcher-ready, 0 blocked, 0 parity-ready. Source AI остаётся `INTEGRATED`, не `PARITY`: данные больше не теряются, но известные strategic-number, `DEFAULT` и `Random` semantics ещё закрыты не полностью. Постоянный cache содержит 65 runtime archetype и 21 471 asset; validation — `0 errors, 181 source-owned warnings`. Полный gate — `A-006 suite: 176 passed, 0 failed`. Windows PCK пересобран (219 549 316 байт, 2026-09-13 18:45:08); автономные smoke-runs `campaign_pyrrhus_of_epirus` и `campaign_mithridates` завершены с кодом 0 и без runtime-ошибок. Bulk-load, retained terrain, viewport environment field, инкрементные индексы и детерминированная binary-heap A* устраняют только блокирующие просадки; финальный performance budget и согласованный group-route contract остаются I13. Морские executable observations I12-019G всё ещё `capture_pending`.

**Статус I12-020I:** завершено на уровне `INTEGRATED`. `Сиракузцы` импортированы как фиксированная карта 144×144 с 4 сторонами и 2 900 исходными объектами: 1 968 runtime entities (165 units, 522 buildings, 1 281 resources), 725 лёгких environment items, 199 навигационных препятствий и 7 presentation markers. Composite Bowman 6 и Heavy Cavalry 38 оформлены вариантами существующих линий; Fire Galley 360, Hero Archimedes 382 и Mirror Tower 383 получили общие source-driven archetypes, а Double Pole Flag 162 остаётся presentation-only. Огненная галера использует составные исходные слои корпуса и огня. Legacy `CreateInArea` обобщён на живые units и завершённые buildings: десять Legion DAT 282 в точной области дают победу Риму. Оба enemy `Destroy` связаны с immutable scenario object 5998 — гибель Архимеда воспроизводимо завершает миссию поражением. Исходные Iron/Post-Iron/Tool старты сохранены. Object/condition/asset/settings gaps равны нулю; миссия опубликована третьей по порядку кампанийной карточкой. Cache содержит 65 archetype и 21 458 assets; validation — `0 errors, 181 warnings`; полный gate — `A-006 suite: 157 passed, 0 failed`.

**Статус I12-020J:** завершено на уровне `INTEGRATED`. `Зама` импортирована как фиксированная карта 200×200 с 2 сторонами и 10 645 исходными объектами: 6 534 runtime entities (109 units, 255 buildings, 6 170 resources), 4 003 environment items, 96 navigation obstructions и 12 source army flags. После переиспользования общих архетипов единственным недостающим ресурсом был `graphic_322_p2`; теперь четыре римских и восемь карфагенских флагов используют точные палитры. Сохранены Iron/Post-Iron старты и Standard victory с четырьмя классическими путями и исходным таймером 900 секунд. Bootstrap, Wonder, Conquest и локальное поражение доказаны; object/condition/asset/settings gaps равны нулю, миссия опубликована пятой по порядку.

**Статус I12-020K:** завершено на уровне `INTEGRATED`. `Митридат` импортирован как фиксированная карта 200×200 с 5 сторонами и 9 253 исходными объектами: 8 487 runtime entities (126 units, 542 buildings, 7 819 resources), 634 environment items и 132 navigation obstructions. Последний asset `graphic_575` включён в постоянный кэш. Build-order-only AI больше не ошибочно считается отсутствующим: поддержанный production subset выполняется, но military capability остаётся выключенной без исходных strategic rules, поэтому generic атака не придумывается и лишний decision tick не запускается. Все четыре AI-профиля имеют исполнимый partial contract. Сохранены Iron/Bronze/Post-Iron старты, slot 14 запрета Town Center и точное условие уничтожения enemy Wonder scenario object 10755. Bootstrap, source victory и локальное поражение доказаны. Вся кампания имеет 6 launcher-ready, 0 blocked и 0 parity-ready миссий; cache содержит 65 archetype и 21 471 asset; validation — `0 errors, 181 source-owned warnings`.

**Статус I12-020L, фаза 1:** завершена на уровне `INTEGRATED`. Импортёр распознаёт весь фактически встреченный язык build-list `B/C/R/T/U`: 447 записей всех 17 AI-профилей нормализованы в `building/unit/technology`, дополнительные legacy-параметры сохраняются без придуманной трактовки, четыре выключенные обратной косой чертой строки отделены от исполнимых. Неизвестных build-list строк — 0. `B`-записи запрашивают только необходимые допустимые площадки и идут через общий `BuildCommand`; уже начатый foundation засчитывается в target count. `DEFAULT` теперь не считается неизвестным синтаксисом, а хранится как именованная `recognized_pending_baseline` директива. Кэш сценария зависит от SHA-256 самого импортёра, поэтому изменение нормализации больше нельзя случайно скрыть старым результатом. Доказательства: `test_source_campaign_ai_planner.gd`, `test_source_campaign_ai_build_pipeline.gd`, `test_imported_syracuse_match.gd`, campaign audit `6 ready / 0 blocked`; полный gate `162 passed / 0 failed`. Windows PCK пересобран и автономно запускает `campaign_syracuse` без повторной конвертации.

**Статус I12-020L, фаза 2A:** завершена машинная инвентаризация AI-семантик без догадок о поведении оригинала. Все 504 записи strategic-number в 17 профилях классифицированы по capability; нераспознанных ID — 0. После исправления приоритета source-documented no-op 68 записей имеют исполняемую runtime-семантику, 42 являются документированными no-op, 394 записи (66 уникальных ID) остаются явным `pending`. Parity ledger версии 2 считает все 17 профилей и отдельно показывает capability gaps, `DEFAULT`, `RANDOM` и случайный build list; поэтому ни один частичный профиль больше не выглядит полным из-за неполного критерия аудита. Launcher gate остаётся честным: `6 ready / 0 blocked / 0 parity-ready`.

**Статус I12-020L, фаза 2B-1:** подтверждённая `SNTacticalUpdateFrequency` (ID 88) включена в runtime. Значение 2 у пятой команды «Митридата» переводится через фиксированные 20 Hz в 40 simulation ticks; источник интервала хранится как `strategic_number_88`, а профиль без этой записи остаётся явно помеченным `runtime_fallback`. Одновременно исправлена семантическая ошибка: source-комментарий `UNUSED AT THIS POINT` теперь имеет приоритет над общей поддержкой ID, поэтому две записи `SNMaximumAttackGroupSize` Сиракуз больше не меняют размер атакующей группы. Planner игнорирует любой `pending` и source-documented no-op. Целевые planner/Mithridates/Syracuse/ledger tests проходят.

**Статус I12-020L, фаза 2B-2:** по исторической таблице `.per` и оригинальным `.VC` подтверждены и реализованы ID 19 `SNPercentEnemySightedResponse`, ID 20 `SNEnemySightedResponseDistance` и ID 48 `SNAttackResponseSeparationTime`. Урон ближнего боя и снарядов создаёт компактный ограниченный distress journal, который входит в canonical/replay state и показывается только атакованной команде. Source planner берёт целую долю ближайших свободных воинов в исходном радиусе, соблюдает separation time и исключает responders из плановой атаки того же такта. Attack и response capabilities разделены: response-only контракт больше не включает выдуманную плановую атаку. Все шесть миссий пересобраны импортёром `scenario-match-26`; ledger: 504 записи, 119 implemented, 42 source-documented no-op, 343 pending (63 уникальных ID), 0 unclassified. Campaign audit: `6 ready / 0 blocked / 0 parity-ready`; полный gate `163 passed / 0 failed`; cache validation `0 errors / 181 warnings`. Windows PCK пересобран, автономный headless smoke-run `campaign_mithridates` завершён с кодом 0 без повторной конвертации ресурсов. Доказательная база и ещё не реализованные границы описаны в `doc/ror-modern/SOURCE_AI_SEMANTICS_EVIDENCE.md`.

**Статус I12-020L, фаза 2B-3:** создан отдельный от пользовательских формаций сериализуемый `RoRSourceAiAttackGroup`: исходный состав и HP, активные/индивидуально отходящие участники, цель, rally/objective, land/water domain, состояние, revision и причина перехода имеют устойчивое dictionary round-trip. ID 30/31/91 вызывают соответственно общий health retreat, общий death retreat и индивидуальный withdrawal без конфликтующего приказа остальным. ID 49 реализует все четыре подтверждённых режима: recenter, retarget-or-retreat, unconditional retreat и extermination через видимую цель либо детерминированный fog frontier. Группы разных доменов не смешиваются; активные и отходящие участники исключаются из новых волн и distress response. Импортёр `scenario-match-27` пересобрал шесть миссий; ledger: 504 записи, 173 implemented, 42 source-documented no-op, 289 pending (59 уникальных ID), 0 unclassified. Campaign audit: `6 ready / 0 blocked / 0 parity-ready`; cache validation `0 errors / 181 warnings`; целевые lifecycle/planner/pipeline/import tests проходят, полный gate — `165 passed / 0 failed`. Windows PCK пересобран (219 407 572 байт), автономный headless smoke-run `campaign_mithridates` завершён с кодом 0 без повторной конвертации ресурсов.

**Статус I12-020L, фаза 2B-4:** подтверждённые ID 40 `SNGroupFillMethod`, 41 `SNAttackGroupGatherSpacing` и 47 `SNAttackCoordination` работают поверх постоянной source attack-group модели. Fill `0` последовательно заполняет группу до максимума, fill `1` сначала создаёт допустимые минимальные группы и затем детерминированно распределяет остаток по уровням; land/water граница сохраняется. Spread-группа получает rally order и остаётся `ASSEMBLING`, пока каждый живой активный участник не окажется в source spacing; затем состояние становится `READY`. Coordination `0` выпускает каждую готовую группу, `1` держит единственную активную группу, `2` выпускает всю готовую волну одновременно. Эти состояния, wave/order и параметры входят в canonical round-trip; пользовательская формация остаётся только геометрией движения. Повторный поиск одной цели на каждого бойца заменён кэшем по домену без изменения результата. Импортёр `scenario-match-28` пересобрал шесть миссий; ledger: 504 записи, 204 implemented, 42 source-documented no-op, 258 pending (56 уникальных ID), 0 unclassified. Campaign audit: `6 ready / 0 blocked / 0 parity-ready`; cache validation `0 errors / 181 warnings`; модульные fill/gather/coordination проверки и новый authoritative coordination pipeline входят в полный gate `166 passed / 0 failed`. Windows PCK пересобран (219 423 552 байта), автономный `campaign_mithridates` smoke-run завершён с кодом 0.

**Статус I12-020L, фаза 2B-5:** добавлена отдельная сериализуемая `RoRSourceAiAssignmentGroup` для defend/explore, не смешанная с attack lifecycle и пользовательской формацией. Реализованы подтверждённые exploration ID 18/35/42/43/44 и defend ID 22/25/28/38/50/51/52/54/55/56/57/92. Защитные точки выбираются по source priority и неперекрывающимся кругам влияния; группа формируется только из локального минимального состава, перехватывает ближайшую видимую совместимую угрозу и возвращается после выхода за радиус. Гражданский разведчик использует move, военная группа — attack-move по fog-safe navigation frontier. ID 72 остаётся pending, поскольку источник не раскрывает алгоритм вариации. Импортёр `scenario-match-29`: 504 записи, 370 implemented, 42 source-documented no-op, 92 pending (39 уникальных ID), 0 unclassified; девять кампанийных профилей активировали defence, exploration capability gap исчез. Первое ошибочное дальнее назначение выявлено живой сценой по пикам 9 997/10 381 мс; после локального отбора и запрета повторного replanning прогон стабилен, максимум 899 мс при прежнем известном I13 debt. Campaign audit `6 ready / 0 blocked / 0 parity-ready`, cache `0 errors / 181 warnings`, полный gate `168 passed / 0 failed`.

**Статус I12-020L, фаза 2B-6a:** ID 86 `SNStoragePitDistance` и ID 87 `SNGranaryDistance` теперь фильтруют общие авторитетные build-site кандидаты по максимальному расстоянию до любого живого собственного Town Center до выпуска `BuildCommand`. При отсутствии Town Center или допустимой площадки AI ожидает и не обходит placement pipeline. Ограничения независимы и проверены planner-test; импортный контракт «Митридата» подтверждает обе исполняемые записи без искусственного добавления зданий в исходный build list. ID 0–5 отложены до общей workforce policy, ID 73/74/84/85 — до постоянной city/wall plan; ID 76 переклассифицирован из economy в combat control. Импортёр `scenario-match-30`: 504 записи, 372 implemented, 42 source-documented no-op, 90 pending (37 уникальных ID), 0 unclassified. Capability gaps: economy 3, combat control 14, defence 11, naval/transport 4, targeting 3, build order 3, source baseline 6; exploration gap отсутствует. Campaign audit остаётся `6 ready / 0 blocked / 0 parity-ready`.

**Статус I12-020L, фаза 2B-6b:** land ID 16/26/36 и boat ID 59/60/58 теперь независимо формируют доменно-безопасные attack groups; source marker линейно проецируется на ближайшую проходимую клетку домена. ID 61/62/63 создают постоянные water exploration groups через fog-safe frontier и общий cap ID 18. ID 67/68/69/70 создают water defence assignments только у собственных Dock; при уничтожении якоря группа освобождается. Все группы переиспользуют общий canonical lifecycle, публичные команды и fill/gather/coordination/retreat semantics. Импортёр `scenario-match-31`: 504 записи, 402 implemented, 42 source-documented no-op, 60 pending (27 уникальных ID), 0 unclassified; naval/transport gap остаётся только у одного профиля из-за ID 64/65/66. Новые module и authoritative pipeline tests, импортные контракты Пирра/Сиракуз/Митридата и их полные bootstrap/outcome verticals проходят. Полный gate `170 passed / 0 failed`, cache validation `0 errors / 181 source-owned warnings`.

**Статус I12-020L, фаза 2B-7a:** добавлен `source_ai_targeting_executable_gate.json`, привязанный к тем же SHA-256 эталонного `EMPIRESX.EXE` и `empires.dat`. Три изолированных серии измеряют сочетание distance/HP/damage, нулевые множители и область действия zero-priority distance; по каждому случаю обязательны target ID, исходные характеристики, seed, повторения и immutable artifacts. Общий `ParityMeasurementGate` больше не требует trade-секцию у несвязанных манифестов. Автотест проверяет все ID 34/77–83/89/90 и запрещает `PARITY`, пока observations не заполнены; сами ID остаются pending.

**Статус I12-020L, фаза 2B-7b:** исторический `DEFAULT.VC` извлечён из зафиксированного архива и сохранён как версионированный `prototype/data/source_ai/default_vc.json`: 149 уникальных записей ID 0…162, SHA-256 entry `ee2e709bce9538c0ef9a233fab842c03051ed2b6112de62955a52f77b2b8459b`, SHA-256 архива `5f18fd552a804bf6d92e52f41e6e68e62b64e716843f462a1e074c824195faed`. Статус `cataloged_partial_runtime` намеренно отделяет сохранение первичных данных от доказательства правил наследования. `source_ai_random_executable_gate.json` задаёт три серии наблюдений для `RANDOM` rule directive, случайного build list и устойчивости restart/save/load/replay; до captures импортированные `DEFAULT` и `Random` сохраняют прежние pending-статусы. Каталог и оба ограничения закрыты автоматическими тестами без изменения поведения миссий.

**Статус I12-020L, фаза 2B-7c:** ID 64/65/66 теперь обслуживаются общей сериализуемой ролью `escort` внутри прежнего assignment-group lifecycle. Желаемое число считается числом warboat-участников отдельно для торговых, рыболовных и транспортных судов; участники детерминированно распределяются по ближайшим живым якорям, следуют за ними через обычный `AttackMoveCommand`, перехватывают совместимую угрозу и освобождаются при уничтожении якоря. Дистанции следования/перехвата являются явно документированной современной политикой уровня `INTEGRATED`, поскольку таблица задаёт только желаемое число. Все текущие кампанийные значения равны нулю, поэтому миссии не получили нового поведения. Та же итерация реализовала полностью описанный ID 75: командир один раз выбирается по maximum HP, minimum HP или maximum range, хранится в canonical state и пересчитывается тем же методом только после смерти.

**Статус I12-020L, фаза 2B-8a:** `source_ai_workforce_executable_gate.json` фиксирует необходимые наблюдения для ID 0–5: базу процентов и округление, порядок применения caps/перераспределения и смену ролей при reservations/lifecycle events. До измерения все шесть ID остаются pending и не меняют задачи рабочих. Импортёр `scenario-match-33` и все шесть миссий пересобраны: 504 записи, 406 implemented, 42 source-documented no-op, 56 pending (23 уникальных ID), 0 unclassified; naval/transport capability gap исчез.

**Статус I12-020L, фаза 2B-8b:** добавлен единый сериализуемый `RoRSourceAiCityPlan` для ID 73/74/84/85. Он один раз выбирает детерминированный городской якорь, хранит min/max envelope, полный периметр стены и source-sized проходы, переживает save/load и не перескакивает после потери якоря. Геометрия явно имеет уровень `INTEGRATED`: maximum town size задаёт современный квадратный периметр, а проходы равномерно распределены; неизвестный алгоритм executable не имитируется догадкой. Предпочтительные wall cells проходят fog-safe presentation snapshot и обычный authoritative placement/BuildCommand/foundation pipeline. Исправлен проявившийся при дальнем строительстве типизированный возврат из pathfinder cache. Импортёр `scenario-match-34`: 410/42/52 implemented/no-op/pending, 19 уникальных pending ID, 0 unclassified; campaign audit `6 ready / 0 blocked / 0 parity-ready`. Полный gate `176 passed / 0 failed`, cache `0 errors / 181 source-owned warnings`; Windows PCK 219 549 316 байт, оба packaged smoke-run завершены без ошибок.

**Статус I12-020L, фаза 2B-9a:** завершён машинный аудит player palette, alpha и fog boundary. Импортёр `slp-4` использует все десять AoE1 player-colour shades `0…9`; прежняя маска `& 7`, превращавшая два самых тёмных оттенка в самые яркие, удалена. Неиспользуемый AoE1 `palette_offset` больше не выбирает ложную палитру: non-default palette задаётся только явным source-контекстом asset. Представительные building/villager пары доказывают одинаковую alpha mask и изменение исключительно player-colour/outline пикселей; building/defence/naval golden приняты заново после визуальной проверки. Byte-identical PNG/raw больше не перезаписываются при одной смене версии импортёра.

Неизведанный мир и миникарта теперь полностью непрозрачны. Fog polygon следует всем перепадам terrain boundary, удаляет только коллинеарные вершины и использует тот же pixel snapping, что terrain. Presentation snapshot передаёт fog как `PackedByteArray`, не копируя 62 500 ячеек циклом GDScript. Контракт и доказательная граница сохранены в `doc/ror-modern/VISUAL_PARITY_CONTRACT.md`. Контрольный cache-only импорт: `21 471 hits / 0 misses`; validation: `0 errors / 181 source-owned warnings`; полный gate — `177 passed / 0 failed`. Pre-UI Windows PCK: 219 547 664 байт, SHA-256 `acc5ce82dc37492158a72e8dcf9e081252ac12169783f7bcddd6a385c5bfca8`; packaged smoke-runs Пирра и Митридата завершены с кодом 0. Захват оригинального окна и точный парный UI-кадр остаются pending: Windows visual helper дважды завершился внешней ошибкой `trusted Node process exited unexpectedly`, поэтому approximate screenshot не выдан за доказательство.

**Статус I12-020L, фаза 2B-9b1:** импортёр строит `interface-source-inventory.json` по всем трём реальным слоям интерфейса: 368 SLP-записей, 82 повторяющихся ID сохранены раздельно по `data2/inter_up.drs`, `data2/Interfac.drs` и `data/Interfac.drs`. Неоднозначный selector `data2` теперь отклоняется; selection записывает точный архив и явную палитру. Машинно выделены 65 full-screen backgrounds, 16 source HUD-shell записей, четыре repeatable panel, шесть icon-sheet записей и малые controls/decorations; 157 записей честно остаются `unknown_pending_evidence`.

Из `data/Interfac.drs` импортированы 24 штатных HUD-кадра: верх 20 px и низ 126 px для 640/800/1024 и четырёх source-вариантов. `RoRInterfaceSkin` разрешает текстуру только при совпадении точного архива и palette policy; `RoRInterfaceLayout` владеет тремя исходными layout и wide-композицией, сохраняющей левый/правый source edge и повторяющей лишь нейтральный центр без масштабирования pixels. Runtime использует первый source-вариант как `INTEGRATED`, но не называет его римским до executable observation. Нарисованные растянутые 164px containers удалены, command/selection/minimap больше не перекрываются на 800×600, formation controls остаются в общей command grid и не создают отдельного режима. Gate: `179 passed / 0 failed`; cache-only `21 495 / 0`, reference `9 / 0`; validation `0 errors / 181 source-owned warnings`. Windows PCK: 220 268 336 байт, 2026-09-13 21:39:44, SHA-256 `cb9fb344fd4cc88ee1ccd314a13688dc142dbaf0e960b9947e549bcc8aa50bb6`; packaged smoke-runs Пирра и Митридата — exit 0 без runtime errors.

**Следующий шаг:** I12-020L, фаза 2B-9b2 — закончить source command skin: доказать назначения и порядок состояний кандидатов 50713…50716/50725…50728, подключить normal/hover/pressed/disabled без растяжения icon pixels, затем установить точное соответствие четырёх HUD-вариантов игровым контекстам. После восстановления Windows helper добавить immutable side-by-side RoR capture и calibrated rectangles/text baselines; до этого статус только `INTEGRATED`, не `PARITY`. Workforce, targeting, `DEFAULT` inheritance, `Random` и ID 71/72/76 остаются evidence-gated. После машинного parity ledger и AI-vs-scenario доказательств расширять manifest/audit pipeline на остальные кампании и отдельные сценарии. I12-019G и финальный I13 contract сохраняют свой порядок.

**Статус I12-020L, фаза 2B-9b2a:** точный импорт добавил 58 кадров 50713…50716, 50725…50728 и 50745 из `data/Interfac.drs` с palette 50500 и SHA-256 каждого итогового PNG. Машинная сверка опровергла прежнюю гипотезу «четыре кадра = normal/hover/pressed/disabled»: у каждого 50713…50716 все четыре 54×54 кадра побайтно одинаковы; у 50725…50728 четыре 54×31 кадра различны, но без executable observation их роль и композицию назначать нельзя. Контракт исправлен с frame-state bijection на измеряемую композицию backplate/glyph/icon/tint. ID 50745 содержит 26 различных 50×7 кадров прогрессии и подключён к presentation-only health bars с безопасным fallback; его точные source thresholds остаются capture-gated. Новый `source_ui_executable_gate.json` фиксирует hashes executable/DAT/Interfac, четыре обязательные capture-сцены, native resolutions и rectangles/text baselines. Windows helper повторно дважды завершился `trusted Node process exited unexpectedly`, поэтому shell-context/state semantics честно остаются pending и UI всё ещё `INTEGRATED`. Финальный gate блока: `180 passed / 0 failed`, cache-only `21 553 / 0`, interface reference `9 / 0`, validation `0 errors / 181 source-owned warnings`. Windows PCK: 224 248 568 байт, SHA-256 `01dc5318f706c96498fb6f9c2b5f123ab757f41cf6a1d196b9495ecadd7c0d22`; Пирр/Митридат packaged smoke — exit 0.

**Следующий шаг:** завершить 2B-9b2 после восстановления оригинального visual capture: измерить композицию control states, shell-context mapping и native rectangles; только затем заменить временные `StyleBoxFlat`. До этого продолжить независимый source UI-аудит без догадок и полный regression/build gate. После визуальной вертикали вернуться к evidence-gated AI; I13 по-прежнему выполняется после functional/parity ledger и использует 500 юнитов на игрока, 2/4/8 игроков, map ×4 area, stretch ×4 per side и минимум 30% p95 CPU/memory reserve.

Порядок волн:

1. Законченный Stone Age: рабочий, ресурсы, базовые здания, один melee и один ranged юнит.
2. Полный путь одной цивилизации по эпохам.
3. Общий набор юнитов, зданий и технологий.
4. Цивилизационные различия и ограничения.
5. Морская экономика и морской бой.
6. Случайные карты и условия игры.
7. Сценарии/кампании и специальные объекты.
8. Остаточные графические, звуковые и UI-варианты.

Для каждой волны:

1. Обновить матрицу `источник RoR -> каталог -> система -> presentation -> тест`.
2. Добавить данные и только необходимые общие механики.
3. Не вводить специальное ветвление, если механизм может быть data-driven.
4. Запустить применимые L0–L4.
5. Сравнить характеристики, результат и пользовательское поведение с эталоном.
6. Зафиксировать допустимые отличия современной навигации и формаций.

**Выход:** матрица не содержит неизвестных пропусков; отличие исправлено либо является документированным решением.

## I13. Сохранения, оптимизация, упаковка и выпуск

**Цель:** превратить функционально полную игру в устойчивую пользовательскую сборку.

1. Ввести версионированный формат сохранения авторитетного состояния.
2. Реализовать миграции поддерживаемых версий и понятные ошибки несовместимости.
3. Проверить сохранение во время экономики, строительства, формационного движения и боя.
4. Профилировать tick, pathfinding, allocation, render batching, загрузку и UI.
5. Установить бюджеты тика и кадра для контрольных карт и армий.
   - Обязательный population gate — 500 живых управляемых юнитов на каждого активного игрока; хранить отдельные профили для 2, 4 и 8 игроков, то есть до 4 000 одновременно симулируемых юнитов.
   - Обязательный large-map gate — карта с четырёхкратным числом клеток относительно наибольшей подтверждённой исходной карты RoR при сохранении пропорций (примерно удвоенная ширина и высота). Отдельный stretch gate — четырёхкратная ширина и высота, то есть 16-кратное число клеток; он измеряет запас, но не подменяет обязательный выпускной критерий.
   - Сохранить уже применяемую data-oriented модель: авторитетные сущности хранятся как данные и обслуживаются централизованными системами, а не отдельными `CharacterBody`/логическими `Node`. Полную миграцию на сторонний ECS рассматривать только при измеримом выигрыше на одинаковом replay workload.
   - В походном состоянии формации рассчитывать один общий глобальный маршрут/коридор группы; участники следуют связанным слотам и выполняют только локальное избегание.
   - При получении конкретной цели, входе в бой, сборе, строительстве, погрузке и других точных взаимодействиях строить индивидуальные, но связанные маршруты участников внутри общего группового намерения.
   - На одних и тех же повторах сравнить кэш общего маршрута, иерархический поиск и flow field; выбирать механизм по профилю, а не по теоретическому максимуму.
   - Сначала измерить текущий `CanvasItem` pipeline, retained terrain и viewport culling. `MultiMesh`/низкоуровневый RenderingServer применять по однородным render buckets только если сохраняются кадр и направление анимации, отражение, цвет игрока, составные слои и изометрическая глубина.
   - Разнести частоту дорогих AI/perception/path refresh и визуальную интерполяцию, не меняя детерминированный фиксированный simulation tick. Положение камеры может влиять только на presentation, но не на авторитетный мир, replay или исход боя.
   - Chunk streaming вводить только для карт существенно крупнее RoR и выгружать лишь presentation/cache chunks; авторитетные terrain, scenario и entity state не зависят от камеры.
   - Переносить измеренные CPU-hotspots в GDExtension/C++/Rust только после профиля и regression benchmark.
   - Зафиксировать ворота производительности: обычный матч RoR, 500 населения на каждого из 2/4/8 игроков, обязательную карту ×4 по площади и stretch-карту ×4 по каждой стороне. Для каждого хранить simulation tick и render frame `p50/p95/max`, wall-clock duration, число/длительность запросов пути, AI/perception cost, snapshot cost, allocations, draw calls, RAM и VRAM.
   - После достижения плавности оставить не менее 30% измеренного бюджета `p95` по CPU и памяти на будущие игровые системы. Если резерв не достигнут, gate считается пройденным функционально, но не готовым к расширению.
   - Не переносить эту оптимизацию раньше функционального соответствия, кроме минимальных исправлений, необходимых для воспроизводимых проверок и профилирования.
6. Провести длительные AI-матчи и replay-проверки.
7. Проверить восстановление отсутствующего или повреждённого кеша.
8. Создать воспроизводимую release-сборку без debug-зависимостей.
9. Проверить первый запуск, ярлык и последующие запуски без конвертации.
10. Подготовить настройки, журнал диагностики и требования к оригинальным ресурсам.

**Выход:** чистая сборка подготавливает локальные ресурсы, запускается с ярлыка и выдерживает полный матч с сохранением/загрузкой.

## 6. Владельцы уже замеченных проблем

| Наблюдение | Итерация | Архитектурный владелец |
|---|---|---|
| Клик по видимому юниту не даёт ожидаемого результата | I3 | Picking и результат контекстной команды |
| Юниты идут боком | I4 + I5 | Фактическая скорость и таблица направлений SLP |
| Юниты атакуют спиной | I5 | Action facing и контракт анимации |
| Нужен клик по каждому противнику | I6 | Perception, acquisition и stance |
| Строй подавляет боевое поведение | I6 + I7 | Engagement и жизненный цикл группы |
| Юниты перекрываются в бою | I4 + I6 | Reservation, footprint и contact positions |
| Швы и графические артефакты | I9 | Целостный render pipeline |
| Слабая обратная связь UI | I3 + I10 | Результат команды и presentation |

Исправление раньше владеющей итерации допустимо только при блокировке диагностики или следующего контракта. Тогда оно должно быть минимальным и иметь тест.

## 7. Ближайшая практическая очередь

1. Выполнить I0 и актуализировать фактические статусы.
2. Закрыть пробелы I1, сохраняя работающую сборку.
3. Проверить I2; не переписывать готовый кеш без нарушения контракта.
4. Выполнить I3 и получить путь `ввод -> команда -> симуляция -> событие -> feedback`.
5. Выполнить I4 до усложнения боевого AI и формаций.
6. Выполнить I5 и I6.
7. Перевести существующие формации на I7, переиспользуя рабочую геометрию и assignment.
8. После первого интеграционного боя продолжить I8–I13.

Если часть этапа уже работает, агент не повторяет её: он добавляет недостающее доказательство и переходит к первому незакрытому выходному критерию.

## 8. Правила работы агента

1. Прочитать этот файл, `doc/DEVELOPMENT_PLAN.md` и `doc/WORK_TRACKER.md`.
2. Проверить состояние репозитория и сохранить пользовательские изменения.
3. Выбирать первый незакрытый выходной критерий, а не самый заметный дефект.
4. Перед изменением определить владельца состояния и соседние контракты.
5. Не переносить правила в UI, renderer или animation callbacks.
6. Не дублировать данные оригинала константами в нескольких системах.
7. Сохранять детерминизм и стабильную сортировку.
8. Делать изменение небольшим, проверяемым и совместимым с текущей сборкой.
9. Добавлять тест на новый контракт или воспроизведённый дефект.
10. После блока запускать релевантные тесты, затем полный набор.
11. Проверять пользовательскую сборку после headless/integration-проверок.
12. Обновлять `doc/WORK_TRACKER.md`: сделанное, доказательства, ограничения и следующая задача.
13. Не ставить `PARITY` без контрольного сценария, `HARDENED` — без длительной проверки.
14. Спрашивать пользователя только при выборе, меняющем дизайн, баланс, поддерживаемый контент или допустимое отличие от RoR.

## 9. Definition of Done проекта

1. Основной цикл RoR доступен без debug-инструментов.
2. Каталоги покрывают заявленные юниты, здания, технологии, цивилизации, графику и звук.
3. Управление и контекстные команды предсказуемы и имеют полную обратную связь.
4. Экономика, бой, развитие и победа проверены эталонными сценариями.
5. AI проводит полноценный матч через публичные команды.
6. Расширенные формации штатно участвуют в движении и бою без отдельного режима.
7. Визуальные и аудиопроблемы устранены либо документированы как решения.
8. Одинаковый replay даёт одинаковый результат симуляции.
9. Большие матчи укладываются в бюджеты производительности.
10. Сохранение/загрузка, упаковка, кеш и запуск с ярлыка устойчивы.
11. Матрица соответствия RoR не содержит неизвестных пробелов.
12. Release-кандидат прошёл обязательные L0–L4.

## 10. Изменение плана

План можно менять при новых сведениях, сохраняя зависимости. Перед перестановкой итераций нужно ответить:

1. Какой выходной критерий блокирует работу?
2. Почему его нельзя закрыть в текущей итерации?
3. Не создаст ли перестановка временную связь, которую придётся переписать?
4. Какой тест докажет безопасность изменения порядка?

Видимый дефект сам по себе не нарушает порядок. Он становится немедленным приоритетом, если блокирует управление, диагностику, контрольный сценарий или выявляет ошибку фундаментального контракта.
