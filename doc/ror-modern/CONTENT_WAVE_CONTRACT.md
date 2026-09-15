# Контракт вертикальных волн контента

Статус: рабочий контракт I12  
Дата: 2026-09-15

> **Core-first rebaseline 2026-09-14:** новые content waves временно не являются активной очередью. Контракт снова применяется на E4 для всех цивилизаций и на E7 для сценариев/кампаний. До этого текущая работа принадлежит visual/HUD и gameplay core; уже интегрированный контент используется как fixture.

## Назначение

RoR расширяется законченными вертикальными линиями, а не несвязанными объектами. Добавленный элемент считается интегрированным только тогда, когда исходная запись Rise of Rome проходит через нормализованные данные, авторитетную симуляцию, команды, presentation и автоматическое доказательство. Современная навигация, жизненный цикл формаций и задаваемое направление строя являются разрешёнными отличиями; характеристики и весь остальной контент берутся из оригинальных данных.

## Источники истины

- `prototype/assets/generated/objects-catalog.json` — объекты цивилизаций, технологии, effects, costs, producers и исходные graphics/sounds.
- `prototype/assets/generated/graphics-catalog.json` — длительности, направления, кадры и graphic deltas.
- `tools/ror_import/runtime-archetypes.json` — стабильные logical aliases, source identity, behavior tags и декларативные presentation profiles.
- `tools/ror_import/prototype-selection.json` — единственный список ресурсов, которые экспортируются в постоянный локальный кэш.
- `prototype/data/content_waves/stone_age.json` и `roman_all_ages.json` — заявленное покрытие и известные пробелы.

Сгенерированные файлы не редактируются вручную. Импорт выполняется инкрементально: manifest дополняет кэш только отсутствующими/устаревшими кадрами и зависимостями, а byte-identical файлы не переписываются. Полная перепаковка допустима только при несовместимом cache schema, общем изменении decoder/palette/alpha либо явном clean rebuild. Обычный запуск с ярлыка использует готовый кэш.

## Архитектурные владельцы

1. `RoRDataRepository` разрешает alias, internal ID, source unit ID и цивилизационную запись.
2. `SimulationWorld` и выделенные systems владеют состоянием, технологиями, производством, экономикой, боем, навигацией и формациями.
3. `RoRUnitPresentationRegistry` выбирает анимацию по alias, фактическому source unit ID и team palette. Варианты улучшений задаются данными; кадры загружаются лениво при первом обращении.
4. `RoRResourcePresentationRegistry` загружает только asset names ресурсных archetypes и обрабатывает истощение по runtime metadata.
5. `RoRBuildingPresentationRegistry` разрешает архитектуру, строительство, damage, death и graphic deltas.
6. HUD читает presentation snapshot и создаёт обычные команды; он не владеет правилами доступности или баланса.

## Уровни заявления

- `planned`: source IDs известны, реализация и доказательство отсутствуют.
- `partial`: часть линии работает, но перечисленный scope закрыт не полностью.
- `integrated`: каждый ID из `integrated_source_unit_ids` представлен runtime archetype либо source-aware variant, evidence-файл существует, а вертикальный тест проходит.
- `parity`: дополнительно пройдены сравнение с эталоном RoR, необходимые визуальные/звуковые проверки и длительный сценарий. I12 пока не заявляет этот уровень.

Матрица обязана перечислять неизвестное как gap, а не скрывать его. Тест матрицы должен падать, если заявлен integrated source ID без runtime-пути или если исчезло доказательство.

## Порядок добавления линии юнитов

