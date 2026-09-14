class_name RoRMatchRegistry
extends RefCounted

const MATCHES := [
	{
		"id": "prototype_skirmish",
		"title": "Учебная схватка",
		"subtitle": "Небольшая карта для проверки основных механик и формаций",
		"path": "res://data/matches/prototype_match.json",
		"kind": "skirmish",
	},
	{
		"id": "campaign_birth_of_rome",
		"title": "Восхождение Рима",
		"subtitle": "Первая миссия кампании «Расцвет Рима» — ранняя игровая вертикаль",
		"path": "res://assets/generated/matches/birth-of-rome.json",
		"kind": "campaign",
	},
	{
		"id": "campaign_pyrrhus_of_epirus",
		"title": "Пирр Эпирский",
		"subtitle": "Вторая миссия кампании «Расцвет Рима» — оборона двух римских центров",
		"path": "res://assets/generated/matches/pyrrhus-of-epirus.json",
		"kind": "campaign",
	},
	{
		"id": "campaign_syracuse",
		"title": "Сиракузцы",
		"subtitle": "Третья миссия кампании «Расцвет Рима» — провести десять легионеров к Сиракузам",
		"path": "res://assets/generated/matches/syracuse.json",
		"kind": "campaign",
	},
	{
		"id": "campaign_metaurus",
		"title": "Метавр",
		"subtitle": "Четвёртая миссия кампании «Расцвет Рима» — стандартная победа или Чудо",
		"path": "res://assets/generated/matches/metaurus.json",
		"kind": "campaign",
	},
	{
		"id": "campaign_zama",
		"title": "Зама",
		"subtitle": "Пятая миссия кампании «Расцвет Рима» — решающая битва с Карфагеном",
		"path": "res://assets/generated/matches/zama.json",
		"kind": "campaign",
	},
	{
		"id": "campaign_mithridates",
		"title": "Митридат",
		"subtitle": "Шестая миссия кампании «Расцвет Рима» — уничтожить Чудо Митридата",
		"path": "res://assets/generated/matches/mithridates.json",
		"kind": "campaign",
	},
	{
		"id": "campaign_struggle_for_sicily",
		"title": "Борьба за Сицилию",
		"subtitle": "Первая миссия кампании «Первая Пуническая война» — учебная высадка на Сицилии",
		"path": "res://assets/generated/matches/struggle-for-sicily.json",
		"kind": "campaign",
	},
	{
		"id": "campaign_battle_of_mylae",
		"title": "Битва при Милах",
		"subtitle": "Вторая миссия кампании «Первая Пуническая война» — захват и доставка двух артефактов",
		"path": "res://assets/generated/matches/battle-of-mylae.json",
		"kind": "campaign",
	},
	{
		"id": "campaign_battle_of_tunes",
		"title": "Битва при Тунете",
		"subtitle": "Третья миссия кампании «Первая Пуническая война» — уничтожение карфагенского Чуда",
		"path": "res://assets/generated/matches/battle-of-tunes.json",
		"kind": "campaign",
	},
]


static func entries() -> Array:
	var result: Array = []
	for value in MATCHES:
		var entry: Dictionary = value.duplicate(true)
		entry["available"] = FileAccess.file_exists(String(entry["path"]))
		result.append(entry)
	return result


static func resolve(identifier: String) -> Dictionary:
	for entry_value in entries():
		var entry: Dictionary = entry_value
		if identifier == String(entry["id"]) or identifier == String(entry["path"]):
			return entry
	return {}


static func requested_match(arguments: PackedStringArray) -> Dictionary:
	for index in range(arguments.size()):
		var argument := String(arguments[index])
		if argument.begins_with("--match="):
			return resolve(argument.trim_prefix("--match="))
		if argument == "--match" and index + 1 < arguments.size():
			return resolve(String(arguments[index + 1]))
	return {}
