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

## 5. E6-002 — активный марш формаций

Пассивный baseline дополнен отдельным `formation_march` workload. На старте измеряемого окна каждый игрок отправляет 500 юнитов одной настоящей `FormationMoveCommand` в построении `BLOCK`; приказ проходит обычные controller, assignment, corridor, reservation и navigation contracts. В отчёте отдельно сохраняются command phase и последующие активные fixed ticks.

Первый профиль обнаружил три независимые причины квадратичного/кубического роста: Hungarian assignment на 500 участников, повторное построение геометрии всех слотов для каждого участника и отдельный A* с полным поиском резервной точки для каждого юнита даже на полностью открытой местности.

- Точное Hungarian-назначение сохранено для групп до 64 участников. Большая группа использует детерминированное role-band/spatial pairing `O(N log N)`, сохраняя уникальные слоты, прежние допустимые назначения и боевое распределение ролей.
- `FormationCorridor` строит геометрию переходов сразу для всей группы. Прямой проходимый отрезок принимается до A*; при препятствии используется прежний footprint-aware A*.
- Для полностью открытого общего envelope маршрут проверяется один раз и регистрируется для участников с тем же canonical navigation result. Любое препятствие, граница карты, несовместимый домен/ограничение или сдвиг destination reservation автоматически возвращает обычный индивидуальный pathfinding.
- Destination reservation проверяет желаемую точку немедленно и расширяет поиск кольцами, не материализуя заранее кандидатов всей карты.
- Spatial-neighbor query и local movement убрали доказанные промежуточные массивы/таблицы, сохранив конечную сортировку по entity ID и исходный порядок арифметики. Попытка изменить порядок floating-point нормализации была отклонена, поскольку изменила canonical hash.

| Workload, 400×400 | Command до → после | Fixed tick p95 до → после | Canonical SHA-256 |
|---|---:|---:|---|
| 2 × 500 active | 8209 → 815 мс | 196,86 → 141,70 мс | `f8a07914996a…8652`, совпадает |
| 8 × 500 active | 17041 → 5441 мс | 947,27 → 757,65 мс | `3707915a9c01…8b11`, совпадает |

В итоговом 8×500 профиле восемь команд приняты, 4000 юнитов продолжают активный марш. Все 4000 сегментов использовали общий предварительно проверенный коридор. Остаточная стоимость command phase теперь сосредоточена в подготовке/регистрации member routes (`formation.member_routes` p95 `943,71` мс на группу), а не в A*. В активном fixed tick измеренные владельцы: `unit_orders` p95 `541,65` мс, task dispatch `376,14` мс, neighbor query `174,85` мс, local calculation `133,07` мс, component sync `89,66` мс и integration `54,84` мс.

Это архитектурно требуемая модель «общий маршрут на марше — связанные индивидуальные маршруты при препятствии или конкретной цели», но ещё не performance gate. Следующий пакет должен менять представление и обработку самого группового марша, не ослабляя детерминизм, коллизии, локальное уточнение и переход в индивидуальный бой.

## 6. E6-003 — точный active-tick hot path

Следующий пакет не меняет частоту симуляции и не разрежает решения юнитов. Он устраняет расходы, которые не участвуют в результате:

- радиус spatial query теперь вычисляется из реального порога local avoidance `1.6 × (оба footprint + clearance)`, а не из произвольной дополнительной мировой единицы; глобальные максимумы гарантируют, что ни один потенциально влияющий сосед не исключён;
- neighbor buffer и de-duplication generations переиспользуются, окончательная сортировка по entity ID сохранена и выполняется только при фактическом нарушении порядка;
- полный runtime unit schema получает эквивалентную allocation-free component projection без `has/get/default` для каждого поля; отдельный contract сравнивает её результат с общим `sync_dynamic`;
- formation cohesion больше не создаёт Dictionary на каждого участника, а lifecycle reconciliation проходит `FormationGroup.member_ids` через O(1) entity index вместо полного сканирования мира для каждой группы;
- плоский elevation grid возвращает нулевую высоту без четырёх Dictionary lookup на каждого движущегося юнита; счётчик ненулевых вершин поддерживается при каждой мутации;
- полностью пассивный combat roster не строит изменяющуюся world signature, а уже упорядоченный combat roster не сортируется повторно.

| Workload, 400×400 | E6-002 p95 | E6-003 p95 | Изменение | Canonical SHA-256 |
|---|---:|---:|---:|---|
| 2 × 500 formation march | 141,70 мс | 94,86 мс | −33,1% | `f8a07914996a…8652`, совпадает |
| 8 × 500 formation march | 757,65 мс | 518,63 мс | −31,5% | `3707915a9c01…8b11`, совпадает |

На последнем полном 8×500 замере `unit_orders` остаётся главным владельцем (`391,32` мс p95): neighbor query `116,01`, local calculation `111,56`, component sync `50,16`, integration `43,47`. Вне мира formation reconciliation занимает `18,21` мс, events/replay `16,75`, passive autonomy `11,37`. Разброс коротких прогонов заметен, поэтому дальнейшие stage-решения используют более длинные sample windows; приведённый результат — последний полный контрольный прогон, а не лучший из серии.

