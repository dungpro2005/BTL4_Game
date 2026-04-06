# MCTSState.gd
# Nền tảng cho MCTS: clone GameState và apply action thuần túy (không signal, không await)
# Tất cả hàm đều STATIC và PURE — không có side effect lên state thật

class_name MCTSState

# ============================================================
#   Deep copy toàn bộ game state để MCTS simulate mà không
#   ảnh hưởng đến state thật của game
# ============================================================

# Clone toàn bộ GameState (deep copy)
static func clone_state(src: GameState) -> GameState:
	var dst = GameState.new()

	# Các giá trị primitive
	dst.round_num          = src.round_num
	dst.priority_player    = src.priority_player
	dst.attack_token_owner = src.attack_token_owner
	dst.consecutive_passes = src.consecutive_passes
	dst.uid_counter        = src.uid_counter
	dst.phase              = src.phase
	dst.winner             = src.winner
	dst.in_combat          = src.in_combat

	# Combat arrays/dicts
	dst.attackers          = src.attackers.duplicate()
	dst.block_assignments  = src.block_assignments.duplicate()

	# Clone từng player
	dst.players[0] = clone_player(src.players[0])
	dst.players[1] = clone_player(src.players[1])

	return dst

# Clone một PlayerState (deep copy)
static func clone_player(src) -> GameState.PlayerState:
	var dst              = GameState.PlayerState.new()
	dst.nexus_hp         = src.nexus_hp
	dst.mana             = src.mana
	dst.max_mana         = src.max_mana
	dst.spell_mana       = src.spell_mana
	dst.attack_declares  = src.attack_declares
	dst.total_block_damage = src.total_block_damage

	# Array of int — duplicate() là đủ (shallow ok vì int là value type)
	dst.deck  = src.deck.duplicate()
	dst.hand  = src.hand.duplicate()

	# Array of UnitInstance — phải deep copy từng unit
	dst.board = []
	for u in src.board:
		dst.board.append(clone_unit(u))

	return dst

# Clone một UnitInstance (deep copy)
static func clone_unit(src: UnitInstance) -> UnitInstance:
	var dst               = UnitInstance.new()
	dst.uid               = src.uid
	dst.owner_id          = src.owner_id
	dst.card_id           = src.card_id
	dst.unit_name         = src.unit_name
	dst.attack            = src.attack
	dst.health            = src.health
	dst.max_health        = src.max_health
	dst.keyword           = src.keyword
	dst.exhausted         = src.exhausted
	dst.has_shield        = src.has_shield
	dst.is_champion       = src.is_champion
	dst.leveled_up        = src.leveled_up
	dst.temp_atk_bonus    = src.temp_atk_bonus
	dst.attack_count      = src.attack_count
	dst.damage_taken_total = src.damage_taken_total
	return dst

# ============================================================
#   ACTION SPACE
#   Sinh danh sách action hợp lệ cho một player trong state cho trước.
#   Trả về Array[Dictionary], mỗi dict có ít nhất key "type".
# ============================================================

