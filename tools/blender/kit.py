# ============================================================
# THE PILLAR KIT, from image-to-3D (step 3 brief 1 section 4, the
# Higgsfield route, 2026-10-21). Run headless:
#
#   /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/kit.py -- [atlas_px] [samples] [sky] [sun]
#
# The sources are Higgsfield image-to-3D meshes of the concept's pillars
# (assets/models/kit_src/<name>.glb, geometry only, ~500k faces; never
# their textures). Per piece: stood on its base, scaled to the kit's
# height (8), turned so its feature faces the lens (Godot -z = Blender
# +y), a LOW mesh made by decimating it, every face turned OUTWARD (the
# old kit, pillars.py, came out inside out), then our stone and our light
# (stone.py) baked from the full source onto the low mesh, all pieces
# into ONE atlas, light in the colour (the pillar shader is unshaded).
#
# Writes assets/models/kit_new/pillar_<name>.glb, pillar_atlas.png and
# kit.json, and prints the bake's shadow-to-lit ratio (the brief: the
# side away from the key at least ~45 % of the lit side, no face 0).
# ============================================================
import bpy, bmesh, json, math, os, sys
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from stone import new_scene, stone_material, sun_and_sky, LIGHT, LIGHT_GODOT

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ATLAS = int(ARGS[0]) if len(ARGS) > 0 else 2048
SAMPLES = int(ARGS[1]) if len(ARGS) > 1 else 64
SKY = float(ARGS[2]) if len(ARGS) > 2 else 1.2    # with SUN: the side away from the key ~60 % of the lit side (measured below)
SUN = float(ARGS[3]) if len(ARGS) > 3 else 9.0
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "models", "kit_src"))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "models", "kit_new"))
os.makedirs(OUT, exist_ok=True)

HEIGHT = 8.0              # the kit's height; the game scales by the pillar's height (monoliths.gd)
LOW_TRIS = 1500           # the brief's budget per piece
SPACING = 20.0            # how far apart the pieces stand while baking
# (name, source, turn about the vertical in degrees: the feature to +y, toward the lens)
PIECES = [("shaft", "shaft.glb", 0.0), ("niche", "niche.glb", 180.0)]

scene = new_scene(SAMPLES)
sun_and_sky(scene, SKY, SUN)


def import_piece(name, path, turn):
    """The source mesh, base at z 0, centred, HEIGHT tall, turned. Returns the object."""
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.context.scene.objects if o not in before]
    meshes = [o for o in new if o.type == 'MESH']
    for o in new:
        if o.type != 'MESH':
            bpy.data.objects.remove(o, do_unlink=True)
    ob = meshes[0]
    ob.name = "high_" + name
    ob.data.materials.clear()
    bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    me = ob.data
    lo = Vector((min(v.co.x for v in me.vertices), min(v.co.y for v in me.vertices), min(v.co.z for v in me.vertices)))
    hi = Vector((max(v.co.x for v in me.vertices), max(v.co.y for v in me.vertices), max(v.co.z for v in me.vertices)))
    k = HEIGHT / (hi.z - lo.z)
    centre = Vector(((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5, lo.z))
    rot = math.radians(turn)
    for v in me.vertices:
        p = (v.co - centre) * k
        v.co = Vector((p.x * math.cos(rot) - p.y * math.sin(rot), p.x * math.sin(rot) + p.y * math.cos(rot), p.z))
    me.update()
    outward(ob)
    return ob


def outward(ob):
    """Every face's normal pointing out of the solid (the old kit's fault),
    and no custom normals: the source's are for 500k faces, and on the
    decimated copy they send the bake's rays off the surface (whole sides
    came out unbaked, 2026-10-21)."""
    bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    if ob.data.has_custom_normals:
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    bm = bmesh.new(); bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(ob.data); bm.free()
    ob.data.update()


def make_low(high, name):
    low = high.copy(); low.data = high.data.copy(); low.name = "pillar_" + name
    bpy.context.collection.objects.link(low)
    mod = low.modifiers.new("dec", 'DECIMATE'); mod.decimate_type = 'COLLAPSE'
    mod.ratio = LOW_TRIS / max(len(high.data.polygons), 1)
    mod.use_collapse_triangulate = True
    bpy.ops.object.select_all(action='DESELECT'); low.select_set(True)
    bpy.context.view_layer.objects.active = low
    bpy.ops.object.modifier_apply(modifier=mod.name)
    outward(low)
    return low


atlas = bpy.data.images.new("pillar_atlas", ATLAS, ATLAS); atlas.generated_color = (0, 0, 0, 1)
stone = stone_material()
pieces = []
sizes = {}
for (name, src, turn) in PIECES:
    high = import_piece(name, os.path.join(SRC, src), turn)
    high.data.materials.append(stone)
    low = make_low(high, name)
    low.data.materials.clear()
    lm = bpy.data.materials.new("bake_" + name); lm.use_nodes = True
    tex = lm.node_tree.nodes.new("ShaderNodeTexImage"); tex.image = atlas; lm.node_tree.nodes.active = tex
    low.data.materials.append(lm)
    # Apart while baking, or one piece's source shades the next one's
    # faces (whole sides came out black, 2026-10-21); back to 0 to export.
    high.location.x = low.location.x = SPACING * len(pieces)
    pieces.append((low, high, name))
    d = low.dimensions
    sizes[name] = [d.x, d.z, d.y]   # Godot's (x, y up, z)
    print("piece", name, "high faces", len(high.data.polygons), "low tris", len(low.data.polygons), "size", [round(x, 3) for x in sizes[name]])

# One atlas: every low mesh unwrapped, then all islands packed together.
bpy.ops.object.select_all(action='DESELECT')
for (low, high, name) in pieces:
    low.select_set(True)
bpy.context.view_layer.objects.active = pieces[0][0]
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.01)
bpy.ops.uv.pack_islands(margin=0.006)
bpy.ops.object.mode_set(mode='OBJECT')

