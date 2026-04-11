# AIPlayer.gd
# AI cho Nexus Clash - hỗ trợ 2 mode: Easy (random) và Normal (heuristic)

extends Node

const AI_PID = 1
const PLAYER_PID = 0

enum Difficulty { EASY, NORMAL, HARD }
var difficulty: int = Difficulty.NORMAL

const SEARCH_DEPTH = 2
const MAX_ACTION_CANDIDATES = 8
const MAX_BLOCK_CANDIDATES = 6
# ============================================================
#   MAIN ENTRY: Quyết định action trong turn
# ============================================================
func decide_action(state: GameState) -> Dictionary:
	print("AI difficulty = ", difficulty)
	match difficulty:
		Difficulty.EASY:
			return _easy_action(state)
		Difficulty.NORMAL:
			return _normal_action(state)
		Difficulty.HARD:
			return _hard_action(state)
	return {"type": "pass"}

# ============================================================
#   EASY MODE: chọn action ngẫu nhiên trong danh sách hợp lệ
# ============================================================
func _easy_action(state: GameState) -> Dictionary:
	var valid = _get_valid_actions(state)
	if valid.is_empty():
		return {"type": "pass"}
	# Ưu tiên nhỏ: 30% pass, 70% chọn random
	if randf() < 0.3:
		return {"type": "pass"}
	return valid[randi() % valid.size()]

# ============================================================
#   NORMAL MODE: heuristic rule-based
# ============================================================
func _normal_action(state: GameState) -> Dictionary:
	var p = state.get_player(AI_PID)
	var _opp = state.get_player(PLAYER_PID)  # unused but kept for clarity
	
	# --- Ưu tiên 1: Nếu có lethal (có thể giết Nexus ngay) ---
	var lethal = _find_lethal_action(state)
	if lethal != null:
		return lethal
	
	# --- Ưu tiên 2: Dùng spell nếu có trade lời ---
	var spell_trade = _find_spell_trade(state)
	if spell_trade != null:
		return spell_trade
	
	# --- Ưu tiên 3: Summon unit nếu bàn yếu ---
	var my_power = _board_power(state, AI_PID)
	var opp_power = _board_power(state, PLAYER_PID)
	if my_power < opp_power and p.board.size() < GameState.MAX_BOARD_SIZE:
		var summon = _find_best_summon(state)
		if summon != null:
			return summon
	
	# --- Ưu tiên 4: Summon unit nếu đang có lợi thế ---
	if my_power >= opp_power and p.board.size() < GameState.MAX_BOARD_SIZE:
		var summon = _find_best_summon(state)
		if summon != null and randf() < 0.7:
			return summon
	
	# --- Ưu tiên 5: Declare attack nếu có attack token ---
	if state.attack_token_owner == AI_PID:
		var ready_units = _get_ready_units(state, AI_PID)
		if not ready_units.is_empty():
			var attackers = _choose_attackers_normal(state, ready_units)
			if not attackers.is_empty():
				return {"type": "declare_attack", "attackers": attackers}
	
	# --- Mặc định: Pass ---
	return {"type": "pass"}

# ============================================================
#   ATTACK DECISION: chọn unit nào attack
# ============================================================
func decide_attackers(state: GameState) -> Array:
	if difficulty == Difficulty.EASY:
		# Easy: attack random
		var ready_uids = _get_ready_units(state, AI_PID)
		if ready_uids.is_empty():
			return []
		# Chọn ngẫu nhiên 1 đến tất cả ready units
		var count = 1 + randi() % ready_uids.size()
		ready_uids.shuffle()
		return ready_uids.slice(0, count)
	else:
		var ready_uids2 = _get_ready_units(state, AI_PID)
		return _choose_attackers_normal(state, ready_uids2)

# ============================================================
#   BLOCK DECISION: chọn unit nào block
# ============================================================
func decide_blockers(state: GameState, attackers: Array) -> Dictionary:
	match difficulty:
		Difficulty.EASY:
			return _easy_block(state, attackers)
		Difficulty.NORMAL:
			return _normal_block(state, attackers)
		Difficulty.HARD:
			return _hard_block(state, attackers)
	return {}

