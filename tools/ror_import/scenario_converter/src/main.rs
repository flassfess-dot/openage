use genie_cpx::Campaign;
use genie_scx::{Scenario, VictoryConditions};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::env;
use std::error::Error;
use std::fs;
use std::io::Cursor;
use std::path::{Path, PathBuf};

struct Arguments {
    campaign: PathBuf,
    scenario_index: usize,
    output: PathBuf,
}

fn parse_arguments() -> Result<Arguments, String> {
    let mut campaign = None;
    let mut scenario_index = None;
    let mut output = None;
    let mut args = env::args().skip(1);
    while let Some(argument) = args.next() {
        let value = args
            .next()
            .ok_or_else(|| format!("missing value for {argument}"))?;
        match argument.as_str() {
            "--campaign" => campaign = Some(PathBuf::from(value)),
            "--scenario-index" => {
                scenario_index = Some(
                    value
                        .parse::<usize>()
                        .map_err(|_| format!("invalid scenario index {value:?}"))?,
                )
            }
            "--output" => output = Some(PathBuf::from(value)),
            _ => return Err(format!("unknown argument {argument:?}")),
        }
    }
    Ok(Arguments {
        campaign: campaign.ok_or("required argument --campaign")?,
        scenario_index: scenario_index.ok_or("required argument --scenario-index")?,
        output: output.ok_or("required argument --output")?,
    })
}

fn sha256(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}

fn source_filename(path: &Path) -> String {
    path.file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_default()
}

fn active_disabled_ids(values: &[Vec<i32>], counts: &[i32]) -> Vec<Vec<i32>> {
    values
        .iter()
        .enumerate()
        .map(|(slot, entries)| {
            let count = counts.get(slot).copied().unwrap_or(0).max(0) as usize;
            entries
                .iter()
                .take(count)
                .copied()
                .filter(|value| *value > 0)
                .collect()
        })
        .collect()
}

fn legacy_disabled_node_slots(values: &[Vec<i32>]) -> Vec<Vec<usize>> {
    values
        .iter()
        .map(|entries| {
            entries
                .iter()
                .take(16)
                .enumerate()
                .filter_map(|(slot, value)| (*value == 0).then_some(slot))
                .collect()
        })
        .collect()
}

fn victory_conditions_json(conditions: &VictoryConditions) -> Value {
    let entries: Vec<Value> = conditions
        .entries
        .iter()
        .map(|entry| {
            let area = entry.area();
            json!({
                "command": u8::from(entry.command()),
                "object_type": entry.object_type(),
                "player_id": entry.player_id(),
                "area": [area.0, area.1, area.2, area.3],
                "number": entry.number(),
                "count": entry.count(),
                "source_object": entry.source_object(),
                "target_object": entry.target_object(),
                "victory_group": entry.victory_group(),
                "ally_flag": entry.ally_flag(),
                "state": entry.state(),
            })
        })
        .collect();
    let point_entries: Vec<Value> = conditions
        .point_entries
        .iter()
        .map(|entry| {
            json!({
                "command": entry.command(),
                "state": entry.state(),
                "attribute": entry.attribute(),
                "amount": entry.amount(),
                "points": entry.points(),
                "current_points": entry.current_points(),
                "id": entry.id(),
                "group": entry.group(),
                "current_attribute_amount": entry.current_attribute_amount(),
                "attribute1": entry.attribute1(),
                "current_attribute_amount1": entry.current_attribute_amount1(),
            })
        })
        .collect();
    json!({
        "version": conditions.version,
        "state": u8::from(conditions.victory()),
        "total_points": conditions.total_points,
        "starting_points": conditions.starting_points(),
        "starting_group": conditions.starting_group(),
        "entries": entries,
        "point_entries": point_entries,
    })
}

