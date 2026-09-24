extends Node3D
## Root of the test scene. Places Harry at the street's spawn point, bakes the navigation
## mesh the guards walk on (from the street's collision shapes), and sends every guard back
## to his beat whenever Harry respawns. Phase 8 replaces this with world streaming.


func _ready() -> void:
	var street := $LondonStreet as LondonStreet
	var harry := $Harry as Harry
	# Arriving from the hills (or a save): use the named spawn and bring his things.
	var spawn := GameState.find_spawn(get_tree())
	harry.set_spawn(spawn.global_transform if spawn else street.get_spawn_transform())
	GameState.restore(harry)
	GameState.spawn_at = ""
	var cinder := get_node_or_null("Cinder") as Horse
	if cinder and spawn:
		cinder.global_position = spawn.global_position + spawn.global_basis.x * 2.5 + Vector3.UP * 0.1
		if GameState.arrived_mounted:
			cinder.global_position = spawn.global_position + Vector3.UP * 0.1
			harry.try_mount()
	GameState.arrived_mounted = false
	var nav := get_node_or_null("Navigation") as NavigationRegion3D
	if nav:
		nav.bake_navigation_mesh(false)
	harry.respawned.connect(func() -> void:
		get_tree().call_group("guards", "reset_after_player_respawn")
		get_tree().call_group("guard_dogs", "reset_after_player_respawn"))
