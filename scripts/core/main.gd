extends Node3D
## Root of the test scene. Places Harry at the street's spawn point, bakes the navigation
## mesh the guards walk on (from the street's collision shapes), and sends every guard back
## to his beat whenever Harry respawns. Phase 8 replaces this with world streaming.


func _ready() -> void:
	var street := $LondonStreet as LondonStreet
	var harry := $Harry as Harry
	harry.set_spawn(street.get_spawn_transform())
	var nav := get_node_or_null("Navigation") as NavigationRegion3D
	if nav:
		nav.bake_navigation_mesh(false)
	harry.respawned.connect(func() -> void:
		get_tree().call_group("guards", "reset_after_player_respawn"))