Пакет сохраняет одинаковый fixed tick, полный local avoidance, footprint checks, стабильный порядок соседей, формационный lifecycle и индивидуальные маршруты. Целевой бюджет ещё не достигнут; следующая архитектурная граница — отделить общее дальнее продвижение группы от индивидуальной ближней коррекции, не разрежая боевые/целевые решения и не меняя canonical outcome без отдельного обоснованного контракта.

## 7. E6-004 — projection на границе и cache открытого corridor

Авторитетные системы симуляции уже используют плоские runtime-поля сущностей. Дублирующие динамические поля вложенной component-схемы теперь проецируются на глубокую копию только при canonical/presentation snapshot. Это исключает запись десятков Dictionary-полей для каждого юнита каждого такта, но сохраняет точное состояние для render, save, replay и hash. Прямой component test доказывает projection transform, health и animation; lifecycle/save/replay impact-gates проходят.

Общий открытый envelope, проверенный при formation command, теперь остаётся неавторитетным кэшем у участников. Пока предлагаемая позиция внутри envelope и `NavigationGrid.revision` не изменилась, повторная footprint walkability-проверка эквивалентна уже доказанной общей проверке и пропускается. Выход за envelope, новый приказ, release или изменение карты удаляет/игнорирует кэш и возвращает полный `LocalMovement` contract.

| Workload, 400×400 | E6-003 p95 | E6-004 p95 | Canonical SHA-256 |
|---|---:|---:|---|
| 2 × 500 formation march, 2+3 ticks | 94,86 мс | 79,25 мс | `f8a07914996a…8652`, совпадает |
| 8 × 500 formation march, 2+3 ticks | 518,63 мс | 409,30 мс | `3707915a9c01…8b11`, совпадает |
| 8 × 500 formation march, 3+20 ticks | — | 355,28 / 422,84 мс p50/p95 | новый длинный baseline `add690acb205…b95` |

На коротком 8×500 срезе route cache уменьшил local calculation p95 `94,91 → 49,33` мс относительно уже перенёсшего projection E6-004 pre-cache среза; component sync в fixed tick равен нулю. На длинном срезе `unit_orders` остаётся главным владельцем (`317,11` мс p95): neighbor query `127,51`, local calculation `52,16`, integration `46,21`. Все 4 000 юнитов продолжают марш. Бюджет 50 мс и запас 30% пока не достигнут.

## 8. E6-005 — общий марш собранного строя

Предыдущий `formation_march` начинал с широкой региональной сетки и фактически одновременно измерял перестройку 500 участников и последующий марш. Теперь это разные воспроизводимые нагрузки: `formation_assemble` сохраняет старую раскладку, а `formation_march` создаёт тех же 500 Clubman в точных BLOCK-slots у начала маршрута. Это позволяет отдельно оптимизировать обычное дальнее продвижение и дорогой tactical reformation, не скрывая ни одно из них.

Общий режим включается только когда каждый живой участник группы движется в soft slot с одинаковым оставшимся displacement и effective speed, не находится в recovery, а максимальные footprint/clearance безопасны для spacing. Тогда все попарные расстояния сохраняются одной трансляцией. Консервативный group AABB broad phase проверяет другие группы и одиночные сущности. Если рядом никого нет и corridor envelope открыт, внутренний neighbor scan и повторная terrain/local-avoidance работа не могут изменить результат и пропускаются. Внешний контакт сохраняет external avoidance; первая деформация, другой speed/task, stuck, unsafe footprint или revision сетки возвращают полный индивидуальный путь.

| Workload, 400×400, 3+20 ticks | Command | Fixed tick p50/p95/max | Unit orders p95 | Canonical SHA-256 |
|---|---:|---:|---:|---|
| 2 × 500 shared formation march | 485,19 мс | 50,16 / 62,63 / 90,20 мс | 34,33 мс | `0bacd4f86f9b…1e95` |
| 8 × 500 shared formation march | 4604,44 мс | 237,18 / 256,86 / 346,41 мс | 147,68 мс | `eb89955c1e84…a6b2` |

В 8×500 длинном окне зафиксировано 80 000 shared/isolated member-ticks, то есть все 4000 участников использовали доказанный общий режим на всех 20 измеряемых тактах. Внутри `unit_orders`: formation cohesion `33,52` мс p95, neighbor query `20,13`, local calculation `8,22`, integration `39,71`. Отдельный integration scenario подтверждает неизменное spacing, отсутствие overlap, восстановление внешнего avoidance и инвалидирование corridor cache при navigation revision. Runtime hints удаляются из canonical/presentation snapshots.

## 9. E6-006 — специализированный индекс мобильных сущностей

Статические объекты по-прежнему регистрируют весь footprint во всех пересекаемых ячейках: это удобно для редких obstacle/resource/building queries. Мобильные сущности теперь хранятся ровно один раз — по центральной ячейке — в data-oriented массивах `entity/position/radius`. Запрос расширяет диапазон ячеек на максимальный мобильный радиус, после чего применяет прежнюю точную круговую/AABB-проверку с собственным радиусом кандидата. Позиция и радиус фиксируются при построении индекса, поэтому последовательное перемещение юнитов внутри такта не меняет snapshot соседей и не вводит зависимость от порядка обработки.

