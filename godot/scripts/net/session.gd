## MEWD — sessions: where a player's command each tic comes from
## (js/net/session.js).
##
## Game.tic does not hand the player the keyboard. It asks the player's
## SESSION for this tic's command (ticcmd.gd) — or the game's own, for a
## player with none — and hands the player that. Which session decides
## what the game is:
##
##   Local    the game on this machine, single player: the command is
##            this machine's own input (Game.local_cmd), rounded exactly
##            as the wire would round it. The default.
##   Host     a player on a host (server.gd): the command is whatever
##            its client last sent, and a tic with nothing new in it
##            repeats what was held and turns nobody.
##   NetGame.NetSession (remote.gd), a network client's own player.
##
## A session has one member the game calls: cmd(game) → a command.
class_name NetSession

class Local extends RefCounted:
	var kind := "local"
	func cmd(game) -> Dictionary:
		var c: Dictionary = game.local_cmd()
		c["tic"] = game.tics
		return TicCmd.quantize(c)

## How many commands a client may get ahead of the host before the oldest
## are folded: a fifth of a second of burst.
const CMD_BUFFER := 8

class Host extends RefCounted:
	var kind := "host"
	var queue: Array = []
	var held: Dictionary = TicCmd.new_cmd()     # the last command applied
	var applied := 0                            # commands consumed, for the test
	var ack := 0                                # the tic of the last one, so the client can reconcile
	var merged := 0

	## A command has arrived from the client that controls this player.
	func push(c: Dictionary) -> void:
		queue.append(c.duplicate())
		# TOO MANY WAITING, and the oldest is FOLDED INTO the next rather
		# than dropped: its turn is added to the next one's and its presses
		# carried, so a burst costs the host a tic of walking and never a
		# degree of where you are looking
		while queue.size() > CMD_BUFFER:
			var a: Dictionary = queue.pop_front()
			var b: Dictionary = queue[0]
			b.look = b.look + a.look
			b.jump = b.jump or a.jump
			b.use = b.use or a.use
			if int(b.slot) == 0:
				b.slot = a.slot
			if int(b.cycle) == 0:
				b.cycle = a.cycle
			merged += 1

	func cmd(_game) -> Dictionary:
		if not queue.is_empty():
			var c: Dictionary = queue.pop_front()
			held = c
			applied += 1
			ack = int(c.tic)
			return c.duplicate()
		# NOTHING ARRIVED FOR THIS TIC. Keep walking and keep the trigger
		# where it was — a late packet should not stop you dead — but do not
		# turn, and do not press anything that is a press.
		var h := held
		var o := TicCmd.new_cmd()
		o.seen = h.seen
		o.tic = h.tic
		o.side = h.side
		o.fwd = h.fwd
		o.run = h.run
		o.attack = h.attack
		return o
