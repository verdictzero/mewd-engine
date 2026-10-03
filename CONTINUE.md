# MEWD: notes for picking up in a new chat

This is `CONTINUE.md` at the root of mewd-engine. A new chat should read it first.

Written 2026-10-03. It describes the island version on `claude/godot-rewrite`. `main` still holds the Doom-style version (`435efa9`) until the user says "push to main".

---

## 1. Where things live

| | |
|---|---|
| **Repo to work in** | `verdictzero/mewd-engine` (GitHub) |
| **Working branch** | `claude/godot-rewrite`: the island version |
| **main** | `435efa9`: the last Doom-style version, with the editor and the maps. Updated only on "push it" / "push to main" |
| **Island source** | `verdictzero/golf` (the user's other project). Its island system was copied into `godot/island/`. Read it, but don't change it without being asked. |
| **Old repo** | `verdictzero/sellwrong`. **Do not touch it.** |
| **Engine** | Godot **4.7-stable** (it was 4.3). Mobile renderer on Vulkan, for Android and Linux. |
| **Target hardware** | **Anbernic RG557**, an arm64 Android handheld. Linux x86_64 is second. |

Builds are rolling GitHub releases on mewd-engine, replaced on each push to `main` or `claude/godot-rewrite`:
- **`android`**: `.github/workflows/android.yml`. A signed apk; the key comes from the repo secrets `MEWD_KEYSTORE_B64`, `MEWD_KEY_ALIAS` and `MEWD_KEY_PASS`.
- **`linux`**: `.github/workflows/linux.yml`. A `mewd-<sha>.x86_64` plus a `.tar.gz` that keeps the executable bit.

Both workflows bake the islands before exporting. The bakes are cached in `actions/cache`, keyed on `godot/island/**` and the bake code.

## 2. Standing rules from the user

1. **Push to `main` only on an explicit "push it", "push" or "push to main".** Otherwise commit and push to `claude/godot-rewrite`. To update main, fast-forward it: `git push origin claude/godot-rewrite:main`.
2. Don't open pull requests unless asked.
3. Never put model names or IDs in code or docs. End commit messages with the attribution trailer the session's system prompt specifies.
4. **Never run two `godot` processes at once.** They fight over `.godot/`.
5. `GODOT.txt` is the design doc and changelog. Write each change up "at the user's request", in its plain prose style.
6. The user is terse. "New apk" means making sure CI rebuilt the android release for the pushed commit, and saying so.

## 3. The direction (the user's own words, paraphrased)

- No more editor and no more Doom-like levels.
- Keep the player, the NPCs, the weapons and the weapon effects.
- Levels are golf's procedural islands, **pre-baked, as a set behind a level select** (the user chose this). The goal is levels generated from assets the user provides, to cut artist fatigue.
- First island: golf's `island_0` without its ruins, crash site or golf areas. **No responders for now, just lots of NPCs.**

## 4. Setting up a fresh container

```sh
git clone https://github.com/verdictzero/mewd-engine && cd mewd-engine
git checkout claude/godot-rewrite
curl -sSL -o /tmp/g.zip https://github.com/godotengine/godot/releases/download/4.7-stable/Godot_v4.7-stable_linux.x86_64.zip
unzip -q /tmp/g.zip -d /tmp/g && install /tmp/g/Godot_v4.7-stable_linux.x86_64 /usr/local/bin/godot
godot --headless --editor --quit                                                # import, register class names
godot --headless --script res://tools/bake_island.gd -- --all --if-missing     # ~2 min: the island bakes
sh tools/godot-test.sh                                                          # weapons, island, net, death, pad
```

- **Pictures:**
  - `xvfb-run -a -s "-screen 0 1280x720x24" godot --audio-driver Dummy --resolution 1280x720 --path . -- --play --shot=out.png --shot-frames=60`
  - `godot/tests/island_shot.gd` shows a gun held on a row of people: `... --script res://godot/tests/island_shot.gd -- out.png LAUNCHER 120 25`
- **Builds:** `sh tools/build-linux.sh` and `tools/build-android.sh`. Both bake first when they need to; CI uses `tools/ci-android.sh`.

## 5. How the island version works (full write-up: GODOT.txt, "THE ISLAND")

- **`godot/island/`** holds golf's files with their own names, and every `res://` path moved under it:
  - field: `SCRIPT_island_field.gd`
  - mesher and streaming world
  - bake stores, with the autoloads `TerrainBake` and `VegBake`
  - forest and grass scatters, sky cycle, cloud sea, horizon clouds
  - shaders, materials, textures and plant sprites
- **The scene** is `godot/island/scenes/island_0.tscn`: golf's island_0 cut down to the world, plants, sky and clouds.
- **The field** is `godot/island/data/ISLANDFIELD_island0.tres`: golf's hub_solid with these switches off: `zone_enabled`, `sand_enabled`, `crater_enabled`, `divot_enabled` and `ruin_enabled`.
- **`godot/scripts/level/islands.gd`** is the island list, used by the title's NEW GAME, `--map=` and net play. **To add an island:** a scene plus a field `.tres`, and an entry in `Islands.LIST`.
- **Scale:**
  - The game counts 32 units to the metre; the island counts metres.
  - The `Game` node is scaled to 1/32, and the island under it is scaled back up by 32.
  - Shaders that size things in game units multiply by the global `game_unit`; `U.set_unit` sets it.
  - Camera-vs-position code uses the camera's local transform.
- **`IslandLevel`** (`godot/scripts/level/island_level.gd`) extends `Level`:
  - Every point is a sector whose floor is the ground there.
  - There are no lines or walls.
  - A body can't step more than 24 units up, can't drop more than 96 (the crowd), and keeps 2 m back from the coast.
  - It is `layered = true`, so rays, eyes and blasts ask the ground.
  - `populate()` drops the player and 360 townsfolk.
  - `flat_run()` is used by the tests.
- **`IslandGround`** (`godot/scripts/level/island_ground.gd`) is a 2 m height grid sampled from the field. It is baked as `heights_<sig>.bake`. Lookups take about 1 µs, against 34 µs for the field.
- **Bakes:**
  - The terrain (93 MB), the plants (11 MB), the ground (5 MB), and `CODE_DIGESTS.json`, which exported builds need in order to match signatures.
  - They go in `res://godot/island/data/bake/`, which is gitignored.
  - Exports include `*.bake`.
  - An exported Linux build was checked: it reads all three and builds nothing.

## 6. What was removed

- The map editor.
- The maps: the maze, JESSE, THE SPRAWL, THE GRID and THE ANNEXE.
- The block world, DocCompile, BlockCompile, MapGeo and Earcut.
- The doors and the room-to-room nav.
- The terminal's JESSE and EDIT, the title's MAP EDITOR, and F2.
- Their tests.

The old sections of GODOT.txt are kept as the record.

## 7. Open threads / next steps

- **Waiting on the user's RG557 test** of the island apk. Check the load time and the frame rate with 360 people.
- **More islands:** a field `.tres` per island; vary the seed and the settings. Then **user-provided assets**: a manifest of sprites, textures and props per island that the scatters read.
- **Trees aren't solid**, as in golf; walking into a wood dissolves the near ones.
- **Real decals are off**, so marks are quads. The island's terrain isn't cut into the tiles RealDecals wants.
- **Responders are off** (`world.noSquads`). Vans would need roads, or would need to drive on terrain.
- **The web build** (`pages.yml`, main only) would export without a bake and build the island in the browser.
- `godot/tests/perf_bench.gd`, `decal_shot.gd`, `lance_shot.gd`, `potato_shot.gd` and `projectile_shot.gd` are older picture and benchmark tools. They still name the old maps; `--map` falls back to island0.

## 8. Key files

| File | What it does |
|---|---|
| `godot/scripts/game/game.gd` | `start_map` (the island), the frame loop, `hitscan`, `trace`, `explode`, `_island_light` |
| `godot/scripts/main.gd` | Boot, title, loading screen (it waits for `game.island_ready()`), net join |
| `godot/scripts/level/island_level.gd`, `island_ground.gd`, `islands.gd` | The island as a level |
| `godot/scripts/level/level.gd` | The base Level; its Sector class is still what callers type against |
| `tools/bake_island.gd` | The bakes |
| `godot/tests/island_test.gd` | The island suite |
| `godot/island/` | golf's island system |
| `GODOT.txt` | Design doc and changelog |
