"""Build original Keynest glass keys with Blender; never reads user vault data.

Run with Blender --background --factory-startup --python this-file -- [--render].
Only existing, attributed ProviderIcons PNGs are used for brand silhouettes.
"""
import argparse
from collections import defaultdict
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Euler, Vector

HERE = Path(__file__).resolve()
MACOS = HERE.parents[2]
OUT = MACOS / "Resources" / "KeychainArt"
ICONS = MACOS / "Resources" / "ProviderIcons"
PALETTES = {
    "ice": {"name": "冰蓝", "color": "96D4EF"},
    "lavender": {"name": "薰衣草", "color": "C4AFE7"},
    "mint": {"name": "薄荷", "color": "92D6C0"},
    "amber": {"name": "琥珀", "color": "E9B566"},
    "rose": {"name": "玫瑰", "color": "E7A9C4"},
    "graphite": {"name": "石墨", "color": "8A9AAC"},
}
BRAND_COLORS = {"openai": "344C57", "anthropic": "D97757", "google": "3186FF", "cloudflare": "F38020"}
BRAND_COLORS.update({"amap": "0085FE", "browserbase": "FF4500", "cartesia": "309D4B",
    "context7": "047857", "mem0": "9D7FCE", "twilio": "F22F46", "zep": "953BA9",
    "parallel": "30343A", "pinecone": "435567", "huggingface": "FFD21E"})


def rgba(hex_color):
    return tuple(int(hex_color[i:i + 2], 16) / 255 for i in (0, 2, 4)) + (1,)


def linear_rgba(hex_color):
    # Principled sockets use scene-linear values; the public manifest is sRGB.
    return tuple(v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4
                 for v in rgba(hex_color)[:3]) + (1,)


