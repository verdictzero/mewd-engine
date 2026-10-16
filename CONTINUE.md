# FENRIR: notes for picking up in a new chat

This is `CONTINUE.md` at the root of mewd-engine. A new chat should read it first.

FENRIR (Fusion-Enabled Networked Real-time Interactive Rendering; MEWD until 0000041, and the repo keeps that name) is now **a terrain engine**: real places made out of open map data, and golf's procedural island, drawn by the chunked island system, with a camera to fly round them. The game it used to be (weapons, crowd, networking, editor, title, maze) was deleted at the user's request in 0000039 and lives in the git history (before that commit). `README.txt` says how to run it; `GODOT.txt` is the changelog.

---

## 1. Where things live

| | |
|---|---|
| **Repo** | `verdictzero/mewd-engine` (GitHub) |
| **Branches** | work on the session's branch; `main` is updated only when the user says "push to main" (fast-forward: `git push origin <branch>:main`) |
| **Island source** | `verdictzero/golf` (the user's other project). Its island system was copied into `godot/island/`. Read it, but don't change it without being asked. |
| **Engine** | Godot **4.7-stable**, Mobile renderer, for Android (arm64) and Linux x86_64. Screenshots in a container fall back to GL Compatibility under xvfb. |

Builds are rolling GitHub releases replaced on each push to `main`: **`android`** (`.github/workflows/android.yml`, signed with the repo secrets `MEWD_KEYSTORE_B64`, `MEWD_KEY_ALIAS`, `MEWD_KEY_PASS`) and **`linux`** (`.github/workflows/linux.yml`). Both bake the places first (cached on `godot/island/**` and the bake code).

## 2. Standing rules from the user

1. **Push to `main` only on an explicit "push to main".** Don't open pull requests unless asked.
2. Never put model names or IDs in code or docs. End commit messages with the attribution trailer the session's system prompt specifies; commit subjects start with the version, `00000NN: ...`.
3. **The version** (`U.VERSION` in `godot/scripts/core/u.gd`, `project.godot` `config/version`, `export_presets.cfg` `version/name` and `version/code`) goes up by one on every change that ships.
4. **Never run two `godot` processes at once.** They fight over `.godot/`. (Don't `pkill -f` a pattern your own shell's command line matches: it kills the shell.)
5. `GODOT.txt` is the changelog. Write each change up "at the user's request", in its plain prose style.
6. Before committing, revert the editor's `.import` noise: `git diff --name-only | grep '\.import$' | xargs git checkout --` (keep any `.import` you changed on purpose).

## 3. Setting up a fresh container

```sh
curl -sSL -o /tmp/g.zip https://github.com/godotengine/godot/releases/download/4.7-stable/Godot_v4.7-stable_linux.x86_64.zip
unzip -q /tmp/g.zip -d /tmp/g && install /tmp/g/Godot_v4.7-stable_linux.x86_64 /usr/local/bin/godot
godot --headless --editor --quit                                              # import, register class names
godot --headless --script res://tools/bake_island.gd -- --all --if-missing   # the places' bakes (a few minutes)
sh tools/godot-test.sh                                                        # earth, terrain
```

- **Pictures:** `xvfb-run -a -s "-screen 0 1280x720x24" godot --audio-driver Dummy --resolution 1280x720 --path . -- --map=earth_oeschinen --at=900,300 --high=2 --look=sun --look-off=28,10 --sky-hour=18.6 --shot=out.png` (all the viewer's options: `godot/scripts/main.gd`'s header).
- **Builds:** `sh tools/build-linux.sh`, `sh tools/build-android.sh` (CI: `tools/ci-android.sh`).

## 4. How it fits together

- **The viewer** (`godot/scenes/main.tscn`, `godot/scripts/main.gd`): loads a place (`godot/scripts/level/islands.gd`) into the picture's world (`Lofi`, `godot/scripts/render/lofi.gd`: native or retro picture, the grade, grain), adds `FlyCamera` (`godot/scripts/viewer/`), hands the place's `"sky"` to its EnviroSky, takes `--shot=`.
- **The island system** (`godot/island/scripts/world/`): `IslandField` (golf's procedural field) and `EarthField` (a real place's grids) answer every question; `chunk_mesher`, `island_world` (streaming, LODs, prewarm), `veg_scatter` / `grass_scatter` (billboards; per-plant baked light `VegLight` in the instance custom data), `bake_store` + the `TerrainBake` / `VegBake` autoloads (bakes in `godot/island/data/bake/`, gitignored; signatures include code digests, so changing the field, mesher or scatter code means rebaking).
- **A real place** (`tools/earth_fetch.py` → `godot/island/earth/<name>/`): `EarthDress` (control textures, the water meshes, `tod_water_level`, the underwater pass), `EarthSun` (GPU-baked terrain shadows → `tod_sun_shadow`), `CinemaPost` (god rays, flare, bloom, haze: `SHADER_cinema_post`, numbers in `MAT_earth_cinema.tres`), `EnviroSky` (`godot/island/scripts/SCRIPT_enviro_sky.gd`: sky, clock, weather, the `tod_*` globals, cloud shadows `tod_cloud_*`). Shaders: `SHADER_terrain_earth` (12 PBR layers, triplanar, cliffs `SHADERINC_earth_cliff`, sun/cloud shadows `SHADERINC_earth_sun`, caustics `SHADERINC_earth_water`), `SHADER_water_earth` (double-sided: refraction, absorption, SSR, Snell's window), `SHADER_underwater`, `SHADER_veg_billboard` (simple lit, per vertex, off the tod_* globals: sky + wrapped sun on a fake round normal + backlit translucency; no shadow maps, the EarthSun bake read at the corners), `SHADER_sky_enviro`. The earth pack (textures, plant sprites, the composited meadow cards) is `tools/earth_pack.py`; grass is two `GrassScatter` layers (`GrassNear` 25 cm/21 m, the far one 60 cm/80 m) sampling the field on a lattice (`sample_cells`), and the viewer waits on their `filled()`; low plants (grass, ferns, bushes; not trees) take the ground's colour at their foot (`SHADER_veg_billboard` `ground_match`, `SHADERINC_earth_ground`, globals `tod_ground_*` published by `EarthDress`); THE WORLD MAP (`godot/scripts/world_map/`: `WorldMap` window + `MapView` relief from Terrarium tiles, `RegionBuilder` = in-app GDScript port of `tools/earth_fetch.py` without OSM → `user://regions/<name>`, `Regions` = built places as specs (`built_<name>`, template scene + `region`), `GeoFetch` = threaded cached HTTPS with proxy/CA support, `Cog` = GeoTIFF range reader); a built place's first visit records and saves its bakes to `user://bake`; next: OSM in the builder, faster first visits (stream instead of prewarm); the eye gets its input from `main.gd` (`FlyCamera.handle`: the world viewport receives none itself); the badge and icons are made by `tools/brand_icons.gd` from `tools/brand/FENRIR_logo.svg`; the picture is metered on the GPU (`Lofi` `meter`/`meter_hold`, `lofi_meter.gdshader`, Islands "meter"; the viewer sets its rate); the scene is written by `tools/earth/make_scene.py`.
- **Depth in shaders:** both renderers here use reversed depth (sky = 0); view positions come from the documented `CURRENT_RENDERER` branch.
- **Tests:** `godot/tests/earth_test.gd` (the field against its data, then the place through the viewer) and `terrain_test.gd` (every place up through the viewer).
