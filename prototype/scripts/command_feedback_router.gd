class_name RoRCommandFeedbackRouter
extends RefCounted

var event_cursor: int = 0
var pending: Dictionary = {}


func reset() -> void:
	event_cursor = 0
	pending.clear()


func register(command: Variant, accepted_message: String = "", sound_name: String = "", marker: Variant = null) -> void:
	if command == null or int(command.sequence_id) <= 0:
		return
	pending[int(command.sequence_id)] = {
		"accepted_message": accepted_message,
		"sound_name": sound_name,
		"marker": marker,
	}


func consume(events: Array, player_issuer_id: int) -> Array[Dictionary]:
	var feedback_events: Array[Dictionary] = []
	for event_value in events:
		var event: Dictionary = event_value
		event_cursor = maxi(event_cursor, int(event.get("sequence_id", 0)))
		var event_type := String(event.get("type", ""))
		if event_type not in ["command_accepted", "command_rejected", "queued_order_rejected"]:
			continue
		var payload: Dictionary = event.get("payload", {})
		if int(payload.get("issuer_id", 0)) != player_issuer_id:
			continue
		var command_sequence := int(payload.get("sequence_id", -1))
		if event_type == "queued_order_rejected":
			feedback_events.append({
				"type": "command_feedback",
				"accepted": false,
				"sequence_id": command_sequence,
				"command_type": String(payload.get("command_type", "")),
				"reason": String(payload.get("reason", "command_rejected")),
				"message": rejected_message(String(payload.get("reason", "command_rejected"))),
				"sound_name": "",
				"marker": null,
			})
			continue
		# Derived AI/stance reactions use the same command stream but were never
		# registered by a pointer/UI gesture and must not impersonate player input.
		if not pending.has(command_sequence):
			continue
		var registered: Dictionary = pending.get(command_sequence, {})
		var accepted := bool(payload.get("accepted", false))
		feedback_events.append({
			"type": "command_feedback",
			"accepted": accepted,
			"sequence_id": command_sequence,
			"command_type": String(payload.get("command_type", "")),
			"reason": String(payload.get("reason", "")),
			"message": String(registered.get("accepted_message", accepted_message(String(payload.get("command_type", ""))))) if accepted else rejected_message(String(payload.get("reason", "command_rejected"))),
			"sound_name": String(registered.get("sound_name", "")) if accepted else "",
			"marker": registered.get("marker") if accepted else null,
		})
		pending.erase(command_sequence)
	return feedback_events


static func accepted_message(command_type: String) -> String:
	return String({
		"attack": "Атаковать цель",
		"attack_ground": "Атаковать указанную точку",
		"attack_move": "Атаковать с продвижением",
		"convert": "Обратить цель",
		"heal": "Исцелить союзника",
		"martyrdom": "Жертвоприношение совершено",
		"delete_entity": "Выбранные объекты удалены",
		"gather": "Собирать ресурс",
		"return_resources": "Сдать ресурсы",
		"board": "Погрузиться в транспорт",
		"unload": "Высадить пассажиров",
		"set_trade_resource": "Торговый ресурс выбран",
		"trade": "Торговый маршрут назначен",
		"build": "Продолжить строительство",
		"repair": "Ремонтировать цель",
		"tribute": "Дань отправлена",
		"formation_move": "Приказ движения принят",
		"move": "Приказ движения принят",
		"stop": "Юниты остановлены",
		"hold": "Позиция удерживается",
		"stance": "Боевая стойка изменена",
		"train": "Юнит добавлен в очередь",
		"research": "Исследование добавлено в очередь",
		"cancel_production": "Элемент очереди отменён",
		"resign": "Игрок сдался",
	}.get(command_type, "Приказ принят"))


