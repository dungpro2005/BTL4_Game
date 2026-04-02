# UnitInstance.gd
# Đại diện cho một unit đang sống trên sân đấu

class_name UnitInstance

# Định danh duy nhất
var uid: int = 0
# 0 = Player, 1 = AI
var owner_id: int = 0
# ID của card gốc
var card_id: int = 0
# Tên hiển thị
var unit_name: String = ""

# Chỉ số chiến đấu
var attack: int = 0
var health: int = 0
var max_health: int = 0

# Keyword (dùng hằng số từ CardData)
var keyword: int = 0  # CardData.Keyword enum

# Trạng thái
var exhausted: bool = true   # true = summon sickness / đã hành động
var has_shield: bool = false # Shield keyword
var is_champion: bool = false
var leveled_up: bool = false

# Buff tạm thời trong round
var temp_atk_bonus: int = 0

# Đếm cho champion level up
var attack_count: int = 0      # Kael: đếm số lần attack
var damage_taken_total: int = 0 # Lyra: đếm tổng damage nhận

# Lấy attack hiện tại (bao gồm buff tạm)
func get_effective_attack() -> int:
	return attack + temp_atk_bonus

# Nhận damage, xét Shield
func take_damage(amount: int) -> int:
	if amount <= 0:
		return 0
	if has_shield:
		has_shield = false
		return 0
	health -= amount
	damage_taken_total += amount
	return amount

# Kiểm tra còn sống
func is_alive() -> bool:
	return health > 0

# Hồi máu (không vượt max)
func heal(amount: int):
	health = min(health + amount, max_health)

# Reset buff tạm (gọi cuối round)
func reset_temp_buffs():
	temp_atk_bonus = 0

# Tạo UnitInstance từ card data
static func from_card(card: Dictionary, owner: int, uid_val: int) -> UnitInstance:
	var u = UnitInstance.new()
	u.uid = uid_val
	u.owner_id = owner
	u.card_id = card["id"]
	u.unit_name = card["name"]
	u.attack = card.get("attack", 0)
	u.health = card.get("health", 1)
	u.max_health = card.get("health", 1)
	u.keyword = card.get("keyword", 0)
	u.is_champion = (card["type"] == 2)  # CardType.CHAMPION
	u.exhausted = true
	u.has_shield = (u.keyword == 4)  # CardData.Keyword.SHIELD
	return u

# Debug string
func to_string() -> String:
	var kw_str = ""
	match keyword:
		1: kw_str = " [Guard]"
		2: kw_str = " [Quick Strike]"
		3: kw_str = " [Overwhelm]"
		4: kw_str = " [Shield]"
	var ex_str = " (exhausted)" if exhausted else ""
	var lv_str = " ★" if leveled_up else ""
	return "%s %d/%d%s%s%s" % [unit_name + lv_str, attack + temp_atk_bonus, health, kw_str, ex_str, " 🛡" if has_shield else ""]
