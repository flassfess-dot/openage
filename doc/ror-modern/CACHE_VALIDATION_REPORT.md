# Rise of Rome cache validation

Validated graphics: 941; objects: 3580; logical sounds: 234; languages: 10.

| Category | Severity | Count |
|---|---:|---:|
| `missing_slp` | warning | 63 |
| `missing_audio` | warning | 33 |
| `unknown_ids` | error | 0 |
| `broken_deltas` | error | 0 |
| `dependency_cycles` | error | 0 |
| `missing_name_or_icon` | warning | 85 |
| `suspicious_values` | warning | 0 |
| `runtime_catalog` | error | 0 |

## Coverage

| Metric | Covered | Total |
|---|---:|---:|
| Player-facing localized names | 2563 | 2631 |
| Required object icons | 1614 | 1631 |
| Reachable resource-backed graphics with SLP | 610 | 647 |
| Active resource-backed logical sounds with audio | 86 | 90 |

Missing SLP/WAV findings are gaps in the owned source installation. They are warnings, while malformed references and dependency cycles remain errors. Each resource finding records whether an enabled catalog record can reach it.

## missing_slp

- `{"classification": "owned_source_gap", "direct_references": [{"field": "idle", "object_key": "0:163"}, {"field": "move", "object_key": "0:163"}, {"field": "death", "object_key": "0:163"}], "graphic_id": 10, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 251}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 88, "impact": "inactive_or_unreferenced", "reachable": false, "slp_id": 279}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 117, "impact": "inactive_or_unreferenced", "reachable": false, "slp_id": 585}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 219, "impact": "inactive_or_unreferenced", "reachable": false, "slp_id": 703}`
- `{"classification": "owned_source_gap", "direct_references": [{"field": "attack", "object_key": "1:69"}, {"field": "attack", "object_key": "1:236"}, {"field": "attack", "object_key": "1:278"}, {"field": "attack", "object_key": "4:69"}, {"field": "attack", "object_key": "4:236"}, {"field": "attack", "object_key": "4:278"}, {"field": "attack", "object_key": "8:69"}, {"field": "attack", "object_key": "8:236"}, {"field": "attack", "object_key": "8:278"}], "graphic_id": 230, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 14}`
- `{"classification": "owned_source_gap", "direct_references": [{"field": "idle", "object_key": "1:154"}, {"field": "move", "object_key": "1:154"}, {"field": "idle", "object_key": "4:154"}, {"field": "move", "object_key": "4:154"}, {"field": "idle", "object_key": "8:154"}, {"field": "move", "object_key": "8:154"}], "graphic_id": 234, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 14}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 249, "impact": "inactive_or_unreferenced", "reachable": false, "slp_id": 49}`
- `{"classification": "owned_source_gap", "direct_references": [{"field": "attack", "object_key": "1:79"}, {"field": "attack", "object_key": "4:79"}, {"field": "attack", "object_key": "8:79"}], "graphic_id": 264, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 14}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 268, "impact": "inactive_or_unreferenced", "reachable": false, "slp_id": 408}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 337, "impact": "inactive_or_unreferenced", "reachable": false, "slp_id": 462}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 338, "impact": "inactive_or_unreferenced", "reachable": false, "slp_id": 482}`
- `{"classification": "owned_source_gap", "direct_references": [{"field": "attack", "object_key": "2:69"}, {"field": "attack", "object_key": "2:236"}, {"field": "attack", "object_key": "2:278"}, {"field": "attack", "object_key": "5:69"}, {"field": "attack", "object_key": "5:236"}, {"field": "attack", "object_key": "5:278"}, {"field": "attack", "object_key": "7:69"}, {"field": "attack", "object_key": "7:236"}, {"field": "attack", "object_key": "7:278"}], "graphic_id": 352, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 58}`
- `{"classification": "owned_source_gap", "direct_references": [{"field": "idle", "object_key": "2:154"}, {"field": "move", "object_key": "2:154"}, {"field": "idle", "object_key": "5:154"}, {"field": "move", "object_key": "5:154"}, {"field": "idle", "object_key": "7:154"}, {"field": "move", "object_key": "7:154"}], "graphic_id": 356, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 58}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 370, "impact": "inactive_or_unreferenced", "reachable": false, "slp_id": 74}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 371, "impact": "inactive_or_unreferenced", "reachable": false, "slp_id": 93}`
- `{"classification": "owned_source_gap", "direct_references": [{"field": "attack", "object_key": "2:79"}, {"field": "attack", "object_key": "5:79"}, {"field": "attack", "object_key": "7:79"}], "graphic_id": 386, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 58}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 400, "impact": "inactive_or_unreferenced", "reachable": false, "slp_id": 770}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 401, "impact": "inactive_or_unreferenced", "reachable": false, "slp_id": 780}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 402, "impact": "inactive_or_unreferenced", "reachable": false, "slp_id": 793}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 403, "impact": "inactive_or_unreferenced", "reachable": false, "slp_id": 784}`
- `{"classification": "owned_source_gap", "direct_references": [{"field": "attack", "object_key": "0:69"}, {"field": "attack", "object_key": "0:236"}, {"field": "attack", "object_key": "0:278"}, {"field": "attack", "object_key": "10:69"}, {"field": "attack", "object_key": "10:236"}, {"field": "attack", "object_key": "10:278"}, {"field": "attack", "object_key": "11:69"}, {"field": "attack", "object_key": "11:236"}, {"field": "attack", "object_key": "11:278"}, {"field": "attack", "object_key": "12:69"}, {"field": "attack", "object_key": "12:236"}, {"field": "attack", "object_key": "12:278"}], "graphic_id": 423, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 102}`
- `{"classification": "owned_source_gap", "direct_references": [{"field": "idle", "object_key": "0:154"}, {"field": "move", "object_key": "0:154"}, {"field": "idle", "object_key": "10:154"}, {"field": "move", "object_key": "10:154"}, {"field": "idle", "object_key": "11:154"}, {"field": "move", "object_key": "11:154"}, {"field": "idle", "object_key": "12:154"}, {"field": "move", "object_key": "12:154"}], "graphic_id": 427, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 102}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 441, "impact": "inactive_or_unreferenced", "reachable": false, "slp_id": 118}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 442, "impact": "inactive_or_unreferenced", "reachable": false, "slp_id": 137}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 450, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 130}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 455, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 132}`
- `{"classification": "owned_source_gap", "direct_references": [{"field": "attack", "object_key": "0:79"}, {"field": "attack", "object_key": "10:79"}, {"field": "attack", "object_key": "11:79"}, {"field": "attack", "object_key": "12:79"}], "graphic_id": 457, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 102}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 489, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 411}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 563, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 517}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 597, "impact": "inactive_or_unreferenced", "reachable": false, "slp_id": 635}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 626, "impact": "inactive_or_unreferenced", "reachable": false, "slp_id": 148}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 642, "impact": "inactive_or_unreferenced", "reachable": false, "slp_id": 6}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 643, "impact": "inactive_or_unreferenced", "reachable": false, "slp_id": 7}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 658, "impact": "inactive_or_unreferenced", "reachable": false, "slp_id": 146}`
- `{"classification": "owned_source_gap", "direct_references": [{"field": "attack", "object_key": "3:69"}, {"field": "attack", "object_key": "3:236"}, {"field": "attack", "object_key": "3:278"}, {"field": "attack", "object_key": "6:69"}, {"field": "attack", "object_key": "6:236"}, {"field": "attack", "object_key": "6:278"}, {"field": "attack", "object_key": "9:69"}, {"field": "attack", "object_key": "9:236"}, {"field": "attack", "object_key": "9:278"}], "graphic_id": 718, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 158}`
- `{"classification": "owned_source_gap", "direct_references": [{"field": "idle", "object_key": "3:154"}, {"field": "move", "object_key": "3:154"}, {"field": "idle", "object_key": "6:154"}, {"field": "move", "object_key": "6:154"}, {"field": "idle", "object_key": "9:154"}, {"field": "move", "object_key": "9:154"}], "graphic_id": 722, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 158}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 736, "impact": "inactive_or_unreferenced", "reachable": false, "slp_id": 174}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 737, "impact": "inactive_or_unreferenced", "reachable": false, "slp_id": 193}`
- `{"classification": "owned_source_gap", "direct_references": [{"field": "attack", "object_key": "3:79"}, {"field": "attack", "object_key": "6:79"}, {"field": "attack", "object_key": "9:79"}], "graphic_id": 752, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 158}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 835, "impact": "inactive_or_unreferenced", "reachable": false, "slp_id": 708}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 856, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 736}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 858, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 737}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 860, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 739}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 862, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 743}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 864, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 741}`
- `{"classification": "owned_source_gap", "direct_references": [{"field": "attack", "object_key": "13:69"}, {"field": "attack", "object_key": "13:236"}, {"field": "attack", "object_key": "13:278"}, {"field": "attack", "object_key": "14:69"}, {"field": "attack", "object_key": "14:236"}, {"field": "attack", "object_key": "14:278"}, {"field": "attack", "object_key": "15:69"}, {"field": "attack", "object_key": "15:236"}, {"field": "attack", "object_key": "15:278"}, {"field": "attack", "object_key": "16:69"}, {"field": "attack", "object_key": "16:236"}, {"field": "attack", "object_key": "16:278"}], "graphic_id": 865, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 716}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 867, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 752}`
- `{"classification": "owned_source_gap", "direct_references": [{"field": "idle", "object_key": "13:154"}, {"field": "move", "object_key": "13:154"}, {"field": "idle", "object_key": "14:154"}, {"field": "move", "object_key": "14:154"}, {"field": "idle", "object_key": "15:154"}, {"field": "move", "object_key": "15:154"}, {"field": "idle", "object_key": "16:154"}, {"field": "move", "object_key": "16:154"}], "graphic_id": 869, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 716}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 870, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 742}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 872, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 745}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 874, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 748}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 876, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 740}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 878, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 749}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 880, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 747}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 882, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 750}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 883, "impact": "inactive_or_unreferenced", "reachable": false, "slp_id": 732}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 884, "impact": "inactive_or_unreferenced", "reachable": false, "slp_id": 751}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 886, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 738}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 888, "impact": "inactive_or_unreferenced", "reachable": false, "slp_id": 753}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 892, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 744}`
- `{"classification": "owned_source_gap", "direct_references": [], "graphic_id": 897, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 746}`
- `{"classification": "owned_source_gap", "direct_references": [{"field": "attack", "object_key": "13:79"}, {"field": "attack", "object_key": "14:79"}, {"field": "attack", "object_key": "15:79"}, {"field": "attack", "object_key": "16:79"}], "graphic_id": 899, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 716}`
- `{"classification": "owned_source_gap", "direct_references": [{"field": "idle", "object_key": "0:393"}], "graphic_id": 930, "impact": "runtime_candidate_reference", "reachable": true, "slp_id": 799}`