def material(name, color, metal=0, roughness=.16, transmission=0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = linear_rgba(color)
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["IOR"].default_value = 1.46
    bsdf.inputs["Transmission Weight"].default_value = transmission
    bsdf.inputs["Coat Weight"].default_value = .28
    bsdf.inputs["Coat Roughness"].default_value = .10
    mat.diffuse_color = linear_rgba(color)
    return mat


def curve_shape(name, contours, depth, bevel, mat, z=0, role="glass", bevel_segments=None):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "2D"
    curve.fill_mode = "BOTH"
    curve.resolution_u = 1
    curve.extrude = depth / 2 - bevel
    curve.bevel_depth = bevel
    curve.bevel_resolution = bevel_segments if bevel_segments is not None else (3 if role == "glass" else 1)
    for points in contours:
        spline = curve.splines.new("POLY")
        spline.points.add(len(points) - 1)
        for point, (x, y) in zip(spline.points, points):
            point.co = (x, y, 0, 1)
        spline.use_cyclic_u = True
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.location.z = z
    obj.data.materials.append(mat)
    obj["role"] = role
    return obj


def softened_polygon(vertices, radius=.08, steps=6):
    result = []
    for i, raw in enumerate(vertices):
        cur = Vector(raw)
        prev = Vector(vertices[i - 1])
        nxt = Vector(vertices[(i + 1) % len(vertices)])
        offset = min(radius, (prev - cur).length * .43, (nxt - cur).length * .43)
        start = cur + (prev - cur).normalized() * offset
        end = cur + (nxt - cur).normalized() * offset
        for j in range(steps + 1):
            t = j / steps
            p = (1 - t) ** 2 * start + 2 * (1 - t) * t * cur + t ** 2 * end
            result.append(tuple(p))
    return result


def bevel_cube(name, location, scale, mat, bevel=.02):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mod = obj.modifiers.new("Machined edge radius", "BEVEL")
    mod.width = bevel
    mod.segments = 4
    mod = obj.modifiers.new("Weighted metal normals", "WEIGHTED_NORMAL")
    mod.keep_sharp = True
    obj.data.materials.append(mat)
    obj["role"] = "metal"
    return obj


def torus(name, location, radius, thickness, mat):
    bpy.ops.mesh.primitive_torus_add(major_radius=radius, minor_radius=thickness,
        major_segments=48, minor_segments=8, location=location)
    obj = bpy.context.object
    obj.name = name
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    obj.data.materials.append(mat)
    obj["role"] = "metal"
    return obj


def make_body(glass, silver):
    # Runtime coordinates: right-handed, Y up, +Z faces the viewer. The outline
    # has no overlapping blocks: head and stem are one continuous glass solid.
    outline = softened_polygon([
        (-.32, 1.092), (-.532, .89), (-.532, .10), (-.34, -.115),
        (-.108, -.18), (-.108, -1.052), (.108, -1.052), (.108, -.18),
        (.34, -.115), (.532, .10), (.532, .89), (.32, 1.092)
    ], radius=.13, steps=6)
    # Outer contour is CCW; the clockwise hole is a genuine opening through Z.
    hole = [(math.cos(-2 * math.pi * i / 48) * .069,
             1 + math.sin(-2 * math.pi * i / 48) * .069) for i in range(48)]
    parts = [curve_shape("glass-continuous-body", [outline, hole], .28, .028, glass)]
    parts += [torus("connector-front-rim", (0, 1, .140), .082, .009, silver),
              torus("connector-back-rim", (0, 1, -.140), .082, .009, silver)]
    # Restrained metal teeth and inset spine leave most glass visible.
    parts += [bevel_cube("tooth-upper", (.151, -.67, 0), (.26, .14, .20), silver, .024),
              bevel_cube("tooth-lower", (.168, -.91, 0), (.29, .17, .20), silver, .025),
              bevel_cube("shaft-inset-front", (0, -.66, .143), (.055, .65, .021), silver, .01),
              bevel_cube("shaft-inset-back", (0, -.66, -.143), (.055, .65, .021), silver, .01)]
    return parts


def signed_area(points):
    return sum(points[i - 1][0] * p[1] - p[0] * points[i - 1][1] for i, p in enumerate(points)) / 2


def rdp(points, epsilon):
    if len(points) <= 2:
        return points
    start, end = np.array(points[0]), np.array(points[-1])
    delta = end - start
    length = np.linalg.norm(delta)
    if length == 0:
        distances = [np.linalg.norm(np.array(p) - start) for p in points]
    else:
        distances = [abs(delta[0] * (start[1] - p[1]) - delta[1] * (start[0] - p[0])) / length for p in points]
    index = int(np.argmax(distances))
    if distances[index] > epsilon:
        return rdp(points[:index + 1], epsilon)[:-1] + rdp(points[index:], epsilon)
    return [points[0], points[-1]]


def simplify_closed(points, epsilon=1.3):
    pivot = max(range(len(points)), key=lambda i: (points[i][0] - points[0][0]) ** 2 + (points[i][1] - points[0][1]) ** 2)
    result = rdp(points[:pivot + 1], epsilon)[:-1] + rdp(points[pivot:] + [points[0]], epsilon)[:-1]
    return result if len(result) >= 3 else points


def subpixel_contours(field, epsilon):
    """March the original antialiased threshold field, not pixel stair steps.

    Shared grid-edge identities keep adjacent cells watertight. The center
    field resolves diagonal ambiguity; the filled side determines winding so
    interior holes remain clockwise after simplification.
    """
    f = np.pad(field, 1, constant_values=-1)
    positive = f > 0
    cases = (positive[:-1, :-1].astype(int) + positive[:-1, 1:] * 2
             + positive[1:, 1:] * 4 + positive[1:, :-1] * 8)
    lookup = {1: [(3, 0)], 2: [(0, 1)], 3: [(3, 1)], 4: [(1, 2)],
              6: [(0, 2)], 7: [(3, 2)], 8: [(2, 3)], 9: [(2, 0)],
              11: [(1, 2)], 12: [(1, 3)], 13: [(0, 1)], 14: [(3, 0)]}
    graph, points = defaultdict(list), {}
    for y, x in zip(*np.nonzero((cases != 0) & (cases != 15))):
        code = int(cases[y, x])
        center = f[y:y + 2, x:x + 2].mean()
        if code == 5:
            pairs = [(3, 2), (0, 1)] if center > 0 else [(3, 0), (1, 2)]
        elif code == 10:
            pairs = [(0, 3), (1, 2)] if center > 0 else [(0, 1), (2, 3)]
        else:
            pairs = lookup[code]
        edge_keys = [("h", x, y), ("v", x + 1, y), ("h", x, y + 1), ("v", x, y)]
        for pair in pairs:
            keys = [edge_keys[i] for i in pair]
            for key in keys:
                if key not in points:
                    axis, xx, yy = key
                    dx, dy = (1, 0) if axis == "h" else (0, 1)
                    a, b = f[yy, xx], f[yy + dy, xx + dx]
                    t = float(a / (a - b))
                    points[key] = (float(xx + dx * t), float(yy + dy * t))
            graph[keys[0]].append(keys[1])
            graph[keys[1]].append(keys[0])

    def sample(x, y):
        x = max(0, min(float(f.shape[1] - 1.001), x))
        y = max(0, min(float(f.shape[0] - 1.001), y))
        xx, yy = int(x), int(y)
        dx, dy = x - xx, y - yy
        return ((1 - dx) * (1 - dy) * f[yy, xx] + dx * (1 - dy) * f[yy, xx + 1]
                + (1 - dx) * dy * f[yy + 1, xx] + dx * dy * f[yy + 1, xx + 1])

    contours = []
    while graph:
        start = next(iter(graph))
        previous, cursor, contour = None, start, []
        while True:
            contour.append(points[cursor])
            neighbors = graph[cursor]
            if len(neighbors) != 2:
                raise ValueError("Non-manifold marching contour")
            nxt = neighbors[0] if neighbors[0] != previous else neighbors[1]
            if previous is not None:
                del graph[previous]
            previous, cursor = cursor, nxt
            if cursor == start:
                del graph[previous]
                break
        if abs(signed_area(contour)) < 8:
            continue
        simplified = simplify_closed(contour, epsilon)
        # A short inward test on the longest contour segment is less sensitive
        # to tiny antialias noise than the first (arbitrary) marching cell.
        i = max(range(len(contour)), key=lambda k: sum((contour[k][j] - contour[k - 1][j]) ** 2 for j in (0, 1)))
        a, b = contour[i - 1], contour[i]
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy)
        if sample((a[0] + b[0]) / 2 - dy / length * .28,
                  (a[1] + b[1]) / 2 + dx / length * .28) < 0:
            simplified.reverse()
        contours.append(simplified)
    return contours


