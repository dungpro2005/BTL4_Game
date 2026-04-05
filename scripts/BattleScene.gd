# BattleScene.gd
# Script cho màn hình chiến đấu chính của Nexus Clash
# Kết nối với GameManager để nhận state và player input

extends Control

# ── Node refs (sẽ được gán trong .tscn) ──────────────────────
@onready var lbl_round      = $VBox/Header/LblRound
@onready var lbl_phase      = $VBox/Header/LblPhase
@onready var lbl_ai_nexus   = $VBox/Header/LblAINexus
@onready var lbl_player_nexus = $VBox/Header/LblPlayerNexus
@onready var lbl_ai_mana    = $VBox/Header/LblAIMana
@onready var lbl_player_mana = $VBox/Footer/LblPlayerMana
@onready var lbl_log        = $VBox/LogBox/LblLog
@onready var ai_board_hbox  = $VBox/BoardArea/AIBoard
@onready var player_board_hbox = $VBox/BoardArea/PlayerBoard
@onready var hand_hbox      = $VBox/HandScrollArea/HandArea
@onready var btn_end_turn   = $VBox/Footer/BtnEndTurn
@onready var btn_attack     = $VBox/Footer/BtnAttack
@onready var popup_gameover = $PopupGameOver
@onready var lbl_gameover   = $PopupGameOver/VBoxGO/LblResult

# ── Internal state ────────────────────────────────────────────
var selected_hand_index: int = -1
var selected_hand_card_id: int = -1
var expecting_target: bool = false   # True khi spell cần chọn target
var pending_spell_index: int = -1
var pending_spell_target_type: String = "enemy"  # "enemy" | "ally" | "any"

var attack_selecting: bool = false   # True khi player đang chọn unit attack
var selected_attackers: Array = []

var block_mode: bool = false         # True khi player đang chọn block
var block_assignments: Dictionary = {}
var current_attacker_uid: int = -1   # uid đang cần assign blocker

var gm: Node  # GameManager singleton ref

# ── Colors ───────────────────────────────────────────────────
const COLOR_SELECTED   = Color(1, 0.9, 0.2)
const COLOR_NORMAL     = Color(1, 1, 1)
const COLOR_ENEMY      = Color(1, 0.4, 0.4)
const COLOR_ALLY       = Color(0.4, 0.8, 1)
const COLOR_EXHAUSTED  = Color(0.5, 0.5, 0.5)

# ─────────────────────────────────────────────────────────────
func _ready():
	gm = get_node("/root/GameManager")
	gm.state_updated.connect(_on_state_updated)
	gm.log_message.connect(_on_log)
	gm.game_over.connect(_on_game_over)
	gm.combat_started.connect(_on_combat_started)
	
	btn_end_turn.pressed.connect(_on_end_turn_pressed)
	btn_attack.pressed.connect(_on_attack_pressed)
	
	popup_gameover.hide()
	await get_tree().process_frame
	gm.start_new_game()

# ── State Update ─────────────────────────────────────────────
func _on_state_updated(state: GameState):
	_refresh_ui(state)

