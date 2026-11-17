extends RefCounted
## Pure combat math with no scene or node dependencies.
## Kept separate on purpose: later the server can run the same rules.

const DAMAGE_SPREAD := 0.2


## Damage of one hit: the base value, plus or minus a small random spread. Never below 1.
static func roll_damage(base_damage: int) -> int:
	var spread: int = _spread(base_damage)
	return maxi(1, base_damage + randi_range(-spread, spread))


## Lowest and highest damage roll_damage can give, for showing "8 ~ 12".
static func damage_range(base_damage: int) -> Vector2i:
	var spread: int = _spread(base_damage)
	return Vector2i(maxi(1, base_damage - spread), maxi(1, base_damage + spread))


static func _spread(base_damage: int) -> int:
	return maxi(1, roundi(base_damage * DAMAGE_SPREAD))