def extract_silhouette(data, provider):
    """Separate symbols from alpha, opaque favicon plates and known gradients.

    Explicit rules are tied to the attributed source SHA in the manifest. A
    broad alpha rectangle is never accepted silently as a brand silhouette.
    """
    alpha = data[:, :, 3]
    rgb = data[:, :, :3]
    opaque = alpha > .42
    rows, columns = np.nonzero(opaque)
    if not len(rows):
        raise ValueError(f"Empty input image: {provider}")
    cropped = opaque[rows.min():rows.max() + 1, columns.min():columns.max() + 1]
    opacity_coverage = float(cropped.mean())
    method = "alpha"
    field = alpha - .42
    if provider in {"browserbase", "cartesia", "context7", "pinecone", "twilio", "zep"}:
        # White marks on solid or gradient brand-color backgrounds.
        mask = opaque & (rgb.min(axis=2) > .64)
        field = np.minimum(field, rgb.min(axis=2) - .64)
        method = "light-symbol-on-brand-background"
    elif provider in {"kimi", "composio"}:
        mask = opaque & (rgb.max(axis=2) > .32)
        field = np.minimum(field, rgb.max(axis=2) - .32)
        method = "light-or-colored-symbol-on-black-background"
    elif provider in {"feishu", "serper"}:
        mask = opaque & (rgb.min(axis=2) < .68)
        field = np.minimum(field, .68 - rgb.min(axis=2))
        method = "colored-symbol-on-white-background"
    elif provider in {"mem0", "parallel"}:
        mask = opaque & (rgb.max(axis=2) < .40)
        field = np.minimum(field, .40 - rgb.max(axis=2))
        method = "dark-symbol-on-light-background"
    elif provider == "amap":
        mask = opaque & (rgb[:, :, 2] > rgb[:, :, 1] + .20) & (rgb[:, :, 2] > rgb[:, :, 0] + .35)
        field = np.minimum(field, np.minimum(rgb[:, :, 2] - rgb[:, :, 1] - .20, rgb[:, :, 2] - rgb[:, :, 0] - .35))
        method = "blue-arrow-on-multicolor-map-background"
    elif provider == "weaviate":
        mask = opaque & (rgb[:, :, 1] > .27) & (rgb[:, :, 1] > rgb[:, :, 2] * 1.2)
        field = np.minimum(field, np.minimum(rgb[:, :, 1] - .27, rgb[:, :, 1] - rgb[:, :, 2] * 1.2))
        method = "green-yellow-symbol-on-indigo-background"
    elif provider == "huggingface":
        mask = opaque & (rgb.max(axis=2) > .40)
        field = np.minimum(field, rgb.max(axis=2) - .40)
        method = "alpha-with-dark-face-detail-cutouts"
    elif opacity_coverage > .92:
        # General fallback uses the occupied image bounds, not transparent
        # padding or only the four corners (Cartesia has a transparent rim).
        low_y, high_y, low_x, high_x = rows.min(), rows.max(), columns.min(), columns.max()
        yy, xx = np.indices(opaque.shape)
        border = opaque & ((yy < low_y + 8) | (yy > high_y - 8) | (xx < low_x + 8) | (xx > high_x - 8))
        background = np.median(rgb[border], axis=0)
        mask = opaque & (np.linalg.norm(rgb - background, axis=2) > .20)
        field = np.minimum(field, np.linalg.norm(rgb - background, axis=2) - .20)
        method = "opaque-bounds-border-background-subtraction"
    else:
        mask = opaque
    rows, columns = np.nonzero(mask)
    if len(rows) < 24:
        raise ValueError(f"No usable symbol after background separation: {provider}")
    occupied_coverage = float(mask[rows.min():rows.max() + 1, columns.min():columns.max() + 1].mean())
    if occupied_coverage > .94:
        raise ValueError(f"Refusing solid rectangular brand plate: {provider} ({occupied_coverage:.3f})")
    return mask, {"method": method, "sourceOpaqueCoverage": round(opacity_coverage, 6),
                  "silhouetteBoundingBoxCoverage": round(occupied_coverage, 6)}, field


