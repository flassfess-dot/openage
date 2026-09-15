# E3 — матрица готовности игрового ядра

Актуально с: 2026-09-15  
Статус этапа: `IN_PROGRESS`  
Область: один контрольный skirmish-контракт на уже интегрированном римском срезе. Полное наполнение цивилизаций относится к E4, генерация карт и развитие skirmish AI — к E5, нагрузка — к E6, кампании — к E7.

## Правило приёмки

E3 проверяет не наличие отдельных классов, а доступность механики игроку через общий путь `input/HUD -> Command -> GameController -> SimulationWorld -> presentation/replay`. Старый зелёный модуль не переписывается: к нему добавляется недостающее сквозное доказательство. `PASS` ниже означает `INTEGRATED`, а не пиксельное или скрытое алгоритмическое соответствие оригинальному executable.

Основной небольшой fixture: `res://tests/fixtures/e3_save_state_matrix_match.json`. Он не является кампанией и не расширяет runtime-контент.

## Матрица

| Область | Пользовательский выходной критерий | Доказательство | E3 |
|---|---|---|---|
| Выделение и контекст | Одиночный/рамочный выбор, hit order и ПКМ по земле, врагу, ресурсу, фундаменту и зданию дают однозначный результат | `test_input_adapter.gd`, `test_picking_service.gd`, `test_context_resolver.gd`, `test_pointer_command_feedback.gd` | `PASS` |
| Основные приказы | Игрок может вызвать attack-move, stop, hold и смену стойки с HUD и клавиатуры; приказ проходит публичную очередь и replay | `test_player_unit_order_controls.gd`, `test_hud_view_model.gd`, `test_hud_controls.gd` | `PASS` |
| Движение | Одиночный и групповой маршрут учитывают проходимость, reservations, локальное расхождение и восстановление после застревания | `test_navigation_command_pipeline.gd`, `test_destination_reservations.gd`, `test_local_movement.gd`, `test_stuck_recovery.gd` | `PASS` |
| Направление и анимация | Фактическое движение и цель определяют правильные восемь направлений idle/move/attack без боя спиной | `test_facing_convention.gd`, `test_facing.gd`, `test_animation_direction_pipeline.gd` | `PASS` |
| Формации | Пять форм, выбранный front, марш, engagement, release/regroup и завершение маршрута не подавляют бой | `test_formation_lifecycle.gd`, `test_formation_combat_lifecycle.gd`, `test_formation_scenarios.gd` | `PASS` |
| Автономный бой | Стойки, поиск цели, помощь, преследование/leash, retaliation, цепочка целей и возврат к attack-move работают симметрично | `test_combat_awareness_system.gd`, `test_autonomous_combat_pipeline.gd`, `test_melee_combat.gd`, `test_projectiles.gd` | `PASS` |
| Экономика | Сбор, перенос, сдача, охота, ферма и минеральные ресурсы проходят общий economy/order pipeline | `test_gather_cycle.gd`, `test_return_resources_pipeline.gd`, `test_huntable_resource_pipeline.gd`, `test_farm_pipeline.gd`, `test_mineral_resources.gd` | `PASS` |
| Строительство | Placement, стоимость, foundation, работа строителей, завершение и ремонт доступны из обычного HUD | `test_build_palette_pipeline.gd`, `test_build_workflow.gd`, `test_building_cycle.gd`, `test_hud_command_pipeline.gd` | `PASS` |
| Производство и развитие | Очередь, отмена, population reservation, возраст и исследования используют data-driven availability/effects | `test_production_queue.gd`, `test_population_support.gd`, `test_tool_age_progression.gd`, `test_core_building_age_pipeline.gd` | `PASS` |
| Специальные действия | Лечение, обращение и жертвоприношение проходят отдельные системные владельцы и replayable commands | `test_priest_actions_pipeline.gd`, `test_temple_priest_conversion_pipeline.gd` | `PASS` |
| Море | Рыболовство, торговля, транспорт, высадка и морской бой используют те же command/result/state контракты | `test_naval_economy_pipeline.gd`, `test_naval_trade_pipeline.gd`, `test_transport_pipeline.gd`, `test_naval_combat_pipeline.gd` | `PASS` |
| Исход матча | Победа, поражение и сдача терминальны; после исхода новые команды не меняют мир | `test_victory_modes.gd`, `test_resign_pipeline.gd`, `test_game_save_state_matrix.gd` | `PASS` |
| Детерминизм и сохранение | Replay сохраняет такт выдачи и исполнения; save/load восстанавливает восемь активных состояний с тем же canonical SHA-256 | `test_deterministic_replay.gd`, `test_game_save_archive.gd`, `test_game_save_load_pipeline.gd`, `test_game_save_state_matrix.gd` | `PASS` |
| Непрерывный игровой цикл | Один матч через реальный `main` последовательно выполняет управление, экономику, строительство, производство, развитие, формационный бой и победу без прямого изменения мира тестом | ещё не созданный E3 controlled-skirmish acceptance | `OPEN` |

## Закрытый разрыв: полная палитра приказов юниту

- `Q` включает выбор точки attack-move; следующий допустимый клик создаёт `AttackMoveCommand`, а не меняет выделение.
- `X` создаёт `StopCommand`, отменяет текущую задачу и устаревший маршрут формации, но сохраняет стойку.
- `H` создаёт `HoldCommand`, отменяет задачу/маршрут и устанавливает `stand_ground`.
- `V` циклически меняет `aggressive -> defensive -> stand_ground -> passive` через `StanceCommand`.
- Те же четыре действия доступны из command grid. У рабочего они остаются рядом с закрытой кнопкой строительства; открытое строительное подменю временно занимает сетку своими вариантами и возвратом.
- Буквы являются текущими привязками проекта. Это не заявление о точных горячих клавишах RoR; source glyph для неподтверждённых команд не угадывается.

## Следующий пакет

Создать небольшой `controlled skirmish` harness поверх настоящей сцены `main.tscn`. Он должен управлять игрой только публичными действиями игрока и проверять последовательность:

1. выделить рабочего и начать сбор;
2. вернуть ресурс и построить обязательное здание;
3. поставить юнита в очередь и завершить производство;
4. выполнить доступное развитие/исследование;
5. собрать боевую группу, выбрать форму и направление;
6. пройти attack-move, автономный контакт, regroup и добить противника;
7. получить терминальную победу, сохранить/загрузить один промежуточный срез и подтвердить тот же итоговый canonical hash.

Harness не должен напрямую выставлять `task`, HP, ресурсы, очередь или результат матча. Разрешены только fixture-данные до bootstrap, управление камерой/выделением и публичные команды. Первый воспроизведённый разрыв исправляется у владельца соответствующего контракта.

## Внешние справочные проекты

`FolkertVanVerseveld/aoe`, openage и другие показанные пользователем движки разрешены как read-only подсказки по структуре ресурсов, именованию, UI/presentation и возможным архитектурным решениям. Они не являются runtime dependency и не доказывают точное поведение RoR сами по себе. Для утверждения `PARITY` требуются исходные данные RoR и наблюдение установленного executable (кадры, видео либо измеримый сценарий).
