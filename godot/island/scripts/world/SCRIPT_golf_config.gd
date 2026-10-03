class_name GolfConfig
extends Resource

# THE COURSE'S RULES ABOUT PAR, as one resource, resolved per island.
#
# Par used to be a two-line function on `IslandField` -- a length, two
# thresholds, an int. That is enough to LABEL a hole and not enough to be a
# system, because a system has to answer the question for a hole the rule does
# not cover and has to let a course say otherwise about a hole it does cover.
# This is those two things and nothing more yet: the rudiments.
#
# THREE LEVELS, ASKED IN THIS ORDER. Every par in the world comes out of exactly
# one of them, and `par_source` says which, so a number on a scorecard can always
# be traced back to the line that made it:
#
#   1. golf.zones  -- a PAR MARKER. An explicit par written against a zone, by
#                     hole id. This is the override: a course designer saying
#                     "hole 4 is a par 3 whatever its length says".
#   2. the MAKER   -- `par_from_length`, the length bands. The rule that MAKES a
#                     par when nobody has written one down, and the behaviour
#                     every hole in the world has had until now.
#   3. golf.global -- `default_par`. What a hole gets when the marker is absent
#                     and the maker has nothing to say.
#
# WHY THE DEFAULT IS 7, WHICH IS NOT A GOLF NUMBER. That is the point. A fallback
# that is a PLAUSIBLE par is a fallback you cannot see: set it to 4 and a hole
# the maker declined to score comes out looking like every other par 4 on the
# card, and nothing downstream -- HUD, scorecard, test, screenshot -- has any way
# to notice. Seven is off the end of a real scorecard, so the first time level 3
# fires it is visible in the game rather than in a log, and it is visible to a
# player who was never told the system existed. It is a sentinel that is also a
# playable number: the hole still scores, it just scores as the oddity it is.
#
# WHAT MAKES THE MAKER FALL THROUGH. `par5_max` is the maker's reach, and it is
# the whole reason level 3 is reachable from geometry at all rather than being
# dead code kept for tidiness. Below it the bands cover every length; past it the
# maker returns 0 -- "I have no answer for a hole this long" -- and the default
# takes it. At the shipped tuning nothing reaches that far (`hole_length_max` is
# 450 m against a 600 m reach), which is deliberate: the level exists, is tested,
# and changes no hole anyone has already played.
#
# THE CONFIG IS GLOBAL AND IS READ PER ISLAND. One resource describes the whole
# world; `for_island` narrows it to one lattice cell and `IslandField` caches
# that narrowed copy on the `Island` beside its zones and holes. Narrowing is an
# optimisation AND a statement: after it, the markers in hand are exactly the
# ones that island's holes can match, so "what is the config on this island" is a
# question with an object as its answer rather than a filter you have to
# remember to apply.
#
# NOTHING HERE IS STORED BETWEEN RUNS. Like everything else in the field, a par
# is a pure function of the seed, the coordinates and this resource -- fly away
# and back and the card is the same card.


## A par came from a marker written against the zone in `zones`.
const PAR_FROM_ZONE := "zone"
## A par came from the length bands -- the maker.
const PAR_FROM_LENGTH := "length"
## A par came from `default_par`, because neither of the above had an answer.
const PAR_FROM_DEFAULT := "default"


@export_group("global")
## `golf.global.default_par`: the par for a hole no marker names and the maker
## declines to score. Seven, and see the header for why a number nobody would
## mistake for a real par is the right kind of default.
@export var default_par := 7
## Sanity bounds applied to every par this resource hands out, marker and default
## alike. A marker is hand-written data and a typo in a `.tres` should come out
## as a strange hole rather than as a hole worth minus four strokes.
##
## `par_min` IS FLOORED AT 1 WHATEVER IS WRITTEN HERE, because 0 is this file's
## sentinel for "no answer": it is what `marker_par` returns for a hole nobody
## marked and what `par_from_length` returns past the maker's reach. A par_min of
## 0 would let a marker clamp down onto the sentinel and vanish, turning a hole
## somebody deliberately marked into a hole that falls through to the default.
@export var par_min := 1
@export var par_max := 12

