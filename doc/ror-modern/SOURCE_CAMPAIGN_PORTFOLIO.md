# Source campaign portfolio

## Назначение

Этот пакет отвечает на вопрос «какую целую кампанию выгоднее интегрировать следующей» по данным, а не по впечатлению. Он не объявляет миссию готовой только потому, что исходный файл прочитан, и не добавляет аудитные матчи в launcher.

Источник истины:

- `prototype/assets/generated/scenario-catalog.json` — подтверждённые source-файлы и hashes;
- `prototype/data/campaigns/source_campaign_portfolio.json` — детерминированный manifest 14 кампаний / 95 миссий;
- `prototype/data/content_waves/source_campaign_portfolio.json` — воспроизводимая gap matrix;
- `prototype/data/content_waves/rise_of_rome_campaign.json` — более подробный gate уже интегрированной кампании `Расцвет Рима`.

## Воспроизведение

Из корня репозитория:

```powershell
powershell -ExecutionPolicy Bypass -File tools/ror_import/audit_campaign_portfolio.ps1 -Workers 4
```

Конвейер не копирует пользовательские source-файлы в репозиторий. Временные raw/match JSON удаляются после агрегации; постоянные документы содержат только структуру, hashes, counts и диагностические gaps.

Каждая миссия проходит два существующих production-compatible этапа: Rust-извлечение Genie scenario и общую runtime-нормализацию. До четырёх миссий обрабатываются параллельно. Ошибка отдельной миссии записывается как `import_failure_gap` и не прерывает аудит остальных.

## Gate

`launcher_ready` требует нулевые gaps по импорту, объектам, legacy conditions, trigger semantics, AI normalization и assets. `parity_ready` дополнительно требует нулевые source AI semantics, source settings и source-asset fallback gaps. Даже `launcher_ready` в portfolio означает только механический preflight: публикация всё равно требует постоянный match и воспроизводимые bootstrap/source-win/local-defeat tests.

Baseline 2026-09-14:

- 14 кампаний, 95 миссий;
- 17 mechanically launcher-ready, 78 blocked;
- 0 parity-ready;
- 4 `runtime_normalization` blockers из-за менее двух активных source player slots;
- `Расцвет Рима`: 6/6 launcher-ready, 0 blocking gaps, 17 явных AI parity gaps.
- `First Punic War`: 3/3 launcher-ready, 0 blocking gaps; опубликована и исключена из дальнейшего ранжирования manifest-driven правилом.

## Выбор следующего пакета

Неопубликованные кампании сортируются по стабильному score:

1. число заблокированных миссий;
2. сумма blocking records;
3. сумма parity records;
4. число миссий.

Завершённая `First Punic War` больше не участвует в списке кандидатов. Следующей выбрана `Reign of the Hittites`, score `[3, 4, 5, 5]`. Её общий системный пакет:

- общий single-participant bootstrap для учебной миссии `Homelands`, а не сценарное исключение;
- legacy victory command 0 `Capture` по точному scenario object ID;
- source graphic 602;
- постоянные матчи и воспроизводимые исходы для всех пяти миссий;
- остающиеся evidence-gated AI semantics без догадок о скрытых формулах.

Следующий этап не импортирует миссии как пять несвязанных прототипов. Сначала закрываются общие bootstrap/condition/asset owners, затем создаются все пять fixed-source matches и только после воспроизводимых исходов кампания публикуется целиком.
