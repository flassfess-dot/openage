# Конвейер ресурсов Rise of Rome

Проект читает только принадлежащую пользователю локальную установку Rise of Rome и не изменяет её. Импорт выполняется отдельно от запуска игры: ярлык вызывает готовые EXE/PCK и никогда не запускает конвертацию.

## Поток данных

```text
data2/empires.dat + DRS + language DLL
  -> полные source-каталоги objects/graphics/sounds/localization/terrain
  -> декларативный runtime-archetypes.json
  -> нормализованный runtime-catalog.json
  -> RoRDataRepository
  -> авторитетная симуляция
```

Каждый кэш хранит версию схемы, версию импортёра и хеши входов. При неизменных входах генераторы возвращают cache hit. `runtime-catalog.json` разделяет:

- alias текущего игрового API (`villager`, `archer`);
- стабильный internal ID (`ror.unit.villager`);
- исходный unit ID RoR (`118`);
- presentation ID (`unit.villager`).

Новый тип первого среза добавляется в `tools/ror_import/runtime-archetypes.json`. Центральный цикл симуляции не должен получать ветку по имени типа; отличия задаются source record, компонентами, behavior tags и узкой стратегией.

## Команды

- `tools/import-assets.ps1` — явный инкрементальный импорт: добавляет отсутствующие/устаревшие ресурсы и не переписывает byte-identical результаты; полный clean rebuild нужен только при несовместимом формате/декодере.
- `tools/validate-cache.ps1` — проверка ссылок, циклов, runtime ID и отчёт покрытия.
- `tools/build-game.ps1` — тесты и экспорт готовой сборки.
- `tools/run-game.ps1` — только запуск готовой сборки.

## Текущий validation gate

Отчёты находятся в `prototype/assets/generated/validation-report.json` и `doc/ror-modern/CACHE_VALIDATION_REPORT.md`.

## Актуальный порядок и проверки

Core-first очередь закреплена в `doc/DEVELOPMENT_ROADMAP_ROR_PARITY.md`: visual/runtime core -> adaptive HUD -> gameplay core -> все цивилизации -> skirmish/random maps/AI -> performance -> scenarios/campaigns -> release. Исторические campaign next-step записи не являются активными.

Внутри итерации запускается только impact-набор изменённой подсистемы и её прямых потребителей. Пакет завершается коротким smoke; полный suite, cache validation и Windows export выполняются один раз на границе крупного этапа, кроме сквозных изменений simulation/data contract.

На 2026-09-12: 0 структурных errors и 181 warning. Warning не скрываются: это пробелы конкретной исходной установки (63 SLP, 33 WAV, 85 name/icon records), снабжённые классификацией влияния. Error зарезервирован для нарушенной ссылки, цикла зависимости или неконсистентного runtime-каталога.

WSL и полный openage build для повседневной разработки не требуются.

Отдельные проверочные контракты: `VISUAL_PARITY_CONTRACT.md` задаёт границу визуального соответствия, `SOURCE_UI_EXECUTABLE_MEASUREMENT.md` — обязательный порядок доказательства исходных HUD-контролов и их состояний, а `ELEVATION_AWARE_FOG_OPTIMIZATION_PLAN.md` разделяет ближайшее E1-исправление геометрии/depth/map-edge и E6 dirty-chunk/performance backend.
