# Контракт морской вертикали RoR

Статус: source-driven вертикаль I12-019A…F `INTEGRATED`; executable-level `PARITY` ещё не заявляется  
Дата контрольной точки: 2026-09-12

## Цель и границы

Морская вертикаль воспроизводит данные и правила Rise of Rome для Dock, рыбы, рыболовства, торговли, транспорта и боя. Современный поиск пути, предотвращение наложений и формации остаются разрешёнными отличиями. Баланс, эпохи, технологии, ограничения цивилизации, графика и звук берутся из исходных каталогов, а не подбираются вручную.

## Проверенный source-контракт первого среза

- Dock: source 45, Bronze replacement 133, terrain restriction 6. Допустимые исходные поверхности: Water 1, Beach 2, Shallows 4 и WaterDark 22. Базовая стоимость 100 wood; Roman modifier даёт 85 wood. Время строительства 50 секунд, базовый work rate 1.5, 350 HP. Presentation: graphic 212, construction 85, death 216, damage 805/806/807; Bronze root graphic 859, construction 84, death 215, damage 131/132/133.
- Fishing Boat: source 13, class 21, terrain restriction 3, 45 HP, speed 1.4, work rate 0.4, capacity 15, стоимость 50 wood, время 40 секунд, producer/drop site 45. Presentation: idle/move 42, work 43, death 176. Fishing Ship source 14: 75 HP, speed 2, capacity 20, presentation 44/784; technology 4, 50 food + 100 wood, 30 секунд, Bronze Age.
- Fisherman: task form 119, terrain restriction 7, work rate 0.6, capacity 10, presentation 299/680/469/89/185, corpse 150, исходные drop sites 103/109.
- Deep Fish: source 52/53, graphic 316, capacity 250, terrain restriction 3. Shore Fish: source 260/263, graphics 318/319, capacity 250, terrain restriction 3. Source 370 подтверждён как Whale: food capacity 250, terrain restriction 3, graphic 321 / SLP 689, 34 кадра с source timing; runtime/random-map evidence интегрировано.
- Dock completion technology 0 и возрастные technologies 101–103 открывают проверенные production/research paths всех корабельных линий. Technologies 1–9 и 25 реализуют торговые, транспортные и боевые улучшения; Roman-disabled technology 118/Fire Galley 360 остаётся корректно недоступной.

## Проверенный source-контракт транспорта и боя

- Trade Boat 15 -> Merchant Ship 16 и Light Transport 17 -> Heavy Transport 18 производятся и улучшаются исходными Dock-технологиями. Hull/sail presentation использует общий composite unit renderer.
- Transport имеет отдельный сериализуемый cargo component и публичные Board/Unload commands. Capacity, ownership, fog, подход к берегу, смерть перевозчика, population и canonical/replay state проверяются общим simulation pipeline.
- Scout Ship 19 -> War Galley 20 -> Trireme 21 и Catapult Trireme 250 -> Juggernaught 277 используют исходные HP, speed, range, reload, projectile и upgrade technologies. Fire Galley 360/technology 118 остаётся недоступной Romans.
- Снаряд Catapult Trireme 368 использует исходную скорость, area damage, friendly fire и impact graphic 270. Формула attack/armor исправлена до RoR-контракта: отсутствующий armor class равен нулю, вклады классов суммируются до единственного minimum damage, здания получают коэффициент 0.2 и минимум 0.1.

## Проверенный контракт морской торговли

- Trade Boat/Merchant Ship принимает обычную replayable `TradeCommand` на исследованный чужой Dock и отдельную `SetTradeResourceCommand` для food/wood/stone. Собственный Dock целью быть не может.
- Общий для целевого игрока pool начинается с исходных 0 goods, восстанавливается на 1/с до 100 с начала матча и расходуется партиями по 20. При нехватке goods или собственного выбранного ресурса судно ждёт у цели, не списывая ресурс заранее.
- После загрузки 20 единиц судно возвращается в ближайший к цели собственный завершённый Dock, зачисляет gold и повторяет маршрут. Обычный stockpile владельца целевого Dock не меняется.
- Route stage, cargo, pool и policy входят в canonical snapshot/replay. Presentation скрывает приватные route/cargo fields от чужого observer. HUD и contextual cursor создают только публичные команды.
- Exact map-size-dependent distance-to-gold curve из executable пока не измерена. Жизненный цикл не зависит от неё: монотонная ограниченная реализация изолирована в `RoRTradeProfitPolicy` и явно сообщает `calibration_status: measurement_pending`, поэтому статус `PARITY` не заявляется.

## Архитектурные инварианты