static func get_valid_actions(state: GameState, pid: int) -> Array:
	var actions: Array = []
	var p = state.get_player(pid)

	# --- Summon unit / champion ---
	if not state.board_full(pid):
		for card_id in p.hand:
			var card = CardData.get_card(card_id)
			var t = card.get("type", -1)
			if t in [CardData.CardType.UNIT, CardData.CardType.CHAMPION]:
				if p.mana >= card.get("cost", 999):
					actions.append({"type": "summon", "card_id": card_id})

	# --- Cast spell ---
	for card_id in p.hand:
		var card = CardData.get_card(card_id)
		if card.get("type", -1) != CardData.CardType.SPELL:
			continue
		var cost = card.get("cost", 999)
		if not state.can_afford_with_spell_mana(pid, cost):
			continue

		var effect = card.get("effect", "")
		var opp_board = state.get_board(GameState.opponent(pid))

		match effect:
			"damage_unit_or_nexus":
				# Target: Nexus địch (uid = -1) hoặc bất kỳ enemy unit nào
				actions.append({"type": "cast_spell", "card_id": card_id, "target_uid": -1})
				for enemy in opp_board:
					actions.append({"type": "cast_spell", "card_id": card_id, "target_uid": enemy.uid})

			"damage_damaged_enemy_unit":
				# Chỉ target enemy unit đã bị damage
				for enemy in opp_board:
					if enemy.health < enemy.max_health:
						actions.append({"type": "cast_spell", "card_id": card_id, "target_uid": enemy.uid})

			"buff_ally_atk_2_this_round", "give_shield_to_ally", "buff_ally_1_atk_2_hp_permanent":
				# Target: bất kỳ ally unit nào trên sân
				for ally in state.get_board(pid):
					actions.append({"type": "cast_spell", "card_id": card_id, "target_uid": ally.uid})

			"heal_own_nexus_or_damage_enemy_nexus":
				# Dual target: heal nexus mình (0) hoặc damage nexus địch (1)
				actions.append({"type": "cast_spell", "card_id": card_id, "target_uid": 0})
				actions.append({"type": "cast_spell", "card_id": card_id, "target_uid": 1})

	# --- Declare attack (chỉ khi có attack token) ---
	if state.attack_token_owner == pid:
		var ready_uids: Array = []
		for u in state.get_board(pid):
			if not u.exhausted:
				ready_uids.append(u.uid)

		if not ready_uids.is_empty():
			# Sinh tất cả subset không rỗng của ready_uids (tối đa 5 unit → 31 subset)
			# Giới hạn thực tế: chỉ sinh subset hợp lý theo heuristic đơn giản
			# (tất cả unit hoặc từng unit đơn lẻ) để tránh explosion
			var subsets = _generate_attack_subsets(ready_uids)
			for subset in subsets:
				actions.append({"type": "declare_attack", "attackers": subset})

	# --- Pass ---
	actions.append({"type": "pass"})

	return actions

# Sinh subset tấn công hợp lý (tránh exponential explosion)
# Chiến lược: tất cả unit, từng unit đơn, và cặp unit mạnh nhất
static func _generate_attack_subsets(ready_uids: Array) -> Array:
	var subsets: Array = []

	# Luôn thêm: tất cả unit
	subsets.append(ready_uids.duplicate())

	# Từng unit đơn lẻ
	for uid in ready_uids:
		subsets.append([uid])

	# Nếu có >= 3 unit: thêm tất cả trừ unit đầu tiên (giữ lại để phòng thủ)
	if ready_uids.size() >= 3:
		var partial = ready_uids.duplicate()
		partial.pop_front()
		subsets.append(partial)

	return subsets

# ============================================================
#   APPLY ACTION (PURE / SYNCHRONOUS)
#   Áp dụng action lên state — không dùng signal, không await,
#   không gọi CombatManager.resolve_combat() (vì nó mutate trực tiếp).
#   Thay vào đó gọi các hàm nội bộ thuần túy bên dưới.
# ============================================================

# Áp dụng action của pid lên state. Trả về true nếu thành công.
static func apply_action(state: GameState, pid: int, action: Dictionary) -> bool:
	match action.get("type", "pass"):
		"summon":
			return _apply_summon(state, pid, action["card_id"])
		"cast_spell":
			return _apply_spell(state, pid, action["card_id"], action.get("target_uid", -1))
		"declare_attack":
			return _apply_declare_attack(state, pid, action.get("attackers", []))
		"pass":
			state.consecutive_passes += 1
			return true
	return false

# --- Summon ---
static func _apply_summon(state: GameState, pid: int, card_id: int) -> bool:
	var p = state.get_player(pid)
	var card = CardData.get_card(card_id)
	var cost = card.get("cost", 999)

	if not state.can_afford(pid, cost):
		return false
	if state.board_full(pid):
		return false

	var idx = p.hand.find(card_id)
	if idx == -1:
		return false

	state.spend_mana(pid, cost)
	p.hand.remove_at(idx)
	var unit = state.summon_unit(pid, card)

	# Summon effects (pure)
	_apply_summon_effect_pure(state, unit)

	state.consecutive_passes = 0
	state.check_win_condition()
	return true

