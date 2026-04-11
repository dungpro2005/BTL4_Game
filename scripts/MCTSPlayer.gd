# MCTSPlayer.gd
# Thuật toán MCTS gồm 4 bước lặp:
#   1. SELECTION   — đi theo cây từ root xuống leaf (dùng UCB1)
#   2. EXPANSION   — thêm node con mới vào leaf chưa fully expanded
#   3. SIMULATION  — chơi random/heuristic đến terminal hoặc depth limit
#   4. BACKPROP    — cập nhật win/visit ngược lên root
#
# Vì GDScript không có threading thực sự, MCTS chạy đồng bộ với giới hạn số iteration thay vì giới hạn thời gian.

extends Node
class_name MCTSPlayer

# ──────────────────────────────────────────────────────────
#  CÀI ĐẶT
# ──────────────────────────────────────────────────────────
const AI_PID = 1
const PLAYER_PID = 0

## Số iteration MCTS mỗi lần được hỏi action
@export var iterations: int = 500

## Hệ số khai phá UCB1: C = sqrt(2) ≈ 1.414
## Tăng C → khai phá nhiều hơn; Giảm C → khai thác sâu hơn
@export var ucb_c: float = 1.414

## Giới hạn độ sâu simulation (số action) trong một rollout
@export var rollout_depth: int = 20

## Dùng heuristic trong rollout (true) hay chọn action random (false)
@export var use_heuristic_rollout: bool = true

# ──────────────────────────────────────────────────────────
#  NODE CỦA CÂY MCTS
#  GDScript inner class KHÔNG thể gọi method của outer class
#  → mọi logic dùng chung đặt trong MCTSState (static class)
# ──────────────────────────────────────────────────────────
class MCTSNode:
	var state: GameState
	var action: Dictionary        # action dẫn đến node này từ parent
	var pid: int                  # player nào vừa thực hiện action

	var parent: MCTSNode
	var children: Array = []
	var untried_actions: Array = []

	var visit_count: int = 0
	var total_value: float = 0.0  # tổng reward từ góc nhìn AI_PID (pid=1)

	func _init(s: GameState, act: Dictionary, p: int, par: MCTSNode = null):
		state  = s
		action = act
		pid    = p
		parent = par
		# MCTSState.whose_turn()
		var next_pid = MCTSState.whose_turn(s)
		untried_actions = MCTSState.get_valid_actions(s, next_pid)
		untried_actions.shuffle()

	# UCB1 score từ góc nhìn from_pid
	func ucb1(c: float, from_pid: int) -> float:
		if visit_count == 0:
			return INF
		var avg = total_value / float(visit_count)
		# AI_PID = 1 là maximizer; player là minimizer nên invert
		if from_pid != 1:
			avg = -avg
		return avg + c * sqrt(log(float(parent.visit_count)) / float(visit_count))

	func is_fully_expanded() -> bool:
		return untried_actions.is_empty()

	func is_leaf() -> bool:
		return children.is_empty()

	func best_child(c: float, for_pid: int) -> MCTSNode:
		var best: MCTSNode = null
		var best_s: float = -INF
		for child in children:
			var s = child.ucb1(c, for_pid)
			if s > best_s:
				best_s = s
				best = child
		return best

# ──────────────────────────────────────────────────────────
#  MAIN ENTRY
# ──────────────────────────────────────────────────────────

## Trả về action tốt nhất cho AI (pid=1).
func decide_action(state: GameState) -> Dictionary:
	var root_state = MCTSState.clone_state(state)
	var root = MCTSNode.new(root_state, {}, AI_PID, null)

	# Shortcut: nếu chỉ có 1 lựa chọn, không cần search
	if root.untried_actions.size() == 1:
		return root.untried_actions[0]

	for _i in range(iterations):
		var node = _select(root)
		if not MCTSState.is_terminal(node.state):
			node = _expand(node)
		var reward = _simulate(node)
		_backpropagate(node, reward)

	return _best_action(root)

## Block decision — dùng heuristic (phase phụ, không cần full MCTS)
func decide_blockers(state: GameState, attacker_uids: Array) -> Dictionary:
	return MCTSState.auto_block(state, AI_PID, attacker_uids)

# ──────────────────────────────────────────────────────────
#  BƯỚC 1: SELECTION
# ──────────────────────────────────────────────────────────

