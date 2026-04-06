# GameManager.gd
# AutoLoad Singleton - điều phối toàn bộ flow game Nexus Clash
# Đây là trái tim của game: quản lý turn, phases, và kết nối AI

extends Node

# Singleton
var state: GameState
const AI_DIFFICULTY_NORMAL = 1  # AIPlayer.Difficulty.NORMAL
var ai_difficulty: int = AI_DIFFICULTY_NORMAL

# Signal để UI cập nhật
signal state_updated(state: GameState)
signal log_message(msg: String)
signal game_over(winner_id: int)
signal round_started(round_num: int)
signal combat_started(attackers: Array)
signal combat_resolved(log_str: String)

# Pending action từ Player
var player_hand_index_selected: int = -1
var player_spell_target: int = -1
var player_attackers: Array = []
var waiting_for_player_block: bool = false
var waiting_for_player_attack: bool = false

# ============================================================
func _ready():
	AIPlayer.difficulty = ai_difficulty

# ============================================================
#   GAME SETUP
# ============================================================
func start_new_game(difficulty: int = 1):
	ai_difficulty = difficulty
	AIPlayer.difficulty = difficulty
	
	state = GameState.new()
	DeckManager.setup_game(state)
	
	# Bắt đầu round 1
	DeckManager.begin_round(state)
	state.phase = GameState.Phase.PLAYER_TURN if state.priority_player == 0 else GameState.Phase.AI_TURN
	
	emit_signal("state_updated", state)
	emit_signal("round_started", state.round_num)
	emit_signal("log_message", "=== Game bắt đầu! Round 1 | Attack token: %s ===" % ("Player" if state.attack_token_owner == 0 else "AI"))
	
	# Nếu AI đi trước
	if state.priority_player == 1:
		await _run_ai_turn()

# ============================================================
#   PLAYER ACTIONS
# ============================================================

# Player summon 1 unit từ tay
func player_summon(card_hand_index: int):
	if state.phase != GameState.Phase.PLAYER_TURN:
		return
	var p = state.get_player(0)
	if card_hand_index >= p.hand.size():
		return
	var card_id = p.hand[card_hand_index]
	var card = CardData.get_card(card_id)
	
	# Kiểm tra điều kiện
	if card.get("type") == CardData.CardType.SPELL:
		return  # Dùng player_cast_spell thay thế
	if not state.can_afford(0, card.get("cost", 99)):
		emit_signal("log_message", "Không đủ mana!")
		return
	if state.board_full(0):
		emit_signal("log_message", "Bàn đầy rồi!")
		return
	
	# Summon
	state.spend_mana(0, card.get("cost", 0))
	p.hand.remove_at(card_hand_index)
	var unit = state.summon_unit(0, card)
	CombatManager.apply_summon_effect(state, unit)
	
	emit_signal("log_message", "Player summon: %s" % unit.unit_name)
	emit_signal("state_updated", state)
	state.consecutive_passes = 0
	
	# Sau action, chuyển lượt AI
	await _hand_off_to_ai()

# Player cast spell
func player_cast_spell(card_hand_index: int, target_uid: int):
	if state.phase != GameState.Phase.PLAYER_TURN:
		return
	var p = state.get_player(0)
	if card_hand_index >= p.hand.size():
		return
	var card_id = p.hand[card_hand_index]
	var card = CardData.get_card(card_id)
	if card.get("type") != CardData.CardType.SPELL:
		return
	
	var cost = card.get("cost", 99)
	if not state.can_afford_with_spell_mana(0, cost):
		emit_signal("log_message", "Không đủ mana!")
		return
	
	state.spend_mana(0, cost)
	p.hand.remove_at(card_hand_index)
	var log = CombatManager.apply_spell(state, 0, card, target_uid)
	emit_signal("log_message", "Player cast: " + card["name"] + " → " + log)
	emit_signal("state_updated", state)
	state.consecutive_passes = 0
	
	if state.phase == GameState.Phase.GAME_OVER:
		emit_signal("game_over", state.winner)
		return
	
	await _hand_off_to_ai()

# Player declare attack
func player_declare_attack(attacker_uids: Array):
	if state.phase != GameState.Phase.PLAYER_TURN:
		return
	if state.attack_token_owner != 0:
		emit_signal("log_message", "Bạn không có attack token!")
		return
	if attacker_uids.is_empty():
		return
	
	state.attackers = attacker_uids
	for uid in attacker_uids:
		var u = state.get_unit_by_uid(uid)
		if u: u.exhausted = true
	
	# attack_declares chỉ tăng 1 lần cho cả đợt tấn công
	state.get_player(0).attack_declares += 1
	state.phase = GameState.Phase.COMBAT_BLOCK
	emit_signal("combat_started", attacker_uids)
	emit_signal("log_message", "Player declare attack với %d unit!" % attacker_uids.size())
	
	# AI chọn block
	var block_map = AIPlayer.decide_blockers(state, attacker_uids)
	await get_tree().create_timer(0.8).timeout
	_resolve_combat_phase(block_map)

# Player pass
func player_pass():
	if state.phase != GameState.Phase.PLAYER_TURN:
		return
	state.consecutive_passes += 1
	emit_signal("log_message", "Player pass.")
	
	if state.consecutive_passes >= 2:
		await _end_round()
	else:
		await _hand_off_to_ai()

