# candyLand asset naming

`PREFIX_category_name[_variant].ext` — camelCase inside each part, `_` between parts,
two-digit variants (`_01`, `_02`), view/side last (`_front`, `_back`).

| Prefix      | What                                              | Example                                  |
|-------------|---------------------------------------------------|------------------------------------------|
| `TEXTURE_`  | Tiling surface image, 256x256, opaque             | `TEXTURE_cliff_rock_02.png`              |
| `SPRITE_`   | Cutout billboard / 2D image, 256 wide, 1-bit alpha | `SPRITE_npc_mintGirl_front.png`          |
| `MODEL_`    | 3D mesh file (.glb export, .blend source)         | `MODEL_candyLandWallAndCornerTurret.glb` |
| `MATERIAL_` | Material (inside models, or .tres in Godot)       | `MATERIAL_crystal_refract`               |
| `SHADER_`   | Shader source                                     | `SHADER_crystal_refraction.gdshader`     |
| `SCRIPT_`   | Code / tool scripts                               | `SCRIPT_import_candyLandModel.gd`            |
| `ANIM_`     | Animation clips (reserved)                        | `ANIM_npc_lemonGirl_walk`                |
| `AUDIO_`    | Sound / music (reserved)                          | `AUDIO_sfx_candyCrunch.ogg`              |
| `UI_`       | Interface graphics (reserved)                     | `UI_icon_heart.png`                      |
| `VFX_`      | Particle / effect textures (reserved)             | `VFX_sparkle_01.png`                     |

Suffix tags on material names (acted on by `scripts/SCRIPT_import_candyLandModel.gd` at Godot import):
- `_refract`: replaced with `SHADER_crystal_refraction`
- `_triplanar`: world-space triplanar UVs, nearest filtering (scale via glTF extras `triplanar_scale`)

## Folders
```
textures/terrain        ground, street
textures/cliff          rock, dirt
textures/architecture   wall, column, roof, wood
sprites/npc/candyGirls  front/back per flavor
sprites/foliage/{grass,bush,tree}
sprites/props
models/                 game-ready .glb (dithered textures embedded)
models/source/          .blend
shaders/  scripts/      Godot side
_build/                 build_assets.py: regenerates everything from the originals
```

## Processing (all images)
1. Sprites: chroma key (magenta or green, auto-detected from the border), edge-only despill, specks removed.
2. Resize: textures 256x256; sprites 256 wide, height proportional (premultiplied Lanczos).
3. 1-bit alpha at 50%; edge colors bled into transparent pixels so filtering doesn't make halos.
4. 8x8 ordered Bayer dither down to 16 levels per channel (16x16x16 = 4096 colors).
5. In the GLB, textures use nearest filtering so the dither stays sharp.
