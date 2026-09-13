# Семантика ввода и контекстных команд

Актуально с: 2026-09-12  
Владелец контракта: I3; дальнейшее поведение `attack-move` — I6, явный возврат ресурсов — I8.

## Единый путь

```text
InputEvent
  -> InputAdapter (физическое устройство -> жест/намерение)
  -> PickingService (render order -> hit stack)
  -> ContextResolver (hit + selection -> семантика)
  -> immutable Command
  -> GameController (accepted/rejected на fixed tick)
  -> SimulationEventStream
  -> CommandFeedbackRouter (текст, звук, marker)
```

UI не сообщает об успехе до `command_accepted`. Если цель исчезла между кликом и применением команды, приходит `command_rejected` с устойчивой причиной.

## Матрица правой кнопки

| Цель под курсором | Выбраны работники | Выбраны боевые юниты | Результат сейчас |
|---|---|---|---|
| Земля | move/formation move | move/formation move | `INTEGRATED` |
| Вражеский юнит | attack | attack | `INTEGRATED` |
| Ресурс | gather | явный `no_worker_selected` | `INTEGRATED` |
| Свой фундамент | build | недоступно | `INTEGRATED` |
| Своё повреждённое здание | repair | недоступно | `INTEGRATED` |
| Своё готовое здание | явное отсутствие действия | явное отсутствие действия | `INTEGRATED` |
| Вражеское здание/фундамент | attack | attack | `INTEGRATED` через общий combat target contract |
| Свой юнит | движение к позиции сущности | движение к позиции сущности | `INTEGRATED`, без скрытой подмены иной задачей |

Левая кнопка всегда отвечает только за selection. При перекрытии берётся первый допустимый объект из hit stack в обратном порядке фактической отрисовки. Составное здание дедуплицируется до одной логической сущности. Box selection отдаёт приоритет мобильным юнитам; здание выбирается рамкой только когда в ней нет юнитов.

## Каталог команд

| Команда | Контракт | Текущий уровень |
|---|---|---|
| move / formation_move | точка, форма, world-space forward | `INTEGRATED` |
| attack | entity ID юнита, здания или фундамента | `INTEGRATED` |
| gather | resource entity ID | `INTEGRATED` |
| build | archetype + world position | `INTEGRATED` |
| repair | building entity ID | `INTEGRATED` |
| train | producer ID + archetype | `INTEGRATED` в симуляции и HUD вертикального среза |
| research | producer ID + technology ID | `INTEGRATED` в симуляции; полный UI — I8/I10 |
| stop / hold | список управляемых entity ID | `INTEGRATED` в симуляции; command panel — I10 |
| attack-move | точка + acquisition policy | `INTEGRATED` в command/simulation; кнопка/горячая клавиша — I10 |
| stance | aggressive / defensive / stand_ground / passive | `INTEGRATED` в command/simulation; command panel — I10 |
| return resources | drop-off или автоматический выбор | `INTEGRATED`: явная команда, контекстный ПКМ, replay и data-driven Granary/Storage Pit policy |

## Наблюдаемая обратная связь

- Наведение использует тот же hit stack, что и клик, и подсвечивает логическую сущность.
- Системный курсор отражает `select`, `move`, `attack`, `gather/build/repair` или `unsupported`.
- Marker и звук появляются только после `command_accepted`.
- Отказ показывает локализованную причину и не проигрывает optimistic acknowledgement.
- Correlation выполняется по immutable `issuer_id + sequence_id`.

## Проверки

- `test_input_adapter.gd`: физические события, пороги жестов, модификаторы и HUD boundary.
- `test_picking_service.gd`: render order, composite dedupe, alpha/footprint fallback и box priority.
- `test_context_resolver.gd`: матрица контекстных целей и явные отказы.
- `test_interaction_cursor.gd`: соответствие наведения игровой семантике.
- `test_pointer_command_feedback.gd`: полный путь клика, подтверждение и late rejection.
