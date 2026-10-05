## MEWD — CANDY LAND's music, headless (Music.start_list): its three
## tracks in turn, each crossfaded into the next over XFADE seconds before
## it ends, the last back into the first, round and round; and the
## death music takes over from it.
##   godot --headless --audio-driver Dummy --script res://godot/tests/music_test.gd
extends SceneTree

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1

func _init() -> void:
	var own: Array = Islands.find("candyland").get("music", [])
	check(own.size() == 3, "CANDY LAND has its own three tracks (%d)" % own.size())
	check(not Islands.find("island0").has("music"), "the other island keeps the remixes")
	for u in own:
		var st = load(u)
		check(st != null and st.get_length() > 30.0, "%s loads (%.0f s)" % [u.get_file(), st.get_length() if st else 0.0])
	var m := Music.new()
	root.add_child(m)
	await process_frame
	m.start_list(own)
	check(m.decks[0].playing and m.decks[0].stream.resource_path == own[0], "the first plays")
	# to just before its end
	var L: float = m.decks[0].stream.get_length()
	m.decks[0].seek(L - Music.XFADE - 0.5)
	m._pl_tic(0.0)
	check(m.pl_fade < 0.0, "not fading yet, %.1f s from the end" % (Music.XFADE + 0.5))
	m.decks[0].seek(L - Music.XFADE + 0.2)
	m._pl_tic(0.0)
	check(m.pl_fade >= 0.0 and m.decks[1].playing and m.decks[1].stream.resource_path == own[1], "then the second comes in under it")
	var g := m._gain(m.volume)
	m._pl_tic(Music.XFADE * 0.5)
	var vo := db_to_linear(m.decks[0].volume_db)
	var vi := db_to_linear(m.decks[1].volume_db)
	check(absf(vo - g * 0.5) < 0.02 and absf(vi - g * 0.5) < 0.02, "half way, half each (%.2f, %.2f of %.2f)" % [vo, vi, g])
	m._pl_tic(Music.XFADE * 0.6)
	check(m.pl_fade < 0.0 and m.decks[0].stream.resource_path == own[1] and m.decks[0].playing and not m.decks[1].playing, "and the first out, the second playing alone")
	# and round again
	var L2: float = m.decks[0].stream.get_length()
	m.decks[0].seek(L2 - 1.0)
	m._pl_tic(0.0)
	check(m.decks[1].stream.resource_path == own[2] and m.decks[1].playing, "the second fades into the third")
	m._pl_tic(Music.XFADE * 1.1)
	var L3: float = m.decks[0].stream.get_length()
	m.decks[0].seek(L3 - 1.0)
	m._pl_tic(0.0)
	check(m.decks[1].stream.resource_path == own[0] and m.decks[1].playing, "and the third back into the first: round and round")
	# the title's own music, looping, and NEW GAME's list takes over from it
	m.title_theme()
	check(m.playlist.is_empty() and m.decks[0].playing and m.decks[0].stream.resource_path == Music.TITLE_THEME and m.decks[0].stream.loop, "the title plays Waiting for Something, looping")
	check(not m.decks[1].playing, "and only that")
	m.start_list(own)
	check(m.decks[0].stream.resource_path == own[0] and m.decks[0].playing, "NEW GAME's list takes over from it")
	# the death music takes over
	m.dirge()
	check(m.playlist.is_empty(), "and YOU DIED stops it for the dirge")
	print("music: %s" % ("PASS" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)
