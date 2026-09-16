# AoE1 Definitive Edition как дополнительный источник

Статус: read-only secondary reference  
Инвентаризация: 2026-09-16  
Локальный build: `97381`

## Назначение

AoE1 DE помогает сравнивать данные, AI, presentation и современные решения исполнения. Главным authority для соответствия остаётся Age of Empires: The Rise of Rome 1.1. Новая механика формаций и современная навигация принадлежат нашему движку и не выводятся из DE.

## Зафиксированные источники

| Источник | SHA-256 | Роль |
|---|---|---|
| `AoEDE_s.exe` | `06a3e142b526741a8c23390a2a4088060f41e34b5715cd0b4f2ad442e9c8506a` | Black-box reference, не источник кода |
| `Data/empires-orig.dat` | `d47c59d9ecaf5b83b467c647a69d28eced6a0dc5b2fa873e930c86136df5eb9d` | Byte-identical RoR 1.1 DAT; резервный classic source |
| `Data/empires_classic.dat` | `1c6374e0ca75a230300ff0e0f2fa730d5a03b55cfe819010d7afadf2ef37ebce` | Comparative database; точная семантика требует diff-аудита |
| `Data/empires.dat` | `4d0ac723cb029b9b3356ea006fb90fc1c353ea383db2ea4771ae3c3b5d6bd7e2` | DE database; secondary balance/format evidence |

Установка также содержит 146 `.ai`, 23 `.per`, 3039 gameplay SLP, 171 UI assets, palettes/player colours, sounds, localization, 10 `.aoecpn` и 25 `.aoescn`. Отдельных открытых random-map scripts не найдено.

## Authority matrix

| Вопрос | Основной источник | Дополнительный источник | Правило |
|---|---|---|---|
| Classic stats/IDs | RoR `data2/empires.dat` | DE `empires-orig.dat` | Разрешено только при совпадении hash |
| DE differences | Нет | `empires.dat`/`empires_classic.dat` | Сначала машинный diff, затем явное решение |
| Skirmish AI | RoR observations и собственный deterministic AI | DE AI/PER | Нормализованные параметры и тестируемые гипотезы, не слепое копирование |
| Classic graphics/HUD | RoR DRS/SLP и executable captures | DE palettes/UI/SLP | DE используется для диагностики alpha/player colour и масштабирования |
| HD assets | Не входят в classic baseline | DE SLP `x1/x2/x4` | Только отдельный optional profile/cache |
| Random maps | Собственный seed-driven generator и RoR observations | DE executable | Black-box comparison; алгоритм не извлекается из EXE |
| Campaigns | RoR campaign portfolio | DE `.aoecpn/.aoescn` | Отложено до E7 |

## План интеграции

### E5

1. Создать переносимый inventory command, принимающий путь параметром и сохраняющий только build, относительные пути, размеры и hashes.
2. Сделать трёхсторонний DAT diff `RoR ↔ empires-orig ↔ DE`, запрещающий тихую замену classic values.
3. Нормализовать AI/PER в evidence ledger: build orders, attack delay, group sizing, retreat, defence, exploration и diplomacy-related параметры.
4. Связать подтверждённые параметры с собственными AI policies и acceptance tests случайного матча.

E5-002 уже отделил versioned skirmish settings от генератора. Ни один preset не получает статус classic/DE parity из одного названия: `source_status` каталога остаётся `engine_contract_pending_ror_ui_calibration`, пока E5-003 не получит переносимые executable observations. DE AI/PER подключаются после map contract и не изменяют настройки или поведение автоматически.

### E6

1. Профилировать `x1/x2/x4` decode/cache/memory/render стоимость отдельно от classic PCK.
2. Использовать DE player-colour/palette материалы для диагностики масок, но не менять classic pixel baseline автоматически.
3. Сравнить большие матчи и UI scaling как наблюдаемое поведение, не пытаться переносить закрытую реализацию движка.

### E7–E8

1. Исследовать `.aoecpn/.aoescn` отдельным адаптером после стабилизации генератора карт и AI.
2. Использовать DE как дополнительную side-by-side проверку QoL и разрешений; финальный RoR parity подтверждается классическим источником.

## Cache и распространение

- Путь установки задаётся только параметром/локальной настройкой и не коммитится.
- Namespace DE не пересекается с классическим cache; ключ включает build, source hash, decoder version, palette и scale.
- Инкрементальный импорт добавляет только отсутствующие outputs; обычный запуск ничего не конвертирует.
- Исходные игровые файлы, извлечённые кадры, музыка, звук и сценарии Microsoft не включаются в Git или распространяемый пакет.
