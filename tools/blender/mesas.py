# ============================================================
# THE MESAS — the canyon's pillar kit (step 3 brief 2 section 3,
# 2026-10-21; concept D, docs/concept/directions/D_monolith_canyon.png).
# Run headless:
#
#   /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/mesas.py
#
# Built by script from our own geometry, nothing baked: a mesa is a stack
# of TIERS, each an irregular prism (6-9 sides, every corner pushed in or
# out), a little narrower at its top than at its foot, set slightly off
# the tier below -- so the sides are big flat facets with ledges between
# them, and the top is flat. Flat shaded (every face its own normal): the
# game's mesa shader lights each facet by the sun as three tones and
# gives it its pastel colour (props.gd), so the mesh carries only shape.
#
# Also two TREES (2026-10-21, Milko: "missing the trees on top of the
# mountains"): a pine (two stacked six-sided cones) and a round one (a
# low ball on a stub), 1 tall, base at y 0. monoliths.gd stands a few on
# every grassy mesa top.
#
# Writes assets/models/mesas/pillar_<name>.glb (base at y 0, HEIGHT tall,
# centred on x/z), tree_<name>.glb, and kit.json: each mesa's size
# (Godot's x, y up, z), its flat top (the centre x / z and the radius
# that stays inside it, in piece units -- where the trees may stand), and
# each tree's size. Deterministic: the same seed per piece every run.
# ============================================================
import bpy, bmesh, json, math, os, random
from mathutils import Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "models", "mesas"))
os.makedirs(OUT, exist_ok=True)

HEIGHT = 8.0     # the kit's height; the game scales a piece by the mesa's height (monoliths.gd)
RADIUS = 1.0     # a tier's mean corner distance before its own scale
# (name, seed, tiers): how many tiers sets how many ledges a mesa shows.
PIECES = [("a", 11, 3), ("b", 23, 4), ("c", 37, 5), ("d", 41, 3), ("e", 59, 4), ("f", 73, 2)]


def tier_ring(rng, sides, scale, dx, dy):
    """One tier's footprint: `sides` corners, each pushed in or out."""
    turn = rng.uniform(0.0, 2.0 * math.pi)
    ring = []
    for i in range(sides):
        a = turn + 2.0 * math.pi * (i + rng.uniform(-0.25, 0.25)) / sides
        r = RADIUS * scale * rng.uniform(0.8, 1.15)
        ring.append((dx + r * math.cos(a), dy + r * math.sin(a)))
    return ring


def build(name, seed, tiers):
    rng = random.Random(seed)
    bm = bmesh.new()
    top = None
    # Tier heights: shares of HEIGHT, the lowest tallest (it runs down into the clouds).
    shares = [rng.uniform(0.7, 1.3) for _ in range(tiers)]
    shares[0] += 1.0
    total = sum(shares)
    z = 0.0
    scale = 1.0
    dx = dy = 0.0
    for t in range(tiers):
        h = HEIGHT * shares[t] / total
        sides = rng.randint(6, 9)
        ring = tier_ring(rng, sides, scale, dx, dy)
        taper = rng.uniform(0.9, 0.97)
        cx = sum(p[0] for p in ring) / sides
        cy = sum(p[1] for p in ring) / sides
        lo = [bm.verts.new((x, y, z)) for (x, y) in ring]
        hi = [bm.verts.new((cx + (x - cx) * taper, cy + (y - cy) * taper, z + h)) for (x, y) in ring]
        for i in range(sides):
            j = (i + 1) % sides
            bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
        bm.faces.new(hi)                      # the top: a ledge, or the mesa's flat top
        # The top tier's cap: its centre and the radius inside it.
        inner = min(math.hypot(v.co.x - cx, v.co.y - cy) for v in hi) * math.cos(math.pi / sides)
        top = (cx, cy, inner)
        if t == 0:
            bm.faces.new(list(reversed(lo)))  # the foot (deep in the clouds, but closed)
        # The next tier: narrower, nudged off centre, so a ledge shows.
        z += h
        scale *= rng.uniform(0.84, 0.95) * taper
        dx = cx + rng.uniform(-0.18, 0.18)
        dy = cy + rng.uniform(-0.18, 0.18)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    # Centre on x/y (Blender's ground plane), base at z 0.
    xs = [v.co.x for v in bm.verts]; ys = [v.co.y for v in bm.verts]
    ox = (min(xs) + max(xs)) * 0.5; oy = (min(ys) + max(ys)) * 0.5
    for v in bm.verts:
        v.co.x -= ox; v.co.y -= oy
    top = (top[0] - ox, top[1] - oy, top[2])
    me = bpy.data.meshes.new("pillar_" + name)
    bm.to_mesh(me); bm.free()
    for p in me.polygons:
        p.use_smooth = False
    ob = bpy.data.objects.new("pillar_" + name, me)
    bpy.context.collection.objects.link(ob)
    return ob, top


def cone(bm, r, z0, z1, sides, turn):
    ring = [bm.verts.new((r * math.cos(turn + 2 * math.pi * i / sides), r * math.sin(turn + 2 * math.pi * i / sides), z0)) for i in range(sides)]
    apex = bm.verts.new((0.0, 0.0, z1))
    for i in range(sides):
        bm.faces.new((ring[i], ring[(i + 1) % sides], apex))
    bm.faces.new(list(reversed(ring)))


def tree(name):
    bm = bmesh.new()
    if name == "pine":
        cone(bm, 0.42, 0.0, 0.62, 6, 0.0)
        cone(bm, 0.3, 0.42, 1.0, 6, 0.5)
    else:
        bmesh.ops.create_cone(bm, cap_ends=True, segments=5, radius1=0.08, radius2=0.08, depth=0.4,
                              matrix=Matrix.Translation((0, 0, 0.2)))
        bmesh.ops.create_uvsphere(bm, u_segments=6, v_segments=4, radius=0.36,
                                  matrix=Matrix.Translation((0, 0, 0.64)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    me = bpy.data.meshes.new("tree_" + name)
    bm.to_mesh(me); bm.free()
    for p in me.polygons:
        p.use_smooth = False
    ob = bpy.data.objects.new("tree_" + name, me)
    bpy.context.collection.objects.link(ob)
    return ob


def export(ob, path):
    bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format='GLB', export_yup=True,
                              export_apply=True, export_materials='NONE', export_normals=True, export_texcoords=False)


bpy.ops.wm.read_factory_settings(use_empty=True)
sizes = {}
tops = {}
trees = {}
tris = {}
for (name, seed, tiers) in PIECES:
    ob, top = build(name, seed, tiers)
    d = ob.dimensions
    sizes[name] = [round(d.x, 4), round(d.z, 4), round(d.y, 4)]   # Godot's (x, y up, z)
    tops[name] = [round(top[0], 4), round(-top[1], 4), round(top[2], 4)]   # Godot's z is Blender's -y
    tris[name] = len(ob.data.polygons)
    export(ob, os.path.join(OUT, "pillar_%s.glb" % name))
for name in ["pine", "round"]:
    ob = tree(name)
    d = ob.dimensions
    trees[name] = [round(d.x, 4), round(d.z, 4), round(d.y, 4)]
    tris["tree_" + name] = len(ob.data.polygons)
    export(ob, os.path.join(OUT, "tree_%s.glb" % name))
json.dump({"sizes": sizes, "tops": tops, "trees": trees}, open(os.path.join(OUT, "kit.json"), "w"), indent=1)
print("MESAS DONE", OUT, "triangles", tris, "tops", tops, "trees", trees)