# --- Cast Spell ---
static func _apply_spell(state: GameState, pid: int, card_id: int, target_uid: int) -> bool:
	var p = state.get_player(pid)
	var card = CardData.get_card(card_id)
	var cost = card.get("cost", 999)

	if not state.can_afford_with_spell_mana(pid, cost):
		return false

	var idx = p.hand.find(card_id)
	if idx == -1:
		return false

	state.spend_mana(pid, cost)
	p.hand.remove_at(idx)

	_apply_spell_effect_pure(state, pid, card, target_uid)

	state.consecutive_passes = 0
	state.check_win_condition()
	return true

# --- Declare Attack + Auto Block (simple heuristic cho simulation) ---
static func _apply_declare_attack(state: GameState, attacker_pid: int, attacker_uids: Array) -> bool:
	if state.attack_token_owner != attacker_pid:
		return false
	if attacker_uids.is_empty():
		return false

	# Exhaust attackers
	for uid in attacker_uids:
		var u = state.get_unit_by_uid(uid)
		if u:
			u.exhausted = true

	state.get_player(attacker_pid).attack_declares += 1

	# Defender tự động chọn block (simple heuristic)
	var defender_pid = GameState.opponent(attacker_pid)
	var block_map = auto_block(state, defender_pid, attacker_uids)

	# Resolve combat
	_resolve_combat_pure(state, attacker_pid, attacker_uids, block_map)

	state.consecutive_passes = 0
	state.check_win_condition()
	return true

# ============================================================
#   AUTO BLOCK (heuristic đơn giản cho simulation)
#   Defender ưu tiên: ngăn lethal → trade có lời → không block
# ============================================================

static func auto_block(state: GameState, defender_pid: int, attacker_uids: Array) -> Dictionary:
	var assignments: Dictionary = {}
	var defender_board = state.get_board(defender_pid)
	if defender_board.is_empty():
		return assignments

	var available_blockers: Array = defender_board.duplicate()
	var defender_nexus = state.get_player(defender_pid).nexus_hp

	# Tính tổng damage nếu không block
	var total_unblocked = 0
	for uid in attacker_uids:
		var u = state.get_unit_by_uid(uid)
		if u:
			total_unblocked += u.get_effective_attack()

	var must_block = (total_unblocked >= defender_nexus)

	for atk_uid in attacker_uids:
		if available_blockers.is_empty():
			break
		var attacker = state.get_unit_by_uid(atk_uid)
		if attacker == null:
			continue

		var best_blocker: UnitInstance = null

		if must_block:
			# Ưu tiên blocker có thể sống sót
			for b in available_blockers:
				if b.health > attacker.get_effective_attack():
					best_blocker = b
					break
			# Không tìm được → dùng blocker đầu tiên
			if best_blocker == null:
				best_blocker = available_blockers[0]
		else:
			# Chỉ block nếu trade có lời (giết attacker mà blocker sống)
			for b in available_blockers:
				if (b.get_effective_attack() >= attacker.health and
					b.health > attacker.get_effective_attack()):
					best_blocker = b
					break

		if best_blocker != null:
			assignments[atk_uid] = best_blocker.uid
			available_blockers.erase(best_blocker)

	return assignments

# ============================================================
#   RESOLVE COMBAT (pure — không signal, không await)
# ============================================================

static func _resolve_combat_pure(state: GameState, attacker_pid: int,
		attacker_uids: Array, block_map: Dictionary) -> void:
	var defender_pid = GameState.opponent(attacker_pid)

	for atk_uid in attacker_uids:
		var attacker = state.get_unit_by_uid(atk_uid)
		if attacker == null:
			continue

		# On-attack effects
		if attacker.card_id == 10:  # Skybreaker
			attacker.temp_atk_bonus += 1
		if attacker.is_champion and attacker.leveled_up and attacker.card_id in [17, 18]:
			attacker.temp_atk_bonus += 1

		if block_map.has(atk_uid):
			var blk_uid = block_map[atk_uid]
			var blocker = state.get_unit_by_uid(blk_uid)
			if blocker != null and blocker.is_alive():
				_resolve_one_pure(state, attacker, blocker, defender_pid)
			else:
				# Blocker đã chết → đánh thẳng Nexus
				state.get_player(defender_pid).nexus_hp -= attacker.get_effective_attack()
		else:
			# Unblocked → damage Nexus
			state.get_player(defender_pid).nexus_hp -= attacker.get_effective_attack()

	state.remove_dead_units()
	_check_champion_levelups_pure(state)

