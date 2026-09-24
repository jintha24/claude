class_name ArrowBench
extends Interactable
## Harry's fletching bench: ash shafts, goose feathers, padded blunt heads, bone whistles
## and a few steel broadheads. Half a minute's work (a few seconds' hold) fills his quiver.

@export var blunt_to: int = 12
@export var whistle_to: int = 6
@export var broadhead_to: int = 8


func _ready() -> void:
	interact_range = 1.8


func get_prompt(harry: Harry) -> String:
	var c := harry.combat
	if c.blunt_arrows >= blunt_to and c.whistle_arrows >= whistle_to and c.broadhead_arrows >= broadhead_to:
		return ""
	return "Make arrows"


func interact(harry: Harry) -> void:
	harry.interaction.begin_hold(self, "Fletching arrows", 3.0, func() -> void:
		var c := harry.combat
		c.add_ammo("blunt", maxi(blunt_to - c.blunt_arrows, 0))
		c.add_ammo("whistle", maxi(whistle_to - c.whistle_arrows, 0))
		c.add_ammo("broadhead", maxi(broadhead_to - c.broadhead_arrows, 0)))
