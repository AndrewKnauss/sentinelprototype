# Enemy Variety - Implementation Summary

## Files Created
- `scripts/entities/enemies/EnemyScout.gd` - Fast kiter
- `scripts/entities/enemies/EnemyTank.gd` - Armored charger
- `scripts/entities/enemies/EnemySniper.gd` - Long-range with laser
- `scripts/entities/enemies/EnemySwarm.gd` - Weak rusher

## Files Modified
- `scripts/server/ServerMain.gd`
  - Added `_spawn_enemy(pos, enemy_type)` with type selection
  - Added `_weighted_random()` helper
  - Updated `_respawn_enemy()` to preserve type
  - Updated `_on_peer_connected()` to send enemy types
  - Added type-specific damage in bullet spawning
  
- `scripts/net/Net.gd`
  - Updated `spawn_entity` RPC to handle enemy_type parameter
  - Spawns correct enemy class based on type

- `CLAUDE.md`
  - Documented enemy types and stats
  - Added known issues section

## Enemy Types

### Scout (25% spawn rate)
- **Speed**: 140 (1.75x base)
- **Health**: 80 (0.5x base)
- **Damage**: 15 (0.6x base)
- **Behavior**: Kites at 300-500 range, strafes
- **Color**: Orange

### Tank (15% spawn rate)
- **Speed**: 50 (0.625x base)
- **Health**: 400 (2.67x base)
- **Armor**: 60% damage reduction
- **Damage**: 35 (1.4x base)
- **Behavior**: Charges every 8s for 2s at 200 speed
- **Color**: Dark gray
- **Size**: 1.5x normal

### Sniper (15% spawn rate)
- **Speed**: 60 (0.75x base)
- **Health**: 100 (0.67x base)
- **Damage**: 60 (2.4x base)
- **Range**: 700 (vs 400 normal)
- **Behavior**: Stays stationary, 1.5s laser warning before shot
- **Color**: Purple
- **Visual**: Red laser line when aiming

### Swarm (25% spawn rate)
- **Speed**: 120 (1.5x base)
- **Health**: 50 (0.33x base)
- **Damage**: 10 (0.4x base)
- **Behavior**: Rush directly, rapid fire at <150 range
- **Color**: Cyan
- **Size**: 0.7x normal

### Normal (20% spawn rate)
- **Speed**: 80 (baseline)
- **Health**: 150 (baseline)
- **Damage**: 25 (baseline)
- **Behavior**: Standard chase/wander/separate
- **Color**: Dark red

## Spawn Weights
```gdscript
types = ["scout", "tank", "sniper", "swarm", "normal"]
weights = [0.25, 0.15, 0.15, 0.25, 0.2]
```

## Network Sync
- Enemy type sent in spawn_entity RPC via `extra.enemy_type`
- Type preserved across respawns
- Clients spawn correct enemy class
- Sniper aiming state synced via get/apply_replicated_state

## Testing Checklist
- [ ] All enemy types spawn correctly
- [ ] Colors are distinct
- [ ] Scout kiting behavior works
- [ ] Tank charges and armor works
- [ ] Sniper laser appears when aiming
- [ ] Swarm rushes aggressively
- [ ] Different damage values apply
- [ ] Enemies respawn as same type
- [ ] Late-joining clients see correct types
- [ ] Combat feels balanced

## Balance Notes
- Scout/Swarm are most common (50% combined) for action
- Tank/Sniper are rare (30% combined) for variety
- Normal enemies fill gaps (20%)
- Damage ranges from 10 (Swarm) to 60 (Sniper)
- HP ranges from 50 (Swarm) to 400 (Tank)

## Known Issues
1. Sniper laser needs valid player target - fixed by finding nearest player
2. Enemy colors may need better distinction in actual game
3. Tank charge might feel too strong/weak - needs playtesting
4. Sniper 1.5s aim time might be too long/short - needs playtesting