Это удаляет per-unit Dictionary wrapper, многократную регистрацию одного footprint и generation-based de-duplication из горячего пути. Стабильная сортировка по EntityId, общий поиск целей/выбора, external-formation filter и прежняя геометрия distance checks сохранены. Прямой тест дополнительно проверяет крупный footprint, точную границу попадания, использование позиции на начало такта, неполную selection-запись и переиспользуемый neighbor buffer.

| Workload, 400×400 | Fixed tick p50/p95/max | Spatial index p95 | Neighbor query p95 | Canonical SHA-256 |
|---|---:|---:|---:|---|
| 8 × 500 shared march, 3+20 | `216,94 / 236,04 / 240,05` мс | `15,17` мс | `18,62` мс | `5dea1e756cae…78ba` |
| 8 × 500 formation assemble, 3+20 | `280,82 / 304,82 / 325,22` мс | `11,45` мс | `64,11` мс | `c75e75c7f1f…4859` |

Для чистого A/B предыдущий commit `26b1fa38` повторно измерен из отдельного worktree тем же бинарником и теми же параметрами: shared march дал `239,49 / 320,87` мс p50/p95, spatial index `27,77` мс и neighbor query `26,29` мс. Новый вариант дал тот же полный canonical hash `5dea1e…78ba`; различие с ранее сохранённым E6-005 hash оказалось не следствием индекса — повторный запуск самого E6-005 commit воспроизводит новый контрольный hash. Интеграционные gates движения, автономного боя, pointer selection, navigation stress, shared formation и replay проходят.

## 10. E6-007 — матрица активных нагрузок и timing боя

Один идеальный formation march больше не используется как заместитель всей игры. Manual benchmark теперь разделяет шесть нагрузок: `passive_full_population`, уже собранный `formation_march`, исходное `formation_assemble`, независимый `individual_crossing`, публичный `group_click_reservation` и парный `combat_contact`. Командная фаза хранится отдельно от последующих fixed ticks.

- `individual_crossing 8×500 / 2+3`: приняты и остаются активны все 4000 юнитов; p50/p95 `298,46 / 313,89` мс, `unit_orders` `248,57`, neighbor query `59,14`, local calculation `97,52`, integration `37,41`; canonical SHA-256 `a476eff76b04…5d8`.
- Первый `combat_contact 8×500 / 2+3`: p50/p95 `488,12 / 504,87` мс, animation `172,87`, task `154,25`; SHA-256 `524337057386…ff`. Это отдельный худший active owner, а не оценка обычного раннего матча.
- Боевой hot path раньше для каждого атакующего на каждом такте заново находил source graphic и выполнял глубокое копирование полного Dictionary. Теперь неизменяемый timing `damage/projectile frame + frame rate` кэшируется по kind/team/source/worker-role source и инвалидируется при смене catalog/civilization/technology. На том же коротком окне хэш полностью совпал, p95 fixed tick `493,26` мс, animation `153,01` мс против `172,87`. Короткий трёхтактовый срез является направленным A/B, а не финальным stage gate.

Полный `group_click_reservation 8×500` до следующего пакета не дошёл до первого fixed tick более чем за три минуты и был остановлен. Поэтому проблема зафиксирована отдельным command workload и не маскируется метриками уже выданного приказа.

## 11. E6-008 — массовый приказ и конечные позиции

Профиль массового клика обнаружил два независимых повтора: каждая проверка кандидата линейно обходила все ранее занятые конечные позиции, а каждый участник строил и сортировал те же кольца кандидатов с начала; после назначения каждый юнит отдельно запускал A* по полностью открытой области.

- Reservations получили точный spatial bucket index; мобильная конечная позиция хранится в одном bucket, а collision check рассматривает только ячейки в сумме радиусов. Освобождение удаляет запись из обоих индексов; максимальный радиус может только консервативно расширить запрос до `clear()`.
- Для последовательности с одинаковой точкой, радиусом, доменом, restriction и revision порядок ring offsets кэшируется, а поиск продолжается после последнего успешного кандидата. Любое фактическое освобождение позиции или изменение сигнатуры сбрасывает cursor; tie-break и итоговые координаты сохранены.
- Обычный групповой MoveCommand сначала освобождает старые позиции всей выборки, затем детерминированно резервирует новые. Если единый bounding envelope всех стартов и назначений полностью проходим для максимального footprint, он проверяется один раз, после чего каждому участнику регистрируется прямой маршрут. Неодинаковый domain/restriction или препятствие сохраняют обычный индивидуальный A*.

Одинаковая шкала `2 игрока, 200×200, 0+1` до spatial index дала command wall `392,89 / 1297,97 / 4659,01` мс для `50/100/200` юнитов на игрока. После spatial index — `385,83 / 857,90 / 2205,10` мс с полностью совпадающими hashes. На `2×500` последовательные ступени дали `9197,61` мс после spatial index, `3815,75` мс после ring cursor и `326,81` мс после общего открытого маршрута; последний вариант зарегистрировал 1000 prevalidated member routes и ни одного A*. SHA-256 до/после общего маршрута одинаков: `037b60ffad48…cab`.

Полный `8×500 / 400×400` теперь принимает все восемь команд за `1246,09` мс вместо незавершённого многоминутного запуска; все 4000 участников активны, первый active tick — `343,52` мс, зарегистрировано 4000 prevalidated routes. Command latency ещё требует дальнейшей пакетной обработки, но перестала быть блокирующей. Navigation reservation/command, stress, formations, autonomous/melee combat, replay и save/load impact gates проходят.

