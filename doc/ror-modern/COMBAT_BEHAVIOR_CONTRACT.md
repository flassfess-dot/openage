# Контракт восприятия и боевого поведения

Актуально с: 2026-09-12  
Владелец: I6

## Единый путь

```text
player / perception / future strategic AI
  -> immutable command
  -> GameController ordering + accepted/rejected event
  -> SimulationWorld task/order pipeline
  -> SimulationCombatSystem
  -> attack/hit/damage/death events
```

Удалён старый `enemy_orders`, который напрямую менял только вражеских юнитов. `CombatAwarenessSystem` выполняется между пользовательскими командами текущего fixed tick и продвижением мира; поэтому явный приказ имеет приоритет, а реакция обеих сторон использует тот же command result contract. Производные команды не создают ложный звук или marker пользовательского клика.

## Perception query

`PerceptionService` фильтрует живые враждебные цели по дальности, союзам, актуальной видимости, доступности пути и дополнительной политике. Результат сортируется детерминированно:

1. цель, прямо атакующая наблюдателя;
2. меньше уже назначенных атакующих;
3. боевой класс перед работником и статической целью;
4. квадрат расстояния;
5. стабильный entity ID.

Целями одного attack contract являются юниты, здания и фундаменты. Melee contact вычисляется от footprint, для здания — от прямоугольной границы. Разрушение здания освобождает навигацию, отменяет его очередь с возвратом резервов и создаёт typed death event.

## Стойки

| Stance | Самостоятельный захват | Преследование |
|---|---|---|
| `aggressive` | видимая достижимая цель в acquisition range | до исходного leash |
| `defensive` | напавший на юнита или ближайшего союзника | до leash |
| `stand_ground` | только цель уже в weapon/contact range | отсутствует |
| `passive` | отсутствует | отсутствует |

Работник по умолчанию defensive, боевой мобильный юнит aggressive, неспособная атаковать сущность passive. Значения хранятся в authoritative state и components; изменение stance — сериализуемая команда.

## Продолжение приказов

- `attack_move` сохраняет конечную точку перед автономным контактом.
- После смерти цели следующая выбирается до шага мира, поэтому юнит не возвращается в formation slot после каждого убийства.
- Когда целей нет, юнит возобновляет attack-move/движение или возвращается в formation home.
- Потеря видимости, недостижимость и превышение leash имеют устойчивые completion reasons.
- Получивший melee/projectile damage юнит сохраняет `retaliation_target_id`; defensive allies могут помочь в своей acquisition range.

## Проверки

- `test_perception_service.gd`: фильтры и стабильное ранжирование.
- `test_combat_awareness_system.gd`: четыре stance и помощь союзнику.
- `test_autonomous_combat_pipeline.gd`: общий command pipeline, отсутствие ложной UI-обратной связи, attack-move, цепочка целей, возврат, потеря видимости/leash и разрушение здания.
- Существующие `test_melee_combat.gd`, `test_projectiles.gd` и `test_formation_scenarios.gd` покрывают contact slots, ranged/projectile и групповые случаи.
- `test_deterministic_replay.gd` запрещает расхождение нового контура между записью и воспроизведением.

Статус I6: `INTEGRATED`. До `PARITY` остаются численные эталоны RoR для acquisition/leash/stance, полный набор классов целей и длительные L3/L4 боевые записи.
