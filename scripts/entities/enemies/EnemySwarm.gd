extends Enemy
class_name EnemySwarm

# =============================================================================
# EnemySwarm.gd
# =============================================================================
# Fast, weak enemy that rushes targets aggressively.
# Spawns in groups to overwhelm players with numbers.
# =============================================================================

const SWARM_SPEED: float = 120.0  # 1.5x base
const SWARM_HEALTH: float = 50.0  # 0.33x base
const SWARM_DAMAGE: float = 10.0  # 0.4x base
const SWARM_FIRE_RATE: float = 0.4  # Very fast
const SWARM_CLOSE_RANGE: float = 150.0


func _ready() -> void:
	_base_color = Color(0.0, 1.0, 1.0)  # Cyan
	super._ready()
	health = SWARM_HEALTH
	_sprite.scale = Vector2(0.7, 0.7)


func _ai_chase_and_shoot(delta: float) -> void:
	"""Aggressive rush - no hesitation."""
	var to_player = target_player.global_position - global_position
	var dist = to_player.length()
	
	rotation = to_player.angle()
	
	# Always rush directly at target
	velocity = to_player.normalized() * SWARM_SPEED
	global_position += velocity * delta
	
	# Rapid fire at close range
	if dist < SWARM_CLOSE_RANGE and _shoot_cooldown <= 0:
		_shoot_cooldown = SWARM_FIRE_RATE
		wants_to_shoot.emit(to_player.normalized())
