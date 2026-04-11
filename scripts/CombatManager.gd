# CombatManager.gd
# Xử lý toàn bộ combat: declare attack, block, resolve damage
# Hỗ trợ keyword: Quick Strike, Overwhelm, Shield, Guard

extends Node

# Giải quyết 1 cặp đánh nhau (attacker vs blocker)
# Trả về {attacker_alive, blocker_alive, overflow}
func resolve_one_combat(attacker: UnitInstance, blocker: UnitInstance) -> Dictionary:
	var overflow = 0
	var atk_dmg = attacker.get_effective_attack()
	var blk_dmg = blocker.get_effective_attack()
	var blk_hp_before = blocker.health   # lưu HP trước combat để tính overflow
	
	var atk_qs = (attacker.keyword == CardData.Keyword.QUICK_STRIKE)
	var blk_qs = (blocker.keyword == CardData.Keyword.QUICK_STRIKE)
	
	if atk_qs and not blk_qs:
		# Attacker có Quick Strike → đánh trước
		blocker.take_damage(atk_dmg)
		if not blocker.is_alive():
			# Blocker chết ngay → attacker không nhận phản đòn
			if attacker.keyword == CardData.Keyword.OVERWHELM:
				overflow = max(0, atk_dmg - blk_hp_before)
			return {"attacker_alive": true, "blocker_alive": false, "overflow": overflow}
		# Blocker sống sót → phản đòn
		attacker.take_damage(blk_dmg)
		
	elif blk_qs and not atk_qs:
		# Blocker có Quick Strike → đánh trước
		attacker.take_damage(blk_dmg)
		if not attacker.is_alive():
			# Attacker chết từ Quick Strike blocker → không có overflow
			return {"attacker_alive": false, "blocker_alive": true, "overflow": 0}
		# Attacker sống sót → phản đòn
		blocker.take_damage(atk_dmg)
		if attacker.keyword == CardData.Keyword.OVERWHELM and not blocker.is_alive():
			overflow = max(0, atk_dmg - blk_hp_before)
			
	else:
		# Cả hai cùng đánh (không ai / cả hai có Quick Strike)
		attacker.take_damage(blk_dmg)
		blocker.take_damage(atk_dmg)
		if attacker.keyword == CardData.Keyword.OVERWHELM and not blocker.is_alive():
			overflow = max(0, atk_dmg - blk_hp_before)
	
	return {
		"attacker_alive": attacker.is_alive(),
		"blocker_alive": blocker.is_alive(),
		"overflow": overflow
	}

# Giải quyết toàn bộ combat sau khi blockers đã được assign
# state: GameState
# attacker_pid: player đang tấn công
# attackers: [uid] - các unit tấn công
# block_assignments: {attacker_uid: blocker_uid} - có thể empty (= không block)
# Trả về log string
func resolve_combat(state: GameState, attacker_pid: int, attackers: Array, block_assignments: Dictionary) -> String:
	var log_str = ""
	var defender_pid = GameState.opponent(attacker_pid)
	
	for atk_uid in attackers:
		var attacker = state.get_unit_by_uid(atk_uid)
		if attacker == null:
			continue
		
		# Skybreaker effect: +1 atk khi attack
		if attacker.card_id == 10:
			attacker.temp_atk_bonus += 1
		
		# Kael leveled up effect: +1 atk khi attack
		if attacker.is_champion and attacker.leveled_up and attacker.card_id in [17, 18]:
			attacker.temp_atk_bonus += 1
		
		# Đếm attack cho Kael champion level up
		state.get_player(attacker_pid).attack_declares += 1
		
		if block_assignments.has(atk_uid):
			var blk_uid = block_assignments[atk_uid]
			var blocker = state.get_unit_by_uid(blk_uid)
			if blocker != null and blocker.is_alive():
				var result = resolve_one_combat(attacker, blocker)
				
				# Log kết quả
				var atk_status = "✖" if not result["attacker_alive"] else "✓"
				var blk_status = "✖" if not result["blocker_alive"] else "✓"
				log_str += "%s[%s] vs %s[%s]" % [attacker.unit_name, atk_status, blocker.unit_name, blk_status]
				
				# Overflow vào Nexus (chỉ hiện khi > 0)
				if result["overflow"] > 0:
					state.get_player(defender_pid).nexus_hp -= result["overflow"]
					log_str += " → 💥Overflow %d→Nexus" % result["overflow"]
				log_str += "\n"
				
				state.get_player(defender_pid).total_block_damage += blocker.damage_taken_total
			else:
				# Blocker đã chết rồi → đánh thẳng Nexus
				var dmg = attacker.get_effective_attack()
				state.get_player(defender_pid).nexus_hp -= dmg
				log_str += "%s → Nexus -%d\n" % [attacker.unit_name, dmg]
		else:
			# Không bị block → damage vào Nexus
			var dmg = attacker.get_effective_attack()
			state.get_player(defender_pid).nexus_hp -= dmg
			log_str += "%s unblocked → Nexus -%d\n" % [attacker.unit_name, dmg]
	
	# Dọn unit chết
	state.remove_dead_units()
	
	# Kiểm tra champion level up
	check_champion_levelups(state)
	
	# Kiểm tra win
	state.check_win_condition()
	
	return log_str