1. Извлечь из Roman civilization record все source IDs линии, producer, costs, creation time, combat/geometry/sounds/graphics, dead-unit links и технологии unlock/upgrade.
2. Записать линию в матрицу со статусом `planned` или `partial` до реализации.
3. Создать один logical runtime archetype для линии. Базовый source ID задаётся в `source_unit_id`, последующие ступени — в `presentation_variants` по source ID.
4. Добавить только фактически используемые idle/move/attack/death/corpse assets для player 1 и player 2 в selection manifest.
5. Перегенерировать и провалидировать постоянный кэш. Ошибки недопустимы; предупреждения должны оставаться классифицированными исходными пробелами.
6. Проверить обычный research/production pipeline: исходную блокировку, prerequisites, стоимость/время, unlock либо upgrade, изменение уже существующих сущностей и наследование будущими.
7. Проверить source-derived характеристики и presentation каждого состояния, включая вражескую палитру и death/corpse lifecycle.
8. Только после прохождения evidence изменить статус матрицы на `integrated`.

Специальная ветка по имени нового юнита в центральном tick, input или renderer запрещена, если поведение выражается существующим system/tag/profile. Если обнаружена новая общая механика, сначала вводится её отдельный владелец и контрактный тест.

## Порядок добавления ресурса или здания

Для ресурса обязательны source identity, resource type, amount/capacity, footprint, gather/drop-off policy, depletion и presentation. Для здания обязательны source footprint/cost/time, placement, construction/repair, hidden technology connector, production/research, population/drop-site effects при наличии, damage/death и освобождение navigation footprint.

## Текущий срез

- Stone Age matrix не содержит скрытых gaps: береговая/глубоководная рыба, Fisherman 119, Dock 45 и Fishing Boat 13 имеют авторитетный runtime path и evidence.
- Roman matrix: наземные unit/building линии, defences, Wonder, Priest actions и вся source-driven морская вертикаль интегрированы. Naval economy включает Whale 370; Trade/Transport — Dock-to-Dock lifecycle; combat 19 -> 20 -> 21/250 -> 277 имеет damage/death/impact, доступные source sounds, обе палитры/composite golden, mixed-domain AI и full-roster stress. Executable-level side-by-side и точная distance-to-gold формула остаются отдельными измеряемыми `PARITY` gaps.
- E4 all-civilizations matrix перечисляет все 16 игровых цивилизаций и 41 общую линию roster. ID 15/16 закреплены по исходному каталогу как Palmyran/Macedonian. Roman и цивилизации 1–8 имеют полный вертикальный статус `integrated`; ещё 7 цивилизаций остаются `planned` до собственных end-to-end доказательств.
- Civilization effects сохраняют дробные rule resources отдельно от целочисленных складов экономики. Уже подключены Faith Recharge 35, Farm Food 36 и Tribute Inefficiency 46; attribute 15 реализован как исходная base armor, применяемая при отсутствии явной брони соответствующего класса.
- Placement и navigation используют декларативные movement domain/source terrain restriction. Dock обязан иметь доступную воду для флота и сухопутный периметр для строителя. Deep Fish принимает только водного gatherer, Shore Fish — наземного Fisherman либо водного gatherer.
- Составные корабли рендерятся общим unit-composite contract: hull, sail, oars и weapon layer выбираются из source graphics/deltas без корабельных веток в renderer.
- Asset cache: 23315 выбранных элементов и 68 runtime archetypes; unit/building/resource/projectile/effect/icon frames загружаются лениво. Волна цивилизаций 1–4 добавила только 504 отсутствовавших P1/P2 кадра архитектуры, остальные 22811 записей были cache hits. Manifest умеет явно выбирать `data`/`data2` при совпадающих SLP ID.
- Последний полный boundary gate E3: `192 passed, 0 failed`, cache validation — `0 errors, 181 warnings`, Windows export и packaged smoke успешны. E4-001…E4-005 прошли impact-набор общей матрицы, roster, civilization rules и вертикалей цивилизаций 1–8; полный suite/cache/export будет выполнен один раз на границе E4.

## Ближайшая очередь

1. E1–E3 завершены; E4 использует их как неизменяемый gameplay-core baseline.
2. Тем же контрактом закрыть end-to-end вертикали цивилизаций 9–12 и 14–16 поверх общей матрицы roster и правил.
3. На E5 закрыть data requirements skirmish/random maps/AI.
4. После E6 возобновить scenarios/campaigns с `Reign of the Hittites` по сохранённой portfolio matrix.
