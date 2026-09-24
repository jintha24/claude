class_name LeverLock
extends RefCounted
## A Victorian lever lock (Chubb, Bramah and Barron patterns were everywhere by 1866).
##
## Every lever has to be lifted to exactly the height of its gate before the bolt will
## pass. Picking means feeling for each one in turn: in the game a marker sweeps up and
## down and you press E when it's inside the gate.
##
## `detector`: Chubb's famous detector lock (1818). A lever lifted too far trips the
## detector, which jams the bolt until the proper key is turned. There is no second try.

var levers: int = 3
## Width of each gate (0..1 of the sweep). Smaller = harder.
var gate_width: float = 0.2
var detector: bool = false
var jammed: bool = false
var locked: bool = true
## Keys in Harry's inventory with this id open the lock outright ("" = no key exists).
var key_id: String = ""
var display_name: String = "lock"


static func make(lever_count: int, gate: float, key: String = "", name: String = "lock", has_detector: bool = false) -> LeverLock:
	var l := LeverLock.new()
	l.levers = lever_count
	l.gate_width = gate
	l.key_id = key
	l.display_name = name
	l.detector = has_detector
	return l


## "3-lever", "5-lever detector" etc. for the prompt.
func describe() -> String:
	return "%d-lever%s" % [levers, " detector" if detector else ""]