## 12. E6-009 — стабильная фаза восстановления боя

Профиль `combat_contact` показал, что находящийся на cooldown юнит каждый такт выполнял две ложные order-transition: `Recover → FaceTarget → Recover`. Направление на цель действительно должно обновляться, но фаза приказа до готовности следующей атаки остаётся `Recover`. Теперь переход в `FaceTarget/PerformAction` происходит только при нулевом cooldown; то же правило применено к статическим атакующим объектам. Прямой тест подтверждает, что recovery tick не раздувает order history.

Длинный A/B выполнен тем же бинарником на текущем дереве и временном worktree commit `9e5e6ba6`, `8×500 combat_contact / 400×400 / 3+20`:

| Вариант | Fixed tick p50/p95/max | Combat task p50/p95 | Animation p50/p95 | Canonical SHA-256 |
|---|---:|---:|---:|---|
| E6-008 | `467,34 / 501,22 / 507,04` мс | `148,91 / 160,84` мс | `141,21 / 147,14` мс | `f27402f2c5f7…ae66` |
| E6-009 | `463,77 / 483,36 / 490,48` мс | `139,56 / 146,69` мс | `144,68 / 151,42` мс | `5aa4590c3c15…14f` |

Новый hash принят намеренно: различие — отсутствие недостоверных повторов `FaceTarget/Recover` во внутренней bounded history, а не изменение урона, attack timing или направления. Animation/melee/order/autonomous-combat gates проходят. Боевой tick всё ещё почти в десять раз выше бюджета, поэтому E6 продолжается.

## 13. E6-010 — полный экономический цикл и инкрементальный fog

В benchmark добавлен `gather_economy`, использующий реальный runtime/object/graphics catalog: 500 Villager на игрока распределены по выровненным по navigation grid Berry Bush, совместимым Granary и выполняют обычный `gather → carry → deposit → return`. Источники разделены максимум по два работника, поэтому тест не подменяется искусственной очередью у одного объекта. Отчёт отдельно фиксирует принятые команды, gather/deposit cycles, несущих груз работников и stockpile каждого игрока.

Контрольный `2×500 / 400×400 / 520+240` до оптимизации дал `137,89 / 204,11` мс p50/p95 fixed tick, `60,00 / 69,99` мс fog и `51,83 / 115,66` мс task. Все 1000 работников активны; завершены 988 разгрузок и 11 671 акт сбора.

Gameplay fog переведён с полного сброса visible-состояния всей карты на счётчики перекрытия и дельты footprint каждого источника зрения. Движущиеся источники равномерно распределены по четырём deterministic buckets; смерть, появление, изменение команды/радиуса и явный запрос обновляются немедленно, обычное перемещение — не позднее трёх последующих fixed ticks (150 мс). Это ограничивает кадр без потери explored history и создаёт единый seam для будущего terrain/elevation occlusion.

После изменения тот же профиль дал `91,52 / 150,92` мс fixed tick, а fog — `17,62 / 21,45` мс. Sample wall уменьшился `35,21 → 23,18` с. Экономический итог точен и совпадает: 988 разгрузок, 11 671 сбор, food `5060/5000`; изменился canonical hash, поскольку bounded visibility cadence намеренно входит в авторитетное fog-состояние. Fog/visibility/diplomacy/combat-awareness tests закрепляют overlap counts, принудительное немедленное обновление и верхнюю границу bucket-цикла.

Оставшийся владелец нагрузки теперь измерен, а не предполагается: `unit_orders.task` даёт `49,04 / 106,65` мс, 893 возвратных path query — `4,19 / 8,14` мс каждый. Синхронный переход большой группы способен собрать сотни малых A* в одном такте. Следующий пакет сравнивает общий flow/corridor для одинаковой точки сдачи с нативным data-oriented navigation kernel; перенос в GDExtension разрешён именно для этого измеренного владельца, но экономика, footprint contract и deterministic result остаются в GDScript-authoritative API.

## 14. Следующие профили и запреты

1. Расширить formation-профили отдельными `formation_assemble`, crossing-groups, narrow-corridor и combat-transition окнами. Общий марш уже не должен оптимизироваться ценой перестроения, сжатия/восстановления или внешнего avoidance.
2. Сохранить отдельные `move/local-avoidance/combat/gather` workloads и устранять только их измеренные полные обходы/повторные вычисления; следующий gather-owner — пакетные маршруты source/drop-site, а не изменение скорости или вместимости рабочих.
3. Добавить активный 2/4/8-player AI/combat workload, отдельно измеряя snapshot и planning cadence.
4. Добавить render baseline с world/minimap fog, source composite/player colour, culling, draw calls, CPU frame и GPU frame. Headless simulation numbers не являются доказательством плавного UI.
5. Повторить после retained fog chunks и общего world/minimap cache; camera pan не должен менять canonical hash или инициировать полный authoritative rebuild.
6. Не переходить на MultiMesh, сторонний ECS, C# или GDExtension без профиля соответствующего владельца. E6-010 теперь разрешает узкий прототип GDExtension для path/flow/local-movement массивов: публичный command/order API, authoritative экономика и сериализация остаются движковыми, а чистый вычислительный kernel обязан иметь GDScript fallback, одинаковый deterministic outcome и lifecycle/save/replay regressions. Намеренное улучшение movement/formation может создать новый hash baseline только после отдельного UX/collision/stress/replay gate; изменение характеристик, экономики или правил боя этим не разрешается.