def logo_from_png(path, mat):
    image = bpy.data.images.load(str(path), check_existing=False)
    resolution = min(640, max(512, image.size[0], image.size[1]))
    image.scale(resolution, resolution)
    data = np.array(image.pixels[:], dtype=np.float32).reshape(resolution, resolution, 4)
    mask, extraction, field = extract_silhouette(data, path.stem)
    extraction["samplingResolution"] = resolution
    extraction["tracing"] = "subpixel-isocontour"
    extraction["simplificationTolerancePixels"] = resolution * .00125
    mask_image = bpy.data.images.new(f"QA silhouette {path.stem}", width=resolution, height=resolution, alpha=True)
    mask_pixels = np.zeros_like(data)
    mask_pixels[:, :, :3] = .13
    mask_pixels[:, :, 3] = mask
    mask_image.pixels.foreach_set(mask_pixels.reshape(-1))
    mask_image.filepath_raw = str(OUT / "previews" / "masks" / f"{path.stem}.png")
    mask_image.file_format = "PNG"
    mask_image.save()
    bpy.data.images.remove(mask_image)
    contours = subpixel_contours(field, resolution * .00125)
    if not contours:
        raise ValueError(f"Empty brand silhouette: {path.name}")
    all_points = np.array([p for contour in contours for p in contour])
    low, high = all_points.min(axis=0), all_points.max(axis=0)
    center = (low + high) / 2
    scale = .64 / max(high - low)
    transformed = [[((x - center[0]) * scale, .43 + (y - center[1]) * scale) for x, y in contour] for contour in contours]
    obj = curve_shape(f"brand-{path.stem}-relief", transformed, .038, .0025, mat, z=.167, role="logo")
    foreground = data[mask, :3]
    saturation = foreground.max(axis=1) - foreground.min(axis=1)
    colored = foreground[saturation > .15]
    color = "415A68"
    if len(colored) > len(foreground) * .05:
        # Quantized dominant colored cluster avoids blending a multi-color mark
        # into mud. Monochrome artwork gets a legible dark enamel finish.
        buckets = np.round(colored * 7).astype(int)
        unique, counts = np.unique(buckets, axis=0, return_counts=True)
        dominant = unique[np.argmax(counts)]
        selected = colored[np.all(buckets == dominant, axis=1)]
        rgb = np.median(selected, axis=0)
        color = "".join(f"{int(round(float(v) * 255)):02X}" for v in rgb)
    bpy.data.images.remove(image)
    return obj, len(contours), BRAND_COLORS.get(path.stem, color), extraction