# Giải quyết một cặp combat (hỗ trợ Quick Strike, Overwhelm, Shield)
static func _resolve_one_pure(state: GameState, attacker: UnitInstance,
		blocker: UnitInstance, defender_pid: int) -> void:
	var overflow = 0

	if attacker.keyword == CardData.Keyword.QUICK_STRIKE:
		var dmg = attacker.get_effective_attack()
		blocker.take_damage(dmg)
		if not blocker.is_alive():
			if attacker.keyword == CardData.Keyword.OVERWHELM:
				overflow = max(0, dmg - blocker.max_health)
		else:
			attacker.take_damage(blocker.get_effective_attack())
	else:
		var atk_dmg = attacker.get_effective_attack()
		var blk_dmg = blocker.get_effective_attack()
		attacker.take_damage(blk_dmg)
		blocker.take_damage(atk_dmg)
		if attacker.keyword == CardData.Keyword.OVERWHELM and not blocker.is_alive():
			overflow = max(0, atk_dmg - blocker.max_health)

	if overflow > 0:
		state.get_player(defender_pid).nexus_hp -= overflow

	# Cập nhật block damage cho Lyra
	state.get_player(defender_pid).total_block_damage += blocker.damage_taken_total

# ============================================================
#   SPELL EFFECTS (pure)
# ============================================================

static func _apply_spell_effect_pure(state: GameState, caster_pid: int,
		card: Dictionary, target_uid: int) -> void:
	var defender_pid = GameState.opponent(caster_pid)
	var effect = card.get("effect", "none")
	var val = card.get("spell_value", 0)

	match effect:
		"damage_unit_or_nexus":
			if target_uid == -1:
				state.get_player(defender_pid).nexus_hp -= val
			else:
				var target = state.get_unit_by_uid(target_uid)
				if target:
					target.take_damage(val)
					state.remove_dead_units()

		"buff_ally_atk_2_this_round":
			var target = state.get_unit_by_uid(target_uid)
			if target and target.owner_id == caster_pid:
				target.temp_atk_bonus += val

		"give_shield_to_ally":
			var target = state.get_unit_by_uid(target_uid)
			if target and target.owner_id == caster_pid:
				target.has_shield = true

		"damage_damaged_enemy_unit":
			var target = state.get_unit_by_uid(target_uid)
			if target and target.owner_id != caster_pid and target.health < target.max_health:
				target.take_damage(val)
				state.remove_dead_units()

		"buff_ally_1_atk_2_hp_permanent":
			var target = state.get_unit_by_uid(target_uid)
			if target and target.owner_id == caster_pid:
				target.attack += 1
				target.health += 2
				target.max_health += 2

		"heal_own_nexus_or_damage_enemy_nexus":
			# target_uid: 0 = heal mình, 1 = damage địch
			if target_uid == 0:
				state.get_player(caster_pid).nexus_hp = min(
					state.get_player(caster_pid).nexus_hp + val, 20)
			else:
				state.get_player(defender_pid).nexus_hp -= val

# ============================================================
#   SUMMON EFFECTS (pure)
# ============================================================

static func _apply_summon_effect_pure(state: GameState, unit: UnitInstance) -> void:
	var card = CardData.get_card(unit.card_id)
	var effect = card.get("effect", "none")
	var owner = unit.owner_id
	var enemy_pid = GameState.opponent(owner)

	match effect:
		"on_summon_damage_1_enemy":
			var enemies = state.get_board(enemy_pid)
			if not enemies.is_empty():
				# Deterministic: chọn enemy có HP thấp nhất thay vì random
				var weakest: UnitInstance = enemies[0]
				for e in enemies:
					if e.health < weakest.health:
						weakest = e
				weakest.take_damage(1)
				state.remove_dead_units()

		"on_summon_heal_nexus_2":
			state.get_player(owner).nexus_hp = min(
				state.get_player(owner).nexus_hp + 2, 20)

# ============================================================
#   CHAMPION LEVEL UP (pure)
# ============================================================