Текущий deadline фиксированного 20-Гц тика `50 мс` ещё не достигнут: true-march даёт p95 `236,04` мс, individual crossing `313,89` мс и combat contact около `493` мс на экстремальном `8×500 all-active`; полный gather-cycle даёт `150,92` мс на `2×500`. Эти числа не следует трактовать как FPS или как обычную экранную нагрузку. Значения 4/8×500 для экономики выполняются после устранения измеренного path burst, чтобы не тратить многоминутный прогон на известный синхронный blocker. E6 остаётся открытым.

Performance gates с E6-011 разделены:

1. **Simulation deadline:** `p95 < 50 мс` означает, что 20-Гц авторитетная симуляция не накапливает долг.
2. **Comfort/headroom:** реалистичный смешанный матч `2/4/8 × 500` должен иметь `p95 ≤ 35 мс`, оставляя не менее 30% бюджета для новых механик.
3. **Main-thread/render:** пока симуляция и presentation делят главный поток, отдельно измеряется sim slice на tick-кадрах (`8–15 мс` как целевой диапазон) и полный CPU/GPU frame против `16,67 мс` для 60 FPS. Видимая сцена тестируется отдельно от общего числа сущностей матча.
4. **Extreme stress:** `8×500 all-active` одновременно заставляет 4 000 сущностей двигаться, искать путь или сражаться. Это ворота на отсутствие runaway, многосекундных stalls и неограниченного simulation debt, а не обещание, что все 4 000 обычно находятся на экране или принимают сложное решение каждый тик.
5. **Offscreen authority:** камера разрешает culling и batching только presentation. Дальние idle/маршевые группы удешевляются через event-driven/sparse systems, activity sectors и общий групповой маршрут, сохраняя детерминированный исход мира.

## 15. E6-011 — нативный deterministic A* без переноса правил игры

Измеренный A* owner вынесен в отдельный `RoRPathKernel` GDExtension. Он хранит плоские arrays стоимости/родителей/generation stamp и бинарную кучу без per-node Dictionary allocations. Входом служит revisioned byte mask базовой проходимости для одной пары movement-domain/restriction; clearance вычисляется внутри kernel по тому же четырёхточечному footprint contract. Direction order, diagonal corner rule, octile heuristic и score/y/x tie-break повторяют fallback. GDScript по-прежнему выбирает nearest goal, проверяет прямой путь, сглаживает raw cells и владеет command/order/economy/save/replay. Отсутствующая DLL автоматически оставляет прежний путь активным.

Контрольный последовательный A/B, `gather_economy 2×500 / 400×400 / 520 warmup + 240 sample`:

| Метрика | GDScript | Native kernel |
|---|---:|---:|
| command wall | 1171,38 мс | 649,89 мс |
| sample wall | 23,11 с | 21,37 с |
| fixed tick p50 / p95 / max | 90,27 / 149,42 / 263,04 мс | 90,51 / 106,51 / 126,70 мс |
| world advance p95 | 143,74 мс | 100,38 мс |
| unit orders p95 | 117,17 мс | 74,39 мс |
| task p95 | 106,17 мс | 63,41 мс |
| path query p50 / p95 / max | 3,759 / 8,588 / 12,849 мс | 0,786 / 0,944 / 1,267 мс |

В обоих прогонах выполнены 893 path request: 324 прямых и 569 A*. Результат полностью совпадает — 11 671 gather, 988 deposits, food `5060/5000`, canonical SHA-256 `3a2e5d64f4f800028f5b3689015bf178139da9efbf00913bc969cbe1ab9b49d7`. До prewarm построение маски занимало 1846,85 мс внутри первой массовой команды; теперь уникальные movement/restriction masks активных unit готовятся после bulk-load. Это увеличивает стадию загрузки карты, но устраняет пользовательский first-click hitch. Следующая оптимизация должна атаковать оставшиеся `63,41` мс task dispatch и синхронность волны return/deposit, а не переносить экономику или весь мир в C++.

## 16. E6-012 — нативное локальное избегание с GDScript-authority

Stage-профиль того же workload разделил `simulation.unit_orders.task`: approaching и returning давали p95 около `40,0/44,9` мс, harvesting `17,5` мс; агрегированные neighbor query, local calculation и integration занимали `8,6 + 20,8 + 9,1` мс. Это подтвердило локальное движение как следующий владелец, а не послужило поводом переносить весь unit/order loop.

`RoRPathKernel` теперь также получает один immutable snapshot позиции, радиуса, clearance, push priority и здоровья на tick. Для каждой movement-domain/restriction mask он строит нативный spatial hash, собирает соседей в стабильном ID-порядке и повторяет прежнюю avoidance/terrain-alternative арифметику. Результат — только proposed velocity и diagnostic state. GDScript по-прежнему интегрирует позицию, обновляет facing/elevation, выполняет arrival, recovery/repath/stop и все задачи. Отсутствующая DLL отключает одновременно оба native kernels и оставляет прежний алгоритм.

