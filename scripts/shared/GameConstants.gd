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
const PLAYER_DASH_SPEED: float = 1000.0  # Dash speed boost
const PLAYER_DASH_DURATION: float = 0.15  # Seconds
const PLAYER_DASH_COOLDOWN: float = 1.0  # Seconds between dashes

# Sprint
const PLAYER_SPRINT_SPEED: float = 330.0  # 1.5x base (220)
const PLAYER_SPRINT_STAMINA_COST: float = 20.0  # Per second
const PLAYER_STAMINA_MAX: float = 100.0
const PLAYER_STAMINA_REGEN: float = 15.0  # Per second when not sprinting

# Enemy
const ENEMY_MOVE_SPEED: float = 80.0
const ENEMY_MAX_HEALTH: float = 150.0
const ENEMY_SHOOT_COOLDOWN: float = 2.0
const ENEMY_SHOOT_RANGE: float = 400.0
const ENEMY_RESPAWN_TIME: float = 10.0
const ENEMY_FRIENDLY_FIRE: bool = false  # Set to false to disable enemy-to-enemy damage
const ENEMY_AGGRO_RANGE: float = 600.0  # Max distance to maintain aggro
const ENEMY_AGGRO_LOCK_TIME: float = 3.0  # Seconds to stick to attacker

# Bullet
const BULLET_SPEED: float = 600.0
const BULLET_DAMAGE: float = 25.0
const BULLET_LIFETIME: float = 3.0  # Seconds before despawn

# Wall
const WALL_MAX_HEALTH: float = 200.0
const WALL_BUILD_RANGE: float = 100.0
const WALL_SIZE_SIDE: float = 32.0
const WALL_SIZE: Vector2 = Vector2(32, 32)

# Networking
const USE_WEBSOCKET: bool = true  # false = ENet, true = WebSocket
const DEFAULT_PORT: int = 24567
const INTERP_DELAY_TICKS: int = 2 # Client interpolation delay
const RECONCILE_POSITION_THRESHOLD: float = 5.0

# Spawn area
const SPAWN_MIN: Vector2 = Vector2(100, 100)
const SPAWN_MAX: Vector2 = Vector2(700, 500)

# Input buttons
const BTN_SHOOT: int = 1
const BTN_BUILD: int = 2
const BTN_DASH: int = 4
const BTN_SPRINT: int = 8
const BTN_RELOAD: int = 16
const BTN_SWITCH_1: int = 32
const BTN_SWITCH_2: int = 64
const BTN_SWITCH_3: int = 128
