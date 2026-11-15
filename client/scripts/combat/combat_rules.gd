extends RefCounted
## Pure combat math with no scene or node dependencies.
## Kept separate on purpose: later the server can run the same rules.

const DAMAGE_SPREAD := 0.2


## Damage of one hit: the base value, plus or minus a small random spread. Never below 1.
static func roll_damage(base_damage: int) -> int:
	var spread: int = maxi(1, roundi(base_damage * DAMAGE_SPREAD))
	return maxi(1, base_damage + randi_range(-spread, spread))
