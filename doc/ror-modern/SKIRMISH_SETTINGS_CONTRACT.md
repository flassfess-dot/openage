# Контракт настроек случайной игры

Статус: E5-002 integrated engine contract  
Дата: 2026-09-16

## Назначение

Настройки лобби, генерация карты, bootstrap, replay и сохранения используют один декларативный контракт. Launcher не создаёт игровой мир и не дублирует правила: он собирает настройки, передаёт их `RoRSkirmishSettings`, получает обычный валидированный `MatchDefinition` и запускает неизменный `main.tscn`.

## Поля

- От двух до восьми активных слотов; ровно один локальный человек, сейчас в стабильном player slot 1, остальные слоты принадлежат AI.
- Для каждого слота отдельно заданы civilization ID 1…16, player colour 1…8 и alliance ID 1…8. Alliance не подменяет ID игрока: совпавшие alliance ID преобразуются в пары взаимных отношений.
- Общие настройки содержат resource preset, Stone/Tool/Bronze/Iron starting age, population limit, map size/type/seed и victory mode.
- Закрытый слот не попадает в match definition. Повторные team/colour, неизвестная цивилизация, нулевой seed, неподдерживаемый preset и неоднозначный local human отклоняются до запуска.

Каталог находится в `prototype/data/skirmish/settings_catalog.json`, имеет собственную версию схемы и не зависит от UI. Его текущий `source_status` — `engine_contract_pending_ror_ui_calibration`: размеры и названия пресетов являются рабочими параметрами движка, пока E5-003 не закрепит их наблюдениями классического RoR. Они не заявляются как уже доказанные исходные значения.

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
- `inland_v1` и `coastal_v1` дают рабочую детерминированную основу. Распределение terrain/resources, честные spawn distances, водная связность, map-type portfolio и source калибровка принадлежат E5-003.
- AI использует существующий общий policy contract. Нормализация classic/DE AI/PER evidence и полноценный долгий AI-матч идут после E5-003.
- Campaign definitions не переводятся в эту схему и остаются замороженными до E7.

## Доказательства E5-002

- Pure builder: стабильный fingerprint, 2/8 игроков, 16 цивилизаций, colours/alliances, эпохи, ресурсы, population 500 и victory mapping.
- Launcher: 8 настраиваемых слотов и generated launch без предварительного JSON-файла.
- Main scene: in-memory definition проходит обычный bootstrap, starting age/population/towns и save fingerprint.
- Затронутые match definition и HUD integrations проходят; импорт ресурсов, полный suite, cache validation и export не запускались до границы E5.
