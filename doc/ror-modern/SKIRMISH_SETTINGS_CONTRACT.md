# Контракт настроек случайной игры

Статус: E5-002 integrated engine contract  
Дата: 2026-09-16

## Назначение

Настройки лобби, генерация карты, bootstrap, replay и сохранения используют один декларативный контракт. Launcher не создаёт игровой мир и не дублирует правила: он собирает настройки, передаёт их `RoRSkirmishSettings`, получает обычный валидированный `MatchDefinition` и запускает неизменный `main.tscn`.

## Поля

- От двух до восьми активных слотов; ровно один локальный человек, сейчас в стабильном player slot 1, остальные слоты принадлежат AI.
- Для каждого слота отдельно заданы civilization ID 1…16, player colour 1…8 и alliance ID 1…8. Alliance не подменяет ID игрока: совпавшие alliance ID преобразуются в пары взаимных отношений.
- Общие настройки содержат resource preset, Stone/Tool/Bronze/Iron starting age, population limit, map size/type/seed, victory mode и AI difficulty `easy/standard/hard`.
- Закрытый слот не попадает в match definition. Повторные team/colour, неизвестная цивилизация, нулевой seed, неподдерживаемый preset и неоднозначный local human отклоняются до запуска.

Каталог находится в `prototype/data/skirmish/settings_catalog.json`, имеет собственную версию схемы и не зависит от UI. Его текущий `source_status` — `engine_contract_pending_ror_ui_calibration`: размеры и названия пресетов являются рабочими параметрами движка до финальной source-калибровки E8 и не заявляются как уже доказанные исходные значения. Список сложностей и их параметры принадлежат отдельному `prototype/data/ai/skirmish_policies.json`; launcher получает их через builder, не поддерживая дублирующую таблицу.

## Выход и сохранения

Builder детерминированно создаёт:

1. player definitions и starting positions;
2. по Town Center и три Villager на активного игрока;
3. начальные ресурсы, эпоху, population limit и AI policy;
4. взаимные alliances и victory rules;
5. карту с seed и версионированным generator profile.

Результат проходит общий `RoRMatchDefinition.normalize`. Его canonical fingerprint становится идентификатором `generated://skirmish/<hash>`, поэтому quicksave не принимает другую комбинацию настроек как тот же матч. `main.gd` принимает in-memory override, но после bootstrap generated и file-backed матчи используют одинаковые simulation, replay и save pipelines.

## Явные границы следующего пакета

- `colour_index` уже является независимой частью player data, но полный набор восьми source palette variants в presentation — отдельная проверяемая работа E5/E8; выбор цвета не считается визуально завершённым только из-за наличия поля.
- E5-003 добавил `inland_v1`, `highlands_v1`, `coastal_v1` и `islands_v1` с автоматическими spawn/resource/connectivity/naval guarantees. Exact RoR preset dimensions, названия и статистическое распределение terrain всё ещё требуют source-калибровки; рабочий engine contract не выдаётся за классический алгоритм.
- E5-005 подключил `skirmish_policy_v1`: AI difficulty, cadence, задержку/разделение атак, минимальный/максимальный отряд и оборонную реакцию. E5-006A добавил проверяемую opening economy: порядок/лимиты построек, жильё, число рабочих, source-cost-aware переход эпохи, достижимые foundations и боевую группу. Это ещё не полноценная стратегическая игра: E5-006B/C должны закрыть deterministic victory для двух игроков, 4/8 сторон, diplomacy и водную экономику/войну.
- Campaign definitions не переводятся в эту схему и остаются замороженными до E7.

## Доказательства E5-002

- Pure builder: стабильный fingerprint, 2/8 игроков, 16 цивилизаций, colours/alliances, эпохи, ресурсы, population 500 и victory mapping.
- Launcher: 8 настраиваемых слотов и generated launch без предварительного JSON-файла.
- Main scene: in-memory definition проходит обычный bootstrap, starting age/population/towns и save fingerprint.
- AI policy: source hash/values, три сложности и передача разрешённой политики в generated players проверяются отдельно; тактическое поведение проходит unit и command-pipeline integration.
- Затронутые match definition и HUD integrations проходят; импорт ресурсов, полный suite, cache validation и export не запускались до границы E5.