fn main() -> Result<(), Box<dyn Error>> {
    let arguments = parse_arguments().map_err(|message| format!("argument error: {message}"))?;
    let campaign_bytes = fs::read(&arguments.campaign)?;
    let mut campaign = Campaign::from(Cursor::new(campaign_bytes.as_slice()))?;
    let campaign_name = campaign.name().to_owned();
    let scenario_name = campaign
        .get_name(arguments.scenario_index)
        .ok_or("scenario index is outside the campaign")?
        .to_owned();
    let scenario_filename = campaign
        .get_filename(arguments.scenario_index)
        .ok_or("scenario index is outside the campaign")?
        .to_owned();
    let scenario_bytes = campaign.by_index_raw(arguments.scenario_index)?;
    let scenario = Scenario::read_from(Cursor::new(scenario_bytes.as_slice()))?;

    let map = scenario.map();
    let terrain_ids: Vec<u8> = map.tiles().map(|tile| tile.terrain).collect();
    let tile_elevations: Vec<i8> = map.tiles().map(|tile| tile.elevation).collect();
    let layered_terrain_ids: Vec<i32> = map
        .tiles()
        .map(|tile| tile.layered_terrain.map(i32::from).unwrap_or(-1))
        .collect();
    let zones: Vec<i8> = map.tiles().map(|tile| tile.zone).collect();

    let settings = scenario.settings();
    let base_properties = settings.player_base_properties();
    let start_resources = settings.player_start_resources();
    let scenario_players = scenario.scenario_players();
    let world_players = scenario.world_players();
    let object_players = scenario.player_objects();
    let slot_count = [
        base_properties.len(),
        start_resources.len(),
        scenario_players.len(),
        world_players.len(),
        object_players.len(),
    ]
    .into_iter()
    .max()
    .unwrap_or(0);

    let mut players = Vec::with_capacity(slot_count);
    for slot in 0..slot_count {
        let base = base_properties.get(slot);
        let start = start_resources.get(slot);
        let scenario_player = scenario_players.get(slot);
        let world = world_players.get(slot);
        let files = settings.player_files().get(slot);
        players.push(json!({
            "slot": slot,
            "active": base.map(|value| value.active()).unwrap_or(false),
            "player_type": base.map(|value| value.player_type()),
            "civilization_id": base.map(|value| value.civilization()),
            "posture": base.map(|value| value.posture()),
            "name": scenario_player.and_then(|value| value.name.clone()),
            "color": scenario_player.and_then(|value| value.color),
            "view": scenario_player.map(|value| [value.view.0, value.view.1]),
            "location": scenario_player.map(|value| [value.location.0, value.location.1]),
            "allied_victory": scenario_player.map(|value| value.allied_victory).unwrap_or(false),
            "relations": scenario_player.map(|value| value.relations.clone()).unwrap_or_default(),
            "unit_diplomacy": scenario_player.map(|value| value.unit_diplomacy.clone()).unwrap_or_default(),
            "start_resources": start.map(|value| json!({
                "food": value.food(),
                "wood": value.wood(),
                "gold": value.gold(),
                "stone": value.stone(),
                "ore": value.ore(),
                "goods": value.goods(),
                "player_color": value.player_color(),
            })),
            "world_resources": world.map(|value| json!({
                "food": value.food(),
                "wood": value.wood(),
                "gold": value.gold(),
                "stone": value.stone(),
                "ore": value.ore(),
                "goods": value.goods(),
                "population": value.population(),
            })),
            "source_ai": {
                "rule_name": settings.player_ai_rules().get(slot).and_then(|value| value.as_deref()),
                "rule_type": settings.ai_rules_types().get(slot).copied(),
                "embedded_rules": files.and_then(|value| value.ai_rules()),
                "build_list_name": settings.player_build_lists().get(slot).and_then(|value| value.as_deref()),
                "embedded_build_list": files.and_then(|value| value.build_list()),
                "city_plan_name": settings.player_city_plans().get(slot).and_then(|value| value.as_deref()),
                "embedded_city_plan": files.and_then(|value| value.city_plan()),
            },
            "victory_conditions": scenario_player
                .map(|value| victory_conditions_json(&value.victory)),
        }));
    }

    let diplomacy: Vec<Vec<i32>> = settings
        .diplomacy()
        .iter()
        .map(|row| row.iter().map(|stance| (*stance).into()).collect())
        .collect();
    let mut objects = Vec::new();
    for (owner_slot, player_objects) in object_players.iter().enumerate() {
        for object in player_objects {
            let source_unit_id: u16 = object.object_type.into();
            objects.push(json!({
                "owner_slot": owner_slot,
                "scenario_object_id": object.id,
                "source_unit_id": source_unit_id,
                "position": [object.position.0, object.position.1, object.position.2],
                "state": object.state,
                "angle": object.angle,
                "frame": object.frame,
                "garrisoned_in": object.garrisoned_in,
            }));
        }
    }

    let (trigger_version, trigger_count, condition_count, effect_count) =
        if let Some(system) = scenario.triggers() {
            let mut conditions = 0usize;
            let mut effects = 0usize;
            for trigger in system.triggers() {
                conditions += trigger.conditions().count();
                effects += trigger.effects().count();
            }
            (
                Some(system.version()),
                system.num_triggers() as usize,
                conditions,
                effects,
            )
        } else {
            (None, 0, 0, 0)
        };

    let global_victory = settings.victory();
    let legacy_victory_players: Vec<Value> = settings
        .legacy_victory_info()
        .iter()
        .enumerate()
        .map(|(player_slot, entries)| {
            let entries: Vec<Value> = entries
                .iter()
                .enumerate()
                .map(|(condition_slot, entry)| {
                    json!({
                        "condition_slot": condition_slot,
                        "object_type": entry.object_type,
                        "all_flag": entry.all_flag,
                        "player_id": entry.player_id,
                        "dest_object_id": entry.dest_object_id,
                        "area": [entry.area.0, entry.area.1, entry.area.2, entry.area.3],
                        "victory_type": entry.victory_type,
                        "amount": entry.amount,
                        "attribute": entry.attribute,
                        "object_id": entry.object_id,
                        "dest_object_id2": entry.dest_object_id2,
                    })
                })
                .collect();
            json!({
                "player_slot": player_slot,
                "allied_victory": settings.allied_victory().get(player_slot).copied().unwrap_or(0),
                "entries": entries,
            })
        })
        .collect();

    let payload: Value = json!({
        "schema_version": 3,
        "source": {
            "campaign_filename": source_filename(&arguments.campaign),
            "campaign_name": campaign_name,
            "campaign_sha256": sha256(&campaign_bytes),
            "scenario_index": arguments.scenario_index,
            "scenario_name": scenario_name,
            "scenario_filename": scenario_filename,
            "scenario_sha256": sha256(&scenario_bytes),
            "scenario_format_version": scenario.format_version().to_string(),
            "scenario_data_version": scenario.data_version(),
        },
        "description": scenario.description().unwrap_or_default(),
        "map": {
            "size": [map.width(), map.height()],
            "terrain_ids": terrain_ids,
            "tile_elevations": tile_elevations,
            "layered_terrain_ids": layered_terrain_ids,
            "zones": zones,
        },
        "players": players,
        "diplomacy": diplomacy,
        "objects": objects,
        "legacy_victory": {
            "global": {
                "conquest": global_victory.conquest(),
                "ruins": global_victory.ruins(),
                "relics": global_victory.relics(),
                "discoveries": global_victory.discoveries(),
                "exploration": global_victory.exploration(),
                "gold": global_victory.gold(),
            },
            "all_conditions_required": settings.victory_all_flag(),
            "players": legacy_victory_players,
        },
        "scenario_settings": {
            "multiplayer_victory_type": settings.multiplayer_victory_type(),
            "victory_score": settings.victory_score(),
            "victory_time": settings.victory_time(),
            "all_technologies": settings.all_technologies(),
            "player_start_ages": settings
                .player_start_ages()
                .iter()
                .map(|age| age.to_i32(settings.version()))
                .collect::<Vec<i32>>(),
            // Classic AoE/RoR data versions store twenty on/off technology-tree
            // node flags per player, not a counted list of technology IDs. The
            // first sixteen slots correspond to the Options-tab controls and the
            // remaining four are reserved. Newer Genie formats use real ID lists.
            "disabled_technologies_format": if settings.version() < 1.18 {
                "legacy_node_flags"
            } else {
                "technology_id_lists"
            },
            "disabled_technologies": if settings.version() < 1.18 {
                vec![Vec::<i32>::new(); settings.disabled_technologies().len()]
            } else {
                active_disabled_ids(
                    settings.disabled_technologies(),
                    settings.num_disabled_technologies(),
                )
            },
            "disabled_technologies_raw": settings.disabled_technologies(),
            "disabled_technology_counts": settings.num_disabled_technologies(),
            "legacy_disabled_technology_node_slots": if settings.version() < 1.18 {
                legacy_disabled_node_slots(settings.disabled_technologies())
            } else {
                Vec::<Vec<usize>>::new()
            },
            "disabled_units": active_disabled_ids(
                settings.disabled_units(),
                settings.num_disabled_units(),
            ),
            "disabled_buildings": active_disabled_ids(
                settings.disabled_buildings(),
                settings.num_disabled_buildings(),
            ),
        },
        "deferred_scenario_logic": {
            "trigger_version": trigger_version,
            "trigger_count": trigger_count,
            "condition_count": condition_count,
            "effect_count": effect_count,
        },
    });

    if let Some(parent) = arguments.output.parent() {
        fs::create_dir_all(parent)?;
    }
    let mut encoded = serde_json::to_vec_pretty(&payload)?;
    encoded.push(b'\n');
    fs::write(&arguments.output, encoded)?;
    println!(
        "converted {} scenario {}: {}x{}, {} objects, {} triggers",
        campaign_name,
        arguments.scenario_index,
        map.width(),
        map.height(),
        objects.len(),
        trigger_count
    );
    Ok(())
}