# ============================================================
#   AI TURN
# ============================================================
func _run_ai_turn():
	if state.phase == GameState.Phase.GAME_OVER:
		return
	state.phase = GameState.Phase.AI_TURN
	emit_signal("state_updated", state)
	
	# Delay nhỏ cho UX
	await get_tree().create_timer(0.6).timeout
	
	if state.phase == GameState.Phase.GAME_OVER:
		return
	
	var action = AIPlayer.decide_action(state)
	
	match action.get("type", "pass"):
		"summon":
			var card_id = action["card_id"]
			var p = state.get_player(1)
			var idx = p.hand.find(card_id)
			if idx != -1:
				var card = CardData.get_card(card_id)
				state.spend_mana(1, card.get("cost", 0))
				p.hand.remove_at(idx)
				var unit = state.summon_unit(1, card)
				CombatManager.apply_summon_effect(state, unit)
				emit_signal("log_message", "AI summon: %s" % unit.unit_name)
				state.consecutive_passes = 0
				emit_signal("state_updated", state)
				
				if state.phase == GameState.Phase.GAME_OVER:
					emit_signal("game_over", state.winner)
					return
				# Tiếp tục lượt AI (có thể còn action)
				await get_tree().create_timer(0.5).timeout
				await _run_ai_turn()
				return
		
		"cast_spell":
			var card_id = action["card_id"]
			var target_uid = action.get("target_uid", -1)
			var p = state.get_player(1)
			var idx = p.hand.find(card_id)
			if idx != -1:
				var card = CardData.get_card(card_id)
				state.spend_mana(1, card.get("cost", 0))
				p.hand.remove_at(idx)
				var log = CombatManager.apply_spell(state, 1, card, target_uid)
				emit_signal("log_message", "AI cast: %s → %s" % [card["name"], log])
				state.consecutive_passes = 0
				emit_signal("state_updated", state)
				
				if state.phase == GameState.Phase.GAME_OVER:
					emit_signal("game_over", state.winner)
					return
				await get_tree().create_timer(0.5).timeout
				await _run_ai_turn()
				return
		
		"declare_attack":
			var attackers = action.get("attackers", [])
			if not attackers.is_empty():
				for uid in attackers:
					var u = state.get_unit_by_uid(uid)
					if u: u.exhausted = true
				state.attackers = attackers
				state.get_player(1).attack_declares += 1
				state.phase = GameState.Phase.COMBAT_BLOCK
				# Set waiting_for_player_block TRƯỚC khi emit signal
				waiting_for_player_block = true
				emit_signal("combat_started", attackers)
				emit_signal("log_message", "AI declare attack với %d unit! Chọn unit block hoặc nhấn End Turn để bỏ qua." % attackers.size())
				emit_signal("state_updated", state)
				return
		
		"pass":
			state.consecutive_passes += 1
			emit_signal("log_message", "AI pass.")
			if state.consecutive_passes >= 2:
				await _end_round()
				return
			# Trả lượt cho Player
			state.phase = GameState.Phase.PLAYER_TURN
			state.priority_player = 0
			emit_signal("state_updated", state)

# Player submit block assignments (khi AI attack)
func player_submit_blocks(block_map: Dictionary):
	if not waiting_for_player_block:
		return
	waiting_for_player_block = false
	_resolve_combat_phase(block_map)

# ============================================================
#   COMBAT RESOLVE
# ============================================================
func _resolve_combat_phase(block_map: Dictionary):
	state.block_assignments = block_map  # Lưu lại để UI có thể hiển thị
	state.phase = GameState.Phase.COMBAT_RESOLVE
	
	var attacker_pid = state.attack_token_owner
	if not state.attackers.is_empty():
		var first_uid = state.attackers[0]
		var u = state.get_unit_by_uid(first_uid)
		if u: attacker_pid = u.owner_id
	
	var log_str = CombatManager.resolve_combat(state, attacker_pid, state.attackers, block_map)
	state.attackers = []
	state.block_assignments = {}
	
	emit_signal("combat_resolved", log_str)
	emit_signal("log_message", "Combat: " + log_str)
	emit_signal("state_updated", state)
	
	if state.phase == GameState.Phase.GAME_OVER:
		emit_signal("game_over", state.winner)
		return
	
	# Sau combat, tiếp tục lượt của ai vừa attack
	state.consecutive_passes = 0
	var next_pid = attacker_pid
	state.priority_player = next_pid
	
	if next_pid == 1:
		state.phase = GameState.Phase.AI_TURN
		await get_tree().create_timer(0.5).timeout
		await _run_ai_turn()
	else:
		state.phase = GameState.Phase.PLAYER_TURN
		emit_signal("state_updated", state)

# ============================================================
#   HANDOFF: Sau khi Player action → AI action → Player
# ============================================================
func _hand_off_to_ai():
	if state.phase == GameState.Phase.GAME_OVER:
		return
	state.priority_player = 1
	await _run_ai_turn()

# ============================================================
#   END ROUND
# ============================================================
func _end_round():
	state.phase = GameState.Phase.ROUND_END
	emit_signal("log_message", "=== Round %d kết thúc ===" % state.round_num)
	
	if state.winner != -1:
		emit_signal("game_over", state.winner)
		return
	
	await get_tree().create_timer(1.0).timeout
	
	DeckManager.begin_round(state)
	CombatManager.check_champion_levelups(state)
	state.check_win_condition()
	
	if state.winner != -1:
		emit_signal("state_updated", state) # Cập nhật UI trước khi báo Game Over
		emit_signal("game_over", state.winner)
		return
	
	emit_signal("round_started", state.round_num)
	emit_signal("log_message", "=== Round %d bắt đầu | Token: %s ===" % [
		state.round_num,
		"Player" if state.attack_token_owner == 0 else "AI"
	])
	
	state.priority_player = state.attack_token_owner
	if state.priority_player == 0:
		state.phase = GameState.Phase.PLAYER_TURN
	else:
		state.phase = GameState.Phase.AI_TURN
	
	emit_signal("state_updated", state)
	
	if state.priority_player == 1:
		await _run_ai_turn()