scene.render.bake.use_selected_to_active = True
scene.render.bake.cage_extrusion = 0.15
scene.render.bake.max_ray_distance = 0.0     # no limit: the decimated surface can sit well off the source
scene.render.bake.margin = 6
first = True
for (low, high, name) in pieces:
    bpy.ops.object.select_all(action='DESELECT')
    high.select_set(True); low.select_set(True)
    bpy.context.view_layer.objects.active = low
    scene.render.bake.use_clear = first
    first = False
    bpy.ops.object.bake(type='COMBINED', pass_filter={'DIRECT', 'INDIRECT', 'COLOR', 'DIFFUSE'})
    print("baked", name)
atlas.filepath_raw = os.path.join(OUT, "pillar_atlas.png"); atlas.file_format = 'PNG'; atlas.save()

# The acceptance numbers: per piece, the area-weighted mean brightness
# (the PNG's 0-1 values) of the side faces turned toward the key and of
# those turned away, and how many faces came out black. Each face is
# sampled at seven points inside its UV triangle; points that land off
# the baked island (a sliver's rounding) are skipped.
px = atlas.pixels[:]
def lum_at(u, v):
    x = min(ATLAS - 1, max(0, int(u * ATLAS))); y = min(ATLAS - 1, max(0, int(v * ATLAS)))
    i = (y * ATLAS + x) * 4
    return 0.299 * px[i] + 0.587 * px[i + 1] + 0.114 * px[i + 2]
BARY = [(1/3, 1/3, 1/3), (0.6, 0.2, 0.2), (0.2, 0.6, 0.2), (0.2, 0.2, 0.6), (0.45, 0.45, 0.1), (0.45, 0.1, 0.45), (0.1, 0.45, 0.45)]
key = Vector((LIGHT.x, LIGHT.y, 0.0)).normalized()
for (low, high, name) in pieces:
    uvl = low.data.uv_layers.active.data
    sums = {"lit": [0.0, 0.0], "away": [0.0, 0.0]}
    black = 0
    black_area = 0.0
    face_l = []
    for poly in low.data.polygons:
        uvs = [uvl[li].uv for li in poly.loop_indices][:3]
        vals = [lum_at(a * uvs[0].x + b * uvs[1].x + c * uvs[2].x, a * uvs[0].y + b * uvs[1].y + c * uvs[2].y) for (a, b, c) in BARY]
        vals = [x for x in vals if x > 0.004]
        if not vals:
            black += 1
            black_area += poly.area
            continue
        l = sum(vals) / len(vals)
        face_l.append(l)
        n = poly.normal
        if abs(n.z) > 0.7:
            continue
        f = Vector((n.x, n.y, 0.0)).normalized().dot(key)
        side = "lit" if f > 0.3 else "away" if f < -0.3 else None
        if side:
            sums[side][0] += l * poly.area; sums[side][1] += poly.area
    la = sums["lit"][0] / max(sums["lit"][1], 1e-6); aa = sums["away"][0] / max(sums["away"][1], 1e-6)
    face_l.sort()
    print("BAKE %s lit %.3f away %.3f ratio %.0f %%  darkest 1 %% of faces %.3f  faces with no baked pixel %d of %d (%.2f %% of the area)" % (
        name, la, aa, 100.0 * aa / max(la, 1e-6), face_l[len(face_l) // 100], black, len(low.data.polygons),
        100.0 * black_area / sum(p.area for p in low.data.polygons)))

# Export the low meshes, one GLB each, Y up, base at y = 0.
for (low, high, name) in pieces:
    bpy.data.objects.remove(high, do_unlink=True)
    low.location.x = 0.0
for (low, high, name) in pieces:
    bpy.ops.object.select_all(action='DESELECT'); low.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "pillar_%s.glb" % name), use_selection=True,
                              export_format='GLB', export_yup=True, export_apply=True, export_materials='NONE',
                              export_normals=True, export_texcoords=True)
json.dump({"atlas": "pillar_atlas.png", "sizes": sizes, "light": list(LIGHT_GODOT)}, open(os.path.join(OUT, "kit.json"), "w"), indent=1)
print("KIT DONE", OUT, sizes)