func _select(root: MCTSNode) -> MCTSNode:
	var node = root
	while not MCTSState.is_terminal(node.state) and node.is_fully_expanded():
		var current_pid = MCTSState.whose_turn(node.state)
		node = node.best_child(ucb_c, current_pid)
	return node

# ──────────────────────────────────────────────────────────
#  BƯỚC 2: EXPANSION
# ──────────────────────────────────────────────────────────

func _expand(node: MCTSNode) -> MCTSNode:
	if node.untried_actions.is_empty():
		return node

	var action = node.untried_actions.pop_back()
	var acting_pid = MCTSState.whose_turn(node.state)

	var new_state = MCTSState.clone_state(node.state)
	MCTSState.apply_action(new_state, acting_pid, action)

	if new_state.consecutive_passes >= 2 and not MCTSState.is_terminal(new_state):
		MCTSState.apply_round_end(new_state)

	var child = MCTSNode.new(new_state, action, acting_pid, node)
	node.children.append(child)
	return child

# ──────────────────────────────────────────────────────────
#  BƯỚC 3: SIMULATION (Rollout)
# ──────────────────────────────────────────────────────────

func _simulate(node: MCTSNode) -> float:
	var sim_state = MCTSState.clone_state(node.state)
	var depth = 0

	while not MCTSState.is_terminal(sim_state) and depth < rollout_depth:
		var current_pid = MCTSState.whose_turn(sim_state)
		var actions = MCTSState.get_valid_actions(sim_state, current_pid)

		if actions.is_empty():
			break

		var chosen: Dictionary
		if use_heuristic_rollout:
			chosen = _heuristic_rollout_action(sim_state, current_pid, actions)
		else:
			chosen = actions[randi() % actions.size()]

		MCTSState.apply_action(sim_state, current_pid, chosen)

		if sim_state.consecutive_passes >= 2 and not MCTSState.is_terminal(sim_state):
			MCTSState.apply_round_end(sim_state)

		depth += 1

	return MCTSState.evaluate(sim_state, AI_PID)

# Heuristic nhẹ trong rollout: lethal > attack > summon > spell > random
func _heuristic_rollout_action(state: GameState, pid: int, actions: Array) -> Dictionary:
	var opp_nexus = state.get_player(GameState.opponent(pid)).nexus_hp

	# Lethal spell
	for a in actions:
		if a["type"] == "cast_spell":
			var card = CardData.get_card(a["card_id"])
			var val = card.get("spell_value", 0)
			var effect = card.get("effect", "")
			if effect in ["damage_unit_or_nexus", "heal_own_nexus_or_damage_enemy_nexus"]:
				if val >= opp_nexus and a.get("target_uid", 0) != 0:
					return a

	for a in actions:
		if a["type"] == "declare_attack": return a
	for a in actions:
		if a["type"] == "summon": return a
	for a in actions:
		if a["type"] == "cast_spell": return a

	return actions[randi() % actions.size()]

# ──────────────────────────────────────────────────────────
#  BƯỚC 4: BACKPROPAGATION
# ──────────────────────────────────────────────────────────

func _backpropagate(node: MCTSNode, reward: float) -> void:
	var current = node
	while current != null:
		current.visit_count += 1
		current.total_value += reward
		current = current.parent

# ──────────────────────────────────────────────────────────
#  CHỌN ACTION TỐT NHẤT (Most Visited)
# ──────────────────────────────────────────────────────────

func _best_action(root: MCTSNode) -> Dictionary:
	if root.children.is_empty():
		if not root.untried_actions.is_empty():
			return root.untried_actions[0]
		return {"type": "pass"}

	var best: MCTSNode = root.children[0]
	for child in root.children:
		if child.visit_count > best.visit_count:
			best = child
	return best.action

# ──────────────────────────────────────────────────────────
#  DEBUG
# ──────────────────────────────────────────────────────────

func debug_print_top(root: MCTSNode, top_n: int = 5) -> void:
	var sorted_children = root.children.duplicate()
	sorted_children.sort_custom(func(a, b): return a.visit_count > b.visit_count)
	print("=== MCTS top %d (iter=%d) ===" % [top_n, iterations])
	for i in range(min(top_n, sorted_children.size())):
		var c = sorted_children[i]
		var avg = c.total_value / float(c.visit_count) if c.visit_count > 0 else 0.0
		print("  [%d] visits=%d avg=%.2f  %s" % [i, c.visit_count, avg, str(c.action)])