Последовательный A/B `gather_economy 2×500 / 400×400 / 520+240`, уже с одинаковым stage instrumentation:

| Метрика | GDScript movement | Native local kernel |
|---|---:|---:|
| sample wall | 21,96 с | 19,70 с |
| fixed tick p50 / p95 | 92,30 / 109,526 мс | 80,782 / 95,566 мс |
| world advance p95 | 103,761 мс | 88,925 мс |
| unit orders p95 | 75,690 мс | 62,058 мс |
| task p95 | 63,742 мс | 45,671 мс |
| snapshot preparation p95 | — | 5,065 мс |
| neighbor query p95 | 8,631 мс | 3,435 мс |
| local calculation p95 | 20,837 мс | 4,227 мс |
| movement integration p95 | 9,064 мс | 8,726 мс |
| fog p95 | 22,314 мс | 22,419 мс |

Оба прогона дали 11 671 gather, 988 deposits и food `5060/5000`; три native прогона повторили canonical hash `c4244f120085360a47d0b53aaf786f4396e48ad135c73190fa66ffaa90bcc747`. Он отличается от GDScript baseline из-за допустимого нового floating-point пути movement, а не из-за правил экономики. Принятие прошло через kernel parity, gather/return/snapshot, local movement, stuck recovery, formation interaction/shared motion, navigation stress и deterministic replay tests. Live component facade после gather/deposit сохраняется узкой carrier-only синхронизацией. Comfort gate всё ещё открыт: фиксированный p95 `95,6` мс выше simulation deadline `50` и цели `35` мс. Следующие владельцы — remaining gather-stage work и fog; snapshot duplication для нескольких movement domains отдельно измеряется на naval/mixed workload до дальнейшего расширения C++.

## 17. E6-013 — нативная геометрия vision footprint без переноса fog authority

Внутренний stage-профиль fog на текущем `2×500` показал p95: ensure players `1,115` мс, collect sources `16,180`, внутри него `_vision_cells` `9,460`, reconcile overlap counts `5,443`. Первый безопасный шаг заменил строковые `unit:ID/building:ID` ключи на `(ID << 1) | category`; fog p95 снизился `22,246 → 20,722` мс, canonical state не изменился.

После этого добавлен отдельный `RoRVisibilityKernel`. Его единственный gameplay-вызов получает map size, center и radius и возвращает тот же отсортированный row-major `PackedInt32Array`. Вся семантика игрока/союза, source lifecycle, overlap counts, UNKNOWN/EXPLORED/VISIBLE, revision, snapshot и terrain-conforming presentation остаётся в `RoRFogOfWar`. Отсутствующая DLL или `--native-visibility=false` использует исходную GDScript-геометрию.

Последовательный A/B после integer-key шага, `gather_economy 2×500 / 400×400 / 520+240`:

| Метрика | GDScript geometry | Native visibility kernel |
|---|---:|---:|
| sample wall | 19,09 с | 16,56 с |
| fixed tick p50 / p95 | 77,972 / 94,530 мс | 67,344 / 81,784 мс |
| world advance p95 | 88,044 мс | 76,172 мс |
| fog p50 / p95 | 17,172 / 20,722 мс | 9,837 / 10,987 мс |
| collect sources p95 | 15,027 мс | 5,769 мс |
| vision geometry p95 | 9,647 мс | 0,835 мс |
| reconcile p95 | 5,126 мс | 4,523 мс |
| unit orders p95 | 61,325 мс | 58,680 мс |
| unit task p95 | 44,535 мс | 42,959 мс |

Hash `c4244f120085360a47d0b53aaf786f4396e48ad135c73190fa66ffaa90bcc747`, 11 671 gather, 988 deposits и food `5060/5000` совпали. Exact native/GDScript footprints проверены для центра, границ, fractional и zero radius; fog/visibility, diplomacy, replay и save/load проходят. Observability test теперь корректно принимает как A* expanded nodes, так и direct-path resolution: открытый прямой маршрут не обязан искусственно запускать A*. Deadline `50` и comfort `35` мс ещё открыты; следующий измеренный owner — GDScript unit task/gather validation, а не дальнейшее расширение fog kernel без нового профиля.

## 18. E6-014 — устранение временных объектов в gather hot path

Профиль E6-013 показал, что после ускорения path/local movement/fog главным остаточным владельцем остаётся `unit_orders.task`. Каждый из 1000 рабочих на каждом такте создавал Dictionary с `moving/animation_state`, повторно проходил общий worker/tag contract и заново запрашивал неизменяемый `allowed_gatherer_domains` из каталога. Эти операции заменены внутренним integer state code и чтением уже нормализованной runtime schema. Совместимость старых сохранений/ручных fixtures остаётся на границе при отсутствии закэшированного resource field.

Сопоставимый `gather_economy 2×500 / 400×400 / 520+240`, все native kernels включены:

| Метрика | E6-013 | E6-014 |
|---|---:|---:|
| sample wall | 16,56 с | 15,41 с |
| fixed tick p50 / p95 | 67,344 / 81,784 мс | 62,453 / 76,760 мс |
| fixed tick max | — | 92,265 мс |
| world advance p95 | 76,172 мс | 70,988 мс |
| unit orders p95 | 58,680 мс | 53,276 мс |
| unit task p95 | 42,959 мс | 38,195 мс |
| approaching p95 | 24,139 мс | 19,647 мс |
| harvesting p95 | 16,921 мс | 13,813 мс |
| returning p95 | 25,901 мс | 24,050 мс |
| fog p95 | 10,987 мс | 11,199 мс |
| native movement snapshot p95 | — | 4,192 мс |
| movement integration p95 | — | 8,181 мс |

Canonical hash `c4244f120085360a47d0b53aaf786f4396e48ad135c73190fa66ffaa90bcc747` и экономический итог полностью совпали: 11 671 gather, 988 deposits, food `5060/5000`, 693 несущих ресурсы юнита. Gather/dropoff, naval economy, deterministic replay и save/load impact gates проходят. Deadline `50` и comfort `35` мс ещё не достигнуты. Следующий профиль разделяет returning-stage lookup/transition и движение, а также проверяет стоимость подготовки native movement snapshot; новый нативный перенос допустим только при подтверждённом вычислительном ядре.

## 19. E6-015 — однородный movement snapshot и boundary-normalized gather

`prepare_native_movement_snapshot` раньше каждый такт заново создавал шесть packed arrays, форматировал `movement_domain:restriction` для каждого юнита и строил два промежуточных Dictionary даже когда все 1000 участников принадлежали одной конфигурации. Теперь arrays переиспользуются, однородный состав получает один shared kernel, а mixed-domain путь сохраняет прежнее раздельное назначение. Отдельный native regression проверяет одновременные land/water units.

В gather hot loop найден eager fallback языка: выражение по умолчанию `resource.get("resource_type_id", resource_type_for(...resource_stats...))` вычисляло catalog lookup до вызова `get`, даже когда готовое поле существовало. Нормализованное поле теперь читается напрямую, а fallback остаётся только для старых/ручных fixtures. Совместимость команды с team/domain по-прежнему проверяется при назначении; ownership transfer и смена роли явно отменяют приказ, поэтому их повторный lookup каждый fixed tick устранён.

Сопоставимый `gather_economy 2×500 / 400×400 / 520+240`:

| Метрика | E6-014 | E6-015 |
|---|---:|---:|
| sample wall | 15,41 с | 14,11 с |
| fixed tick p50 / p95 | 62,453 / 76,760 мс | 57,582 / 70,570 мс |
| world advance p95 | 70,988 мс | 64,860 мс |
| unit orders p95 | 53,276 мс | 48,117 мс |
| unit task p95 | 38,195 мс | 35,210 мс |
| approaching p95 | 19,647 мс | 17,166 мс |
| harvesting p95 | 13,813 мс | 11,608 мс |
| returning p95 | 24,050 мс | 24,046 мс |
| native movement snapshot p95 | 4,192 мс | 1,715 мс |

Hash `c4244f120085360a47d0b53aaf786f4396e48ad135c73190fa66ffaa90bcc747`, 11 671 gather, 988 deposits, food `5060/5000` и 693 carrying units совпали. Gather/return/naval economy, pathfinder mixed-domain и deterministic replay gates проходят.

Дополнительный aggregate профиль не изменяет симуляцию и суммирует уже измеренное время path запросов внутри одного тика. Он показал `simulation.navigation.path_queries` p95 `10,041` мс, max `20,972` мс при p95 отдельного запроса `0,937` мс. Расширенный exact-cache эксперимент не дал попаданий или улучшения: волна состоит из разных текущих позиций и конечных slots, поэтому изменение ключа удалено. Следующий архитектурный owner — revisioned source/drop-site corridor: один дальний маршрут на группу с индивидуальными конечными слотами/local avoidance и автоматическим fallback при препятствии или изменении navigation revision.

## 20. E6-016 — native direct-cell и smoothing geometry

Перед введением нового flow/corridor контракта измерена стоимость уже существующего request. После нативного A* каждый запрос по-прежнему выполнял GDScript direct-cell traversal и greedy smoothing с повторными line-of-sight проверками. Обе операции являются чистой геометрией над той же revisioned byte mask, поэтому добавлены в `RoRPathKernel`; ближайшая допустимая цель, exact world endpoint, movement domain/restriction/clearance selection, `NavigationService` envelope, order/path lifecycle и fallback остались в GDScript.

Новый parity test сравнивает полные world paths native/fallback на прямом пути, препятствиях, обратном направлении и clearance. Direction order, diagonal corner rule, heap tie-break и smoothing contract сохранены. Последовательный A/B `gather_economy 2×500 / 400×400 / 520+240`:

| Метрика | E6-015 aggregate profile | E6-016 |
|---|---:|---:|
| sample wall | 14,14 с | 13,84 с |
| fixed tick p50 / p95 / max | 57,644 / 71,076 / 88,280 мс | 57,271 / 65,622 / 74,122 мс |
| world advance p95 | 65,512 мс | 58,604 мс |
| unit orders p95 | 48,959 мс | 41,376 мс |
| unit task p95 | 36,170 мс | 27,539 мс |
| returning p95 | 24,193 мс | 21,439 мс |
| aggregate path p95 / max | 10,041 / 20,972 мс | 1,329 / 3,290 мс |
| single path request p95 | 0,937 мс | 0,095 мс |