1. `movement_domain` и `terrain_restriction_id` являются данными сущности; центральные BuildCommand, movement и gather ticks не проверяют alias Dock/Fish/Fishing Boat.
2. Проверка footprint учитывает радиус объекта, а не только центральную клетку. Placement здания задаёт допустимую поверхность и обязательные соседние domains.
3. Dock допустим только тогда, когда весь footprint соответствует source restriction и на периметре есть одновременно доступная land- и water-сторона.
4. Ресурс объявляет допустимые domains сборщика. Deep Fish отклоняет наземного Villager; Shore Fish допускает Fisherman и Fishing Boat.
5. Fishing Boat использует тот же component/order/gather/carry/drop-off pipeline, что и другие работники. Водный spawn после производства разрешается исходным restriction создаваемого корабля.
6. Drop-site совместимость учитывает source lineage здания, поэтому улучшенный Dock 133 сохраняет исходные обязанности Dock 45.
7. UI и AI могут только создавать публичные команды. Они не размещают корабль, не переносят груз и не меняют ресурсный pool напрямую.
8. Любой следующий корабль добавляется logical archetype + source variants, а не отдельной веткой центральной симуляции.
9. Seeded map публикует зарезервированные Dock footprint/staging cells, и SimulationWorld не может пересадить процедурный ресурс обратно в этот резерв во время source-aware placement correction.
10. Статические mixed-domain цели публикуют `target_domains`; Dock доступен land и water группам. Групповой AI assault использует AttackCommand и общий FormationCombat slot assignment, а не останавливается походной формацией в точке цели.

## Интегрированное доказательство

`test_naval_economy_pipeline.gd` проверяет source IDs, римскую стоимость, автоматический Dock unlock, береговую placement policy, construction presentation, water spawn, рыболовство и сдачу, Fisherman task form, Bronze Dock replacement и Fishing Ship upgrade. Random-map/bootstrap tests закрепляют Whale 370, резерв footprint/staging и фактическую доступность Dock после загрузки ресурсов. `test_transport_pipeline.gd` закрепляет production/upgrades, cargo/board/unload, death/conversion/population/fog и replay. `test_naval_trade_pipeline.gd` закрепляет source command 111, выбор ресурса, общий pool/ожидание, ближайший Dock, 20-unit transaction, gold return, повтор маршрута, information boundary и mixed-domain Dock target. `test_naval_combat_pipeline.gd` закрепляет римский combat roster, projectiles и точные 5/35 damage cases. `test_naval_presentation_effects.gd` проверяет DAT damage thresholds 50/65/75/80%, death replacement, impact lifetime и fog-safe effect/audio. `test_naval_presentation_golden.gd` фиксирует 11 source-вариантов, обе палитры, hull/sail/oars/weapon, damage/death и impact единым RGBA hash. `test_full_roster_naval_stress.gd` проводит весь флот по длинному водному маршруту и заставляет все пять combat sources выпустить правильные projectiles. `test_ai_player.gd`, `test_ai_command_pipeline.gd` и `test_mixed_domain_ai_match.gd` проверяют fleet production, trade/transport phases, явную групповую атаку, принятые команды, domain safety и terminal Conquest. `test_naval_executable_measurement_gate.gd` идентифицирует эталонную сборку, проверяет полноту будущих visual/audio/trade observations и не позволяет заявить `PARITY` при pending capture.

Контрольная точка: `A-006 suite: 138 passed, 0 failed`; cache validation — `0 errors, 181 source-owned warnings`; 52 runtime archetype; 16563 выбранных assets; контрольный импорт — `16563 cache hits, 0 misses`; Windows export и headless smoke-run успешны.

## Известные ограничения

- Roman Dock 133 ссылается на composite child graphic 860/SLP 739, отсутствующий в установленном исходном DRS. Root graphic 859 доступен; пропуск остаётся source-owned warning, без нарисованной замены.
- Composite hull/sail/oars/weapon и обе player palettes прошли структурный и RGBA-golden аудит по импортированным исходным SLP. Это регрессионное доказательство наших source bindings, но не side-by-side сравнение с кадром оригинального executable.
- Random-map generator гарантирует свободный source-valid Dock footprint и внешние land/water staging cells для каждой активной команды. Полная соревновательная балансировка береговых расстояний/ресурсов остаётся задачей расширенных random-map fairness rules.
- Economic/tactical AI различает land/water knowledge, собирает fish, строит Dock, производит флот, торгует, атакует и проводит Transport через board/sail/unload. Более сложная координация нескольких десантов остаётся будущим расширением, но базовый planner и длительное evidence завершены.
- Dock-to-Dock lifecycle интегрирован. Точная distance-to-gold policy остаётся отдельной задачей измерения оригинального executable.
- Damage/death/impact effects и доступные naval sound bindings интегрированы. Source sound 138 не содержит WAV resource (`resource_id = -1`), поэтому command voice остаётся честным source-owned пропуском без выдуманной замены. Fire Galley projectile presentation не входит в римский playable roster и остаётся общим будущим gap.

## Следующие срезы в обязательном порядке

Они относятся к E3/E4 executable/content calibration и не требуют раннего возвращения к сценариям или кампаниям.

1. Заполнить созданный `naval_executable_gate.json`: снять side-by-side кадры и тайминги оригинальной RoR на трёх фиксированных сценах для проверки source-driven golden, attack/death/impact audio timing и ориентации.
2. Заполнить trade observations оригинального executable на фиксированных картах/дистанциях и заменить только `RoRTradeProfitPolicy`, не меняя lifecycle.

Морские gameplay-линии уже имеют статус `integrated`. `naval_world_parity` остаётся в `deferred_lines` только как измеряемый executable-level gate; переносить его в завершённые и заявлять `PARITY` можно лишь после двух сравнений выше.
