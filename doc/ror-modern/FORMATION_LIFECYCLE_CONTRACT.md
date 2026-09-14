# Контракт жизненного цикла формации

Актуально с: 2026-09-12  
Владелец: I7

## Модель группы

`FormationGroup` хранит стабильные `group_id`, упорядоченные members, anchor, forward, preferred formation type, spacing, slots, assignments, route/corridor, policy и наблюдаемое состояние lifecycle. Геометрия и assignment остаются отдельными стратегиями: добавление новой формы не меняет бой, navigation или renderer.

## State machine

```text
ASSEMBLE -> TRAVEL -> DEPLOY
    |          |         |
    +----------+------> ENGAGED
                         |
                      REGROUP -> REFORM -> DEPLOY
                         |          |
                         +-> ENGAGED+

любое состояние без участников -> DISBAND
```

- `ASSEMBLE`: группа создана, route ещё может оказаться заблокирован.
- `TRAVEL`: участники идут по corridor к своим слотам; слот является мягкой целью с допуском, а не физическим constraint каждого кадра.
- `DEPLOY`: участники прибыли; сохраняются выбранные форма и направление.
- `ENGAGED`: хотя бы один участник в бою; hard slot снят у всех, formation не подавляет pursuit/contact positions.
- `REGROUP`: контакт окончен, выжившие возвращаются к актуальным formation homes.
- `REFORM`: короткая подтверждаемая фаза окончательной геометрии; один стабильный такт служит hysteresis перед `DEPLOY`.
- `DISBAND`: живых участников не осталось или группу явно распустили.

Каждый переход увеличивает `lifecycle_revision`, сохраняет reason и создаёт `formation_state_changed`. У юнита виден `formation_slot_mode`: `soft`, `released`, `hard` или `none`. Направление на текущую угрозу хранится отдельно как `engagement_forward` и не уничтожает выбранный пользователем front.

## Связь с боем и навигацией

- Вход в атаку немедленно освобождает destination reservation и ставит slot mode `released`.
- `FormationCombat` распределяет индивидуальные melee/ranged contact positions; lifecycle не рассчитывает урон.
- После последней цели предыдущий attack-move возобновляется, а сохранённая formation возвращается через `REGROUP`.
- Corridor может временно сжимать форму в узком месте и восстановить preferred type после прохода.
- Смерть участника удаляет его из группы, перестраивает слоты и старается сохранить совместимые assignment остальных.

## Проверки

- `test_formation_lifecycle.gd`: все состояния, slot modes и hysteresis.
- `test_formation_combat_lifecycle.gd`: command -> ENGAGED -> REGROUP -> REFORM -> DEPLOY и наблюдаемые события.
- `test_formation_membership.gd`: потери, добавление/удаление и сохранение assignment.
- `test_formation_scenarios.gd`: размеры 2/3/7/20/100, повороты, смешанные типы, узкий проход, бой и потеря переднего ряда.

Статус I7: `INTEGRATED`. В core-first очереди E3 повторно закрывает поведение окружения/отступления и связанные индивидуальные маршруты у точной цели, а E6 — калибровку и производительность массовых групп с общим походным маршрутом. `PARITY/HARDENED` не заявляется до прохождения обоих этапов.