## missing_audio

- `{"active_binding_count": 16, "classification": "owned_source_gap", "fallback_available": false, "filename": "okamala.wav", "impact": "active_binding_without_audio", "resource_id": 5157, "sound_id": 3}`
- `{"active_binding_count": 0, "classification": "owned_source_gap", "fallback_available": false, "filename": "squeek.wav", "impact": "inactive_or_unreferenced", "resource_id": 5185, "sound_id": 37}`
- `{"active_binding_count": 0, "classification": "owned_source_gap", "fallback_available": false, "filename": "clubhit.wav", "impact": "inactive_or_unreferenced", "resource_id": 5049, "sound_id": 49}`
- `{"active_binding_count": 0, "classification": "owned_source_gap", "fallback_available": false, "filename": "newore.wav", "impact": "inactive_or_unreferenced", "resource_id": 5149, "sound_id": 63}`
- `{"active_binding_count": 8, "classification": "owned_source_gap", "fallback_available": true, "filename": "elewild2.wav", "impact": "active_binding_with_fallback", "resource_id": 5073, "sound_id": 66}`
- `{"active_binding_count": 0, "classification": "owned_source_gap", "fallback_available": false, "filename": "fructu.wav", "impact": "inactive_or_unreferenced", "resource_id": 5091, "sound_id": 81}`
- `{"active_binding_count": 0, "classification": "owned_source_gap", "fallback_available": false, "filename": "gaz.wav", "impact": "inactive_or_unreferenced", "resource_id": 5094, "sound_id": 83}`
- `{"active_binding_count": 0, "classification": "owned_source_gap", "fallback_available": false, "filename": "goat.wav", "impact": "inactive_or_unreferenced", "resource_id": 5095, "sound_id": 84}`
- `{"active_binding_count": 144, "classification": "owned_source_gap", "fallback_available": false, "filename": "birth.wav", "impact": "active_binding_without_audio", "resource_id": 5026, "sound_id": 97}`
- `{"active_binding_count": 0, "classification": "owned_source_gap", "fallback_available": false, "filename": "hit2.wav", "impact": "inactive_or_unreferenced", "resource_id": 5115, "sound_id": 99}`
- `{"active_binding_count": 0, "classification": "owned_source_gap", "fallback_available": false, "filename": "Thud.wav", "impact": "inactive_or_unreferenced", "resource_id": 5001, "sound_id": 100}`
- `{"active_binding_count": 0, "classification": "owned_source_gap", "fallback_available": false, "filename": "hntdrms.wav", "impact": "inactive_or_unreferenced", "resource_id": 5117, "sound_id": 111}`
- `{"active_binding_count": 0, "classification": "owned_source_gap", "fallback_available": false, "filename": "throw.wav", "impact": "inactive_or_unreferenced", "resource_id": 5197, "sound_id": 112}`
- `{"active_binding_count": 0, "classification": "owned_source_gap", "fallback_available": false, "filename": "mandinks.wav", "impact": "inactive_or_unreferenced", "resource_id": 5137, "sound_id": 122}`
- `{"active_binding_count": 0, "classification": "owned_source_gap", "fallback_available": false, "filename": "mining.wav", "impact": "inactive_or_unreferenced", "resource_id": 5146, "sound_id": 130}`
- `{"active_binding_count": 0, "classification": "owned_source_gap", "fallback_available": false, "filename": "mine.wav", "impact": "inactive_or_unreferenced", "resource_id": 5145, "sound_id": 131}`
- `{"active_binding_count": 0, "classification": "owned_source_gap", "fallback_available": false, "filename": "outwood.wav", "impact": "inactive_or_unreferenced", "resource_id": 5160, "sound_id": 149}`
- `{"active_binding_count": 0, "classification": "owned_source_gap", "fallback_available": true, "filename": "tomaka.wav", "impact": "inactive_or_unreferenced", "resource_id": 5200, "sound_id": 152}`
- `{"active_binding_count": 16, "classification": "owned_source_gap", "fallback_available": true, "filename": "tomaka.wav", "impact": "active_binding_with_fallback", "resource_id": 5200, "sound_id": 154}`
- `{"active_binding_count": 1, "classification": "owned_source_gap", "fallback_available": false, "filename": "horse8.wav", "impact": "active_binding_without_audio", "resource_id": 5119, "sound_id": 155}`
- `{"active_binding_count": 68, "classification": "owned_source_gap", "fallback_available": false, "filename": "rubble.wav", "impact": "active_binding_without_audio", "resource_id": 5172, "sound_id": 164}`
- `{"active_binding_count": 0, "classification": "owned_source_gap", "fallback_available": false, "filename": "sabre.wav", "impact": "inactive_or_unreferenced", "resource_id": 5174, "sound_id": 165}`
- `{"active_binding_count": 0, "classification": "owned_source_gap", "fallback_available": false, "filename": "sextus.wav", "impact": "inactive_or_unreferenced", "resource_id": 5175, "sound_id": 166}`
- `{"active_binding_count": 0, "classification": "owned_source_gap", "fallback_available": false, "filename": "sworhit.wav", "impact": "inactive_or_unreferenced", "resource_id": 5194, "sound_id": 172}`
- `{"active_binding_count": 0, "classification": "owned_source_gap", "fallback_available": false, "filename": "hit1.wav", "impact": "inactive_or_unreferenced", "resource_id": 5114, "sound_id": 181}`
- `{"active_binding_count": 0, "classification": "owned_source_gap", "fallback_available": false, "filename": "tiger.wav", "impact": "inactive_or_unreferenced", "resource_id": 5199, "sound_id": 182}`
- `{"active_binding_count": 0, "classification": "owned_source_gap", "fallback_available": false, "filename": "turo.wav", "impact": "inactive_or_unreferenced", "resource_id": 5204, "sound_id": 186}`
- `{"active_binding_count": 0, "classification": "owned_source_gap", "fallback_available": false, "filename": "help.wav", "impact": "inactive_or_unreferenced", "resource_id": 5110, "sound_id": 187}`
- `{"active_binding_count": 0, "classification": "owned_source_gap", "fallback_available": false, "filename": "beach.wav", "impact": "inactive_or_unreferenced", "resource_id": 5023, "sound_id": 191}`
- `{"active_binding_count": 0, "classification": "owned_source_gap", "fallback_available": false, "filename": "taloma.wav", "impact": "inactive_or_unreferenced", "resource_id": 5195, "sound_id": 195}`
- `{"active_binding_count": 0, "classification": "owned_source_gap", "fallback_available": false, "filename": "tomaka.wav", "impact": "inactive_or_unreferenced", "resource_id": 5200, "sound_id": 196}`
- `{"active_binding_count": 0, "classification": "owned_source_gap", "fallback_available": false, "filename": "thud.wav", "impact": "inactive_or_unreferenced", "resource_id": 5198, "sound_id": 199}`
- `{"active_binding_count": 0, "classification": "owned_source_gap", "fallback_available": false, "filename": "zgo.wav", "impact": "inactive_or_unreferenced", "resource_id": 5241, "sound_id": 211}`