func _refresh_ui(state: GameState):
	if state == null: return
	var gm_state = state
	
	# Header info
	lbl_round.text = "Round %d" % gm_state.round_num
	var p0 = gm_state.get_player(0)
	var p1 = gm_state.get_player(1)
	lbl_player_nexus.text = "❤ %d" % p0.nexus_hp
	lbl_ai_nexus.text    = "❤ %d" % p1.nexus_hp
	lbl_player_mana.text = "💧 %d/%d  ✨%d" % [p0.mana, p0.max_mana, p0.spell_mana]
	lbl_ai_mana.text     = "AI 💧 %d/%d" % [p1.mana, p1.max_mana]
	
	# Phase / turn indicator
	var phase_text := ""
	var phase_color := Color(1, 1, 1)
	match gm_state.phase:
		GameState.Phase.PLAYER_TURN:
			if attack_selecting:
				phase_text = "⚔ CHỌN ATTACKER"
				phase_color = Color(1, 0.8, 0.2)
			elif expecting_target:
				phase_text = "🎯 CHỌN MỤC TIÊU"
				phase_color = Color(0.4, 0.9, 1)
			else:
				phase_text = "🟢 LƯỢT CỦA BẠN"
				phase_color = Color(0.3, 1, 0.4)
		GameState.Phase.AI_TURN:
			phase_text = "🔴 LƯỢT AI"
			phase_color = Color(1, 0.4, 0.4)
		GameState.Phase.COMBAT_DECLARE:
			phase_text = "⚔ COMBAT - TẤN CÔNG"
			phase_color = Color(1, 0.6, 0.2)
		GameState.Phase.COMBAT_BLOCK:
			phase_text = "🛡 COMBAT - CHỌN BLOCK"
			phase_color = Color(0.4, 0.6, 1)
		GameState.Phase.COMBAT_RESOLVE:
			phase_text = "💥 COMBAT - KẾT QUẢ"
			phase_color = Color(1, 0.8, 0.4)
		GameState.Phase.ROUND_END:
			phase_text = "⏳ KẾT ROUND"
			phase_color = Color(0.8, 0.8, 0.8)
		GameState.Phase.GAME_OVER:
			phase_text = "🏆 KẾt THÚC"
			phase_color = Color(1, 0.85, 0.1)
		_:
			phase_text = ""
	if lbl_phase:
		lbl_phase.text = phase_text
		lbl_phase.add_theme_color_override("font_color", phase_color)
	_rebuild_board(ai_board_hbox, gm_state, 1)
	_rebuild_board(player_board_hbox, gm_state, 0)
	
	# Hand
	_rebuild_hand(hand_hbox, gm_state)
	
	# Buttons
	var is_player_turn = (gm_state.phase == GameState.Phase.PLAYER_TURN)
	
	# Kiểm tra có unit nào sẵn sàng tấn công không
	var has_ready_attackers = false
	for u in gm_state.get_board(0):
		if not u.exhausted:
			has_ready_attackers = true
			break
	
	# Nếu đang chọn attacker mà không còn unit nào → cho phép End Turn và highlight nó
	var stuck_in_attack = attack_selecting and not has_ready_attackers
	
	# End Turn: enable khi player turn HOẶC trong block phase
	var in_block_phase = (gm_state.phase == GameState.Phase.COMBAT_BLOCK)
	btn_end_turn.disabled = (not is_player_turn and not in_block_phase)
	# Declare Attack: bật khi player turn và có attack token
	# Confirm Attack: luôn bật khi đang attack_selecting (để player cancel hoặc confirm)
	if attack_selecting:
		btn_attack.disabled = false   # Confirm Attack luôn bật
	else:
		btn_attack.disabled = (not is_player_turn) or (gm_state.attack_token_owner != 0)
	btn_attack.text = "⚔ Declare Attack" if not attack_selecting else "✔ Confirm Attack"
	
	# Highlight End Turn khi block mode hoặc không có gì làm
	if block_mode or stuck_in_attack or (is_player_turn and not attack_selecting and not block_mode and not has_ready_attackers):
		btn_end_turn.add_theme_color_override("font_color", Color(1, 0.9, 0.1))
		btn_end_turn.modulate = Color(1.2, 1.2, 0.6, 1.0)
		if stuck_in_attack:
			_on_log("⚠ Không có unit nào sẵn sàng! Nhấn End Turn / Pass để bỏ qua lượt.")
	else:
		btn_end_turn.remove_theme_color_override("font_color")
		btn_end_turn.modulate = Color(1, 1, 1, 1)

