func _spawn_enemy(pos: Vector2) -> void:
	var enemy = Enemy.new()
	enemy.net_id = Replication.generate_id()
	enemy.authority = 1
	enemy.global_position = pos
	enemy.died.connect(func(_id): _respawn_enemy(enemy))
	enemy.wants_to_shoot.connect(func(dir): _spawn_bullet(enemy.global_position, dir, 0))
	_world.add_child(enemy)
	_enemies.append(enemy)
	
	# Tell clients
	Net.spawn_entity.rpc({
		"type": "enemy",
		"net_id": enemy.net_id,
		"pos": pos,
		"extra": {}
	})
