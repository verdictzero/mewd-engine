# The fetus launcher's game copy -- see THE FETUS LAUNCHER in GODOT.txt.
#   blender -b -P prep_fetus_launcher.py -- <fetus_launcher.glb> <out.glb>
#
# The user's file (tools/art/models/fetus_launcher.glb, 47.6 MB, 86k
# triangles, 34 PNGs) is eleven parts, each baked in Blender to its own
# colour, normal and AO-roughness-metal sheets. The game's gun shader reads
# a colour and nothing else (gun.gdshader: the map, and one `metal` for its
# made-up sheen), so:
# 1. the two heavy parts decimated (DECIMATE): the caged barrel's 45k
#    triangles -- the cage's holes -- and the body's 26k; the rest as they are
# 2. each part's AO, and the relief of its normal map, multiplied into its
#    colour, as the arc maw's were (make_game_model.py), and the sheet cut
#    to TEX (the body's to TEX_BODY): the light the bake saw stays in the
#    picture though no light reaches the gun
# 3. its metal and roughness sheets down to one number each, the mean over
#    the part's own texels, which is what gun.gdshader can use; the normal
#    and AO-roughness-metal sheets dropped
# 4. the canister's glass keeps its name (the game puts gun_glass.gdshader
#    on it) but no pictures at all
# 5. exported with one UV set, no tangents, JPEG
import bpy, sys, os
import numpy as np

a = sys.argv[sys.argv.index('--') + 1:]
GLB, OUT = a[0], a[1]
TEX = 512
TEX_BODY = 1024
DECIMATE = {'barrel_ext': 9000, 'main_gun_body': 11000}

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)
meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']

def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)

# 1
for o in meshes:
    if o.name not in DECIMATE:
        continue
    n0 = tris(o)
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active = o; o.select_set(True)
    m = o.modifiers.new('dec', 'DECIMATE'); m.decimate_type = 'COLLAPSE'
    m.ratio = DECIMATE[o.name] / n0; m.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier='dec')
    print('DECIMATE', o.name, n0, '->', tris(o))

def px(im):
    arr = np.empty(im.size[0] * im.size[1] * 4, np.float32); im.pixels.foreach_get(arr)
    return arr.reshape(im.size[1], im.size[0], 4)

def lin(x): return np.where(x <= 0.04045, x / 12.92, ((x + 0.055) / 1.055) ** 2.4)
def srgb(x):
    x = np.clip(x, 0, 1); return np.where(x <= 0.0031308, x * 12.92, 1.055 * x ** (1 / 2.4) - 0.055)

def image_named(part, kind):
    for im in bpy.data.images:
        n = im.name
        if kind == 'base' and n.startswith(part + '_BaseColor'):
            return im
        if kind == 'orm' and n.startswith(part + '_AO-'):
            return im
        if kind == 'normal' and n.startswith(part + '_Normal'):
            return im
    return None

# 2 + 3 + 4
for o in meshes:
    part = o.name
    mat = o.data.materials[0]
    N, L = mat.node_tree.nodes, mat.node_tree.links
    if part == 'glass':
        base = image_named(part, 'base')
        tint = px(base)[..., :3].reshape(-1, 3).mean(axis=0) if base else np.array([0.8, 0.6, 0.6])
        N.clear()
        out = N.new('ShaderNodeOutputMaterial'); b = N.new('ShaderNodeBsdfPrincipled')
        L.new(b.outputs['BSDF'], out.inputs['Surface'])
        b.inputs['Base Color'].default_value = (*tint, 1.0)
        b.inputs['Metallic'].default_value = 0.0; b.inputs['Roughness'].default_value = 0.1
        print('GLASS', part, 'tint', tint)
        continue
    base, orm, nrm = image_named(part, 'base'), image_named(part, 'orm'), image_named(part, 'normal')
    for im in (base, orm, nrm):
        if im is not None: im.colorspace_settings.name = 'Non-Color'
    S = base.size[0]
    alb = px(base)[..., :3]
    o4 = px(orm) if orm is not None else np.ones((S, S, 4), np.float32)
    if o4.shape[0] != S:
        orm.scale(S, S); o4 = px(orm)
    ao = o4[..., 0:1]
    shade = 0.35 + 0.65 * ao
    if nrm is not None:
        if nrm.size[0] != S: nrm.scale(S, S)
        nz = np.clip(px(nrm)[..., 2:3] * 2 - 1, 0, 1)
        shade = shade * (0.6 + 0.4 * nz ** 2)
    game = srgb(lin(alb) * shade)
    # the part's own texels: not the black between its islands
    used = alb.max(axis=-1) > 0.02
    metal = float(o4[..., 2][used].mean()) if used.any() else 0.0
    rough = float(o4[..., 1][used].mean()) if used.any() else 0.5
    size = TEX_BODY if part == 'main_gun_body' else TEX
    img = bpy.data.images.new(part, S, S, alpha=False)
    full = np.ones((S, S, 4), np.float32); full[..., :3] = game
    img.pixels.foreach_set(full.ravel())
    if S != size: img.scale(size, size)
    N.clear()
    out = N.new('ShaderNodeOutputMaterial'); b = N.new('ShaderNodeBsdfPrincipled')
    t = N.new('ShaderNodeTexImage'); t.image = img
    L.new(t.outputs['Color'], b.inputs['Base Color']); L.new(b.outputs['BSDF'], out.inputs['Surface'])
    b.inputs['Metallic'].default_value = metal; b.inputs['Roughness'].default_value = rough
    print('PART', part, 'tex', S, '->', size, 'metal %.2f rough %.2f' % (metal, rough), 'tris', tris(o))

# 5
bpy.ops.object.select_all(action='DESELECT')
for o in meshes: o.select_set(True)
print('TRIS', sum(tris(o) for o in meshes))
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True,
                          export_tangents=False, export_image_format='JPEG', export_jpeg_quality=88,
                          export_vertex_color='NONE', export_extras=False, export_apply=True)
print('EXPORTED', OUT, os.path.getsize(OUT))