def mesh_document(objects):
    result = {"schemaVersion": 1, "coordinateSystem": "right-handed-y-up-front-positive-z",
              "anchor": [0, 1, 0], "meshes": []}
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for obj in objects:
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        mesh.calc_loop_triangles()
        transform = obj.matrix_world
        normal_transform = transform.to_3x3().inverted().transposed()
        positions, normals, indices, lookup = [], [], [], {}
        for triangle in mesh.loop_triangles:
            tri_positions = [transform @ mesh.vertices[mesh.loops[i].vertex_index].co for i in triangle.loops]
            rounded_positions = [Vector(tuple(round(float(v), 6) for v in p)) for p in tri_positions]
            if (rounded_positions[1] - rounded_positions[0]).cross(rounded_positions[2] - rounded_positions[0]).length_squared < 1e-18:
                continue  # Curve tessellation can emit collinear filler triangles.
            for loop_index in triangle.loops:
                loop = mesh.loops[loop_index]
                p = transform @ mesh.vertices[loop.vertex_index].co
                n = (normal_transform @ mesh.corner_normals[loop_index].vector).normalized()
                packed = tuple(round(float(v), 6) for v in (*p, *n))
                if not all(math.isfinite(v) for v in packed):
                    raise ValueError("Non-finite export")
                if packed not in lookup:
                    lookup[packed] = len(lookup)
                    positions.extend(packed[:3])
                    normals.extend(packed[3:])
                indices.append(lookup[packed])
        result["meshes"].append({"name": obj.name, "role": obj.get("role", "metal"),
            "positions": positions, "normals": normals, "indices": indices})
        evaluated.to_mesh_clear()
    return result