func _rebuild_board(hbox: HBoxContainer, state: GameState, pid: int):
	for child in hbox.get_children():
		child.queue_free()
	
	for unit in state.get_board(pid):
		var card_ui = _make_unit_card(unit, pid)
		hbox.add_child(card_ui)
	
	# Empty slots
	var empty = GameState.MAX_BOARD_SIZE - state.get_board(pid).size()
	for _i in range(empty):
		var slot = _make_empty_slot()
		hbox.add_child(slot)

func _rebuild_hand(hbox: HBoxContainer, state: GameState):
	for child in hbox.get_children():
		child.queue_free()
	
	var p = state.get_player(0)
	for i in range(p.hand.size()):
		var card_id = p.hand[i]
		var card = CardData.get_card(card_id)
		# Unit/Champion chỉ dùng regular mana; Spell dùng được cả spell mana
		var card_type = card.get("type", 0)
		var is_spell = (card_type == CardData.CardType.SPELL)
		var available_mana = p.mana + (p.spell_mana if is_spell else 0)
		var card_ui = _make_hand_card(card, i, available_mana)
		hbox.add_child(card_ui)

# ── Unit card UI ─────────────────────────────────────────────
func _make_unit_card(unit: UnitInstance, pid: int) -> Panel:
	var panel = Panel.new()
	panel.custom_minimum_size = Vector2(100, 110)
	
	# Style background
	var is_attacker = (unit.uid in gm.state.attackers) and (gm.state.phase == GameState.Phase.COMBAT_BLOCK)
	var style = StyleBoxFlat.new()
	if unit.exhausted and not is_attacker:
		style.bg_color = Color(0.25, 0.25, 0.25, 0.9)
	elif pid == 0:
		style.bg_color = Color(0.1, 0.3, 0.5, 0.9)
	else:
		style.bg_color = Color(0.5, 0.1, 0.1, 0.9)
	
	if is_attacker:
		if unit.uid == current_attacker_uid:
			# Unit này đang được chọn để block → viền vàng sáng
			style.bg_color = Color(0.5, 0.25, 0.0, 0.95)
			style.border_color = Color(1, 1, 0, 1)
			style.set_border_width_all(4)
		else:
			# Unit đang tấn công (chưa chọn) → viền cam
			style.bg_color = Color(0.5, 0.15, 0.0, 0.9)
			style.border_color = Color(1, 0.5, 0.1, 1)
			style.set_border_width_all(3)
	elif unit.is_champion:
		style.border_color = Color(1, 0.8, 0.2)
		style.set_border_width_all(2)
	else:
		style.border_color = Color(0.6, 0.6, 0.6)
		style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	
	# VBox chứa labels (fill toàn bộ panel)
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)
	
	var name_lbl = Label.new()
	name_lbl.text = ("★ " if unit.leveled_up else "") + unit.unit_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(name_lbl)
	
	var stat_lbl = Label.new()
	stat_lbl.text = "%d / %d" % [unit.get_effective_attack(), unit.health]
	stat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stat_lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(stat_lbl)
	
	var kw_lbl = Label.new()
	var kw = CardData.keyword_name(unit.keyword)
	kw_lbl.text = kw + (" 🛡" if unit.has_shield else "")
	kw_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kw_lbl.add_theme_font_size_override("font_size", 10)
	vbox.add_child(kw_lbl)
	
	# Exhausted overlay
	if unit.exhausted:
		var ex_lbl = Label.new()
		ex_lbl.text = "💤"
		ex_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ex_lbl.add_theme_font_size_override("font_size", 18)
		vbox.add_child(ex_lbl)
	
	# Invisible button overlay để bắt click (mouse_filter = STOP nhưng transparent)
	var btn = Button.new()
	btn.flat = true
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	btn.add_theme_color_override("font_pressed_color", Color(0, 0, 0, 0))
	btn.add_theme_color_override("font_hover_color", Color(0, 0, 0, 0))
	var btn_style = StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", btn_style)
	btn.add_theme_stylebox_override("pressed", btn_style)
	btn.add_theme_stylebox_override("hover", btn_style)
	btn.pressed.connect(_on_unit_clicked.bind(unit.uid, pid))
	panel.add_child(btn)
	
	return panel