func _easy_block(state: GameState, attackers: Array) -> Dictionary:
	var assignments = {}
	var my_units = _get_ready_non_exhausted(state, AI_PID)
	my_units.shuffle()
	var available = my_units.duplicate()
	
	for atk_uid in attackers:
		var attacker = state.get_unit_by_uid(atk_uid)
		if attacker == null or available.is_empty():
			break
		# 50% block ngẫu nhiên
		if randf() < 0.5:
			var blocker_uid = available.pop_front()
			assignments[atk_uid] = blocker_uid
	return assignments

func _normal_block(state: GameState, attackers: Array) -> Dictionary:
	var assignments = {}
	var my_units_uid = _get_ready_non_exhausted(state, AI_PID)
	var available_uid = my_units_uid.duplicate()
	var opp_nexus = state.get_player(AI_PID).nexus_hp
	
	# Tính tổng damage nếu không block gì
	var total_unblocked_dmg = 0
	for atk_uid in attackers:
		var u = state.get_unit_by_uid(atk_uid)
		if u: total_unblocked_dmg += u.get_effective_attack()
	
	# Ưu tiên 1: Ngăn lethal
	if total_unblocked_dmg >= opp_nexus:
		# Phải block để cứu nexus
		for atk_uid in attackers:
			if available_uid.is_empty():
				break
			var attacker = state.get_unit_by_uid(atk_uid)
			if attacker == null: continue
			# Tìm blocker tốt nhất (có thể giết attacker mà không chết)
			var best = _find_best_blocker(attacker, available_uid, state)
			if best != -1:
				assignments[atk_uid] = best
				available_uid.erase(best)
	else:
		# Ưu tiên 2: Trade có lời (giết attacker mà blocker sống sót)
		for atk_uid in attackers:
			if available_uid.is_empty():
				break
			var attacker = state.get_unit_by_uid(atk_uid)
			if attacker == null: continue
			var best = _find_favorable_trade(attacker, available_uid, state)
			if best != -1:
				assignments[atk_uid] = best
				available_uid.erase(best)
	
	# Ưu tiên 3: Bảo vệ champion (không để champion chết vô ích)
	# (Đã được xử lý qua heuristic trên)
	
	return assignments

# ============================================================
#   SPELL EVALUATION (Normal mode)
# ============================================================
func _find_lethal_action(state: GameState) -> Variant:
	var p = state.get_player(AI_PID)
	var opp_nexus = state.get_player(PLAYER_PID).nexus_hp
	
	# Kiểm tra damage spell có thể giết nexus không
	for card_id in p.hand:
		var card = CardData.get_card(card_id)
		if card.get("type") != CardData.CardType.SPELL:
			continue
		var effect = card.get("effect", "")
		var val = card.get("spell_value", 0)
		var cost = card.get("cost", 99)
		if p.mana < cost:
			continue
		if effect in ["damage_unit_or_nexus", "heal_own_nexus_or_damage_enemy_nexus"]:
			if val >= opp_nexus:
				var target_id = -1 if effect == "damage_unit_or_nexus" else 1
				return {"type": "cast_spell", "card_id": card_id, "target_uid": target_id}
	return null

func _find_spell_trade(state: GameState) -> Variant:
	var p = state.get_player(AI_PID)
	var opp_board = state.get_board(PLAYER_PID)
	
	for card_id in p.hand:
		var card = CardData.get_card(card_id)
		if card.get("type") != CardData.CardType.SPELL:
			continue
		var cost = card.get("cost", 99)
		if p.mana < cost:
			continue
		var effect = card.get("effect", "")
		var val = card.get("spell_value", 0)
		
		if effect == "damage_unit_or_nexus" or effect == "damage_damaged_enemy_unit":
			# Tìm enemy unit có thể kill
			for enemy in opp_board:
				if enemy.health <= val:
					if effect == "damage_damaged_enemy_unit" and enemy.health == enemy.max_health:
						continue
					return {"type": "cast_spell", "card_id": card_id, "target_uid": enemy.uid}
	return null