## unknown_ids

No findings.

## broken_deltas

No findings.

## dependency_cycles

No findings.

## missing_name_or_icon

- `{"fallback_name_available": true, "icon_id": -1, "icon_required": true, "name_id": 5191, "name_required": true, "object_key": "0:248"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "0:363"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "0:374"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "0:389"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "0:390"}`
- `{"fallback_name_available": true, "icon_id": -1, "icon_required": true, "name_id": 5191, "name_required": true, "object_key": "1:248"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "1:363"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "1:374"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "1:389"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "1:390"}`
- `{"fallback_name_available": true, "icon_id": -1, "icon_required": true, "name_id": 5191, "name_required": true, "object_key": "2:248"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "2:363"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "2:374"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "2:389"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "2:390"}`
- `{"fallback_name_available": true, "icon_id": -1, "icon_required": true, "name_id": 5191, "name_required": true, "object_key": "3:248"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "3:363"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "3:374"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "3:389"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "3:390"}`
- `{"fallback_name_available": true, "icon_id": -1, "icon_required": true, "name_id": 5191, "name_required": true, "object_key": "4:248"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "4:363"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "4:374"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "4:389"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "4:390"}`
- `{"fallback_name_available": true, "icon_id": -1, "icon_required": true, "name_id": 5191, "name_required": true, "object_key": "5:248"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "5:363"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "5:374"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "5:389"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "5:390"}`
- `{"fallback_name_available": true, "icon_id": -1, "icon_required": true, "name_id": 5191, "name_required": true, "object_key": "6:248"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "6:363"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "6:374"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "6:389"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "6:390"}`
- `{"fallback_name_available": true, "icon_id": -1, "icon_required": true, "name_id": 5191, "name_required": true, "object_key": "7:248"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "7:363"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "7:374"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "7:389"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "7:390"}`
- `{"fallback_name_available": true, "icon_id": -1, "icon_required": true, "name_id": 5191, "name_required": true, "object_key": "8:248"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "8:363"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "8:374"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "8:389"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "8:390"}`
- `{"fallback_name_available": true, "icon_id": -1, "icon_required": true, "name_id": 5191, "name_required": true, "object_key": "9:248"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "9:363"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "9:374"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "9:389"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "9:390"}`
- `{"fallback_name_available": true, "icon_id": -1, "icon_required": true, "name_id": 5191, "name_required": true, "object_key": "10:248"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "10:363"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "10:374"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "10:389"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "10:390"}`
- `{"fallback_name_available": true, "icon_id": -1, "icon_required": true, "name_id": 5191, "name_required": true, "object_key": "11:248"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "11:363"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "11:374"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "11:389"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "11:390"}`
- `{"fallback_name_available": true, "icon_id": -1, "icon_required": true, "name_id": 5191, "name_required": true, "object_key": "12:248"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "12:363"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "12:374"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "12:389"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "12:390"}`
- `{"fallback_name_available": true, "icon_id": -1, "icon_required": true, "name_id": 5191, "name_required": true, "object_key": "13:248"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "13:363"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "13:374"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "13:389"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "13:390"}`
- `{"fallback_name_available": true, "icon_id": -1, "icon_required": true, "name_id": 5191, "name_required": true, "object_key": "14:248"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "14:363"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "14:374"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "14:389"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "14:390"}`
- `{"fallback_name_available": true, "icon_id": -1, "icon_required": true, "name_id": 5191, "name_required": true, "object_key": "15:248"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "15:363"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "15:374"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "15:389"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "15:390"}`
- `{"fallback_name_available": true, "icon_id": -1, "icon_required": true, "name_id": 5191, "name_required": true, "object_key": "16:248"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "16:363"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "16:374"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "16:389"}`
- `{"fallback_name_available": false, "icon_id": -1, "icon_required": false, "name_id": 0, "name_required": true, "object_key": "16:390"}`

## suspicious_values

No findings.

## runtime_catalog

No findings.