static func _check_champion_levelups_pure(state: GameState) -> void:
	for pid in range(2):
		var p = state.get_player(pid)
		for u in p.board:
			if not u.is_champion or u.leveled_up:
				continue
			if u.card_id in [17, 18] and p.attack_declares >= 2:
				_level_up_pure(u, state, pid)
			elif u.card_id in [19, 20] and p.total_block_damage >= 5:
				_level_up_pure(u, state, pid)

static func _level_up_pure(u: UnitInstance, state: GameState, pid: int) -> void:
	u.leveled_up = true
	var card = CardData.get_card(u.card_id)
	u.attack = card.get("level_up_atk", u.attack)
	var new_hp = card.get("level_up_hp", u.health)
	var hp_increase = new_hp - u.max_health
	u.max_health = new_hp
	u.health = min(u.health + hp_increase, new_hp)

	# Lyra: cho Guard ally +1 HP
	if u.card_id in [19, 20]:
		for ally in state.get_player(pid).board:
			if ally.uid != u.uid and ally.keyword == CardData.Keyword.GUARD:
				ally.health += 1
				ally.max_health += 1

# ============================================================
#   ROUND END (pure — dùng khi MCTS cần simulate qua round mới)
# ============================================================

static func apply_round_end(state: GameState) -> void:
	state.round_num += 1
	for pid in range(2):
		var p = state.get_player(pid)
		p.max_mana   = min(p.max_mana + 1, GameState.MAX_MANA)
		var leftover = p.mana
		p.spell_mana = min(p.spell_mana + leftover, GameState.MAX_SPELL_MANA)
		p.mana       = p.max_mana
		for u in p.board:
			u.reset_temp_buffs()
			u.exhausted = false
		# Rút 1 lá
		if not p.deck.is_empty() and p.hand.size() < GameState.MAX_HAND_SIZE:
			var card_id = p.deck.pop_front()
			p.hand.append(card_id)

	# Đổi attack token
	if state.round_num > 1:
		state.attack_token_owner = GameState.opponent(state.attack_token_owner)
	state.consecutive_passes = 0

# ============================================================
#   WHOSE TURN
#   Xác định player nào đang hành động trong state hiện tại.
#   Đặt ở đây để cả MCTSNode lẫn MCTSPlayer đều gọi được.
# ============================================================

static func whose_turn(state: GameState) -> int:
	if state.phase == GameState.Phase.COMBAT_BLOCK:
		return GameState.opponent(state.attack_token_owner)
	return state.priority_player

# ============================================================
#   IS TERMINAL
# ============================================================

static func is_terminal(state: GameState) -> bool:
	return state.phase == GameState.Phase.GAME_OVER or state.winner != -1

# ============================================================
#   HEURISTIC EVALUATE (từ góc nhìn pid — score càng cao càng tốt)
# ============================================================

static func evaluate(state: GameState, pid: int) -> float:
	var opp = GameState.opponent(pid)

	# Terminal states
	if state.winner == pid:
		return 100000.0
	if state.winner == opp:
		return -100000.0

	var my_p  = state.get_player(pid)
	var opp_p = state.get_player(opp)

	var my_atk  = 0; var my_hp  = 0; var my_guard  = 0; var my_lv  = 0
	var opp_atk = 0; var opp_hp = 0; var opp_guard = 0; var opp_lv = 0

	for u in my_p.board:
		my_atk += u.get_effective_attack()
		my_hp  += u.health
		if u.keyword == CardData.Keyword.GUARD: my_guard += 1
		if u.leveled_up: my_lv += 1

	for u in opp_p.board:
		opp_atk += u.get_effective_attack()
		opp_hp  += u.health
		if u.keyword == CardData.Keyword.GUARD: opp_guard += 1
		if u.leveled_up: opp_lv += 1

	var score = 0.0
	score += (my_p.nexus_hp  - opp_p.nexus_hp)  * 50.0
	score += (my_atk         - opp_atk)          * 8.0
	score += (my_hp          - opp_hp)           * 6.0
	score += (my_p.hand.size() - opp_p.hand.size()) * 4.0
	score += (my_p.mana + my_p.spell_mana)       * 2.0
	score += (my_lv          - opp_lv)           * 20.0
	score += (my_guard       - opp_guard)        * 5.0
	return score
