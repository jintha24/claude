class_name SafehouseBed
extends CampBed
## The cot in St Giles's crypt: once Father Bernard has taken Harry in (mission 5) he can
## sleep and save here, as at the cave.


func get_prompt(harry: Harry) -> String:
	if not Story.get_flag("st_giles_safehouse"):
		return ""
	return super.get_prompt(harry)