@export_group("maker")
## Run the length bands at all. Off, every hole that carries no marker takes
## `default_par` -- which is the one-line way to get a flat par-7 course, and the
## cheapest way to see at a glance which holes on an island DO carry markers.
@export var derive_from_length := true
## Length at or below which the maker says par 3, then par 4, then par 5. The
## first two are the thresholds a scorecard uses and are what `IslandField` has
## always used; the third is this system's addition and is the maker's REACH.
## Past it the maker has no answer and `default_par` takes the hole.
@export var par3_max := 230.0
@export var par4_max := 400.0
@export var par5_max := 600.0

@export_group("zones")
## `golf.zones`: PAR MARKERS, keyed by hole. A marker beats the maker outright,
## which is what makes a course something you can author rather than only tune.
##
## The key is a `Hole.id` -- `"cellX:cellZ:index"` -- with `*` allowed in place of
## a field, and the most specific key that matches a hole wins:
##
##   "0:0:3"   hole 3 on the island in lattice cell (0, 0)       most specific
##   "*:*:3"   hole 3 on every island that has one
##   "3"       shorthand for the line above
##   "0:0:*"   every hole on that island
##   "*"       every hole in the world                           least specific
##
## THE HOLE NUMBER IS THE SPECIFIC HALF OF A KEY, not the cell, which is why
## `"*:*:3"` sits above `"0:0:*"` and not below it. A key that names a hole is a
## RULE about that hole; a key that names only an island is that island's
## DEFAULT, and a default is the thing a rule is supposed to beat. Reading it the
## other way round would make `"0:0:*"` an override you cannot get out from
## under, and would mean a course could not say "this island plays par 6, except
## the third".
##
## It is also the ordering that survives `for_island`. Narrowing rewrites these
## five forms into two -- an index or a `*` -- and two levels of precedence is
## all that survives the rewrite, so the five have to sort into those two blocks
## cleanly or the narrowed config would answer differently from the global one.
##
## `"*:*:3"` and `"3"` are the SAME statement at the same specificity, so write
## one or the other; if both are present the first one in the dictionary wins and
## that is an accident waiting to be diffed rather than a rule to rely on.
@export var zones: Dictionary = {}

## The lattice cell `for_island` narrowed this config to, or `Vector2i.MAX` on a
## config that was never narrowed. Read-only, and deliberately NOT exported: it
## is a fact about one copy in memory, not tuning, and it has no business being
## written into a `.tres`.
var island_cell := Vector2i.MAX


## The par for a hole: the three levels of the header, in order.
##
## `length` may be 0 for a hole whose geometry is not in hand, which is not an
## error -- it is how you ask "what would this hole number score here", and it
## simply takes the maker out of the running.
func par_for(cell: Vector2i, index: int, length: float) -> int:
	var marked := marker_par(cell, index)
	if marked > 0:
		return marked
	var made := par_from_length(length)
	if made > 0:
		return clamp_par(made)
	return clamp_par(default_par)


## Which of the three levels produced `par_for`'s answer: one of `PAR_FROM_ZONE`,
## `PAR_FROM_LENGTH`, `PAR_FROM_DEFAULT`. Asked separately rather than returned
## alongside the par because almost every caller wants only the number, and the
## two together would make the common call site unpack a dictionary to read an
## int out of it.
func par_source(cell: Vector2i, index: int, length: float) -> String:
	if marker_par(cell, index) > 0:
		return PAR_FROM_ZONE
	if par_from_length(length) > 0:
		return PAR_FROM_LENGTH
	return PAR_FROM_DEFAULT


## The par written against a hole in `zones`, or 0 if none is. Most specific key
## wins; see the `zones` comment for the grammar.
func marker_par(cell: Vector2i, index: int) -> int:
	var best := 0
	var best_rank := -1
	for key in zones:
		var m := _match_marker(str(key), cell, index)
		if m < 0 or m <= best_rank:
			continue
		best_rank = m
		best = clamp_par(int(zones[key]))
	return best


## The maker: par for a tee-to-pin distance, by the bands above. Returns 0 when
## the maker has no answer -- the bands are switched off, the length is not a
## length, or the hole is longer than the maker's reach -- which is the signal
## `par_for` reads to fall through to `default_par`.
func par_from_length(length: float) -> int:
	if not derive_from_length or length <= 0.0:
		return 0
	if length <= par3_max:
		return 3
	if length <= par4_max:
		return 4
	if length <= par5_max:
		return 5
	return 0


## Every par handed out goes through here. Public because a caller assembling a
## card from markers of its own should land in the same range the field does.
## See `par_min` for why the floor is a floor and not just the number written.
func clamp_par(par: int) -> int:
	var lo := maxi(par_min, 1)
	return clampi(par, lo, maxi(par_max, lo))