func _make_hand_card(card: Dictionary, index: int, available_mana: int) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(90, 120)
	
	var vbox = VBoxContainer.new()
	panel.add_child(vbox)
	
	# Cost
	var cost_lbl = Label.new()
	cost_lbl.text = "💧%d" % card.get("cost", 0)
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(cost_lbl)
	
	# Name
	var name_lbl = Label.new()
	name_lbl.text = card.get("name", "?")
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(name_lbl)
	
	# Type / stat
	var t = card.get("type", 0)
	var stat_lbl = Label.new()
	if t == CardData.CardType.SPELL:
		stat_lbl.text = "[Spell]"
	else:
		stat_lbl.text = "%d/%d" % [card.get("attack", 0), card.get("health", 0)]
	stat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(stat_lbl)
	
	# Keyword
	var kw_lbl = Label.new()
	kw_lbl.text = CardData.keyword_name(card.get("keyword", 0))
	kw_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kw_lbl.add_theme_font_size_override("font_size", 10)
	vbox.add_child(kw_lbl)
	
	var can_afford = available_mana >= card.get("cost", 99)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.4, 0.15, 0.95) if can_afford else Color(0.2, 0.2, 0.2, 0.8)
	if index == selected_hand_index:
		style.bg_color = Color(0.5, 0.4, 0.0, 0.95)
		style.set_border_width_all(3)
		style.border_color = COLOR_SELECTED
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	
	# Bài không đủ mana hiện icon khoá
	if not can_afford:
		var lock_lbl = Label.new()
		lock_lbl.text = "🔒 %d💧" % card.get("cost", 0)
		lock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_lbl.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
		vbox.add_child(lock_lbl)
	
	# Luôn thêm button - nếu không đủ mana thì hiện cảnh báo
	var btn = Button.new()
	btn.flat = true
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if can_afford:
		btn.pressed.connect(_on_hand_card_clicked.bind(index, card))
	else:
		btn.pressed.connect(func(): _on_log("⚠ Cần %d💧 mana (bạn có %d)" % [card.get("cost", 0), available_mana]))
	panel.add_child(btn)
	
	return panel

func _make_empty_slot() -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(100, 110)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 0.5)
	style.set_border_width_all(1)
	style.border_color = Color(0.3, 0.3, 0.3)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	return panel

# ── Input Handlers ───────────────────────────────────────────
func _on_hand_card_clicked(index: int, card: Dictionary):
	if gm.state.phase != GameState.Phase.PLAYER_TURN:
		return
	var t = card.get("type", 0)
	
	if t in [CardData.CardType.UNIT, CardData.CardType.CHAMPION]:
		# Summon trực tiếp
		gm.player_summon(index)
		selected_hand_index = -1
	elif t == CardData.CardType.SPELL:
		if selected_hand_index == index:
			# Deselect
			selected_hand_index = -1
			expecting_target = false
		else:
			var effect = card.get("effect", "")
			var state = gm.state
			var enemy_board = state.get_board(1)
			var ally_board  = state.get_board(0)

			# Spell không cần target → cast luôn
			if effect == "heal_own_nexus_or_damage_enemy_nexus":
				gm.player_cast_spell(index, 0)  # heal own nexus mặc định
				selected_hand_index = -1

			# Fire Bolt: ưu tiên chọn target; nếu không có unit thì bắn Nexus
			elif effect == "damage_unit_or_nexus":
				if enemy_board.is_empty():
					# Không có unit → bắn thẳng vào Nexus địch
					gm.player_cast_spell(index, -1)
					selected_hand_index = -1
					_on_log("Fire Bolt → Nexus địch!")
				else:
					selected_hand_index = index
					pending_spell_index = index
					pending_spell_target_type = "enemy"
					expecting_target = true
					_on_log("Chọn target cho %s (unit hoặc Nexus địch)..." % card["name"])
			# Tactical Shot: chỉ có thể target enemy unit đã bị damage
			elif effect == "damage_damaged_enemy_unit":
				var damaged = enemy_board.filter(func(u): return u.health < u.max_health)
				if damaged.is_empty():
					_on_log("⚠ Không có enemy unit nào đã bị damage!")
					selected_hand_index = -1
				else:
					selected_hand_index = index
					pending_spell_index = index
					pending_spell_target_type = "enemy"
					expecting_target = true
					_on_log("Chọn enemy unit đã bị damage cho %s..." % card["name"])

			# Buff spell: cần ally unit
			elif effect in ["buff_ally_atk_2_this_round", "give_shield_to_ally", "buff_ally_1_atk_2_hp_permanent"]:
				if ally_board.is_empty():
					_on_log("⚠ Không có ally unit nào trên sân!")
					selected_hand_index = -1
				else:
					selected_hand_index = index
					pending_spell_index = index
					pending_spell_target_type = "ally"
					expecting_target = true
					_on_log("Chọn ally unit cho %s..." % card["name"])

			else:
				selected_hand_index = index
				pending_spell_index = index
				expecting_target = true
				_on_log("Chọn target cho %s..." % card["name"])

		_refresh_ui(gm.state)


