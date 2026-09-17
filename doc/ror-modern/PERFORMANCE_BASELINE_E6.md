# E6-001 — воспроизводимый runtime baseline

Статус: первый simulation-only baseline выполнен 2026-09-17. Он не является итоговым performance gate: workload содержит полный лимит живых сущностей, но они пассивны; активные формации, AI decisions, pathfinding, бой и render frame измеряются следующими отдельными профилями. Wall-clock метрики не входят в canonical state и не сериализуются.

## 1. Воспроизводимость

- Инструмент: `prototype/tests/manual/benchmark_e6_runtime.gd`.
- Измеритель: отключаемый `RoRPerformanceProbe`; хранит ограниченные выборки и выдаёт `mean/p50/p95/max` в микросекундах.
- Fixed tick, фазы controller и каждая система `SimulationTickPipeline` измеряются отдельно. Pathfinder сообщает число запросов, cache hits, unreachable и развёрнутых A* nodes.
- Каждый workload использует 3 прогревочных и 20 измеряемых fixed ticks, 500 Clubman на каждого игрока, passive stance и неизменяемые позиции.
- Required area-x4: `400×400`, то есть четырёхкратное число клеток относительно каталожной Giant `200×200`. Stretch: `800×800`, то есть четырёхкратная ширина и высота.
- Машина baseline: Windows, Intel Core i7-7700 3.60 GHz, 8 logical processors.

Пример запуска одного case:

```powershell
Godot_v4.7.2-stable_win64.exe --headless --path prototype --script res://tests/manual/benchmark_e6_runtime.gd -- --case=area_x4_8p --players=8 --units-per-player=500 --map-side=400 --warmup-ticks=3 --sample-ticks=20 --output=res://qa/performance/e6-area-x4-8p.json
```

`prototype/qa/performance` является локальным выходом и не попадает в Git или Windows package.

## 2. Найденный дефект

`GameController._emit_runtime_task_changes()` проходил все боевые сущности и для каждого ID вызывал линейные `SimulationWorld.find_unit/find_building`. Это превращало неизменившуюся событийную фазу в O(N²): при 4000 сущностях её p95 составлял 1336,45 мс из общего тика 1621,47 мс.

`SimulationWorld` теперь поддерживает неавторитетные индексы `units_by_id` и `buildings_by_id`. Массивы, стабильный порядок систем, canonical snapshot и игровая семантика сохранены. Индексы синхронизируются при add, purge, foundation cancellation и reset. Контрактный тест проверяет identity lookup и очистку lifecycle.

## 3. Результаты до и после

| Workload | До p50/p95, мс | После p50/p95, мс | Events p95 до → после | Unit orders p95 после | Static / peak memory после |
|---|---:|---:|---:|---:|---:|
| 2 × 500, 400×400 | 132,46 / 146,19 | 65,96 / 70,78 | 76,53 → 2,93 | 46,43 | 137,0 / 303,1 МБ |
| 4 × 500, 400×400 | 431,24 / 448,14 | 134,23 / 137,79 | 303,73 → 5,29 | 90,89 | 167,1 / 467,5 МБ |
| 8 × 500, 400×400 | 1529,08 / 1621,47 | 279,84 / 292,38 | 1336,45 → 11,49 | 180,60 | 227,4 / 745,5 МБ |
| 8 × 500, 800×800 stretch | — | 274,08 / 294,08 | — → 10,77 | 183,15 | 445,1 / 1328,6 МБ |

Canonical SHA-256 каждого 2/4/8-player area-x4 workload совпадает до и после индекса. На 4000 сущностях p95 уменьшен примерно на 82%; масштабирование fixed tick стало близким к линейному. Почти одинаковый tick на 400×400 и 800×800 показывает, что после прогрева текущий passive workload ограничен сущностями, а не площадью. Площадь остаётся существенным фактором bootstrap-памяти.

## 4. Первый разбор `unit_orders`

После устранения квадратичного lookup в `unit_orders` добавлены вложенные измерения без изменения simulation state. Они показали, что на пассивных 8 × 500 юнитах основная стоимость принадлежала не AI и не поиску пути, а повторной обработке уже неподвижных сущностей.

- Allocation-free перенос полей movement component (без создания таблицы соответствий для каждого юнита на каждом тике) уменьшил `unit_orders` p95 с `196,94` до `162,17` мс, а `animation_sync` — с `126,09` до `93,71` мс.
- Для юнита, который вошёл и вышел из такта в `idle`, не имеет маршрута и не изменил позицию, больше не вызывается общий local-movement path. Его component projection обновляет только реально меняющиеся health/cooldown/worker/animation поля; любой переход задачи или позиции автоматически использует полный путь.
- На том же `8 × 500 / 400×400 / 3+20 ticks` workload итоговый fixed tick p50/p95 стал `200,21 / 212,69` мс. `unit_orders` p95 — `113,25` мс, task dispatch — `10,20` мс, animation+component sync — `67,67` мс (`component_sync` `59,84` мс). Это финальный безопасный вариант: он сохраняет прежнее обнуление остаточной скорости и обновление `previous_position` на первом такте после остановки.
- Canonical SHA-256 до и после обеих оптимизаций одинаков: `0a02c57c4a1bddcb491c369544b3d259c3edc6998ca402ca88c5fa80db5ef1cd`.

Итоговый p95 относительно первого 8 × 500 baseline уменьшен с `1621,47` до `212,69` мс (примерно на 86,9%). Это всё ещё более чем в четыре раза выше обязательного 50-мс fixed-tick бюджета и не включает требуемый 30% резерв.

Прямые проверки охватывают component equivalence, measured/unmeasured hash, fixed timestep, snapshot/death lifecycle и переходы idle → movement/combat/gather/formation. Полный suite/export внутри этого E6-пакета не выполнялся по принятой boundary-политике.

## 5. Следующие профили и запреты

1. Добавить непассивные `move/local-avoidance/combat/gather` workloads и устранять только их измеренные полные обходы/повторные вычисления; idle workload больше не служит заменой этим профилям.
2. Добавить formation-march workload: один общий маршрут/коридор группы, локальное следование слотам, затем связанное индивидуальное уточнение при конкретной цели.
3. Добавить активный 2/4/8-player AI/combat workload, отдельно измеряя snapshot и planning cadence.
4. Добавить render baseline с world/minimap fog, source composite/player colour, culling, draw calls, CPU frame и GPU frame. Headless simulation numbers не являются доказательством плавного UI.
5. Повторить после retained fog chunks и общего world/minimap cache; camera pan не должен менять canonical hash или инициировать полный authoritative rebuild.
6. Не переходить на MultiMesh, сторонний ECS, C# или GDExtension до профиля соответствующего владельца. Любая оптимизация обязана сохранить canonical hash и пройти прямые lifecycle/save/replay regressions.

Текущий обязательный 50-мс tick budget ещё не достигнут: даже 2×500 имеет p95 70,78 мс, а 8×500 — 292,38 мс. E6 остаётся открытым; для будущих механик после достижения бюджета требуется ещё не менее 30% p95-запаса.
