class_name ExodriftPlaytestRecorder
extends Node

const REPORT_PATH := "user://exodrift_playtest_report.json"
const MAX_EVENTS := 600

var session: Dictionary = {}
var active_battle: Dictionary = {}

func _ready() -> void:
	start_session()

func start_session() -> void:
	session = {
		"session_id": "%d-%06d" % [Time.get_unix_time_from_system(), randi_range(0, 999999)],
		"milestone": "M20",
		"platform": "Web" if OS.has_feature("web") else OS.get_name(),
		"started_unix": Time.get_unix_time_from_system(),
		"run_id": "", "counters": {}, "battles": [], "events": [], "tester_notes": ""
	}
	active_battle.clear()
	record_event(&"session_started")

func begin_run(run_id: String) -> void:
	session["run_id"] = run_id
	record_event(&"run_started", {"run_id": run_id})
	_save_snapshot()

func begin_battle(context: Dictionary) -> void:
	active_battle = context.duplicate(true)
	active_battle["started_msec"] = Time.get_ticks_msec()
	record_event(&"battle_started", context)

func finish_battle(report: Dictionary) -> void:
	if active_battle.is_empty():
		return
	var result := active_battle.duplicate(true)
	result["duration_seconds"] = float(Time.get_ticks_msec() - int(active_battle.get("started_msec", Time.get_ticks_msec()))) / 1000.0
	result.erase("started_msec")
	result["outcome"] = str(report.get("outcome", "unknown"))
	result["objective_success"] = bool(report.get("objective_success", false))
	result["carrier_hull"] = float(report.get("carrier_hull", 0.0))
	result["friendly_craft_remaining"] = int(report.get("interceptor_craft_count", 0)) + int(report.get("scout_craft_count", 0))
	result["survivors_adrift"] = int(report.get("survivors_adrift", 0))
	(session["battles"] as Array).append(result)
	record_event(&"battle_finished", result)
	active_battle.clear()
	_save_snapshot()

func increment(counter_name: StringName, amount: int = 1) -> void:
	var counters: Dictionary = session.get("counters", {})
	var key := String(counter_name)
	counters[key] = int(counters.get(key, 0)) + amount
	session["counters"] = counters

func record_event(event_name: StringName, data: Dictionary = {}) -> void:
	if session.is_empty():
		start_session()
	var events: Array = session.get("events", [])
	events.append({"time_seconds": float(Time.get_ticks_msec()) / 1000.0, "event": String(event_name), "data": data.duplicate(true)})
	while events.size() > MAX_EVENTS:
		events.pop_front()
	session["events"] = events

func record_feedback(notes: String) -> void:
	session["tester_notes"] = notes.strip_edges()
	record_event(&"tester_feedback_saved", {"characters": notes.length()})
	_save_snapshot()

func acceptance_snapshot() -> Dictionary:
	var counters: Dictionary = session.get("counters", {})
	return {
		"onboarding_completed": int(counters.get("onboarding_completed", 0)) > 0,
		"used_active_ping": int(counters.get("active_pings", 0)) > 0,
		"opened_tactical_map": int(counters.get("tactical_opens", 0)) > 0,
		"issued_orders": int(counters.get("orders_issued", 0)) > 0,
		"launched_wings": int(counters.get("wing_launches", 0)) > 0,
		"recalled_wings": int(counters.get("wing_recalls", 0)) > 0,
		"battle_count": (session.get("battles", []) as Array).size(),
		"completed_run": int(counters.get("runs_completed", 0)) > 0
	}

func summary_text() -> String:
	var counters: Dictionary = session.get("counters", {})
	var battles: Array = session.get("battles", [])
	var acceptance := acceptance_snapshot()
	var battle_lines: Array[String] = []
	for battle_data in battles:
		battle_lines.append("- S%d %s / %s: %s, %.1fs, carrier hull %.0f%%" % [int(battle_data.get("sector", 0)) + 1, str(battle_data.get("layout", "unknown")), str(battle_data.get("node_id", "unknown")), str(battle_data.get("outcome", "unknown")), float(battle_data.get("duration_seconds", 0.0)), float(battle_data.get("carrier_hull", 0.0)) * 100.0])
	return """EXODRIFT M20 FLEET COMMAND PLAYTEST DEBRIEF
Session: %s  Platform: %s  Run: %s

FIRST-TIME COMMAND CHECKS
- Orientation completed: %s
- Active sensor used: %s
- Tactical map opened: %s
- Fleet order issued: %s
- Wing launched / recalled: %s / %s

COUNTERS
Pings %d | Tactical opens %d | Orders %d | Completed %d | Rejected %d
Wheel cancels %d | Doctrine changes %d | Wing launches %d | Recalls %d
Flak barrages %d | Missile salvos %d | Withdrawals %d

BATTLES (%d)
%s

TESTER QUESTIONS
1. What was the first moment you felt confused or blocked?
2. Did sensor identification and missile locking make sense?
3. Did you understand that the tactical map remains live?
4. When did you decide to recall or abandon a wing?
5. Which encounter felt repetitive, unfair, or especially memorable?
6. What single change would most improve your next run?

NOTES
%s""" % [str(session.get("session_id", "unknown")), str(session.get("platform", "unknown")), str(session.get("run_id", "none")), _yes_no(bool(acceptance.onboarding_completed)), _yes_no(bool(acceptance.used_active_ping)), _yes_no(bool(acceptance.opened_tactical_map)), _yes_no(bool(acceptance.issued_orders)), _yes_no(bool(acceptance.launched_wings)), _yes_no(bool(acceptance.recalled_wings)), int(counters.get("active_pings", 0)), int(counters.get("tactical_opens", 0)), int(counters.get("orders_issued", 0)), int(counters.get("orders_completed", 0)), int(counters.get("orders_rejected", 0)), int(counters.get("command_wheel_cancels", 0)), int(counters.get("stance_changes", 0)), int(counters.get("wing_launches", 0)), int(counters.get("wing_recalls", 0)), int(counters.get("flak_barrages", 0)), int(counters.get("missile_salvos", 0)), int(counters.get("withdrawals", 0)), battles.size(), "\n".join(battle_lines) if not battle_lines.is_empty() else "- No completed battles recorded.", str(session.get("tester_notes", ""))]

func report_path() -> String:
	return REPORT_PATH

func _yes_no(value: bool) -> String:
	return "YES" if value else "NO"

func _save_snapshot() -> void:
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(session, "  "))
	file.close()
