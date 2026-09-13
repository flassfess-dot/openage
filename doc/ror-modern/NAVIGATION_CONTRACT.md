# Контракт навигации и locomotion

Актуально с: 2026-09-12  
Владелец: I4

## Границы подсистем

```text
Command / Task
  -> destination reservation
  -> NavigationService request
  -> Pathfinder result
  -> LocalMovement desired/actual velocity
  -> authoritative position
```

- `NavigationGrid` владеет проходимостью, occupancy, terrain restrictions и монотонной `revision`.
- `Pathfinder` выполняет детерминированный глобальный поиск и сглаживание.
- `NavigationService` выдаёт монотонный `request_id` и результат со статусом, причиной и использованной ревизией сетки.
- `DestinationReservations` устраняет конфликт конечных footprint.
- `LocalMovement` рассчитывает локальное избегание без физического RNG.
- `StuckRecovery` задаёт ограниченную последовательность local replan → priority boost → global replan → stable stop.
- `FormationCorridor` строит общий коридор и временное сжатие группы, не подменяя индивидуальные пути.

## Результат маршрута

Каждый результат содержит `request_id`, `entity_id`, `purpose`, start/requested/resolved goal, movement domain, terrain restriction, grid revision, `resolved|unreachable`, стабильную причину и waypoints. Юнит хранит ID и статус последнего потреблённого результата для диагностики.

Команда движения подтверждается только если хотя бы один допустимый участник получил маршрут. Если ни один маршрут не существует, command result равен `command_rejected/no_path`; юнит остаётся в устойчивом `idle`, а presentation не показывает marker успеха.

## Направления

- `desired_facing` следует желаемой скорости до локального избегания.
- `movement_facing` следует фактическому перемещению после avoidance и clamp.
- `action_facing` принадлежит текущему действию/цели и не перезаписывается обходным манёвром.
- `facing` пока является совместимым presentation-полем: при движении показывает `movement_facing`, при выполнении действия — `action_facing`. Полный animation-state arbitration принадлежит I5.

## Доказательства

- L0: pathfinder, grid, footprints, reservations, local movement, stuck recovery.
- L1: `test_navigation_command_pipeline.gd` — command result, request correlation, прибытие и `no_path`.
- L2: `test_navigation_stress.gd` — встречные потоки, общие назначения, лесной коридор и здание.
- Formation matrix проверяет группы до 100 участников, узкое место и восстановление строя.