# ============================================================
#   HELPER FUNCTIONS
# ============================================================
func _get_valid_actions(state: GameState) -> Array:
	var actions = []
	var p = state.get_player(AI_PID)
	
	# Summon actions
	for card_id in p.hand:
		var card = CardData.get_card(card_id)
		if card.get("type") in [CardData.CardType.UNIT, CardData.CardType.CHAMPION]:
			if p.mana >= card.get("cost", 99) and not state.board_full(AI_PID):
				actions.append({"type": "summon", "card_id": card_id})
		elif card.get("type") == CardData.CardType.SPELL:
			if p.mana >= card.get("cost", 99):
				# Spell target: enemy nexus hoặc enemy unit đầu tiên
				var opp_board = state.get_board(PLAYER_PID)
				var target = -1
				if not opp_board.is_empty():
					target = opp_board[0].uid
				actions.append({"type": "cast_spell", "card_id": card_id, "target_uid": target})
	
	# Attack action
	if state.attack_token_owner == AI_PID:
		var all_ready = _get_ready_units(state, AI_PID)
		if not all_ready.is_empty():
			actions.append({"type": "declare_attack", "attackers": all_ready})
	
	return actions

func _get_ready_units(state: GameState, pid: int) -> Array:
	var uids = []
	for u in state.get_board(pid):
		if not u.exhausted:
			uids.append(u.uid)
	return uids

func _get_ready_non_exhausted(state: GameState, pid: int) -> Array:
	# Trả về uid tất cả unit (cả exhausted, dùng cho blocking)
	var uids = []
	for u in state.get_board(pid):
		uids.append(u.uid)
	return uids

func _board_power(state: GameState, pid: int) -> int:
	var total = 0
	for u in state.get_board(pid):
		total += u.get_effective_attack() + u.health
	return total

func _find_best_summon(state: GameState) -> Variant:
	var p = state.get_player(AI_PID)
	var best_card_id = -1
	var best_cost = -1
	for card_id in p.hand:
		var card = CardData.get_card(card_id)
		var t = card.get("type", -1)
		if t not in [CardData.CardType.UNIT, CardData.CardType.CHAMPION]:
			continue
		var cost = card.get("cost", 99)
		if cost <= p.mana and cost > best_cost:
			best_cost = cost
			best_card_id = card_id
	if best_card_id != -1:
		return {"type": "summon", "card_id": best_card_id}
	return null

func _choose_attackers_normal(state: GameState, ready_uids: Array) -> Array:
	# Normal: chọn tất cả unit có lợi thế (attack >= enemy health)
	var attackers = []
	var opp_board = state.get_board(PLAYER_PID)
	
	for uid in ready_uids:
		var u = state.get_unit_by_uid(uid)
		if u == null: continue
		# Luôn attack nếu không có đối thủ
		if opp_board.is_empty():
			attackers.append(uid)
			continue
		# Attack nếu có thể kill enemy hoặc là champion
		var can_kill_someone = false
		for enemy in opp_board:
			if u.get_effective_attack() >= enemy.health:
				can_kill_someone = true
				break
		if can_kill_someone or u.is_champion:
			attackers.append(uid)
	
	# Nếu không có ai đáng tấn công, vẫn attack 1 unit để gây áp lực
	if attackers.is_empty() and not ready_uids.is_empty():
		attackers.append(ready_uids[0])
	
	return attackers

func _find_best_blocker(attacker: UnitInstance, available_uid: Array, state: GameState) -> int:
	# Tìm blocker có thể sống sót sau khi block
	for uid in available_uid:
		var blocker = state.get_unit_by_uid(uid)
		if blocker == null: continue
		if blocker.health > attacker.get_effective_attack():
			return uid
	# Không tìm được → chọn unit mạnh nhất
	if not available_uid.is_empty():
		return available_uid[0]
	return -1

