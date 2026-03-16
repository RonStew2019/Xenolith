"""
Generate a simple humanoid character as a .glTF file with skeleton and animation.
No external dependencies — just Python stdlib.

Author: Blufus the Code Puppy 🐶
"""
import struct
import json
import base64
import math


# ─── Skeleton Definition ─────────────────────────────────────────────────────
# (parent_bone, local_translation, world_position)
BONES = {
    "Hips":      (None,      (0, 0.85, 0),      (0, 0.85, 0)),
    "Spine":     ("Hips",    (0, 0.25, 0),      (0, 1.10, 0)),
    "Head":      ("Spine",   (0, 0.35, 0),      (0, 1.45, 0)),
    "ArmL":      ("Spine",   (-0.35, 0, 0),     (-0.35, 1.10, 0)),
    "ForearmL":  ("ArmL",    (0, -0.22, 0),     (-0.35, 0.88, 0)),
    "ArmR":      ("Spine",   (0.35, 0, 0),      (0.35, 1.10, 0)),
    "ForearmR":  ("ArmR",    (0, -0.22, 0),     (0.35, 0.88, 0)),
    "LegL":      ("Hips",    (-0.15, 0, 0),     (-0.15, 0.85, 0)),
    "ShinL":     ("LegL",    (0, -0.38, 0),     (-0.15, 0.47, 0)),
    "LegR":      ("Hips",    (0.15, 0, 0),      (0.15, 0.85, 0)),
    "ShinR":     ("LegR",    (0, -0.38, 0),     (0.15, 0.47, 0)),
}
BONE_ORDER = [
    "Hips", "Spine", "Head",
    "ArmL", "ForearmL", "ArmR", "ForearmR",
    "LegL", "ShinL", "LegR", "ShinR",
]

# ─── Body Parts: (center, radii, bone_name) ──────────────────────────────────
# shape: box uses half-extents, ellipsoid uses radii.
N_SEGMENTS = 14  # horizontal slices (around Y axis)
N_RINGS = 10     # vertical slices (pole to pole)

BODY_PARTS = [
    # ── Torso ──
    ("box",       (0, 0.88, 0),       (0.19, 0.11, 0.13), "Hips"),
    ("box",       (0, 1.03, 0),       (0.14, 0.04, 0.10), "Spine"),
    ("box",       (0, 1.21, 0),       (0.22, 0.14, 0.14), "Spine"),
    # ── Head ──
    ("ellipsoid", (0, 1.55, 0),       (0.12, 0.12, 0.12), "Head"),
    # ── Left arm: shoulder ball -> socketed upper arm -> elbow ball -> socketed forearm ──
    ("ellipsoid", (-0.42, 1.21, 0),   (0.05, 0.05, 0.05), "ArmL"),
    ("socketed",  (-0.42, 1.05, 0),   (0.05, 0.12),       "ArmL"),
    ("ellipsoid", (-0.42, 0.90, 0),   (0.04, 0.04, 0.04), "ForearmL"),
    ("socketed",  (-0.42, 0.74, 0),   (0.045, 0.12),      "ForearmL"),
    # ── Right arm ──
    ("ellipsoid", (0.42, 1.21, 0),    (0.05, 0.05, 0.05), "ArmR"),
    ("socketed",  (0.42, 1.05, 0),    (0.05, 0.12),       "ArmR"),
    ("ellipsoid", (0.42, 0.90, 0),    (0.04, 0.04, 0.04), "ForearmR"),
    ("socketed",  (0.42, 0.74, 0),    (0.045, 0.12),      "ForearmR"),
    # ── Left leg: hip ball -> socketed thigh -> knee ball -> socketed shin ──
    ("ellipsoid", (-0.12, 0.78, 0),   (0.06, 0.06, 0.06), "LegL"),
    ("socketed",  (-0.12, 0.58, 0),   (0.08, 0.16),       "LegL"),
    ("ellipsoid", (-0.12, 0.39, 0),   (0.05, 0.05, 0.05), "ShinL"),
    ("socketed",  (-0.12, 0.18, 0),   (0.07, 0.17),       "ShinL"),
    # ── Right leg ──
    ("ellipsoid", (0.12, 0.78, 0),    (0.06, 0.06, 0.06), "LegR"),
    ("socketed",  (0.12, 0.58, 0),    (0.08, 0.16),       "LegR"),
    ("ellipsoid", (0.12, 0.39, 0),    (0.05, 0.05, 0.05), "ShinR"),
    ("socketed",  (0.12, 0.18, 0),    (0.07, 0.17),       "ShinR"),
]

