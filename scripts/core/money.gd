class_name Money
extends RefCounted
## Victorian money. Everything is stored in pence (d):
##   12 pence = 1 shilling (s), 20 shillings = 1 pound (L), so 1 pound = 240 pence.
## For scale in 1866: a labourer earned about 20s a week, a loaf of bread cost about 6d,
## and a good gold pocket watch was worth about 10 pounds.

const PENCE_PER_SHILLING := 12
const PENCE_PER_POUND := 240


static func pounds(p: float) -> int:
	return int(round(p * PENCE_PER_POUND))


static func shillings(s: float) -> int:
	return int(round(s * PENCE_PER_SHILLING))


## "£2 4s 6d", "7s 3d", "9d".
static func format(pence: int) -> String:
	var negative := pence < 0
	pence = absi(pence)
	var l := pence / PENCE_PER_POUND
	var s := (pence % PENCE_PER_POUND) / PENCE_PER_SHILLING
	var d := pence % PENCE_PER_SHILLING
	var parts: Array[String] = []
	if l > 0:
		parts.append("£%d" % l)
	if s > 0:
		parts.append("%ds" % s)
	if d > 0 or parts.is_empty():
		parts.append("%dd" % d)
	return ("-" if negative else "") + " ".join(parts)
