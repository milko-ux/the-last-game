#!/usr/bin/env python3
"""Decimate the prop models for the web build (Phase A brief 4).

The GLBs Milko drops in assets/models/ are ~30k triangles each; a busy bar
would draw hundreds of thousands. This makes a lighter copy of each in
assets/models/lod/ with the UVs (and so the baked texture) preserved, so the
game scenes reference the light copy and the originals stay untouched.

    python3 tools/decimate_models.py            # all, to the budgets below
    python3 tools/decimate_models.py slammer    # one

Needs: pip install trimesh fast_simplification

Method: plain quadric decimation (fast_simplification), then every new
vertex takes the baked texture's COLOUR at the closest point on the
ORIGINAL surface, stored as a vertex colour. No UVs, no texture in the
light copy: the image-to-3D bakes are hundreds of tiny UV islands, so
re-projected UVs shatter (tried), and the texture-aware decimator
(pymeshlab) refuses to collapse across islands and stops at 3-4x (tried).
The clay is near-uniform, so vertex colour keeps what matters (the dark
eye recesses are geometry); the shaders add their own grain.
"""
import os
import sys
import tempfile

import fast_simplification
import numpy as np
import trimesh

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "assets", "models")
DST = os.path.join(SRC, "lod")

# Triangle budgets. Hazards are near and few.
BUDGET = {
    "gate_pillar": 4000,
    "sweeper_segment": 2000,
    "slammer": 3500,
    "orbiter_pillar": 3500,
    "volley_emitter": 3500,
}

# The buildings (2026-09-20): GEOMETRY ONLY, no colours from the bake (the
# rule is no AI image textures in the game; their material is procedural,
# see props.gd BUILDING_SHADER). Two copies each: the near one keeps the
# carved symbols and the recessed circle as geometry (they ARE geometry in
# the source: checked with an untextured render; at 1.5k they were mush,
# at 6k they read cleanly), the far one is what the fog carries.
# output name -> (source model, triangles)
GEOMETRY_ONLY = {
    "building_tall_hi": ("building_tall", 6000),
    "building_tall": ("building_tall", 1500),
    "building_stacked_hi": ("building_stacked", 6000),
    "building_stacked": ("building_stacked", 1800),
}


def _weld_and_simplify(mesh, target):
    # The bakes split every vertex on a UV-island border; decimating that
    # opens a crack at every island. Weld first (positions only).
    welded = trimesh.Trimesh(vertices=mesh.vertices, faces=mesh.faces, process=False)
    welded.merge_vertices(merge_tex=True, merge_norm=True)
    v0 = np.asarray(welded.vertices, dtype=np.float64)
    f0 = np.asarray(welded.faces, dtype=np.int64)
    reduction = 1.0 - min(1.0, target / float(len(f0)))
    return fast_simplification.simplify(v0, f0, target_reduction=reduction)


def decimate_geometry(out_name: str, src_name: str, target: int) -> None:
    scene = trimesh.load(os.path.join(SRC, src_name + ".glb"), force="scene")
    mesh = list(scene.geometry.values())[0]
    v, f = _weld_and_simplify(mesh, target)
    result = trimesh.Trimesh(vertices=v, faces=f, process=False)
    trimesh.repair.fix_winding(result)
    trimesh.repair.fix_normals(result)
    result.vertex_normals
    os.makedirs(DST, exist_ok=True)
    dst = os.path.join(DST, out_name + ".glb")
    result.export(dst)
    print(f"{out_name}: {len(mesh.faces)} -> {len(f)} triangles, geometry only  ({os.path.getsize(dst) // 1024} KB)")


def decimate(name: str, target: int) -> None:
    src = os.path.join(SRC, name + ".glb")
    scene = trimesh.load(src, force="scene")
    geoms = list(scene.geometry.values())
    if len(geoms) != 1:
        raise SystemExit(f"{name}: expected one mesh, found {len(geoms)}")
    mesh = geoms[0]
    uv = mesh.visual.uv
    image = mesh.visual.material.baseColorTexture if hasattr(mesh.visual.material, "baseColorTexture") else mesh.visual.material.image

    v, f = _weld_and_simplify(mesh, target)
    # Vertex colours: the texture at the closest point of the original surface.
    closest, _dist, tri = trimesh.proximity.closest_point(mesh, v)
    bary = trimesh.triangles.points_to_barycentric(mesh.triangles[tri], closest)
    uv0 = np.asarray(uv, dtype=np.float64)
    t = np.einsum("ij,ijk->ik", bary, uv0[np.asarray(mesh.faces)[tri]])
    img = np.asarray(image.convert("RGB"))
    h, w = img.shape[:2]
    px = np.clip((t[:, 0] % 1.0) * (w - 1), 0, w - 1).astype(int)
    py = np.clip(((1.0 - t[:, 1]) % 1.0) * (h - 1), 0, h - 1).astype(int)
    colours = np.concatenate([img[py, px], np.full((len(v), 1), 255, dtype=np.uint8)], axis=1)
    result = trimesh.Trimesh(vertices=v, faces=f, process=False)
    trimesh.repair.fix_winding(result)
    trimesh.repair.fix_normals(result)
    result.vertex_normals  # computed and exported, so Godot does not flat-shade it
    result.visual = trimesh.visual.ColorVisuals(result, vertex_colors=colours)
    os.makedirs(DST, exist_ok=True)
    dst = os.path.join(DST, name + ".glb")
    result.export(dst)
    print(f"{name}: {len(mesh.faces)} -> {len(f)} triangles  ({os.path.getsize(dst) // 1024} KB)")


if __name__ == "__main__":
    names = sys.argv[1:] or list(BUDGET) + list(GEOMETRY_ONLY)
    for n in names:
        if n in GEOMETRY_ONLY:
            decimate_geometry(n, *GEOMETRY_ONLY[n])
        else:
            decimate(n, BUDGET[n])