# Kiểm tra champion level up sau mỗi combat
func check_champion_levelups(state: GameState):
	for pid in range(2):
		var p = state.get_player(pid)
		for u in p.board:
			if not u.is_champion or u.leveled_up:
				continue
			# Kael: level up sau 2 lần declare attack
			if u.card_id in [17, 18]:
				if p.attack_declares >= 2:
					level_up_unit(u, state, pid)
			# Lyra: level up sau khi nhận/block 5 damage
			elif u.card_id in [19, 20]:
				if p.total_block_damage >= 5:
					level_up_unit(u, state, pid)

func level_up_unit(u: UnitInstance, state: GameState, pid: int):
	u.leveled_up = true
	var card = CardData.get_card(u.card_id)
	u.attack = card.get("level_up_atk", u.attack)
	var new_hp = card.get("level_up_hp", u.health)
	var hp_increase = new_hp - u.max_health
	u.max_health = new_hp
	u.health = min(u.health + hp_increase, new_hp)
	
	# Lyra level up effect: cho Guard ally +1 HP
	if u.card_id in [19, 20]:
		for ally in state.get_player(pid).board:
			if ally.uid != u.uid and ally.keyword == CardData.Keyword.GUARD:
				ally.health += 1
				ally.max_health += 1

# Áp dụng spell effect
# Trả về log string
func apply_spell(state: GameState, caster_pid: int, card: Dictionary, target_uid: int) -> String:
	var log_str = ""
	var defender_pid = GameState.opponent(caster_pid)
	var effect = card.get("effect", "none")
	var val = card.get("spell_value", 0)
	
	match effect:
		"damage_unit_or_nexus":
			if target_uid == -1:
				# Damage Nexus địch
				state.get_player(defender_pid).nexus_hp -= val
				log_str = "%s → Nexus địch -%d\n" % [card["name"], val]
			else:
				var target = state.get_unit_by_uid(target_uid)
				if target:
					target.take_damage(val)
					log_str = "%s → %s -%d\n" % [card["name"], target.unit_name, val]
					state.remove_dead_units()
		
		"buff_ally_atk_2_this_round":
			var target = state.get_unit_by_uid(target_uid)
			if target and target.owner_id == caster_pid:
				target.temp_atk_bonus += val
				log_str = "%s → +%d ATK tạm\n" % [target.unit_name, val]
		
		"give_shield_to_ally":
			var target = state.get_unit_by_uid(target_uid)
			if target and target.owner_id == caster_pid:
				target.has_shield = true
				log_str = "%s → Shield!\n" % target.unit_name
		
		"damage_damaged_enemy_unit":
			var target = state.get_unit_by_uid(target_uid)
			if target and target.owner_id != caster_pid and target.health < target.max_health:
				target.take_damage(val)
				log_str = "%s → Tactical -%d\n" % [target.unit_name, val]
				state.remove_dead_units()
		
		"buff_ally_1_atk_2_hp_permanent":
			var target = state.get_unit_by_uid(target_uid)
			if target and target.owner_id == caster_pid:
				target.attack += 1
				target.health += 2
				target.max_health += 2
				log_str = "%s → +1/+2 perm\n" % target.unit_name
		
		"heal_own_nexus_or_damage_enemy_nexus":
			if target_uid == 0:  # heal own
				state.get_player(caster_pid).nexus_hp = min(
					state.get_player(caster_pid).nexus_hp + val, 20)
				log_str = "Nexus Surge → heal %d\n" % val
			else:  # damage enemy nexus
				state.get_player(defender_pid).nexus_hp -= val
				log_str = "Nexus Surge → damage %d\n" % val
	
	state.check_win_condition()
	return log_str

# Áp dụng summon effect của unit
func apply_summon_effect(state: GameState, unit: UnitInstance):
	var card = CardData.get_card(unit.card_id)
	var effect = card.get("effect", "none")
	var owner_pid = unit.owner_id
	var enemy_pid = GameState.opponent(owner_pid)
	
	match effect:
		"on_summon_damage_1_enemy":
			# Arc Archer: gây 1 damage lên enemy unit ngẫu nhiên
			var enemies = state.get_board(enemy_pid)
			if not enemies.is_empty():
				var target = enemies[randi() % enemies.size()]
				target.take_damage(1)
				state.remove_dead_units()
		
		"on_summon_heal_nexus_2":
			# Battle Priest: hồi 2 HP cho Nexus đồng minh
			state.get_player(owner_pid).nexus_hp = min(
				state.get_player(owner_pid).nexus_hp + 2, 20)