def make_charm(provider, source_logo, color, silver):
    # A brand charm is its actual filled silhouette, with the source cutouts.
    # No key body, backing plaque, texture plane or rectangular frame is added.
    scale = 1.35 / .64
    contours = [[(p.co.x * scale, (p.co.y - .43) * scale + .12)
                 for p in spline.points] for spline in source_logo.data.splines]
    top_offset = .795 - max(y for contour in contours for x, y in contour)
    contours = [[(x, y + top_offset) for x, y in contour] for contour in contours]
    mat = material(f"Charm {provider} polished enamel", color, metal=.06, roughness=.22)
    body = curve_shape(f"charm-{provider}-glass-relief", contours, .22, 0,
                       mat, role="logo", bevel_segments=0)
    # Bevel an actual solid inward; Curve bevel expands the 2-D contour and
    # incorrectly thickens strokes/narrows holes. Cap normals stay planar.
    evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = bpy.data.meshes.new_from_object(evaluated)
    welded = bmesh.new()
    welded.from_mesh(mesh)
    bmesh.ops.remove_doubles(welded, verts=list(welded.verts), dist=.000001)
    bmesh.ops.recalc_face_normals(welded, faces=list(welded.faces))
    welded.to_mesh(mesh)
    welded.free()
    body_name = body.name
    bpy.data.objects.remove(body, do_unlink=True)
    body = bpy.data.objects.new(body_name, mesh)
    bpy.context.collection.objects.link(body)
    body["role"] = "logo"
    for polygon in body.data.polygons:
        polygon.use_smooth = abs(polygon.normal.z) < .9
    bevel = body.modifiers.new("Inward micro bevel", "BEVEL")
    bevel.width, bevel.segments = .014, 3
    bevel.limit_method, bevel.angle_limit = "ANGLE", math.radians(28)
    bevel.use_clamp_overlap = True
    bevel.harden_normals = True
    bevel.affect = "EDGES"
    top = max(y for contour in contours for x, y in contour)
    # Use the silhouette's actual uppermost point as the attachment. An angled
    # short silver neck reaches the centered suspension loop without filling
    # any logo holes (e.g. OpenAI's knot or Cloudflare's offset cloud crest).
    top_points = [(x, y) for contour in contours for x, y in contour if y > top - .018]
    attachment_x = min(top_points, key=lambda p: abs(p[0]))[0]
    start, end = Vector((attachment_x, top + .004, 0)), Vector((0, .90, 0))
    direction = end - start
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=.024, depth=direction.length,
                                       location=(start + end) / 2)
    neck = bpy.context.object
    neck.name = f"charm-{provider}-attachment"
    neck.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
    neck.data.materials.append(silver)
    neck["role"] = "metal"
    for face in neck.data.polygons:
        face.use_smooth = True
    loop = torus(f"charm-{provider}-suspension-ring", (0, 1, 0), .113, .018, silver)
    return [body, neck, loop]


