"""Read-only static AI audit. Does not execute GDScript, tests or a build."""
from __future__ import annotations
import ast
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".tools/ai-static"))
from gdtoolkit.parser import parser


def main() -> None:
    prototype = ROOT / "prototype"
    paths = sorted((prototype / "scripts").glob("ai_*.gd"))
    paths += [prototype / "scripts" / name for name in ["simulation_observation_queries.gd", "skirmish_ai_policy.gd", "match_lifecycle_service.gd", "game_save_archive.gd"]]
    paths += [prototype / "tools/benchmark_ai.gd"]
    errors = []
    graph = {}
    declarations = {}
    for path in paths:
        text = path.read_text(encoding="utf-8")
        try:
            parser.parse(text)
        except Exception as error:
            errors.append(f"{path.name}: syntax: {error}")
        graph[path] = []
        for reference in re.findall(r'preload\("res://([^"\n]+)"\)', text):
            target = prototype / reference
            if not target.exists(): errors.append(f"{path.name}: missing preload {reference}")
            graph[path].append(target)
        match = re.search(r"^class_name\s+(\w+)", text, re.M)
        if match:
            if match[1] in declarations: errors.append(f"Duplicate class {match[1]}")
            declarations[match[1]] = path
    active, done = set(), set()
    def visit(path):
        if path in active:
            errors.append(f"Preload cycle through {path.name}")
            return
        if path in done: return
        active.add(path)
        for target in graph.get(path, []): visit(target)
        active.remove(path)
        done.add(path)
    for path in graph: visit(path)
    for path in (prototype / "tools").glob("*ai*.py"):
        try: ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        except SyntaxError as error: errors.append(str(error))
    catalog = json.loads((prototype / "data/ai/skirmish_policies.json").read_text(encoding="utf-8"))
    matrix = json.loads((prototype / "data/ai/benchmark_matrix.json").read_text(encoding="utf-8"))
    settings = json.loads((prototype / "data/skirmish/settings_catalog.json").read_text(encoding="utf-8"))
    positive = ["maximum_workers", "maximum_farms", "maximum_bases", "maximum_foundations", "memory_ticks", "maximum_enemy_memory", "gather_retry_ticks", "command_retry_ticks", "worker_search_budget", "resource_candidate_budget", "gather_command_budget", "combat_sample_budget", "maximum_operations", "regroup_ticks", "assembly_timeout_ticks", "operation_order_interval_ticks", "scout_interval_ticks", "scout_candidate_budget", "minimum_naval_escort"]
    variants = 0
    for profile in catalog["profiles"]:
        for difficulty in catalog["difficulties"]:
            policy = profile["runtime"] | difficulty["overrides"]
            variants += 1
            label = profile["id"] + "/" + difficulty["id"]
            for field in positive:
                if policy.get(field, 0) <= 0: errors.append(f"{label}: nonpositive {field}")
            if not 30 <= policy["forecast_seconds"] <= 60: errors.append(f"{label}: forecast range")
            if not 0 < policy["retreat_ratio"] < policy["attack_ratio"]: errors.append(f"{label}: strength hysteresis")
            if policy["maximum_operations"] > 8 or policy["maximum_enemy_memory"] > 1024: errors.append(f"{label}: persistence bound")
            if policy["minimum_attack_group_size"] > policy["maximum_attack_group_size"]: errors.append(f"{label}: group bounds")
            if not set(policy["age_saving_construction_exceptions"]) <= set(policy["construction_priorities"]): errors.append(f"{label}: construction exception")
            for kind in policy["construction_priorities"]:
                if policy["building_limits"].get(kind, 0) <= 0: errors.append(f"{label}: building limit {kind}")
    references = {"map_type_ids": "map_types", "map_size_ids": "map_sizes", "resource_preset_ids": "resource_presets", "starting_age_ids": "starting_ages"}
    for axis, section in references.items():
        valid = {entry["id"] for entry in settings[section]}
        if not set(matrix[axis]) <= valid: errors.append(f"Matrix has unknown {axis}")
    if not set(matrix["opponent_policy_ids"]) <= {p["id"] for p in catalog["profiles"]}: errors.append("Unknown opponent policy")
    if not set(matrix["difficulty_ids"]) <= {d["id"] for d in catalog["difficulties"]}: errors.append("Unknown difficulty")
    if any(not 1 <= civ <= 16 for pair in matrix["civilization_pairs"] for civ in pair): errors.append("Invalid civilization")
    # The new planners must remain detached and observer-driven. The only new
    # live actor lookups are guarded owner-side enrichment in AiProfile.actor.
    for name in ["ai_adaptive_economy.gd", "ai_operations.gd", "ai_strategy_state.gd", "ai_combat_model.gd", "ai_plan_budget.gd"]:
        text = (prototype / "scripts" / name).read_text(encoding="utf-8")
        if re.search(r"\bworld\.(?:find_|get_units|get_buildings)|\brandi\(|\brandf\(|Time\.", text): errors.append(f"{name}: live-world/random/time dependency")
    profile = (prototype / "scripts/ai_observation_profile.gd").read_text(encoding="utf-8")
    guard = profile.index('if int(row.get("team", 0)) != team:')
    lookup = profile.index('world.find_building(')
    if guard > lookup: errors.append("Foreign actor lookup before observer guard")
    runtime = (prototype / "scripts/ai_runtime_coordinator.gd").read_text(encoding="utf-8")
    if runtime.index('if decisions.active:') > runtime.index('ai.collect_feedback'): errors.append("Feedback before active-job guard")
    if runtime.index('command.params.erase("_ai_feedback")') > runtime.index('controller.enqueue_command'): errors.append("Planner metadata leaks into replay")
    cases = 1
    for axis in ["seeds", "map_type_ids", "map_size_ids", "resource_preset_ids", "starting_age_ids", "difficulty_ids", "civilization_pairs", "opponent_policy_ids", "swap_positions"]: cases *= len(matrix[axis])
    result = {"mode": "static_only", "gdscript_files_parsed": len(paths), "policy_variants_checked": variants, "prepared_matrix_cases": cases, "tests_run": 0, "builds_run": 0, "matches_run": 0, "errors": errors, "limits": "Grammar and source contracts only; engine type checking and gameplay strength are unverified."}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if errors: raise SystemExit(1)


if __name__ == "__main__":
    main()
