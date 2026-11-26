class_name MatchConfig
extends RefCounted
## Match mode flags for Munchies. Respawn and player-eat live here, not in swallow tests.

enum Mode {
	TIMER,
	SCORE_TARGET,
	MAP_CLEARED,
	UNLIMITED,
	LAST_STANDING,
}

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
var hole_count: int = 2 ## 2–4; extras are bots


static func for_mode(m: Mode, hole_count: int = 2) -> MatchConfig:
	var c := MatchConfig.new()
	c.mode = m
	c.hole_count = clampi(hole_count, 2, 4)
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


func label() -> String:
	return MODE_LABELS.get(mode, "Timer") as String


func end_title() -> String:
	if mode == Mode.SCORE_TARGET:
		return "Reached %d" % score_target
	return END_TITLES.get(mode, "Match over") as String


func has_end_card() -> bool:
	return mode != Mode.UNLIMITED