func _find_favorable_trade(attacker: UnitInstance, available_uid: Array, state: GameState) -> int:
	for uid in available_uid:
		var blocker = state.get_unit_by_uid(uid)
		if blocker == null: continue
		# Trade lời: giết attacker mà blocker sống
		if blocker.get_effective_attack() >= attacker.health and blocker.health > attacker.get_effective_attack():
			return uid
		# Cân bằng: cả hai chết nhưng attacker mạnh hơn
		if blocker.get_effective_attack() >= attacker.health:
			return uid
	return -1

# ============================================================
#   Heuristic score cho 1 state (dùng cho lookahead nếu cần)
# ============================================================
func evaluate_state(state: GameState) -> float:
	var ai_p = state.get_player(AI_PID)
	var pl_p = state.get_player(PLAYER_PID)
	
	var ai_board_atk = 0
	var ai_board_hp = 0
	var leveled_ai = 0
	var guard_ai = 0
	for u in ai_p.board:
		ai_board_atk += u.get_effective_attack()
		ai_board_hp += u.health
		if u.leveled_up: leveled_ai += 1
		if u.keyword == CardData.Keyword.GUARD: guard_ai += 1
	
	var pl_board_atk = 0
	var pl_board_hp = 0
	var leveled_pl = 0
	var guard_pl = 0
	for u in pl_p.board:
		pl_board_atk += u.get_effective_attack()
		pl_board_hp += u.health
		if u.leveled_up: leveled_pl += 1
		if u.keyword == CardData.Keyword.GUARD: guard_pl += 1
	
	var score = 0.0
	score += (ai_p.nexus_hp - pl_p.nexus_hp) * 50.0
	score += (ai_board_atk - pl_board_atk) * 8.0
	score += (ai_board_hp - pl_board_hp) * 6.0
	score += (ai_p.hand.size() - pl_p.hand.size()) * 4.0
	score += (ai_p.mana + ai_p.spell_mana) * 2.0
	score += (leveled_ai - leveled_pl) * 20.0
	score += (guard_ai - guard_pl) * 5.0
	return score
func _hard_action(state: GameState) -> Dictionary:
	var result = _minimax_root(state, SEARCH_DEPTH, AI_PID)
	return result.get("action", {"type": "pass"})

func _hard_block(state: GameState, attackers: Array) -> Dictionary:
	var candidates = _generate_block_maps_for_pid(state, AI_PID, attackers)
	if candidates.is_empty():
		return {}

	var best_map = {}
	var best_score = -INF

	for block_map in candidates:
		var sim = state.clone_state()
		CombatManager.resolve_combat(sim, PLAYER_PID, attackers, block_map)
		var score = evaluate_state(sim)
		if score > best_score:
			best_score = score
			best_map = block_map

	return best_map

func _minimax_root(state: GameState, depth: int, acting_pid: int) -> Dictionary:
	var actions = _get_valid_actions_for_pid(state, acting_pid)
	if actions.is_empty():
		return {"action": {"type": "pass"}, "score": evaluate_state(state)}

	var best_action = {"type": "pass"}
	var best_score = -INF

	for action in actions:
		var sim = _simulate_action(state, action, acting_pid)
		var score = _minimax(sim, depth - 1, false, GameState.opponent(acting_pid), -INF, INF)
		if score > best_score:
			best_score = score
			best_action = action

	return {"action": best_action, "score": best_score}

func _minimax(state: GameState, depth: int, maximizing: bool, acting_pid: int, alpha: float, beta: float) -> float:
	if depth <= 0 or state.phase == GameState.Phase.GAME_OVER or state.winner != -1:
		return evaluate_state(state)

	var actions = _get_valid_actions_for_pid(state, acting_pid)
	if actions.is_empty():
		return evaluate_state(state)

	if maximizing:
		var value = -INF
		for action in actions:
			var sim = _simulate_action(state, action, acting_pid)
			value = max(value, _minimax(sim, depth - 1, false, GameState.opponent(acting_pid), alpha, beta))
			alpha = max(alpha, value)
			if beta <= alpha:
				break
		return value
	else:
		var value = INF
		for action in actions:
			var sim = _simulate_action(state, action, acting_pid)
			value = min(value, _minimax(sim, depth - 1, true, GameState.opponent(acting_pid), alpha, beta))
			beta = min(beta, value)
			if beta <= alpha:
				break
		return value

