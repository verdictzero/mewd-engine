# MEWD: notes for picking up in a new chat

This is `CONTINUE.md` at the root of mewd-engine. A new chat should read it first.

Written 2026-10-02. The state described here is at **mewd-engine `6c30ba6`**.

---

## 1. Where things live

| | |
|---|---|
| **Repo to work in** | `verdictzero/mewd-engine` (GitHub) |
| **Working branch** | `claude/godot-rewrite` |
| **main** | the same as `claude/godot-rewrite`: the code at `6c30ba6`, plus this file |
| **Old repo** | `verdictzero/sellwrong`. **Do not touch it again.** All its block-world work is merged into mewd-engine (merge `5a4d47e`). |
| **Engine** | Godot **4.3-stable**. Uses the Mobile renderer on Vulkan, on both Android and Linux. |
| **Target hardware** | **Anbernic RG557**, an arm64 Android handheld. Linux x86_64 is the second target. |

Builds are published as rolling GitHub releases on mewd-engine. Each push to `main` or `claude/godot-rewrite` replaces them:
- **`android`**: `.github/workflows/android.yml`. A signed apk, signed with the repo secrets `MEWD_KEYSTORE_B64`, `MEWD_KEY_ALIAS` and `MEWD_KEY_PASS`.
- **`linux`**: `.github/workflows/linux.yml`. Contains `mewd-<sha>.x86_64` and a `.tar.gz` that keeps the executable bit.

Both workflows have `concurrency: <name>-release, cancel-in-progress: false`. Two pushes take turns instead of deleting each other's release.

## 2. Standing rules from the user

1. **Push to `main` only when the user says "push it" or "push".** Otherwise commit and push to `claude/godot-rewrite`. Main is updated by fast-forwarding it from the branch: `git push origin claude/godot-rewrite:main`.
2. Don't open pull requests unless asked.
3. Never put model names or IDs in commits, code or docs.
4. End every commit message with:
   ```
   Co-Authored-By: Claude <noreply@anthropic.com>
   ```
   Use whatever trailer the new session's system prompt specifies.
5. **Never run two `godot` processes at the same time.** They fight over `.godot/` imports and the class cache.
6. `GODOT.txt` is the design doc and changelog. Write up every user-requested change there in its own section, in the same plain prose style ("at the user's request").
7. The user speaks tersely ("push it new apk etc"). "New apk" means: make sure the CI android release is rebuilt for the pushed commit, and say so.

## 3. Setting up a fresh container

```sh
git clone https://github.com/verdictzero/mewd-engine && cd mewd-engine
git checkout claude/godot-rewrite
# Godot 4.3 headless editor on the PATH as `godot`:
curl -sSL -o /tmp/g.zip https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip
unzip -q /tmp/g.zip -d /tmp/g && install /tmp/g/Godot_v4.3-stable_linux.x86_64 /usr/local/bin/godot
godot --headless --editor --quit     # register class_names (run again after adding any)
```

- **Tests:** run `sh tools/godot-test.sh`. It runs all 13 suites and exits non-zero on any failure. The suites are weapons, forest, jesse, sprawl, net, editor, editorui, decals, death, pad, layers, layerspane and texdrop. **All of them pass at `6c30ba6`.**
- **Linux build:** run `sh tools/build-linux.sh build/linux/mewd.x86_64`. It fetches only the two Linux templates out of the 1 GB template archive, by range request. The output is a single ~197 MB file with the game packed inside.
- **Android build:**
  - Locally: `tools/build-android.sh`. It needs the Android SDK, Java, the 4.3 Android templates, and a keystore in `MEWD_KEYSTORE`.
  - CI: `tools/ci-android.sh` is the self-contained version. **Easiest path: push, then let CI make the apk.** The old container's local keystore (`/opt/android/mewd-release.keystore`) won't exist in a new one.
- **Benchmark:** `godot --headless --script res://godot/tests/perf_bench.gd -- --map=<annexe|maze|sprawl> [--warm] [--json=out.json]`.
  - Use xvfb + llvmpipe (or a GPU) for draw-call counts.
  - It reports load time, meshes and nodes, draw calls looking four ways, the steady state, two rockets into rings of 8 shoppers, and the cerebral bore on a living victim.
- **Godot quirks:**
  - The game's profiler `_prof` resets every 60 frames, so read it every frame.
  - After adding a `class_name`, run `godot --headless --import` or `--editor --quit`, or you get parse errors.

## 4. What the game is now (short)

**The level format is blocks.**
- Every level is boxes plus an infinite ground plane (`GROUND_EXTENT 65536`), stacked in storeys (`STOREY_H 128`).
- `BlockCompile` turns blocks into Level sectors/columns. `BlockDoc` (`godot/scripts/maps/block_doc.gd`) holds the blocks.
- Levels are THE ANNEXE (3 layers), the maze, THE SPRAWL, JESSE, the forest, and others. There is a level-select page on the title screen.