# Face definitions: (normal, 4 corner signs)
BOX_FACES = [
    ((0, 0, 1),  [(-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]),
    ((0, 0, -1), [(1, -1, -1), (-1, -1, -1), (-1, 1, -1), (1, 1, -1)]),
    ((0, 1, 0),  [(-1, 1, 1), (1, 1, 1), (1, 1, -1), (-1, 1, -1)]),
    ((0, -1, 0), [(-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1)]),
    ((1, 0, 0),  [(1, -1, 1), (1, -1, -1), (1, 1, -1), (1, 1, 1)]),
    ((-1, 0, 0), [(-1, -1, -1), (-1, -1, 1), (-1, 1, 1), (-1, 1, -1)]),
]


def make_box(center, half_extents):
    """Generate verts, normals, and indices for an axis-aligned box."""
    cx, cy, cz = center
    hx, hy, hz = half_extents
    positions, normals, indices = [], [], []

    for normal, corners in BOX_FACES:
        base = len(positions)
        for sx, sy, sz in corners:
            positions.append((cx + sx * hx, cy + sy * hy, cz + sz * hz))
            normals.append(normal)
        indices.extend([base, base + 1, base + 2, base, base + 2, base + 3])

    return positions, normals, indices


def make_ellipsoid(center, radii, n_seg=N_SEGMENTS, n_ring=N_RINGS):
    """Generate an ellipsoid mesh centered at `center` with given (rx, ry, rz) radii.

    Uses a standard UV-sphere topology: pole vertices + ring strips.
    Normals are analytically correct for ellipsoid surfaces.
    """
    cx, cy, cz = center
    rx, ry, rz = radii
    positions, normals, indices = [], [], []

    # ── Vertices: top pole, ring bands, bottom pole ───────────────
    positions.append((cx, cy + ry, cz))
    normals.append((0.0, 1.0, 0.0))

    for i in range(1, n_ring):
        phi = math.pi * i / n_ring
        sp, cp = math.sin(phi), math.cos(phi)
        for j in range(n_seg):
            theta = 2.0 * math.pi * j / n_seg
            # Unit-sphere direction
            ux, uy, uz = sp * math.cos(theta), cp, sp * math.sin(theta)
            positions.append((cx + rx * ux, cy + ry * uy, cz + rz * uz))
            # Ellipsoid normal: gradient of (x/rx)^2+(y/ry)^2+(z/rz)^2
            nx, ny, nz = ux / rx, uy / ry, uz / rz
            inv_len = 1.0 / math.sqrt(nx * nx + ny * ny + nz * nz)
            normals.append((nx * inv_len, ny * inv_len, nz * inv_len))

    positions.append((cx, cy - ry, cz))
    normals.append((0.0, -1.0, 0.0))

    # ── Indices: top fan, quad strips, bottom fan ─────────────────
    for j in range(n_seg):
        indices.extend([0, 1 + j, 1 + (j + 1) % n_seg])

    for i in range(n_ring - 2):
        for j in range(n_seg):
            cur = 1 + i * n_seg + j
            nxt = 1 + i * n_seg + (j + 1) % n_seg
            below = cur + n_seg
            nxt_below = nxt + n_seg
            indices.extend([cur, below, nxt_below, cur, nxt_below, nxt])

    bottom = len(positions) - 1
    ring_start = 1 + (n_ring - 2) * n_seg
    for j in range(n_seg):
        indices.extend([bottom, ring_start + (j + 1) % n_seg, ring_start + j])

    return positions, normals, indices


def make_revolved_profile(center, profile, n_seg=N_SEGMENTS):
    """Surface of revolution from a list of (y_offset, radius) points.

    Generates a closed mesh by revolving the profile around the Y axis.
    Handles r~0 poles at tips. Normals derived analytically from the
    profile tangent — correct for any single-valued r(y) profile.
    """
    cx, cy, cz = center
    positions, normals, indices = [], [], []
    ring_info = []  # (start_vertex_index, is_pole)

    for pi, (y_off, r) in enumerate(profile):
        start = len(positions)
        is_pole = r < 1e-6
        ring_info.append((start, is_pole))

        if is_pole:
            positions.append((cx, cy + y_off, cz))
            ny = -1.0 if pi < len(profile) // 2 else 1.0
            normals.append((0.0, ny, 0.0))
        else:
            # Profile derivative dr/dy via central (or one-sided) differences
            if 0 < pi < len(profile) - 1:
                dr = profile[pi + 1][1] - profile[pi - 1][1]
                dy = profile[pi + 1][0] - profile[pi - 1][0]
            elif pi == 0:
                dr = profile[1][1] - r
                dy = profile[1][0] - y_off
            else:
                dr = r - profile[-2][1]
                dy = y_off - profile[-2][0]

            dr_dy = dr / dy if abs(dy) > 1e-10 else 0.0
            denom = math.sqrt(1.0 + dr_dy * dr_dy)
            n_r = 1.0 / denom
            n_y = -dr_dy / denom

            for j in range(n_seg):
                theta = 2.0 * math.pi * j / n_seg
                ct, st = math.cos(theta), math.sin(theta)
                positions.append((cx + r * ct, cy + y_off, cz + r * st))
                normals.append((n_r * ct, n_y, n_r * st))

    # Connect adjacent rings with triangles
    for pi in range(len(profile) - 1):
        s0, p0 = ring_info[pi]
        s1, p1 = ring_info[pi + 1]

        if p0 and p1:
            continue
        elif p0:  # bottom pole -> ring
            for j in range(n_seg):
                nj = (j + 1) % n_seg
                indices.extend([s0, s1 + j, s1 + nj])
        elif p1:  # ring -> top pole
            for j in range(n_seg):
                nj = (j + 1) % n_seg
                indices.extend([s1, s0 + nj, s0 + j])
        else:  # ring -> ring quad strip
            for j in range(n_seg):
                nj = (j + 1) % n_seg
                indices.extend([s0 + j, s1 + j, s1 + nj])
                indices.extend([s0 + j, s1 + nj, s0 + nj])

    return positions, normals, indices


def make_socketed_limb(center, dims, n_seg=N_SEGMENTS, socket_inset=0.9):
    """Cylinder with concave dished end caps that cup floating ball joints.

    dims = (body_radius, half_height).
    Each end has a spherical dish recessed into the cylinder so ball joints
    nestle into concave sockets.  The dish radius is smaller than the
    cylinder body by `socket_inset`, creating a gentle shoulder where the
    constant-radius tube meets each socket.

    socket_inset: dish-rim radius as a fraction of body radius (< 1.0).
    """
    R, H = dims
    depth = min(0.04, H * 0.25)  # how deep each dish recesses
    n_cap = 5                     # profile rings per dish
    R_sock = R * socket_inset     # dish rim radius (narrower than cylinder)

    cx, cy, cz = center
    positions, normals, indices = [], [], []
    ring_info = []  # (start_vertex_index, is_pole)

    def _pole(y_off, ny):
        ring_info.append((len(positions), True))
        positions.append((cx, cy + y_off, cz))
        normals.append((0.0, ny, 0.0))

    def _ring(y_off, r, nr, ny):
        ring_info.append((len(positions), False))
        for j in range(n_seg):
            theta = 2.0 * math.pi * j / n_seg
            ct, st = math.cos(theta), math.sin(theta)
            positions.append((cx + r * ct, cy + y_off, cz + r * st))
            normals.append((nr * ct, ny, nr * st))

    # ── Bottom dish: pole (recessed inside cylinder) → rim ──
    # Profile: r(α) = R_sock·sin α,  y(α) = −H + depth·cos α,  α ∈ [0, π/2]
    # Interior-surface normal (faces down toward ball joint below):
    #   n_r ∝  dy/dα = −depth·sin α  (inward)
    #   n_y ∝ −dr/dα = −R_sock·cos α  (downward)
    _pole(-H + depth, -1.0)
    for i in range(1, n_cap + 1):
        a = i / n_cap * math.pi / 2
        r = R_sock * math.sin(a)
        y_off = -H + depth * math.cos(a)
        mag = math.sqrt(depth**2 * math.sin(a)**2 + R_sock**2 * math.cos(a)**2)
        _ring(y_off, r, -depth * math.sin(a) / mag, -R_sock * math.cos(a) / mag)

    # ── Cylinder body (constant full radius, outward normals) ──
    n_cyl = max(2, int(2.0 * H / 0.04))
    for ci in range(1, n_cyl):
        _ring(-H + ci / n_cyl * 2.0 * H, R, 1.0, 0.0)

    # ── Top dish: rim → pole (recessed inside cylinder) ──
    # Profile: r(α) = R_sock·cos α,  y(α) = H − depth·sin α,  α ∈ [0, π/2]
    # Interior-surface normal (faces up toward ball joint above):
    #   n_r ∝  dy/dα = −depth·cos α  (inward)
    #   n_y ∝ −dr/dα =  R_sock·sin α  (upward)
    for i in range(n_cap):
        a = i / n_cap * math.pi / 2
        r = R_sock * math.cos(a)
        y_off = H - depth * math.sin(a)
        mag = math.sqrt(depth**2 * math.cos(a)**2 + R_sock**2 * math.sin(a)**2)
        _ring(y_off, r, -depth * math.cos(a) / mag, R_sock * math.sin(a) / mag)
    _pole(H - depth, 1.0)

    # ── Triangulation (same topology as make_revolved_profile) ──
    for ri in range(len(ring_info) - 1):
        s0, p0 = ring_info[ri]
        s1, p1 = ring_info[ri + 1]
        if p0 and p1:
            continue
        elif p0:
            for j in range(n_seg):
                nj = (j + 1) % n_seg
                indices.extend([s0, s1 + j, s1 + nj])
        elif p1:
            for j in range(n_seg):
                nj = (j + 1) % n_seg
                indices.extend([s1, s0 + nj, s0 + j])
        else:
            for j in range(n_seg):
                nj = (j + 1) % n_seg
                indices.extend([s0 + j, s1 + j, s1 + nj])
                indices.extend([s0 + j, s1 + nj, s0 + nj])

    return positions, normals, indices



def quat_from_axis_angle(axis, angle_rad):
    """Quaternion (x, y, z, w) from axis-angle."""
    s = math.sin(angle_rad / 2)
    return (axis[0] * s, axis[1] * s, axis[2] * s, math.cos(angle_rad / 2))


# ─── Buffer Packing Helpers ──────────────────────────────────────────────────

class BufferBuilder:
    """Accumulates binary data, buffer views, and accessors for a glTF."""

    def __init__(self):
        self.buf = bytearray()
        self.views = []
        self.accessors = []

    def _align(self):
        while len(self.buf) % 4:
            self.buf.append(0)

    def add_view(self, data: bytes, target=None):
        self._align()
        idx = len(self.views)
        view = {"buffer": 0, "byteOffset": len(self.buf), "byteLength": len(data)}
        if target:
            view["target"] = target
        self.views.append(view)
        self.buf.extend(data)
        return idx

    def add_accessor(self, view_idx, comp_type, count, acc_type, min_v=None, max_v=None):
        idx = len(self.accessors)
        acc = {
            "bufferView": view_idx,
            "componentType": comp_type,
            "count": count,
            "type": acc_type,
        }
        if min_v is not None:
            acc["min"] = min_v
        if max_v is not None:
            acc["max"] = max_v
        self.accessors.append(acc)
        return idx

    def finalize(self):
        self._align()
        return bytes(self.buf)


# ─── Constants ────────────────────────────────────────────────────────────────
FLOAT = 5126
USHORT = 5123
UBYTE = 5121
ARRAY_BUFFER = 34962
ELEMENT_ARRAY = 34963


def build_gltf():
    """Assemble the complete glTF dict with embedded binary buffer."""
    bb = BufferBuilder()

    # ── Combine all body parts into one mesh ──────────────────────
    all_pos, all_norm, all_idx = [], [], []
    all_joints, all_weights = [], []

    shape_fn = {"box": make_box, "ellipsoid": make_ellipsoid, "socketed": make_socketed_limb}
    for shape, center, dims, bone_name in BODY_PARTS:
        bone_idx = BONE_ORDER.index(bone_name)
        pos, norm, idx = shape_fn[shape](center, dims)
        offset = len(all_pos)
        all_pos.extend(pos)
        all_norm.extend(norm)
        all_idx.extend(i + offset for i in idx)
        all_joints.extend((bone_idx, 0, 0, 0) for _ in pos)
        all_weights.extend((1.0, 0.0, 0.0, 0.0) for _ in pos)

    # ── Pack mesh data ────────────────────────────────────────────
    pos_min = [min(p[i] for p in all_pos) for i in range(3)]
    pos_max = [max(p[i] for p in all_pos) for i in range(3)]

    pos_acc = bb.add_accessor(
        bb.add_view(b"".join(struct.pack("<3f", *p) for p in all_pos), ARRAY_BUFFER),
        FLOAT, len(all_pos), "VEC3", pos_min, pos_max,
    )
    norm_acc = bb.add_accessor(
        bb.add_view(b"".join(struct.pack("<3f", *n) for n in all_norm), ARRAY_BUFFER),
        FLOAT, len(all_norm), "VEC3",
    )
    idx_acc = bb.add_accessor(
        bb.add_view(b"".join(struct.pack("<H", i) for i in all_idx), ELEMENT_ARRAY),
        USHORT, len(all_idx), "SCALAR", [min(all_idx)], [max(all_idx)],
    )
    joint_acc = bb.add_accessor(
        bb.add_view(b"".join(struct.pack("<4B", *j) for j in all_joints), ARRAY_BUFFER),
        UBYTE, len(all_joints), "VEC4",
    )
    weight_acc = bb.add_accessor(
        bb.add_view(b"".join(struct.pack("<4f", *w) for w in all_weights), ARRAY_BUFFER),
        FLOAT, len(all_weights), "VEC4",
    )

    # ── Inverse bind matrices ─────────────────────────────────────
    ibm_bytes = bytearray()
    for name in BONE_ORDER:
        wx, wy, wz = BONES[name][2]
        ibm_bytes.extend(struct.pack(
            "<16f",
            1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  -wx, -wy, -wz, 1,
        ))
    ibm_acc = bb.add_accessor(bb.add_view(bytes(ibm_bytes)), FLOAT, len(BONE_ORDER), "MAT4")

    # ── Wave animation (right arm + head bob) ─────────────────────
    def pack_anim(times, rotations):
        t_acc = bb.add_accessor(
            bb.add_view(struct.pack(f"<{len(times)}f", *times)),
            FLOAT, len(times), "SCALAR", [min(times)], [max(times)],
        )
        r_acc = bb.add_accessor(
            bb.add_view(b"".join(struct.pack("<4f", *r) for r in rotations)),
            FLOAT, len(rotations), "VEC4",
        )
        return t_acc, r_acc

    arm_t, arm_r = pack_anim(
        [0.0, 0.3, 0.6, 0.9, 1.2],
        [
            quat_from_axis_angle((0, 0, 1), 0),
            quat_from_axis_angle((0, 0, 1), math.radians(-90)),
            quat_from_axis_angle((0, 0, 1), math.radians(-45)),
            quat_from_axis_angle((0, 0, 1), math.radians(-90)),
            quat_from_axis_angle((0, 0, 1), 0),
        ],
    )
    head_t, head_r = pack_anim(
        [0.0, 0.3, 0.6, 0.9, 1.2],
        [
            quat_from_axis_angle((0, 0, 1), 0),
            quat_from_axis_angle((0, 0, 1), math.radians(15)),
            quat_from_axis_angle((0, 0, 1), math.radians(-15)),
            quat_from_axis_angle((0, 0, 1), math.radians(15)),
            quat_from_axis_angle((0, 0, 1), 0),
        ],
    )

    # ── Node tree ─────────────────────────────────────────────────
    BONE_START = 2  # nodes 0=Root, 1=Mesh, 2+=bones
    bone_node = {name: BONE_START + i for i, name in enumerate(BONE_ORDER)}

    nodes = [
        {"name": "Root", "children": [1, BONE_START]},
        {"name": "CharacterMesh", "mesh": 0, "skin": 0},
    ]
    for name in BONE_ORDER:
        parent, local_t, _ = BONES[name]
        children = [bone_node[n] for n in BONE_ORDER if BONES[n][0] == name]
        node = {"name": name, "translation": list(local_t)}
        if children:
            node["children"] = children
        nodes.append(node)

    # ── Finalize buffer ───────────────────────────────────────────
    final_buf = bb.finalize()

    return {
        "asset": {"version": "2.0", "generator": "Blufus the Code Puppy 🐶"},
        "scene": 0,
        "scenes": [{"name": "Scene", "nodes": [0]}],
        "nodes": nodes,
        "meshes": [{
            "name": "CharacterBody",
            "primitives": [{
                "attributes": {
                    "POSITION": pos_acc,
                    "NORMAL": norm_acc,
                    "JOINTS_0": joint_acc,
                    "WEIGHTS_0": weight_acc,
                },
                "indices": idx_acc,
                "material": 0,
            }],
        }],
        "skins": [{
            "name": "Armature",
            "inverseBindMatrices": ibm_acc,
            "joints": [bone_node[n] for n in BONE_ORDER],
            "skeleton": BONE_START,
        }],
        "materials": [{
            "name": "Skin",
            "doubleSided": True,
            "pbrMetallicRoughness": {
                "baseColorFactor": [0.3, 0.55, 0.95, 1.0],
                "metallicFactor": 0.1,
                "roughnessFactor": 0.7,
            },
        }],
        "animations": [{
            "name": "Wave",
            "samplers": [
                {"input": arm_t, "output": arm_r, "interpolation": "LINEAR"},
                {"input": head_t, "output": head_r, "interpolation": "LINEAR"},
            ],
            "channels": [
                {"sampler": 0, "target": {"node": bone_node["ArmR"], "path": "rotation"}},
                {"sampler": 1, "target": {"node": bone_node["Head"], "path": "rotation"}},
            ],
        }],
        "accessors": bb.accessors,
        "bufferViews": bb.views,
        "buffers": [{
            "byteLength": len(final_buf),
            "uri": "data:application/octet-stream;base64,"
                   + base64.b64encode(final_buf).decode("ascii"),
        }],
    }


def main():
    gltf = build_gltf()
    output = "character.gltf"

    with open(output, "w") as f:
        json.dump(gltf, f, indent=2)

    stats = gltf["accessors"]
    print(f"[OK] Generated {output}")
    print(f"   Vertices:  {stats[0]['count']}")
    print(f"   Triangles: {stats[2]['count'] // 3}")
    print(f"   Bones:     {len(BONE_ORDER)} ({', '.join(BONE_ORDER)})")
    print(f"   Buffer:    {gltf['buffers'][0]['byteLength']} bytes")
    print(f"   Animation: 'Wave' (1.2s loop)")
    print(f"\nDrop this into your Godot project and it'll auto-import!")


if __name__ == "__main__":
    main()