static func rejected_message(reason: String) -> String:
	return String({
		"no_eligible_units": "Нет подходящих юнитов",
		"attack_ground_unavailable": "Для атаки по земле нужны осадные орудия",
		"invalid_ground_target": "Точка обстрела вне карты",
		"order_queue_full": "Очередь приказов заполнена",
		"queue_unsupported": "Этот приказ нельзя добавить в очередь",
		"no_eligible_workers": "В группе нет работников",
		"no_eligible_healers": "В группе нет жрецов, способных лечить",
		"no_eligible_martyr": "Нет жреца, способного совершить жертвоприношение",
		"invalid_target": "Цель больше недоступна",
		"invalid_healing_target": "Эту цель нельзя исцелить",
		"healing_target_not_allied": "Можно исцелять только союзные войска",
		"self_healing_forbidden": "Жрец не может исцелять себя",
		"target_fully_healed": "Цель уже полностью здорова",
		"martyrdom_not_researched": "Сначала исследуйте Жертвоприношение",
		"martyrdom_requires_conversion": "Сначала прикажите жрецу обратить вражеского юнита",
		"martyrdom_conversion_not_started": "Жрец должен сначала начать обращение цели",
		"invalid_martyrdom_target": "Жертвоприношение действует только на вражеских юнитов",
		"martyrdom_priest_immune": "Жертвоприношение не действует на вражеского жреца",
		"friendly_target": "Нельзя атаковать союзника",
		"resource_unavailable": "Ресурс больше недоступен",
		"resource_not_owned": "Нельзя собирать ресурс другого игрока",
		"no_carried_resources": "У выбранных работников нет груза",
		"invalid_dropoff": "Это здание не принимает переносимый ресурс",
		"invalid_transport": "Транспорт недоступен",
		"no_eligible_passengers": "Нет подходящих пассажиров",
		"invalid_passenger": "Пассажир недоступен",
		"passenger_not_owned": "Можно погружать только свои и союзные войска",
		"passenger_domain_forbidden": "Этот тип юнита нельзя погрузить",
		"passenger_not_in_range": "Пассажир должен подойти к транспорту",
		"transport_full": "В транспорте нет свободных мест",
		"transport_empty": "Транспорт пуст",
		"landing_too_far": "Выберите берег рядом с транспортом",
		"landing_blocked": "На выбранном берегу нет места для высадки",
		"invalid_cargo_selection": "Выбранных пассажиров нет в транспорте",
		"invalid_cargo_state": "Состояние груза повреждено",
		"no_eligible_traders": "Выберите торговое судно",
		"invalid_trade_resource": "Этот ресурс нельзя использовать для торговли",
		"invalid_trade_dock": "Выбранное здание не является торговым портом",
		"trade_requires_foreign_dock": "Торговать можно только с чужим портом",
		"trade_dock_unexplored": "Сначала разведайте торговый порт",
		"no_home_dock": "Для торговли нужен собственный порт",
		"trade_route_unreachable": "Торговое судно не может пройти по этому маршруту",
		"no_path": "До указанной точки нет доступного пути",
		"unreachable_target": "До цели невозможно добраться",
		"invalid_stance": "Неизвестная боевая стойка",
		"issuer_team_mismatch": "Эта сущность принадлежит другому игроку",
		"player_not_active": "Матч для этого игрока уже завершён",
		"build_rejected": "Здесь нельзя строить",
		"building_unavailable": "Это здание ещё не открыто",
		"reseed_unavailable": "Эту ферму сейчас нельзя пересеять",
		"repair_rejected": "Цель нельзя ремонтировать",
		"invalid_tribute_recipient": "Выберите другого игрока для дани",
		"tribute_requires_ally": "Дань можно отправить только союзнику",
		"invalid_tribute_resource": "Недопустимый ресурс для дани",
		"invalid_tribute_amount": "Сумма дани должна быть положительной",
		"invalid_production_building": "Выбранное здание не может производить юнитов",
		"wrong_production_location": "Этот юнит производится в другом здании",
		"unit_unavailable": "Этот юнит ещё не открыт",
		"unknown_unit_type": "Неизвестный тип юнита",
		"unknown_building_type": "Неизвестный тип здания",
		"insufficient_resources": "Недостаточно ресурсов",
		"population_cap": "Достигнут предел населения",
		"queue_full": "Очередь заполнена",
		"invalid_research_building": "Выбранное здание не проводит это исследование",
		"wrong_research_location": "Это исследование проводится в другом здании",
		"missing_prerequisites": "Не выполнены требования исследования",
		"invalid_queue_item": "Элемент очереди больше недоступен",
	}.get(reason, "Приказ отклонён: %s" % reason))
