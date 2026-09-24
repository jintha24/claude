class_name SafehouseChest
extends CampChest
## Father Bernard's strongbox in the crypt: the same stash as the camp chest in the hills
## (Bernard's people carry things between them).


func get_prompt(harry: Harry) -> String:
	if not Story.get_flag("st_giles_safehouse"):
		return ""
	return super.get_prompt(harry)
