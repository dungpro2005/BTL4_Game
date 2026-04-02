# AIPlayer.gd
# AI cho Nexus Clash - hỗ trợ 2 mode: Easy (random) và Normal (heuristic)

extends Node

const AI_PID = 1
const PLAYER_PID = 0

enum Difficulty { EASY, NORMAL }
var difficulty: int = Difficulty.NORMAL

# ============================================================
#   MAIN ENTRY: Quyết định action trong turn
# ============================================================
func decide_action(state: GameState) -> Dictionary:
	if difficulty == Difficulty.EASY:
		return _easy_action(state)
	else:
		return _normal_action(state)

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
	var opp = state.get_player(PLAYER_PID)
	
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
		var ready = _get_ready_units(state, AI_PID)
		if ready.is_empty():
			return []
		# Chọn ngẫu nhiên 1 đến tất cả ready units
		var count = 1 + randi() % ready.size()
		ready.shuffle()
		return ready.slice(0, count)
	else:
		var ready = _get_ready_units(state, AI_PID)
		return _choose_attackers_normal(state, ready)

# ============================================================
#   BLOCK DECISION: chọn unit nào block
# ============================================================
func decide_blockers(state: GameState, attackers: Array) -> Dictionary:
	var assignments = {}
	if difficulty == Difficulty.EASY:
		return _easy_block(state, attackers)
	else:
		return _normal_block(state, attackers)

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
func _find_lethal_action(state: GameState) -> Dictionary:
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

func _find_spell_trade(state: GameState) -> Dictionary:
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
		var ready = _get_ready_units(state, AI_PID)
		if not ready.is_empty():
			actions.append({"type": "declare_attack", "attackers": ready})
	
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

func _find_best_summon(state: GameState) -> Dictionary:
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
