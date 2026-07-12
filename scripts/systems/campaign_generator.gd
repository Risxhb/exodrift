class_name SidebayCampaignGenerator
extends RefCounted

var nodes: Dictionary = {}
var starting_node_ids: Array[StringName] = []

func generate(run_seed: int) -> void:
	nodes.clear()
	starting_node_ids.clear()
	var random := RandomNumberGenerator.new()
	random.seed = run_seed
	for sector in 3:
		_build_sector(sector, random)
	starting_node_ids = [&"s1_entry_a", &"s1_entry_b"]
	_link(&"s1_boss", &"s2_entry_a")
	_link(&"s1_boss", &"s2_entry_b")
	_link(&"s2_boss", &"s3_entry_a")
	_link(&"s2_boss", &"s3_entry_b")

func _build_sector(sector: int, random: RandomNumberGenerator) -> void:
	var prefix := "s%d" % (sector + 1)
	var threat_base := 1 + sector * 2
	var entry_a_type := SidebayCampaignNode.NodeType.COMBAT
	var entry_b_type := SidebayCampaignNode.NodeType.INTEL if sector == 0 else SidebayCampaignNode.NodeType.COMBAT
	var entry_a_objectives := [SidebayCampaignNode.ObjectiveType.INTERCEPTION, SidebayCampaignNode.ObjectiveType.DEFENSE, SidebayCampaignNode.ObjectiveType.ESCORT]
	var entry_b_objective := SidebayCampaignNode.ObjectiveType.CAPTURE if sector == 1 else SidebayCampaignNode.ObjectiveType.EXTRACTION
	var midpoint_objectives := [SidebayCampaignNode.ObjectiveType.EXTRACTION, SidebayCampaignNode.ObjectiveType.ESCORT, SidebayCampaignNode.ObjectiveType.CAPTURE]
	_add(SidebayCampaignNode.create(StringName("%s_entry_a" % prefix), "Contact Line", sector, 0, 0, entry_a_type, threat_base, entry_a_objectives[sector]))
	_add(SidebayCampaignNode.create(StringName("%s_entry_b" % prefix), "Signal Route", sector, 0, 2, entry_b_type, threat_base, entry_b_objective))
	var utility_types := [SidebayCampaignNode.NodeType.SALVAGE, SidebayCampaignNode.NodeType.REPAIR, SidebayCampaignNode.NodeType.INTEL]
	var mid_a_type: SidebayCampaignNode.NodeType = utility_types[random.randi_range(0, utility_types.size() - 1)]
	_add(SidebayCampaignNode.create(StringName("%s_mid_a" % prefix), "Support Window", sector, 1, 0, mid_a_type, threat_base + 1))
	_add(SidebayCampaignNode.create(StringName("%s_mid_b" % prefix), "Fleet Screen", sector, 1, 1, SidebayCampaignNode.NodeType.COMBAT, threat_base + 1, midpoint_objectives[sector]))
	var mid_c_type: SidebayCampaignNode.NodeType = utility_types[random.randi_range(0, utility_types.size() - 1)]
	_add(SidebayCampaignNode.create(StringName("%s_mid_c" % prefix), "Risky Detour", sector, 1, 2, mid_c_type, threat_base + 1))
	var boss_type := SidebayCampaignNode.NodeType.BOSS
	var boss_name := "Sector Command" if sector < 2 else "Strategic Command"
	_add(SidebayCampaignNode.create(StringName("%s_boss" % prefix), boss_name, sector, 2, 1, boss_type, threat_base + 2))
	_link(StringName("%s_entry_a" % prefix), StringName("%s_mid_a" % prefix))
	_link(StringName("%s_entry_a" % prefix), StringName("%s_mid_b" % prefix))
	_link(StringName("%s_entry_b" % prefix), StringName("%s_mid_b" % prefix))
	_link(StringName("%s_entry_b" % prefix), StringName("%s_mid_c" % prefix))
	for mid in ["mid_a", "mid_b", "mid_c"]:
		_link(StringName("%s_%s" % [prefix, mid]), StringName("%s_boss" % prefix))
	_configure_rewards(sector, prefix)

func _configure_rewards(sector: int, prefix: String) -> void:
	for suffix in ["entry_a", "entry_b", "mid_a", "mid_b", "mid_c", "boss"]:
		var node: SidebayCampaignNode = nodes[StringName("%s_%s" % [prefix, suffix])]
		match node.node_type:
			SidebayCampaignNode.NodeType.COMBAT:
				node.reward_supplies = 12 + sector * 4
				node.reward_intel = 1
			SidebayCampaignNode.NodeType.SALVAGE:
				node.reward_supplies = 30 + sector * 8
			SidebayCampaignNode.NodeType.REPAIR:
				node.reward_supplies = 10
			SidebayCampaignNode.NodeType.INTEL:
				node.reward_intel = 3
			SidebayCampaignNode.NodeType.BOSS:
				node.reward_supplies = 25 + sector * 10
				node.reward_intel = 2

func _add(node: SidebayCampaignNode) -> void:
	nodes[node.node_id] = node

func _link(from_id: StringName, to_id: StringName) -> void:
	var from_node: SidebayCampaignNode = nodes.get(from_id)
	if from_node != null and not from_node.connections.has(to_id):
		from_node.connections.append(to_id)

func get_node(node_id: StringName) -> SidebayCampaignNode:
	return nodes.get(node_id)

func reachable_node_ids(state: SidebayRunState) -> Array[StringName]:
	if state.current_node_id == &"":
		return starting_node_ids.duplicate()
	var current := get_node(state.current_node_id)
	return current.connections.duplicate() if current != null else []

func reveal_forecast(state: SidebayRunState) -> Array[StringName]:
	var revealed: Array[StringName] = []
	for reachable_id in reachable_node_ids(state):
		var reachable := get_node(reachable_id)
		for next_id in reachable.connections:
			state.reveal(next_id)
			revealed.append(next_id)
	return revealed
