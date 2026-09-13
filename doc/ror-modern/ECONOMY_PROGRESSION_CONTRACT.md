# Контракт экономики и развития

Статус: I8 `INTEGRATED`  
Дата: 2026-09-12

## Граница ответственности

Экономика является частью авторитетной fixed-tick симуляции. UI, анимация и renderer только отправляют команды и читают snapshot/events. Стоимость, переносимый груз, вместимость, очередь, population reservation, строительство и исследования не меняются напрямую из presentation.

Основной поток:

```text
command -> worker/production task -> fixed tick -> domain events -> snapshot/UI/AI
```

## Ресурсы и рабочие

- Канонические source resource ID: food `0`, wood `1`, stone `2`, gold `3`, population `4`.
- Рабочий проходит `approach -> work -> carry -> return -> deposit -> resume/complete`.
- Груз остаётся у рабочего до физической сдачи; истощение источника не создаёт ресурс в stockpile.
- Подход к ресурсу, стройке и точке сдачи имеет детерминированные слоты. Слоты вдоль периметра здания гарантированно лежат вне занятых navigation cells.
- Одновременные носильщики получают разные начальные точки периметра по stable entity ID и не сходятся в одну точку.
- `ReturnResourcesCommand` позволяет явно сдать груз правым кликом. Команда, AI и replay используют один сериализуемый тип.
- `Granary` принимает food, `Storage Pit` — wood/stone/gold; правила задаются runtime metadata. Town Center остаётся универсальным источником из исходного worker drop-site relationship.

## Строительство

- `BuildCommand` резервирует стоимость при создании фундамента.
- Проверяются runtime archetype/category, footprint, занятые клетки, склон, разведанность и вражеская зона.
- Несколько рабочих вносят аддитивный вклад с исходным work rate.
- Отмена фундамента полностью возвращает зарезервированную стоимость.
- Завершение создаёт `build_complete` и активирует связанный скрытый source technology ID здания.
- Уничтожение отменяет очередь, освобождает footprint и снимает population support.

## Производство и исследования

- Runtime-каталог содержит Villager, Clubman, Bowman, Scout, Town Center, Barracks, House, Granary, Storage Pit и Archery Range с раздельными internal/source/presentation ID.
- Явный `TrainCommand` проверяет принадлежность, завершённость здания, исходный `train_location_id`, object availability, стоимость, очередь и population.
- Barracks completion technology `62` открывает Clubman; Archery Range completion technology `55` открывает Bowman.
- Unit и research разделяют одну очередь здания. Стоимость и population резервируются при принятии команды; отмена возвращает их; blocked spawn сохраняет готовый заказ.
- Переход эпохи использует исходные prerequisites, hidden connectors, стоимость и duration.
- Временный адаптер: старая кнопка прототипа, не указывающая producer ID, может использовать первый producer. Он изолирован в `SimulationProductionSystem.train_unit`; I10 удалит адаптер после появления панели выбранного здания. Любая команда с producer ID уже строго соблюдает правила RoR.

## Население

- Глобальный лимит матча и построенная housing capacity — разные значения.
- До активации runtime housing старые fixture/save используют совместимый cap `50`.
- Первый завершённый provider включает housing model. Town Center и House дают по `4` из исходного storage resource `4`.
- Эффективный cap равен минимуму глобального лимита и housing capacity.
- Foundation не даёт population; завершение добавляет, уничтожение снимает вклад ровно один раз.

## События

Экономический event stream включает:

- `resource_gathered`, `resources_deposited`;
- `foundation_placed`, `foundation_cancelled`, `build_complete`;
- `building_technology_unlocked`, `population_cap_changed`;
- `production_queued`, `production_cancelled`, `unit_produced`;
- `research_queued`, `research_complete`.

## Доказательства

- L1: `test_gather_cycle.gd`, `test_building_cycle.gd`, `test_production_queue.gd`, `test_technology_and_ages.gd`, `test_civilization_modifiers.gd`.
- L1 data/commands: `test_production_availability.gd`, `test_dropoff_policy.gd`, `test_population_support.gd`, `test_return_resources_pipeline.gd`.
- L2 Stone Age: `test_stone_age_economy_loop.gd` физически собирает недостающую древесину, строит Barracks и производит первый Clubman.
- L2 Tool Age: `test_tool_age_progression.gd` строит Barracks/Granary, исследует Tool Age, строит Archery Range и производит смешанный отряд.

`INTEGRATED` не означает `PARITY`: полный tech tree/content, точная таблица build availability, UI всех команд и численная калибровка длительного матча остаются I10/I12.