func _on_unit_clicked(uid: int, pid: int):
	var state = gm.state
	
	# Block mode
	if block_mode:
		if pid == 1:
			# Click vào AI unit → chọn attacker cần block
			var attackers = gm.state.attackers
			if uid in attackers:
				if current_attacker_uid == uid:
					# Click lại → deselect
					current_attacker_uid = -1
					_on_log("🛡 Bỏ chọn attacker. Click AI unit (board trên) để chọn unit muốn block.")
				else:
					current_attacker_uid = uid
					var attacker_unit = state.get_unit_by_uid(uid)
					var attacker_name = attacker_unit.unit_name if attacker_unit else "?"
					_on_log("🛡 Đã chọn block: %s. Giờ click unit của bạn (board dưới) để block, hoặc click AI unit khác." % attacker_name)
				_refresh_ui(state)
			else:
				_on_log("⚠ Unit này không đang tấn công!")
		elif pid == 0 and current_attacker_uid != -1:
			# Click vào unit mình → assign blocker
			var my_unit = state.get_unit_by_uid(uid)
			var attacker_unit = state.get_unit_by_uid(current_attacker_uid)
			if my_unit and not my_unit.exhausted:
				block_assignments[current_attacker_uid] = uid
				_on_log("✅ %s sẽ block %s! Click AI unit khác hoặc End Turn để hoàn tất." % [
					my_unit.unit_name,
					attacker_unit.unit_name if attacker_unit else "?"
				])
				current_attacker_uid = -1
				_refresh_ui(state)
			else:
				_on_log("⚠ Unit này không thể block (kiệt sức)!")
		elif pid == 0 and current_attacker_uid == -1:
			_on_log("⚠ Chưa chọn AI unit cần block! Click AI unit (board trên) trước.")
		return
	
	# Target mode (spell)
	if expecting_target and selected_hand_index != -1:
		var valid_target = false
		if pending_spell_target_type == "ally" and pid == 0:
			valid_target = true
		elif pending_spell_target_type == "enemy" and pid == 1:
			valid_target = true
		elif pending_spell_target_type == "any":
			valid_target = true
		
		if valid_target:
			gm.player_cast_spell(selected_hand_index, uid)
			selected_hand_index = -1
			expecting_target = false
			pending_spell_index = -1
			pending_spell_target_type = "enemy"
		else:
			# Sai target type
			if pending_spell_target_type == "ally":
				_on_log("⚠ Spell này cần chọn unit của bạn (board dưới)!")
			else:
				_on_log("⚠ Spell này cần chọn enemy unit (board trên)!")
		return
	
	# Attack select mode
	if attack_selecting and pid == 0:
		var unit = state.get_unit_by_uid(uid)
		if unit:
			if unit.exhausted:
				_on_log("⚠ %s đang kiệt sức (💤), không thể tấn công!" % unit.unit_name)
			else:
				if uid in selected_attackers:
					selected_attackers.erase(uid)
					_on_log("Bỏ chọn %s" % unit.unit_name)
				else:
					selected_attackers.append(uid)
					_on_log("Đã chọn %d unit tấn công" % selected_attackers.size())
				_refresh_ui(state)

