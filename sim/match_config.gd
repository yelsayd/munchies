class_name MatchConfig
extends RefCounted
## Match mode flags for Munchies. Respawn and player-eat live here, not in swallow tests.
## Setup slots: keyboard (WASD/pad) / keyboard_p2 (arrows) / bot / empty.
## Extra gamepads still deferred. Hole count is derived from filled slots.

enum Mode {
	TIMER,
	SCORE_TARGET,
	MAP_CLEARED,
	UNLIMITED,
	LAST_STANDING,
}

const SLOT_EMPTY := "empty"
const SLOT_KEYBOARD := "keyboard"
## Second local human on the same keyboard (arrow keys). At most one.
const SLOT_KEYBOARD_P2 := "keyboard_p2"
const SLOT_BOT := "bot"

const MODE_LABELS := {
	Mode.TIMER: "Timer",
	Mode.SCORE_TARGET: "Score target",
	Mode.MAP_CLEARED: "Map cleared",
	Mode.UNLIMITED: "Unlimited",
	Mode.LAST_STANDING: "Last hole standing",
}

const END_TITLES := {
	Mode.TIMER: "Time",
	Mode.SCORE_TARGET: "Reached 800",
	Mode.MAP_CLEARED: "Map cleared",
	Mode.LAST_STANDING: "Last hole standing",
}

var mode: Mode = Mode.TIMER
var duration: float = 120.0
var score_target: int = 800
var allow_player_eat: bool = true
var respawn_props: bool = false
var respawn_holes: bool = true
## Filled-slot count (1–4). Prefer reading `slots`; this stays for older call sites.
var hole_count: int = 4
## Four setup slots. Values: "keyboard" | "keyboard_p2" | "bot" | "empty".
var slots: PackedStringArray = PackedStringArray([
	SLOT_KEYBOARD, SLOT_BOT, SLOT_BOT, SLOT_BOT,
])


static func default_slots(filled: int = 4) -> PackedStringArray:
	var n: int = clampi(filled, 1, 4)
	var out := PackedStringArray([SLOT_EMPTY, SLOT_EMPTY, SLOT_EMPTY, SLOT_EMPTY])
	out[0] = SLOT_KEYBOARD
	for i in range(1, n):
		out[i] = SLOT_BOT
	return out


static func is_human_slot(kind: String) -> bool:
	return kind == SLOT_KEYBOARD or kind == SLOT_KEYBOARD_P2


static func for_mode(m: Mode, hole_count: int = 4) -> MatchConfig:
	var c := MatchConfig.new()
	c.mode = m
	c.slots = default_slots(hole_count)
	c.hole_count = c.active_hole_count()
	c.duration = 120.0
	c.score_target = 800
	match m:
		Mode.TIMER:
			c.allow_player_eat = true
			c.respawn_props = false
			c.respawn_holes = true
		Mode.SCORE_TARGET:
			c.allow_player_eat = true
			c.respawn_props = false
			c.respawn_holes = true
		Mode.MAP_CLEARED:
			c.allow_player_eat = true
			c.respawn_props = false
			c.respawn_holes = true
		Mode.UNLIMITED:
			c.allow_player_eat = false
			c.respawn_props = true
			c.respawn_holes = false
		Mode.LAST_STANDING:
			c.allow_player_eat = true
			c.respawn_props = false
			c.respawn_holes = false
	return c


func set_slots(kinds: PackedStringArray) -> void:
	slots = kinds.duplicate()
	while slots.size() < 4:
		slots.append(SLOT_EMPTY)
	if slots.size() > 4:
		slots.resize(4)
	# Slot 0 stays the WASD/pad human when filled.
	if slots[0] != SLOT_EMPTY:
		slots[0] = SLOT_KEYBOARD
	# At most one arrow-key human; keep the first P2 slot, demote extras to bot.
	var seen_p2 := false
	for i in slots.size():
		if str(slots[i]) != SLOT_KEYBOARD_P2:
			continue
		if i == 0 or seen_p2:
			slots[i] = SLOT_BOT if i != 0 else SLOT_KEYBOARD
		else:
			seen_p2 = true
	hole_count = active_hole_count()


func active_hole_count() -> int:
	var n := 0
	for k in slots:
		if str(k) != SLOT_EMPTY:
			n += 1
	return n


func human_slot_count() -> int:
	var n := 0
	for k in slots:
		if is_human_slot(str(k)):
			n += 1
	return n


func label() -> String:
	return MODE_LABELS.get(mode, "Timer") as String


func end_title() -> String:
	if mode == Mode.SCORE_TARGET:
		return "Reached %d" % score_target
	return END_TITLES.get(mode, "Match over") as String


func has_end_card() -> bool:
	return mode != Mode.UNLIMITED
