#!/usr/bin/env python3
"""MEWD — the sample region's scene, godot/island/earth/oeschinen/earth_oeschinen.tscn,
written from the earth pack's sprites (godot/island/earth/sprites/sprites.json).

    python3 tools/earth/make_scene.py

Every other region's scene is this one copied by tools/earth_fetch.py --register,
so this is the template: run it again after `tools/earth_pack.py billboards`
changes the plants. Needs nothing but Python."""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
EARTH = os.path.join(ROOT, "godot", "island", "earth")


def main():
    sp = os.path.join(EARTH, "sprites", "sprites.json")
    sprites = json.load(open(sp))["sprites"] if os.path.exists(sp) else []
    by = {}
    for s in sprites:
        by.setdefault(s["class"], []).append(s["name"])
    ext = []
    ids = {}

    def res(kind, path, rid):
        ext.append('[ext_resource type="%s" path="%s" id="%s"]' % (kind, path, rid))
        return 'ExtResource("%s")' % rid

    world = res("Script", "res://godot/island/scripts/world/SCRIPT_island_world.gd", "1_world")
    field = res("Resource", "res://godot/island/earth/oeschinen/ISLANDFIELD_earth_oeschinen.tres", "2_field")
    terrain = res("Material", "res://godot/island/earth/materials/MAT_earth_terrain.tres", "3_terrain")
    cliff = res("Material", "res://godot/island/earth/materials/MAT_earth_cliff.tres", "4_cliff")
    sky = res("Material", "res://godot/island/earth/materials/MAT_earth_sky_enviro.tres", "5_sky")
    water = res("Material", "res://godot/island/earth/materials/MAT_earth_water.tres", "6_water")
    dress = res("Script", "res://godot/island/scripts/world/SCRIPT_earth_dress.gd", "7_dress")
    veg = res("Script", "res://godot/island/scripts/world/SCRIPT_veg_scatter.gd", "8_veg")
    grass = res("Script", "res://godot/island/scripts/world/SCRIPT_grass_scatter.gd", "9_grass")
    burn = res("Script", "res://godot/island/scripts/world/SCRIPT_veg_burn.gd", "10_burn")
    tod = res("Script", "res://godot/island/scripts/SCRIPT_enviro_sky.gd", "11_tod")
    sea = res("Script", "res://godot/island/scripts/world/SCRIPT_cloud_sea.gd", "13_sea")
    seamat = res("Material", "res://godot/island/candy/materials/MAT_candy_cloud_sea.tres", "14_seamat")
    vmat = res("Material", "res://godot/island/earth/materials/MAT_earth_veg.tres", "17_vmat")
    umat = res("Material", "res://godot/island/earth/materials/MAT_earth_understory.tres", "18_umat")
    fmat = res("Material", "res://godot/island/earth/materials/MAT_earth_fern.tres", "19_fmat")
    gmat = res("Material", "res://godot/island/earth/materials/MAT_earth_grass.tres", "20_gmat")

    def tex_list(cls):
        out = []
        for i, name in enumerate(by.get(cls, [])):
            out.append(res("Texture2D", "res://godot/island/earth/sprites/%s.png" % name, "s_%s_%d" % (cls, i)))
        return "[" + ", ".join(out) + "]"

    conifer, broad = tex_list("conifer"), tex_list("broadleaf")
    bush, fern, grs = tex_list("bush"), tex_list("fern"), tex_list("grass")

    body = '''[gd_scene format=3]

%(ext)s

[sub_resource type="Sky" id="Sky_earth"]
sky_material = %(sky)s
radiance_size = 1
process_mode = 2

[sub_resource type="Environment" id="Env_earth"]
background_mode = 2
sky = SubResource("Sky_earth")
ambient_light_source = 2
ambient_light_color = Color(0.56, 0.66, 0.82, 1)
ambient_light_energy = 1.0
reflected_light_source = 2
tonemap_mode = 2
glow_enabled = true
glow_intensity = 0.4
glow_strength = 1.0
glow_bloom = 0.03
glow_hdr_threshold = 1.2
glow_blend_mode = 1
fog_enabled = false

[node name="EarthOeschinen" type="Node3D"]

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("Env_earth")

[node name="SunPivot" type="Node3D" parent="."]
transform = Transform3D(0.866025, 0.307934, -0.394022, 0, 0.788011, 0.615661, 0.5, -0.533357, 0.682466, 0, 800, 0)

[node name="IslandWorld" type="Node3D" parent="."]
script = %(world)s
field = %(field)s
terrain_material = %(terrain)s
cliff_material = %(cliff)s
view_distance = 3600.0
prewarm = true
generate_collision = false

[node name="EarthDress" type="Node3D" parent="."]
script = %(dress)s
island_world_path = NodePath("../IslandWorld")
water_material = %(water)s

[node name="VegScatter" type="Node3D" parent="."]
script = %(veg)s
island_world_path = NodePath("../IslandWorld")
material = %(vmat)s
understory_material = %(umat)s
fern_material = %(fmat)s
tree_sprites = %(conifer)s
broadleaf_sprites = %(broad)s
bush_sprites = %(bush)s
fern_sprites = %(fern)s
tree_height = Vector2(14, 28)
broadleaf_height = Vector2(10, 20)
bush_height = Vector2(1.4, 3.2)
fern_height = Vector2(0.6, 1.2)
prescatter = true
max_slope = 0.34
sink_most = 0.2

[node name="GrassScatter" type="Node3D" parent="."]
script = %(grass)s
island_world_path = NodePath("../IslandWorld")
sprites = %(grs)s
material = %(gmat)s
grass_grid = 0.6
tuft_size = Vector2(1.1, 0.55)
max_slope = 0.4
view_distance = 80.0

[node name="VegBurn" type="Node3D" parent="."]
script = %(burn)s
burn = 0.0
advance = false
burn_rate = 0.02
stump = 0.0
stump_rate = 0.0
front_radius = 0.0

[node name="EnviroSky" type="Node3D" parent="."]
script = %(tod)s
sky_material = %(sky)s
world_environment = NodePath("../WorldEnvironment")
island_world_path = NodePath("../IslandWorld")
day_of_year = 196
hour = 10.5
weather = "fair"
fog_base = Color(0.62, 0.72, 0.84, 1)

[node name="CloudSea" type="Node3D" parent="."]
script = %(sea)s
cloud_material = %(seamat)s

''' % dict(ext="\n".join(ext), **{k: v for k, v in locals().items() if isinstance(v, str)})
    out = os.path.join(EARTH, "oeschinen", "earth_oeschinen.tscn")
    with open(out, "w") as f:
        f.write(body)
    print("make_scene: %s, %d sprites" % (os.path.relpath(out, ROOT), len(sprites)))


if __name__ == "__main__":
    main()
