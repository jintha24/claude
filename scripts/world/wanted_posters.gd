class_name WantedPosters
extends Node3D
## Captain Crowe's handbills, pasted up on walls round the street and market once the Hill
## Fox is notorious enough (escalation 1+), showing the current reward. Torn down again
## when the fuss dies down.

## [position, yaw] of each poster (on the building faces, about head height).
const SPOTS: Array = [
	[Vector3(-6.26, 1.9, 20.0), PI * 0.5], [Vector3(6.26, 1.9, -12.0), -PI * 0.5],
	[Vector3(-6.26, 1.9, -30.0), PI * 0.5], [Vector3(24.93, 1.9, -62.0), -PI * 0.5],
	[Vector3(-24.93, 1.9, -78.0), PI * 0.5],
]

var _posters: Array[Node3D] = []
var _labels: Array[Label3D] = []


func _ready() -> void:
	add_to_group("wanted_posters")
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.86, 0.8, 0.64)
	paper.roughness = 0.95
	for s: Array in SPOTS:
		var node := Node3D.new()
		node.position = s[0]
		node.rotation.y = s[1]
		add_child(node)
		var quad := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.55, 0.75)
		quad.mesh = qm
		quad.material_override = paper
		node.add_child(quad)
		var l := Label3D.new()
		l.font = UIKit.font()
		l.font_size = 40
		l.pixel_size = 0.0022
		l.modulate = Color(0.12, 0.08, 0.05)
		l.outline_size = 0
		l.position = Vector3(0, 0, 0.005)
		l.width = 230.0
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		node.add_child(l)
		_posters.append(node)
		_labels.append(l)
	Progress.bus().notoriety_changed.connect(func(_v: float, _d: float, _r: String) -> void: refresh())
	refresh()


func is_showing() -> bool:
	return not _posters.is_empty() and _posters[0].visible


func refresh() -> void:
	var on := Progress.escalation() >= 1
	var text := "WANTED\n\nThe Thief known as\nTHE HILL FOX\n\n%s REWARD\n\nfor information leading to his apprehension.\n\nH. CROWE, Capt.\nMetropolitan Police" % Money.format(Progress.bounty()).to_upper()
	for i in _posters.size():
		_posters[i].visible = on
		_labels[i].text = text