func _get_valid_actions_for_pid(state: GameState, pid: int) -> Array:
	var actions = []
	var p = state.get_player(pid)
	var opp_pid = GameState.opponent(pid)

	for card_id in p.hand:
		var card = CardData.get_card(card_id)
		var cost = card.get("cost", 99)

		if card.get("type") in [CardData.CardType.UNIT, CardData.CardType.CHAMPION]:
			if p.mana >= cost and not state.board_full(pid):
				actions.append({"type": "summon", "card_id": card_id})

		elif card.get("type") == CardData.CardType.SPELL:
			if not state.can_afford_with_spell_mana(pid, cost):
				continue

			var effect = card.get("effect", "")
			match effect:
				"damage_unit_or_nexus":
					actions.append({"type": "cast_spell", "card_id": card_id, "target_uid": -1})
					for enemy in state.get_board(opp_pid):
						actions.append({"type": "cast_spell", "card_id": card_id, "target_uid": enemy.uid})

				"buff_ally_atk_2_this_round", "give_shield_to_ally", "buff_ally_1_atk_2_hp_permanent":
					for ally in state.get_board(pid):
						actions.append({"type": "cast_spell", "card_id": card_id, "target_uid": ally.uid})

				"damage_damaged_enemy_unit":
					for enemy in state.get_board(opp_pid):
						if enemy.health < enemy.max_health:
							actions.append({"type": "cast_spell", "card_id": card_id, "target_uid": enemy.uid})

				"heal_own_nexus_or_damage_enemy_nexus":
					actions.append({"type": "cast_spell", "card_id": card_id, "target_uid": 0})
					actions.append({"type": "cast_spell", "card_id": card_id, "target_uid": 1})

	if state.attack_token_owner == pid:
		actions.append_array(_generate_attack_actions_for_pid(state, pid))

	actions.append({"type": "pass"})

	actions.sort_custom(func(a, b): return _score_action_for_ordering(state, a, pid) > _score_action_for_ordering(state, b, pid))
	if actions.size() > MAX_ACTION_CANDIDATES:
		actions = actions.slice(0, MAX_ACTION_CANDIDATES)

	return actions

func _generate_attack_actions_for_pid(state: GameState, pid: int) -> Array:
	var ready = []
	for u in state.get_board(pid):
		if not u.exhausted:
			ready.append(u.uid)

	var actions = []
	if ready.is_empty():
		return actions

	actions.append({"type": "declare_attack", "attackers": ready})

	for uid in ready:
		actions.append({"type": "declare_attack", "attackers": [uid]})

	if ready.size() >= 2:
		actions.append({"type": "declare_attack", "attackers": [ready[0], ready[1]]})

	return actions

func _score_action_for_ordering(state: GameState, action: Dictionary, pid: int) -> float:
	match action.get("type", ""):
		"summon":
			var card = CardData.get_card(action["card_id"])
			var score = card.get("attack", 0) * 2 + card.get("health", 0)
			if card.get("keyword", 0) == CardData.Keyword.GUARD:
				score += 3
			if card.get("type") == CardData.CardType.CHAMPION:
				score += 4
			return score

		"cast_spell":
			var card = CardData.get_card(action["card_id"])
			var effect = card.get("effect", "")
			if effect == "damage_unit_or_nexus" and action.get("target_uid", 0) == -1:
				return 8
			if effect == "damage_damaged_enemy_unit":
				return 7
			if effect == "buff_ally_1_atk_2_hp_permanent":
				return 6
			if effect == "give_shield_to_ally":
				return 5
			return 4

		"declare_attack":
			return 9 + action.get("attackers", []).size()

		"pass":
			return 0

	return 0