**The editor:** `--edit` opens the block editor.
- It has an inspector with a Style section (top/side/under/light) and a "Block styles" list in the Map tab.
- It has a layers pane (stack, eye, move, duplicate, delete) and texture drag-and-drop onto top/side/under/ground.

**Gore and decals:**
- Real `Decal` nodes, at most 8 per mesh, so the world is cut into tiles. Marks with no tile under them become quads.
- The atlas is kept warm by hidden "keeper" decals so it doesn't rebuild mid-fight.

**Controls:** the Pad layer (`pad.gd`) handles any device, plus a wizard.
- "slow" (slow motion) is on b8; run is on b7.

**Doors:**
- Both faces are lit by the side they face.
- The default texture is `DR1_01`, because `DOOR0001` rendered as a black slab.

## 5. Last piece of work: lag on the RG557 (commit `6c30ba6`)

The user reported:
- Major lag on the cerebral bore explosion.
- Some lag in the maze.
- Catastrophic lag in THE SPRAWL, and the same with rocket gore.

**Causes and fixes:**
- **The infinite ground plane was tiled into ~66,000 meshes.**
  - `mapgeo.gd` now tiles only inside `tile_area`, which is the level bounds snapped to the decal tile.
  - Triangles outside go to one `@far` mesh. Triangles that straddle the edge are clipped with `_clip`/`_fan`.
  - `RealDecals.tile_for(area)` doubles the tile size until there are ≤ 400 cells (`MAX_TILES`).
- **Sector lookup was a slow point-in-polygon test (97 µs on the Sprawl).**
  - `level.gd`: polygons with ≥ 32 edges get y-bands (`band_y0`, `band_h`, `band_edges`), bringing it to 10 µs.
- **Doors scanned every actor every tic (1.89 ms on the Sprawl).**
  - `doors.gd` now asks `game.blockmap.near_radius` and the players.
- **Explosions spawned full gore for every victim.**
  - `giblets.eviscerate(..., share)`: `missiles.detonate` passes `1/sqrt(gory victims)`.
  - Blood drops check the floor on alternate tics.
  - `A_Flee` tries 3 directions (`FLEE_TRIES`).
  - Far panicking actors think every 2nd tic; other far actors every 4th.
- **First-explosion hitch.**
  - `main.gd` warm-up waits for the decal bake.
  - It then lays and removes one mark of every kind 120 units ahead of the player (`warm_begin`/`warm_end`).

**Measured on llvmpipe, before → after:**

| | Annexe | maze | Sprawl |
|---|---|---|---|
| level meshes | 66,079 → 57 | 66,372 → 522 | 69,719 → 1,983 |
| draw calls | ~1,400 → 48–89 | ~1,700 → 47–556 | ~2,700 → 728–813 |
| load | 13.7 → 0.25 s | 16.8 → 0.6 s | 22.7 → 4.9 s |
| script time per frame after the bore | | 29.5 → 12.6 ms | 36.9 → 11.5 ms |

The Sprawl tic went from 2.64 to 0.75 ms. Full write-up: `GODOT.txt`, section "WHAT THE HANDHELD LAGGED ON".

**Trade-offs the user may notice:**
- The Sprawl and JESSE use 1024-unit decal tiles, so fewer real decals there.
- Crowd kills have less gore per body.
- Far panickers move at half rate.

## 6. Open threads / what to do next

- **Waiting on the user's RG557 test of `6c30ba6`.** The CI apk is on the `android` release.
  - If the Sprawl still stutters, the offered next step is **drawing blood marks as their own batched meshes instead of `Decal` nodes**. The Sprawl's remaining 700–800 draw calls are mostly the decal tiling.
- A faint ground seam shows in the Annexe screenshot. It predates the perf work: it's identical with full tiling. It hasn't been fixed.
- `GODOT.txt` "WHAT IS NOT PORTED YET" lists remaining web-build features not in the Godot port.

## 7. Key files (all under `godot/scripts/` unless noted)

| File | What it does |
|---|---|
| `game.gd` | Main sim loop, actor LOD, decal tile setup |
| `main.gd` | Boot and the warm-up |
| `mapgeo.gd` | Level to meshes: tiles, `@far`, doors (`door_nodes`, `_obox`) |
| `level.gd` | Sectors and the banded point-in-polygon test |
| `real_decals.gd` | Decal tiles, atlas keepers, warm-up marks |
| `giblets.gd`, `missiles.gd`, `effects.gd`, `actor.gd` | Gore, explosions, AI |
| `doors.gd` | Doors |
| `pad.gd` | Input |
| `title.gd` | Title screen and level select |
| `level/block_compile.gd`, `maps/block_doc.gd`, `ed_doc.gd`, `editor.gd`, `ed_panels.gd`, `ed_layers.gd`, `view2d.gd`, `view3d.gd` | Block world and editor |
| `godot/tests/*.gd` | Suites, plus `perf_bench.gd` |
| `tools/` | Build, test and CI scripts |
| `GODOT.txt` | The design doc / changelog: read its table of contents first |
