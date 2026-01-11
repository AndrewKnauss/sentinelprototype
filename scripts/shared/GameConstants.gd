extends Node
class_name GameConstants

# =============================================================================
# GameConstants.gd
# =============================================================================
# Shared constants used by both server and client.
# Ensures deterministic simulation for prediction/reconciliation.
# =============================================================================

# Physics
const PHYSICS_FPS: int = 60
const FIXED_DELTA: float = 1.0 / 60.0

# Player
const PLAYER_MOVE_SPEED: float = 220.0
const PLAYER_MAX_HEALTH: float = 100.0
const PLAYER_SHOOT_COOLDOWN: float = 0.1  # Seconds between shots

# Enemy
const ENEMY_MOVE_SPEED: float = 80.0
const ENEMY_MAX_HEALTH: float = 150.0
const ENEMY_SHOOT_COOLDOWN: float = 2.0
const ENEMY_SHOOT_RANGE: float = 400.0
const ENEMY_RESPAWN_TIME: float = 100.0
const ENEMY_FRIENDLY_FIRE: bool = false  # Set to false to disable enemy-to-enemy damage

# Bullet
const BULLET_SPEED: float = 800.0
const BULLET_DAMAGE: float = 25.0
const BULLET_LIFETIME: float = 3.0  # Seconds before despawn

# Wall
const WALL_MAX_HEALTH: float = 200.0
const WALL_BUILD_RANGE: float = 100.0
const WALL_SIZE_SIDE: float = 32.0
const WALL_SIZE: Vector2 = Vector2(32, 32)

# Networking
const DEFAULT_PORT: int = 24567
const INTERP_DELAY_TICKS: int = 2 # Client interpolation delay
const RECONCILE_POSITION_THRESHOLD: float = 5.0

# Spawn area
const SPAWN_MIN: Vector2 = Vector2(100, 100)
const SPAWN_MAX: Vector2 = Vector2(700, 500)

# Input buttons
const BTN_SHOOT: int = 1
const BTN_BUILD: int = 2