## This config as it applies to ONE island: same answers for that lattice cell,
## with the markers that can never match it dropped and the survivors rewritten
## into the keys its holes will actually probe.
##
## The answers are identical BY CONSTRUCTION and not by coincidence -- narrowing
## replays the same `_match_marker` ranking the un-narrowed lookup does and keeps
## the winner -- and `tests/TEST_golf_par.gd` checks the two hole for hole anyway,
## because "identical by construction" is a claim about code that both sides are
## free to change.
##
## Asking a narrowed config about a DIFFERENT cell is meaningless and it will not
## stop you: the keys it kept are cell-free by then. `island_cell` is what it
## kept instead, and is there to be asserted against.
func for_island(cell: Vector2i) -> GolfConfig:
	var out: GolfConfig = duplicate(true)
	out.island_cell = cell
	out.zones = {}
	var rank := {}
	for key in zones:
		var k := str(key)
		var narrowed := _narrow_key(k, cell)
		if narrowed.is_empty():
			continue
		# Rank by the specificity of the ORIGINAL key, not of the narrowed one:
		# "0:0:3" and "*:*:3" both narrow to "3" and are not the same claim.
		var r := _key_rank(k)
		if r <= int(rank.get(narrowed, -1)):
			continue
		rank[narrowed] = r
		out.zones[narrowed] = clamp_par(int(zones[key]))
	return out


# How specific a marker key is, as a rank, or -1 for a key that is not one.
# Higher wins. The ranks are the rows of the grammar in `zones`:
#
#   0  "*"          -- the world's blanket
#   1  "cx:cz:*"    -- one island's blanket
#   2  "n", "*:*:n" -- a rule about a hole number, anywhere. One statement, two
#                      spellings, so they share a rank.
#   3  "cx:cz:n"    -- a rule about one hole on one island
#
# THE 0/1 AND 2/3 SPLIT IS LOAD-BEARING, not cosmetic. `_narrow_key` maps 0 and 1
# onto "*" and 2 and 3 onto the index, so the narrowed dictionary can only
# express "blanket beats nothing, a numbered hole beats the blanket". Any
# ordering that interleaved the two blocks would be an ordering `for_island`
# could not carry, and the narrowed config would quietly answer differently from
# the one it was made from.
#
# A HALF-WILDCARDED CELL -- "*:0:3" -- parses, matches only islands on that row,
# and ranks as though the cell were unspecified. It is not in the grammar and
# nobody should write one; it is allowed rather than rejected because rejecting
# it would mean a key that reads as more specific silently doing nothing.
static func _key_rank(key: String) -> int:
	if key == "*":
		return 0
	if key.is_valid_int():
		return 2
	var parts := key.split(":")
	if parts.size() != 3:
		return -1
	for i in 3:
		if parts[i] != "*" and not parts[i].is_valid_int():
			return -1
	var cell_named := parts[0] != "*" and parts[1] != "*"
	var index_named := parts[2] != "*"
	if index_named:
		return 3 if cell_named else 2
	return 1 if cell_named else 0


# The rank at which `key` matches a specific hole, or -1 if it does not match.
# Same ranks as `_key_rank`; this is that function with the wildcards resolved
# against a real cell and index.
static func _match_marker(key: String, cell: Vector2i, index: int) -> int:
	var rank := _key_rank(key)
	if rank < 0:
		return -1
	if rank == 0:
		return 0
	if key.is_valid_int():
		return rank if int(key) == index else -1
	var parts := key.split(":")
	if parts[0] != "*" and int(parts[0]) != cell.x:
		return -1
	if parts[1] != "*" and int(parts[1]) != cell.y:
		return -1
	if parts[2] != "*" and int(parts[2]) != index:
		return -1
	return rank


# A marker key rewritten for one island: "" for a key that cannot match that
# island at all, the hole index as a string for a key that names one, "*" for a
# key that takes the whole island.
static func _narrow_key(key: String, cell: Vector2i) -> String:
	var rank := _key_rank(key)
	if rank < 0:
		return ""
	if rank == 0:
		return "*"
	if key.is_valid_int():
		return key
	var parts := key.split(":")
	if parts[0] != "*" and int(parts[0]) != cell.x:
		return ""
	if parts[1] != "*" and int(parts[1]) != cell.y:
		return ""
	return "*" if parts[2] == "*" else parts[2]