func _on_attack_pressed():
	if attack_selecting:
		# Confirm attack
		if not selected_attackers.is_empty():
			attack_selecting = false
			gm.player_declare_attack(selected_attackers)
			selected_attackers = []
		else:
			attack_selecting = false
		_refresh_ui(gm.state)
	else:
		attack_selecting = true
		selected_attackers = []
		_on_log("Chọn unit để tấn công (click vào unit của bạn), rồi bấm Confirm Attack")
		_refresh_ui(gm.state)

func _on_end_turn_pressed():
	expecting_target = false
	attack_selecting = false
	selected_hand_index = -1
	selected_attackers = []
	
	if block_mode:
		# Submit blocks (có thể rỗng họac đã điền một phần)
		_on_log("Bỏ qua blocking!")
		block_mode = false
		gm.player_submit_blocks(block_assignments)
		block_assignments = {}
	else:
		gm.player_pass()

func _on_combat_started(attackers: Array):
	# Chỉ bật block_mode khi AI tấn công (waiting_for_player_block = true)
	if not gm.waiting_for_player_block:
		# Player đang tấn công, AI tự chọn block, không cần player input
		_on_log("⚔ Player tấn công! AI đang chọn block...")
		_refresh_ui(gm.state)
		return
	block_mode = true
	block_assignments = {}
	_on_log("🛡 AI tấn công! Click AI unit (board trên) để chọn unit muốn block, hoặc nhấn End Turn / Pass.")
	_refresh_ui(gm.state)

func _on_unit_clicked_attacker(atk_uid: int):
	if block_mode:
		current_attacker_uid = atk_uid
		_on_log("Chọn unit của bạn để block attacker này...")

func _check_block_complete(state: GameState):
	_on_log("Block xong! Nhấn 'Confirm Block' hoặc đợi auto")
	block_mode = false
	gm.player_submit_blocks(block_assignments)
	block_assignments = {}
	_refresh_ui(state)

# ── Log ─────────────────────────────────────────────────────
func _on_log(msg: String):
	if lbl_log:
		lbl_log.text = msg

# ── Game Over ────────────────────────────────────────────────
func _on_game_over(winner_id: int):
	print("[BattleScene] _on_game_over called, winner=%d" % winner_id)
	
	var result_text: String
	var result_color: Color
	if winner_id == 0:
		result_text = "🎉 BẠN THẮNG! 🎉\nNexus địch đã bị phá hủy!"
		result_color = Color(0.2, 1, 0.2)
	else:
		result_text = "💀 BẠN THUA! 💀\nNexus của bạn đã bị phá hủy!"
		result_color = Color(1, 0.2, 0.2)
	
	# Hiện popup
	if popup_gameover:
		popup_gameover.visible = true
		if lbl_gameover:
			lbl_gameover.text = result_text
			lbl_gameover.add_theme_color_override("font_color", result_color)
		else:
			print("[BattleScene] ERROR: lbl_gameover is null!")
	else:
		print("[BattleScene] ERROR: popup_gameover is null!")
	
	# Log fallback luôn hiện
	_on_log(result_text.replace("\n", " | "))


func _on_btn_menu_pressed():
	get_tree().change_scene_to_file("res://scenes/MenuScene.tscn")

func _on_btn_restart_pressed():
	get_tree().reload_current_scene()
