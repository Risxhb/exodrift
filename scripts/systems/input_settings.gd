class_name ExodriftInputSettings
extends RefCounted

const ACTION_LABELS := {
	"accelerate": "Increase Throttle", "decelerate": "Decrease Throttle", "boost": "Boost", "brake": "Full Stop",
	"flak_screen": "Toggle Auto Flak", "missile_salvo": "Missile Salvo", "nuclear_torpedo": "Nuclear Torpedo",
	"toggle_tactical": "Tactical Map", "sensor_ping": "Active Ping", "interceptor_wing": "Interceptor Wing",
	"scout_wing": "Scout Wing", "toggle_all_wings": "All Wings / Hangars", "jump_prep": "Jump Preparation",
	"carrier_operations": "Carrier Operations",
	"fleet_group_1": "Fleet Group 1 / Carrier", "fleet_group_2": "Fleet Group 2 / Escort",
	"fleet_group_3": "Fleet Group 3 / Interceptors", "fleet_group_4": "Fleet Group 4 / Scouts",
	"command_stance": "Cycle Fleet Stance", "command_formation": "Cycle Formation",
	"command_recall": "Recall Selected Group", "command_intercept": "Intercept Nearest",
	"command_escort": "Escort Carrier", "command_hold": "Hold Position", "command_withdraw": "Withdraw Selected Group",
	"tactical_center_carrier": "Center Tactical Camera on Carrier"
}

const DEFAULT_KEYS := {
	"accelerate": KEY_W, "decelerate": KEY_S, "boost": KEY_SHIFT, "brake": KEY_CTRL,
	"flak_screen": KEY_1, "missile_salvo": KEY_2, "nuclear_torpedo": KEY_3,
	"toggle_tactical": KEY_TAB, "sensor_ping": KEY_P, "interceptor_wing": KEY_Z,
	"scout_wing": KEY_X, "toggle_all_wings": KEY_B, "jump_prep": KEY_V,
	"carrier_operations": KEY_C,
	"fleet_group_1": KEY_F1, "fleet_group_2": KEY_F2, "fleet_group_3": KEY_F3, "fleet_group_4": KEY_F4,
	"command_stance": KEY_Q, "command_formation": KEY_F, "command_recall": KEY_R,
	"command_intercept": KEY_I, "command_escort": KEY_E, "command_hold": KEY_H, "command_withdraw": KEY_X,
	"tactical_center_carrier": KEY_HOME
}

static func ensure_actions() -> void:
	for action in DEFAULT_KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		if InputMap.action_get_events(action).is_empty():
			rebind(action, int(DEFAULT_KEYS[action]))

static func load_bindings(config: ConfigFile) -> void:
	ensure_actions()
	for action in DEFAULT_KEYS:
		var keycode := int(config.get_value("input", action, DEFAULT_KEYS[action]))
		rebind(action, keycode)

static func save_bindings(config: ConfigFile) -> void:
	for action in DEFAULT_KEYS:
		config.set_value("input", action, action_key(action))

static func rebind(action: String, keycode: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			InputMap.action_erase_event(action, event)
	var key_event := InputEventKey.new()
	key_event.physical_keycode = keycode
	InputMap.action_add_event(action, key_event)

static func action_key(action: String) -> int:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return int(event.physical_keycode if event.physical_keycode != 0 else event.keycode)
	return int(DEFAULT_KEYS.get(action, KEY_NONE))

static func key_label(action: String) -> String:
	return OS.get_keycode_string(action_key(action))