func _simulate_action(state: GameState, action: Dictionary, pid: int) -> GameState:
	var sim = state.clone_state()
	var p = sim.get_player(pid)
	var opp_pid = GameState.opponent(pid)

	match action.get("type", "pass"):
		"summon":
			var card_id = action["card_id"]
			var idx = p.hand.find(card_id)
			if idx != -1:
				var card = CardData.get_card(card_id)
				sim.spend_mana(pid, card.get("cost", 0))
				p.hand.remove_at(idx)
				var unit = sim.summon_unit(pid, card)
				_apply_summon_effect_sim(sim, unit)
			sim.consecutive_passes = 0
			sim.priority_player = opp_pid

		"cast_spell":
			var card_id = action["card_id"]
			var target_uid = action.get("target_uid", -1)
			var idx = p.hand.find(card_id)
			if idx != -1:
				var card = CardData.get_card(card_id)
				sim.spend_mana(pid, card.get("cost", 0))
				p.hand.remove_at(idx)
				CombatManager.apply_spell(sim, pid, card, target_uid)
			sim.consecutive_passes = 0
			sim.priority_player = opp_pid

		"declare_attack":
			var attackers = action.get("attackers", [])
			for uid in attackers:
				var u = sim.get_unit_by_uid(uid)
				if u:
					u.exhausted = true
			var defender_blocks = _generate_best_block_for_sim(sim, opp_pid, attackers)
			CombatManager.resolve_combat(sim, pid, attackers, defender_blocks)
			sim.consecutive_passes = 0
			sim.priority_player = pid

		"pass":
			sim.consecutive_passes += 1
			if sim.consecutive_passes >= 2:
				sim.begin_sim_round()
				sim.priority_player = sim.attack_token_owner
				sim.consecutive_passes = 0
			else:
				sim.priority_player = opp_pid

	return sim

func _generate_block_maps_for_pid(state: GameState, defender_pid: int, attackers: Array) -> Array:
	var result = []
	var defenders = []
	for u in state.get_board(defender_pid):
		defenders.append(u.uid)

	result.append({})

	for atk_uid in attackers:
		for blk_uid in defenders:
			result.append({atk_uid: blk_uid})

	if attackers.size() >= 2 and defenders.size() >= 2:
		result.append({
			attackers[0]: defenders[0],
			attackers[1]: defenders[1]
		})

	if result.size() > MAX_BLOCK_CANDIDATES:
		result = result.slice(0, MAX_BLOCK_CANDIDATES)

	return result

func _generate_best_block_for_sim(state: GameState, defender_pid: int, attackers: Array) -> Dictionary:
	var maps = _generate_block_maps_for_pid(state, defender_pid, attackers)
	if maps.is_empty():
		return {}

	var best_map = {}
	var best_score = INF

	for m in maps:
		var sim = state.clone_state()
		var attacker_pid = GameState.opponent(defender_pid)
		CombatManager.resolve_combat(sim, attacker_pid, attackers, m)
		var score = evaluate_state(sim)
		if defender_pid == PLAYER_PID:
			if score < best_score:
				best_score = score
				best_map = m
		else:
			if -score < best_score:
				best_score = -score
				best_map = m

	return best_map

func _apply_summon_effect_sim(state: GameState, unit: UnitInstance):
	var card = CardData.get_card(unit.card_id)
	var effect = card.get("effect", "none")
	var owner_pid = unit.owner_id
	var enemy_pid = GameState.opponent(owner_pid)

	match effect:
		"on_summon_damage_1_enemy":
			var enemies = state.get_board(enemy_pid)
			if not enemies.is_empty():
				var best_target = enemies[0]
				for e in enemies:
					if e.health < best_target.health:
						best_target = e
				best_target.take_damage(1)
				state.remove_dead_units()

		"on_summon_heal_nexus_2":
			state.get_player(owner_pid).nexus_hp = min(state.get_player(owner_pid).nexus_hp + 2, 20)
