class_name EncounterAction
extends Interactable
## The "[E]" of an encounter: its prompt text and what pressing E does (Encounters).
## With hold_seconds set, E has to be held (pushing a cart) and on_done runs at the end.

var text: Callable
var action: Callable
var hold_seconds := 0.0
var on_done: Callable


func get_prompt(_h: Harry) -> String:
	return text.call() if text.is_valid() else ""


func interact(h: Harry) -> void:
	if hold_seconds > 0.0 and on_done.is_valid():
		h.interaction.begin_hold(self, get_prompt(h), hold_seconds, on_done)
	elif action.is_valid():
		action.call()