def write_mesh(path, objects):
    document = mesh_document(objects)
    path.write_text(json.dumps(document, separators=(",", ":"), ensure_ascii=False) + "\n")
    count = sum(len(m["indices"]) // 3 for m in document["meshes"])
    return count


def point_light(name, position, energy, size, target, color=(1, 1, 1)):
    data = bpy.data.lights.new(name, "AREA")
    data.energy, data.shape, data.size = energy, "DISK", size
    data.color = color
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.location = position
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()
    return obj


def setup_render():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 10
    scene.cycles.transmission_bounces = 8
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "AgX"
    scene.world.color = (.4, .4, .4)
    scene.world.use_nodes = True
    scene.world.node_tree.nodes.get("Background").inputs["Color"].default_value = (.72, .80, .88, 1)
    scene.world.node_tree.nodes.get("Background").inputs["Strength"].default_value = .35
    backdrop = material("Studio warm-white matte", "E7EDF2", roughness=.68)
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.42))
    floor = bpy.context.object
    floor.name = "preview-only-backdrop"
    floor.data.materials.append(backdrop)
    point_light("Studio key softbox", (-3, 4, 5), 500, 4, (0, 0, 0))
    point_light("Studio cool edge", (4, 1, 3), 330, 2, (0, 0, 0), (.77, .89, 1))
    point_light("Studio long rim", (-2, -3, 2), 190, 2, (0, 0, 0))
    camera_data = bpy.data.cameras.new("Preview camera")
    camera = bpy.data.objects.new("Preview camera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera_data.type = "ORTHO"
    rotation = Euler((math.radians(14), math.radians(-18), math.radians(-6)), "XYZ")
    camera.rotation_euler = rotation
    camera.location = Vector((0, 0, 0)) + rotation.to_matrix() @ Vector((0, 0, 8))
    scene.camera = camera
    return camera


def render(path, camera, width, height, scale):
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = width, height
    camera.data.ortho_scale = scale
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def duplicate_key(parts, logo, name, location, color, angle=0):
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    root.location = location
    root.rotation_euler.z = angle
    glass = material(f"Glass {name}", color, roughness=.105, transmission=1)
    for original in parts + ([logo] if logo else []):
        obj = original.copy()
        obj.data = original.data.copy()
        bpy.context.collection.objects.link(obj)
        obj.hide_render = False
        obj.hide_viewport = False
        obj.parent = root
        if obj.get("role") == "glass":
            obj.data.materials.clear()
            obj.data.materials.append(glass)
    return root


def duplicate_charm(parts, name, location, angle=0):
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    root.location = location
    root.rotation_euler = (math.radians(-3), math.radians(-8), angle)
    for original in parts:
        obj = original.copy()
        obj.data = original.data.copy()
        bpy.context.collection.objects.link(obj)
        obj.hide_render = False
        obj.hide_viewport = False
        obj.parent = root
    return root


def main():
    global OUT
    parser = argparse.ArgumentParser()
    parser.add_argument("--render", action="store_true")
    parser.add_argument("--render-charms", action="store_true", help="Render only the independent brand contact sheet")
    parser.add_argument("--quality-study", action="store_true", help="Build four sample brands into previews/quality-study only")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    if args.quality_study:
        OUT = OUT / "previews" / "quality-study"
    for directory in (OUT, OUT / "logos", OUT / "charms", OUT / "source", OUT / "previews", OUT / "previews" / "masks"):
        directory.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    glass = material("Glass ice — recolorable", PALETTES["ice"]["color"], roughness=.105, transmission=1)
    silver = material("Brushed platinum", "BFC9D2", metal=.92, roughness=.21)
    parts = make_body(glass, silver)
    triangle_count = write_mesh(OUT / "glass-key-v1.mesh.json", parts)
    print(f"KEYNEST_BASE_READY {OUT / 'glass-key-v1.mesh.json'} triangles={triangle_count}", flush=True)
    if triangle_count > 11000:
        raise ValueError(f"Base exceeds triangle budget: {triangle_count}")
    logos, charms = {}, {}
    manifest = {"schemaVersion": 1, "generator": f"Blender {bpy.app.version_string}",
        "model": "glass-key-v1.mesh.json", "anchor": [0, 1, 0], "logoCenter": [0, .43, .167],
        "dimensions": [1.12, 2.2, .308], "baseTriangles": triangle_count,
        "materials": {"glass": {"metalness": 0, "roughness": .105, "ior": 1.46, "transmission": 1},
                      "metal": {"color": "BFC9D2", "metalness": .92, "roughness": .21},
                      "logo": {"metalness": .15, "roughness": .20}},
        "colorSpace": "sRGB",
        "charmProfile": {"thickness": .22, "bevel": .014, "bevelMethod": "inward-solid-edge"},
        "charmMaterials": {"logo": {"metalness": .06, "roughness": .22, "ior": 1.46, "transmission": 0, "coat": .28}},
        "palettes": PALETTES, "providers": {}}
    for path in sorted(ICONS.glob("*.png")):
        if args.quality_study and path.stem not in {"openai", "anthropic", "google", "cloudflare"}:
            continue
        color = BRAND_COLORS.get(path.stem, "415A68")
        logo_material = material(f"Brand {path.stem} enamel", color, metal=.15, roughness=.20)
        logo, contour_count, color, extraction = logo_from_png(path, logo_material)
        logo_material.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = linear_rgba(color)
        logo_material.diffuse_color = linear_rgba(color)
        count = write_mesh(OUT / "logos" / f"{path.stem}.mesh.json", [logo])
        if count + triangle_count > 15000:
            raise ValueError(f"Triangle budget exceeded for {path.stem}: {count + triangle_count}")
        logos[path.stem] = logo
        charm_parts = make_charm(path.stem, logo, color, silver)
        charm_count = write_mesh(OUT / "charms" / f"{path.stem}.mesh.json", charm_parts)
        if charm_count >= 15000:
            raise ValueError(f"Charm exceeds triangle budget: {path.stem} {charm_count}")
        charms[path.stem] = charm_parts
        for obj in charm_parts:
            obj.hide_render = True
            obj.hide_viewport = True
        if path.stem == "openai":
            print(f"KEYNEST_CHARM_READY {OUT / 'charms' / 'openai.mesh.json'} triangles={charm_count}", flush=True)
        manifest["providers"][path.stem] = {"mesh": f"logos/{path.stem}.mesh.json", "color": color,
            "charm": f"charms/{path.stem}.mesh.json", "charmTriangles": charm_count,
            "rgba": [round(v, 6) for v in rgba(color)],
            "extraction": extraction,
            "triangles": count, "contours": contour_count, "source": f"../ProviderIcons/{path.name}",
            "sourceSHA256": hashlib.sha256(path.read_bytes()).hexdigest()}
        logo.hide_render = True
        logo.hide_viewport = True
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    for obj in parts:
        obj.hide_render = True
        obj.hide_viewport = True
    camera = setup_render()
    # A separate collection of authored geometry remains in the source .blend.
    hero = duplicate_key(parts, None, "Hero generic ice key", (0, 0, .03), PALETTES["ice"]["color"], math.radians(-9))
    bpy.context.scene.render.resolution_x = 900
    bpy.context.scene.render.resolution_y = 1100
    camera.data.ortho_scale = 2.95
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "source" / "glass-key-v1.blend"), compress=True)
    print(f"KEYNEST_ASSETS_READY providers={len(logos)} baseTriangles={triangle_count}", flush=True)
    if args.render:
        render(OUT / "previews" / "generic-ice-key.png", camera, 900, 1100, 2.95)
    for child in hero.children:
        child.hide_render = True
    palette_roots = []
    if args.render:
        for i, (palette_id, palette) in enumerate(PALETTES.items()):
            x, y = (i % 3 - 1) * 1.8, (.5 - i // 3) * 2.75
            root = duplicate_key(parts, None,
                f"Palette {palette_id}", (x, y, 0), palette["color"], math.radians((-7, 4, -4)[i % 3]))
            palette_roots.append(root)
    camera.rotation_euler = (math.radians(8), math.radians(-12), 0)
    camera.location = camera.rotation_euler.to_matrix() @ Vector((0, 0, 10))
    if args.render:
        render(OUT / "previews" / "six-colors.png", camera, 1500, 1500, 6.2)
    for root in palette_roots:
        for child in root.children:
            child.hide_render = True
    for i, provider in enumerate(("openai", "anthropic", "google", "cloudflare")):
        duplicate_charm(charms[provider], f"Independent brand charm {provider}",
            ((i - 1.5) * 1.85, 0, .03), math.radians(-5 + i * 3))
    camera.data.ortho_scale = 8.4
    bpy.context.scene.render.resolution_x = 2000
    bpy.context.scene.render.resolution_y = 850
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "source" / "brand-charms-v1.blend"), compress=True)
    if args.render or args.render_charms:
        render(OUT / "previews" / "four-brand-charms.png", camera, 2000, 850, 8.4)
        print("KEYNEST_RENDERS_READY", flush=True)


if __name__ == "__main__":
    main()