Оба прогона: 893 запроса, 324 direct hits, 569 A*, 9324 expanded nodes, canonical hash `c4244f120085360a47d0b53aaf786f4396e48ad135c73190fa66ffaa90bcc747`, 11 671 gather, 988 deposits, food `5060/5000`, 693 carriers. Pathfinder/navigation stress, gather/return/naval economy, deterministic replay и save/load gates проходят.

Deadline `50` и comfort `35` мс ещё открыты. После снятия route burst основные владельцы — movement integration p95 `8,451` мс, fog `11,693`, per-unit preparation `6,412` и оставшийся task `27,539`. Следующий профиль должен сначала разделить эти уже измеренные расходы; source/drop-site flow/corridor вводится только если mixed 4/8×500 подтвердит повтор дальних маршрутов, а не как обязательное усложнение однородного теста.

## 21. E6-017 — нулевые операции unit preparation и movement integration

Общий unit loop выполнял одинаковую работу для несовместимых типов: заново писал уже нулевые cooldown/work, входил в conversion component lookup для каждого крестьянина и проверял behavior tags до того, как обнаруживал отсутствующую retaliation target. Movement делал несколько эквивалентных square roots, каждый такт записывал normal stuck state, вызывал clamp далеко от края и пересчитывал нулевую elevation на полностью плоской карте.

Fast paths сохраняют порядок систем и fixed cadence. Положительные таймеры уменьшаются как прежде; enabled converter получает прежний faith update; huntable с target выполняет полный прежний handler. Arrival/overshoot/progress сравниваются по квадратам расстояний, `StuckRecovery.update()` сохраняет строковый публичный facade, а runtime использует `update_squared()`. Неплоская карта всегда сохраняет полный elevation path, пограничная позиция — прежний clamp.

Сопоставимый `gather_economy 2×500 / 400×400 / 520+240`:

| Метрика | E6-016 | E6-017 |
|---|---:|---:|
| sample wall | 13,84 с | 13,00 с |
| fixed tick p50 / p95 | 57,271 / 65,622 мс | 53,977 / 61,109 мс |
| world advance p95 | 58,604 мс | 54,636 мс |
| unit orders p95 | 41,376 мс | 36,501 мс |
| preparation p95 | 6,412 мс | 2,786 мс |
| unit task p95 | 27,539 мс | 26,706 мс |
| movement integration p95 | 8,451 мс | 7,472 мс |
| fog p95 | 11,693 мс | 12,009 мс |

Canonical hash `c4244f120085360a47d0b53aaf786f4396e48ad135c73190fa66ffaa90bcc747`, 11 671 gather, 988 deposits, food `5060/5000` и 693 carriers совпали. Priest/conversion, huntable resource, stuck/local movement, gather/return, navigation stress, deterministic replay и save/load gates проходят. Следующие измеренные владельцы — fog collect/reconcile и remaining gather/movement task; deadline `50` и comfort `35` мс остаются открыты.

## 22. E6-018 — revisioned и пакетное согласование fog sources

Профиль E6-017 разделил fog p95 `12,009` мс на collect `6,198` и reconcile `5,284` мс. Геометрия уже занимала меньше миллисекунды, поэтому расширение C++-границы не требовалось. Runtime source fields читаются из нормализованной schema; неизменившийся source переиспользует прежнюю запись, а изменившийся получает локальную числовую revision. Она не входит в canonical snapshot и заменяет глубокое сравнение словаря вместе с массивом клеток.

Reconcile сохраняет прежний stable source order и overlap semantics, но сначала собирает add/remove/replace deltas. Для каждого observer `PackedByteArray states` и `PackedInt32Array counts` извлекаются один раз, все deltas применяются к этой паре, после чего buffers записываются обратно один раз. Player/alliance ownership, topology rebuild, UNKNOWN/EXPLORED/VISIBLE transitions, public revision, snapshots, save/load, presentation и GDScript visibility authority остались прежними.

Сопоставимый `gather_economy 2×500 / 400×400 / 520+240`:

| Метрика | E6-017 | E6-018 |
|---|---:|---:|
| sample wall | 13,00 с | 12,30 с |
| fixed tick p50 / p95 / max | 53,977 / 61,109 / 72,943 мс | 50,903 / 56,580 / 64,606 мс |
| world advance p95 | 54,636 мс | 50,887 мс |
| fog p95 | 12,009 мс | 9,988 мс |
| fog ensure p95 | 1,008 мс | 0,348 мс |
| fog collect p95 | 6,198 мс | 4,907 мс |
| fog reconcile p95 | 5,284 мс | 4,766 мс |
| unit orders p95 | 36,501 мс | 34,916 мс |
| unit task p95 | 26,706 мс | 25,545 мс |

Canonical hash `c4244f120085360a47d0b53aaf786f4396e48ad135c73190fa66ffaa90bcc747`, 11 671 gather, 988 deposits, food `5060/5000` и 693 carriers совпали. Fog unit tests, bounded visibility refresh, diplomacy, deterministic replay, canonical snapshot, save/load и versioned archive gates проходят. Deadline `50` и comfort `35` мс ещё открыты; следующий measured owner — gather/movement task, после чего выполняются mixed 4/8×500 и visible render profiles.
