extends Node3D
## Root of the test scene. Places Harry at the street's spawn point, bakes the navigation
## mesh the guards walk on (from the street's collision shapes), and sends every guard back
## to his beat whenever Harry respawns. Phase 8 replaces this with world streaming.


func _ready() -> void:
	var street := $LondonStreet as LondonStreet
	var harry := $Harry as Harry
	GameSettings.apply(get_tree())
	# Arriving from the hills or from a save: the right spot, and his things with him.
	var spawn: Variant = GameState.take_spawn(get_tree())
	harry.set_spawn(spawn if spawn != null else street.get_spawn_transform())
	GameState.restore(harry)
	var cinder := get_node_or_null("Cinder") as Horse
	if cinder and spawn != null:
		var t: Transform3D = spawn
		cinder.global_position = t.origin + t.basis.x * 2.5 + Vector3.UP * 0.1
		if GameState.arrived_mounted:
			cinder.global_position = t.origin + Vector3.UP * 0.1
			harry.try_mount()
	GameState.arrived_mounted = false
	if GameState.autosave_on_arrival:
		GameState.autosave_on_arrival = false
		SaveGame.save.call_deferred(get_tree(), 0)
	var nav := get_node_or_null("Navigation") as NavigationRegion3D
	if nav:
		nav.bake_navigation_mesh(false)
	harry.respawned.connect(func() -> void:
		get_tree().call_group("guards", "reset_after_player_respawn")
		get_tree().call_group("guard_dogs", "reset_after_player_respawn"))
