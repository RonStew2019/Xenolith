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
    "ArmL":      ("Spine",   (-0.30, 0.11, 0),  (-0.30, 1.21, 0)),
    "ForearmL":  ("ArmL",    (0, -0.31, 0),     (-0.30, 0.90, 0)),
    "ArmR":      ("Spine",   (0.30, 0.11, 0),   (0.30, 1.21, 0)),
    "ForearmR":  ("ArmR",    (0, -0.31, 0),     (0.30, 0.90, 0)),
    "LegL":      ("Hips",    (-0.12, -0.07, 0), (-0.12, 0.78, 0)),
    "ShinL":     ("LegL",    (0, -0.39, 0),     (-0.12, 0.39, 0)),
    "LegR":      ("Hips",    (0.12, -0.07, 0),  (0.12, 0.78, 0)),
    "ShinR":     ("LegR",    (0, -0.39, 0),     (0.12, 0.39, 0)),
    "FootL":     ("ShinL",   (0, -0.33, 0),     (-0.12, 0.06, 0)),
    "FootR":     ("ShinR",   (0, -0.33, 0),     (0.12, 0.06, 0)),
    "FistL":     ("ForearmL", (0, -0.30, 0),     (-0.30, 0.60, 0)),
    "FistR":     ("ForearmR", (0, -0.30, 0),     (0.30, 0.60, 0)),
}
BONE_ORDER = [
    "Hips", "Spine", "Head",
    "ArmL", "ForearmL", "ArmR", "ForearmR",
    "LegL", "ShinL", "LegR", "ShinR",
    "FootL", "FootR",
    "FistL", "FistR",
]

# ─── Body Parts: (center, radii, bone_name) ──────────────────────────────────
# shape: box uses half-extents, ellipsoid uses radii.
N_SEGMENTS = 14  # horizontal slices (around Y axis)
N_RINGS = 10     # vertical slices (pole to pole)

BODY_PARTS = [
    # ── Torso ──
    ("rounded_box",       (0, 0.88, 0),       (0.19, 0.11, 0.13), "Hips"),
    ("rounded_box",       (0, 1.03, 0),       (0.14, 0.04, 0.10), "Spine"),
    ("rounded_box",       (0, 1.21, 0),       (0.22, 0.14, 0.14), "Spine"),
    # ── Head ──
    ("ellipsoid", (0, 1.55, 0),       (0.12, 0.12, 0.12), "Head"),
    # ── Left arm: shoulder ball -> socketed upper arm -> elbow ball -> socketed forearm ──
    ("ellipsoid", (-0.30, 1.21, 0),   (0.070, 0.070, 0.070), "ArmL"),
    ("socketed",  (-0.30, 1.05, 0),   (0.070, 0.108),        "ArmL"),
    ("ellipsoid", (-0.30, 0.90, 0),   (0.055, 0.055, 0.055), "ForearmL"),
    ("socketed",  (-0.30, 0.74, 0),   (0.062, 0.108),        "ForearmL"),
    # ── Right arm ──
    ("ellipsoid", (0.30, 1.21, 0),    (0.070, 0.070, 0.070), "ArmR"),
    ("socketed",  (0.30, 1.05, 0),    (0.070, 0.108),        "ArmR"),
    ("ellipsoid", (0.30, 0.90, 0),    (0.055, 0.055, 0.055), "ForearmR"),
    ("socketed",  (0.30, 0.74, 0),    (0.062, 0.108),        "ForearmR"),
    # ── Left leg: hip ball -> socketed thigh -> knee ball -> socketed shin ──
    ("ellipsoid", (-0.12, 0.78, 0),   (0.069, 0.069, 0.069), "LegL"),
    ("socketed",  (-0.12, 0.58, 0),   (0.092, 0.13),         "LegL"),
    ("ellipsoid", (-0.12, 0.39, 0),   (0.058, 0.058, 0.058), "ShinL"),
    ("socketed",  (-0.12, 0.18, 0),   (0.081, 0.14),         "ShinL"),
    # ── Right leg ──
    ("ellipsoid", (0.12, 0.78, 0),    (0.069, 0.069, 0.069), "LegR"),
    ("socketed",  (0.12, 0.58, 0),    (0.092, 0.13),         "LegR"),
    ("ellipsoid", (0.12, 0.39, 0),    (0.058, 0.058, 0.058), "ShinR"),
    ("socketed",  (0.12, 0.18, 0),    (0.081, 0.14),         "ShinR"),
    # ── Feet (ball joints at shin bottoms — skating wheels) ──
    ("ellipsoid", (-0.12, 0.06, 0),    (0.09, 0.09, 0.09),  "FootL"),
    ("ellipsoid", (0.12, 0.06, 0),     (0.09, 0.09, 0.09),  "FootR"),
    # ── Fists (chunky brawler mitts) ──
    ("rounded_box", (-0.30, 0.60, 0),  (0.06, 0.05, 0.07), "FistL"),
    ("rounded_box", (0.30, 0.60, 0),   (0.06, 0.05, 0.07), "FistR"),
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




def make_rounded_box(center, half_extents, n_seg=N_SEGMENTS, n_ring=N_SEGMENTS,
                     exponent=4.0):
    """Superellipsoid -- a box with smoothly rounded edges and corners.

    half_extents = (hx, hy, hz).  exponent controls sharpness:
    2.0 = perfect ellipsoid, higher = boxier with tighter edge radii.
    UV-sphere topology with analytical normals from the superellipsoid
    gradient.  n_ring defaults to N_SEGMENTS (14) for better edge detail.
    """
    cx, cy, cz = center
    hx, hy, hz = half_extents
    e = 2.0 / exponent        # parametric exponent
    ne = 2.0 - e              # normal exponent

    def spow(base, exp):
        """Signed power: sign(x) * |x|^exp."""
        if abs(base) < 1e-10:
            return 0.0
        return math.copysign(abs(base) ** exp, base)

    positions, normals, indices = [], [], []

    # Top pole
    positions.append((cx, cy + hy, cz))
    normals.append((0.0, 1.0, 0.0))

    for i in range(1, n_ring):
        phi = math.pi * i / n_ring          # colatitude 0 -> pi
        sp, cp = math.sin(phi), math.cos(phi)
        for j in range(n_seg):
            theta = 2.0 * math.pi * j / n_seg
            ct, st = math.cos(theta), math.sin(theta)
            # Surface position
            px = hx * spow(sp, e) * spow(ct, e)
            py = hy * spow(cp, e)
            pz = hz * spow(sp, e) * spow(st, e)
            positions.append((cx + px, cy + py, cz + pz))
            # Analytical normal (gradient of |x/hx|^n + |y/hy|^n + |z/hz|^n)
            nx = spow(sp, ne) * spow(ct, ne) / hx
            ny = spow(cp, ne) / hy
            nz = spow(sp, ne) * spow(st, ne) / hz
            inv_len = 1.0 / math.sqrt(nx * nx + ny * ny + nz * nz + 1e-20)
            normals.append((nx * inv_len, ny * inv_len, nz * inv_len))

    # Bottom pole
    positions.append((cx, cy - hy, cz))
    normals.append((0.0, -1.0, 0.0))

    # Indices -- same UV-sphere topology as make_ellipsoid
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


def make_socketed_limb(center, dims, n_seg=N_SEGMENTS, socket_inset=0.8):
    """Cylinder with concave dished end caps and smooth rounded lips.

    dims = (body_radius, half_height).
    Each end has a spherical dish recessed into the cylinder so ball joints
    nestle into concave sockets.  A smooth semicircular lip profile bridges
    the dish rim to the cylinder wall, giving a gentle curve where the
    concave cup meets the convex body instead of a sharp crease.

    socket_inset: dish-rim radius as a fraction of body radius (< 1.0).
    """
    R, H = dims
    depth = min(0.04, H * 0.25)  # how deep each dish recesses
    n_cap = 5                     # profile rings per dish
    n_lip = 6                     # profile rings per lip fillet
    R_sock = R * socket_inset     # dish rim radius (narrower than cylinder)

    # Lip geometry: semicircular cross-section bridging R_sock ↔ R
    lip_r = (R - R_sock) / 2.0   # radial half-extent of lip arc
    R_mid = (R_sock + R) / 2.0   # radial centre of lip arc
    lip_depth = lip_r * 1.5       # how far the lip protrudes beyond the end

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
    _pole(-H + depth, -1.0)
    for i in range(1, n_cap + 1):
        a = i / n_cap * math.pi / 2
        r = R_sock * math.sin(a)
        y_off = -H + depth * math.cos(a)
        mag = math.sqrt(depth**2 * math.sin(a)**2 + R_sock**2 * math.cos(a)**2)
        _ring(y_off, r, -depth * math.sin(a) / mag, -R_sock * math.cos(a) / mag)

    # ── Bottom lip: semicircular fillet from dish rim to cylinder wall ──
    # Profile: r(α) = R_mid − lip_r·cos α,  y(α) = −H − lip_depth·sin α
    # α ∈ (0, π), endpoints excluded (shared with dish/cylinder rings).
    # Normals rotate smoothly: inward (dish) → downward → outward (cyl).
    for i in range(1, n_lip + 1):
        a = i / (n_lip + 1) * math.pi
        r = R_mid - lip_r * math.cos(a)
        y_off = -H - lip_depth * math.sin(a)
        nr_raw = -lip_depth * math.cos(a)
        ny_raw = -lip_r * math.sin(a)
        mag = math.sqrt(nr_raw**2 + ny_raw**2)
        _ring(y_off, r, nr_raw / mag, ny_raw / mag)

    # ── Cylinder body (constant full radius, outward normals) ──
    n_cyl = max(2, int(2.0 * H / 0.04))
    for ci in range(n_cyl + 1):
        _ring(-H + ci / n_cyl * 2.0 * H, R, 1.0, 0.0)

    # ── Top lip: semicircular fillet from cylinder wall to dish rim ──
    # Profile: r(α) = R_mid + lip_r·cos α,  y(α) = H + lip_depth·sin α
    # α ∈ (0, π), endpoints excluded.
    for i in range(1, n_lip + 1):
        a = i / (n_lip + 1) * math.pi
        r = R_mid + lip_r * math.cos(a)
        y_off = H + lip_depth * math.sin(a)
        nr_raw = lip_depth * math.cos(a)
        ny_raw = lip_r * math.sin(a)
        mag = math.sqrt(nr_raw**2 + ny_raw**2)
        _ring(y_off, r, nr_raw / mag, ny_raw / mag)

    # ── Top dish: rim → pole (recessed inside cylinder) ──
    # Profile: r(α) = R_sock·cos α,  y(α) = H − depth·sin α,  α ∈ [0, π/2]
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


def quat_mul(a, b):
    """Multiply two quaternions (x,y,z,w).  Result = rotation b then a."""
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (
        aw*bx + ax*bw + ay*bz - az*by,
        aw*by - ax*bz + ay*bw + az*bx,
        aw*bz + ax*by - ay*bx + az*bw,
        aw*bw - ax*bx - ay*by - az*bz,
    )


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

    shape_fn = {"box": make_box, "rounded_box": make_rounded_box, "ellipsoid": make_ellipsoid, "socketed": make_socketed_limb}
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

    # ── Skate animation (1.0s loop) ──────────────────────────────
    #   EXAGGERATED crouched pose, deep lean, wide stance.
    #   Jetpack-powered skating: aggressive, high-energy movement.
    #   Punchy hover-bob at 2x frequency, feet spinning at 2x speed.
    skate_times = [0.0, 0.25, 0.5, 0.75, 1.0]
    time_acc = bb.add_accessor(
        bb.add_view(struct.pack(f"<{len(skate_times)}f", *skate_times)),
        FLOAT, len(skate_times), "SCALAR", [0.0], [1.0],
    )

    def pack_rot(angles_deg, axis=(1, 0, 0)):
        """Pack rotation keyframes from degree values around an axis."""
        rots = [quat_from_axis_angle(axis, math.radians(a)) for a in angles_deg]
        return bb.add_accessor(
            bb.add_view(b"".join(struct.pack("<4f", *r) for r in rots)),
            FLOAT, len(rots), "VEC4",
        )

    def pack_vec3(values):
        """Pack VEC3 keyframes (e.g. translations)."""
        return bb.add_accessor(
            bb.add_view(b"".join(struct.pack("<3f", *v) for v in values)),
            FLOAT, len(values), "VEC3",
        )

    X = (1, 0, 0)

    # Crouched hips: deep crouch with punchy hover-bob at 2x freq
    hb = BONES["Hips"][1]  # base hips local translation
    crouch = -0.14
    bob = 0.05
    hips_out = pack_vec3([
        (hb[0], hb[1] + crouch,       hb[2]),
        (hb[0], hb[1] + crouch + bob, hb[2]),
        (hb[0], hb[1] + crouch,       hb[2]),
        (hb[0], hb[1] + crouch + bob, hb[2]),
        (hb[0], hb[1] + crouch,       hb[2]),
    ])

    # Spine: aggressive forward lean with sway
    #                                 0.0   0.25   0.5   0.75   1.0
    spine_out      = pack_rot([       25,    20,   25,    20,   25], X)
    # Head: stronger counter-tilt to keep looking forward
    head_out       = pack_rot([      -18,   -14,  -18,   -14,  -18], X)
    # Lead leg (left) far forward, trail leg (right) far back
    leg_l_out      = pack_rot([       15,    10,   15,    10,   15], X)
    leg_r_out      = pack_rot([      -55,   -50,  -55,   -50,  -55], X)
    # Shin bends: exaggerated knee angles
    shin_l_out     = pack_rot([       30,    35,   30,    35,   30], X)
    shin_r_out     = pack_rot([       75,    67,   75,    67,   75], X)
    # Arms: forward/back swing (X) combined with elbows-out abduction (Z)
    Z = (0, 0, 1)
    arm_l_abduct = quat_from_axis_angle(Z, math.radians(-30))
    arm_r_abduct = quat_from_axis_angle(Z, math.radians( 30))
    arm_l_rots = [quat_mul(arm_l_abduct, quat_from_axis_angle(X, math.radians(a)))
                  for a in [-35, -30, -35, -30, -35]]
    arm_r_rots = [quat_mul(arm_r_abduct, quat_from_axis_angle(X, math.radians(a)))
                  for a in [ 28,  22,  28,  22,  28]]
    arm_l_out = bb.add_accessor(
        bb.add_view(b"".join(struct.pack("<4f", *r) for r in arm_l_rots)),
        FLOAT, len(arm_l_rots), "VEC4",
    )
    arm_r_out = bb.add_accessor(
        bb.add_view(b"".join(struct.pack("<4f", *r) for r in arm_r_rots)),
        FLOAT, len(arm_r_rots), "VEC4",
    )
    forearm_l_out  = pack_rot([      -65,   -58,  -65,   -58,  -65], X)
    forearm_r_out  = pack_rot([      -70,   -62,  -70,   -62,  -70], X)
    # Feet: continuous forward spin (2 revolutions per cycle — double speed!)
    foot_l_out     = pack_rot([        0,  -180, -360,  -540, -720], X)
    foot_r_out     = pack_rot([        0,  -180, -360,  -540, -720], X)

    # (bone_name, anim_path, output_accessor)
    skate_channels = [
        ("Hips",     "translation", hips_out),
        ("Spine",    "rotation",    spine_out),
        ("Head",     "rotation",    head_out),
        ("LegL",     "rotation",    leg_l_out),
        ("LegR",     "rotation",    leg_r_out),
        ("ShinL",    "rotation",    shin_l_out),
        ("ShinR",    "rotation",    shin_r_out),
        ("ArmL",     "rotation",    arm_l_out),
        ("ArmR",     "rotation",    arm_r_out),
        ("ForearmL", "rotation",    forearm_l_out),
        ("ForearmR", "rotation",    forearm_r_out),
        ("FootL",    "rotation",    foot_l_out),
        ("FootR",    "rotation",    foot_r_out),
        ("FistL",    "rotation",    pack_rot([0, 0, 0, 0, 0], X)),
        ("FistR",    "rotation",    pack_rot([0, 0, 0, 0, 0], X)),
    ]

    # ── JabL animation (left jab, 0.5s) ─────────────────────────
    #   Compact sweeping hook -- arm stays bent, power comes from
    #   torso rotation.  Keyframes bake the skating base pose so the
    #   OneShot overlay keeps the lower body skating.
    hook_l_times = [0.0, 0.10, 0.22, 0.36, 0.5]
    hl_time_acc = bb.add_accessor(
        bb.add_view(struct.pack(f"<{len(hook_l_times)}f", *hook_l_times)),
        FLOAT, len(hook_l_times), "SCALAR", [0.0], [0.5],
    )
    Y = (0, 1, 0)
    crouch_y = hb[1] + crouch          # crouched hips height

    def pack_quat_keys(quats):
        """Pack pre-computed quaternion keyframes."""
        return bb.add_accessor(
            bb.add_view(b"".join(struct.pack("<4f", *q) for q in quats)),
            FLOAT, len(quats), "VEC4",
        )

    def combined_xz(pairs):
        """Build combined X + Z rotation quaternions from (x_deg, z_deg) pairs."""
        return [quat_mul(quat_from_axis_angle(Z, math.radians(z)),
                         quat_from_axis_angle(X, math.radians(x)))
                for x, z in pairs]

    def combined_xy(pairs):
        """Build combined X + Y rotation quaternions from (x_deg, y_deg) pairs."""
        return [quat_mul(quat_from_axis_angle(Y, math.radians(y)),
                         quat_from_axis_angle(X, math.radians(x)))
                for x, y in pairs]

    # Jabbing arm (code-right = visual-left due to PI flip):
    # Quick straight jab FROM the skating crouch. Arm punches out from
    # the elbows-out skate guard. Starts/ends at skate base values.
    #                          rest     cock     PUNCH    retract  rest
    hl_arm_r_out = pack_quat_keys(combined_xz([
        (28, 30), (45, 34), (-120, 5), (-55, 16), (28, 30)]))
    # Forearm: from skating bent (-70) → cocked tighter → extend on impact
    hl_forearm_r_out = pack_rot([-70, -100, 5, -20, -70], X)
    # Fist: slight pronate snap on impact
    hl_fist_r_out = pack_quat_keys(combined_xz([
        (0, 0), (-5, -5), (8, 15), (3, 8), (0, 0)]))
    # Guard arm (code-left = visual-right): holds skate pose
    hl_arm_l_out = pack_quat_keys(combined_xz([
        (-35, -30), (-35, -30), (-35, -30), (-35, -30), (-35, -30)]))
    hl_forearm_l_out = pack_rot([-65, -65, -65, -65, -65], X)
    hl_fist_l_out = pack_rot([0, 0, 0, 0, 0], X)
    # Spine: maintains skating lean (X=25), slight Y twist into jab
    hl_spine_out = pack_quat_keys(combined_xy([
        (25, 0), (27, -5), (22, 15), (24, 8), (25, 0)]))
    # Head: holds skating counter-tilt, small dip on impact
    hl_head_out = pack_rot([-18, -20, -24, -20, -18], X)
    # Hips: stays at skating crouch, tiny drop on impact
    hl_hips_out = pack_vec3([
        (hb[0], crouch_y,        hb[2]),
        (hb[0], crouch_y,        hb[2]),
        (hb[0], crouch_y - 0.02, hb[2]),
        (hb[0], crouch_y - 0.01, hb[2]),
        (hb[0], crouch_y,        hb[2]),
    ])
    # Legs: hold skating pose — jabs don't shift weight
    hl_leg_l_out   = pack_rot([15, 15, 15, 15, 15], X)
    hl_leg_r_out   = pack_rot([-45, -45, -45, -45, -45], X)
    hl_shin_l_out  = pack_rot([30, 30, 30, 30, 30], X)
    hl_shin_r_out  = pack_rot([75, 75, 75, 75, 75], X)
    hl_foot_l_out  = pack_rot([0, 0, 0, 0, 0], X)
    hl_foot_r_out  = pack_rot([0, 0, 0, 0, 0], X)

    hook_l_channels = [
        ("ArmL",     "rotation",    hl_arm_l_out),
        ("ForearmL", "rotation",    hl_forearm_l_out),
        ("FistL",    "rotation",    hl_fist_l_out),
        ("ArmR",     "rotation",    hl_arm_r_out),
        ("ForearmR", "rotation",    hl_forearm_r_out),
        ("FistR",    "rotation",    hl_fist_r_out),
        ("Spine",    "rotation",    hl_spine_out),
        ("Head",     "rotation",    hl_head_out),
        ("Hips",     "translation", hl_hips_out),
        ("LegL",     "rotation",    hl_leg_l_out),
        ("LegR",     "rotation",    hl_leg_r_out),
        ("ShinL",    "rotation",    hl_shin_l_out),
        ("ShinR",    "rotation",    hl_shin_r_out),
        ("FootL",    "rotation",    hl_foot_l_out),
        ("FootR",    "rotation",    hl_foot_r_out),
    ]

    # ── JabR animation (right jab, 0.5s) ── mirror of HookL ─────
    hook_r_times = [0.0, 0.10, 0.22, 0.36, 0.5]
    hr_time_acc = bb.add_accessor(
        bb.add_view(struct.pack(f"<{len(hook_r_times)}f", *hook_r_times)),
        FLOAT, len(hook_r_times), "SCALAR", [0.0], [0.5],
    )
    # Jabbing arm (code-left = visual-right due to PI flip):
    # Quick straight jab FROM the skating crouch. Mirror of JabL.
    #                          rest      cock      PUNCH     retract   rest
    hr_arm_l_out = pack_quat_keys(combined_xz([
        (-35, -30), (-20, -34), (-120, -5), (-60, -16), (-35, -30)]))
    # Forearm: from skating bent (-65) → cocked tighter → extend on impact
    hr_forearm_l_out = pack_rot([-65, -100, 5, -20, -65], X)
    # Fist: slight pronate snap on impact
    hr_fist_l_out = pack_quat_keys(combined_xz([
        (0, 0), (5, 5), (-8, -15), (-3, -8), (0, 0)]))
    # Guard arm (code-right = visual-left): holds skate pose
    hr_arm_r_out = pack_quat_keys(combined_xz([
        (28, 30), (28, 30), (28, 30), (28, 30), (28, 30)]))
    hr_forearm_r_out = pack_rot([-70, -70, -70, -70, -70], X)
    hr_fist_r_out = pack_rot([0, 0, 0, 0, 0], X)
    # Spine: maintains skating lean (X=25), slight Y twist into jab (opposite)
    hr_spine_out = pack_quat_keys(combined_xy([
        (25, 0), (27, 5), (22, -15), (24, -8), (25, 0)]))
    hr_head_out = pack_rot([-18, -20, -24, -20, -18], X)
    # Hips: stays at skating crouch, tiny drop on impact
    hr_hips_out = pack_vec3([
        (hb[0], crouch_y,        hb[2]),
        (hb[0], crouch_y,        hb[2]),
        (hb[0], crouch_y - 0.02, hb[2]),
        (hb[0], crouch_y - 0.01, hb[2]),
        (hb[0], crouch_y,        hb[2]),
    ])
    # Legs: hold skating pose — jabs don't shift weight
    hr_leg_l_out   = pack_rot([15, 15, 15, 15, 15], X)
    hr_leg_r_out   = pack_rot([-45, -45, -45, -45, -45], X)
    hr_shin_l_out  = pack_rot([30, 30, 30, 30, 30], X)
    hr_shin_r_out  = pack_rot([75, 75, 75, 75, 75], X)
    hr_foot_l_out  = pack_rot([0, 0, 0, 0, 0], X)
    hr_foot_r_out  = pack_rot([0, 0, 0, 0, 0], X)

    hook_r_channels = [
        ("ArmR",     "rotation",    hr_arm_r_out),
        ("ForearmR", "rotation",    hr_forearm_r_out),
        ("FistR",    "rotation",    hr_fist_r_out),
        ("ArmL",     "rotation",    hr_arm_l_out),
        ("ForearmL", "rotation",    hr_forearm_l_out),
        ("FistL",    "rotation",    hr_fist_l_out),
        ("Spine",    "rotation",    hr_spine_out),
        ("Head",     "rotation",    hr_head_out),
        ("Hips",     "translation", hr_hips_out),
        ("LegL",     "rotation",    hr_leg_l_out),
        ("LegR",     "rotation",    hr_leg_r_out),
        ("ShinL",    "rotation",    hr_shin_l_out),
        ("ShinR",    "rotation",    hr_shin_r_out),
        ("FootL",    "rotation",    hr_foot_l_out),
        ("FootR",    "rotation",    hr_foot_r_out),
    ]


    # ── Idle animation (2.0s loop) ── relaxed standing breathing ──
    idle_times = [0.0, 0.5, 1.0, 1.5, 2.0]
    idle_time_acc = bb.add_accessor(
        bb.add_view(struct.pack(f"<{len(idle_times)}f", *idle_times)),
        FLOAT, len(idle_times), "SCALAR", [0.0], [2.0],
    )
    ib = BONES["Hips"][1]  # base hips translation
    # Hips: gentle breathing bob
    idle_hips_out = pack_vec3([
        (ib[0], ib[1],        ib[2]),
        (ib[0], ib[1] + 0.01, ib[2]),
        (ib[0], ib[1],        ib[2]),
        (ib[0], ib[1] + 0.01, ib[2]),
        (ib[0], ib[1],        ib[2]),
    ])
    # Spine: very subtle sway
    idle_spine_out = pack_rot([2, 0, -2, 0, 2], X)
    # Head: tiny nod
    idle_head_out = pack_rot([0, 2, 0, -2, 0], X)
    # Arms: relaxed at sides, gentle swing
    idle_arm_l_out = pack_quat_keys(combined_xz([
        (0, -8), (3, -8), (0, -8), (-3, -8), (0, -8)]))
    idle_arm_r_out = pack_quat_keys(combined_xz([
        (0, 8), (-3, 8), (0, 8), (3, 8), (0, 8)]))
    idle_forearm_l_out = pack_rot([-15, -12, -15, -18, -15], X)
    idle_forearm_r_out = pack_rot([-15, -18, -15, -12, -15], X)
    idle_fist_l_out = pack_rot([0, 0, 0, 0, 0], X)
    idle_fist_r_out = pack_rot([0, 0, 0, 0, 0], X)
    # Legs: standing straight, tiny weight shift
    idle_leg_l_out  = pack_rot([0, 0, 0, 0, 0], X)
    idle_leg_r_out  = pack_rot([0, 0, 0, 0, 0], X)
    idle_shin_l_out = pack_rot([2, 2, 2, 2, 2], X)
    idle_shin_r_out = pack_rot([2, 2, 2, 2, 2], X)
    idle_foot_l_out = pack_rot([0, 0, 0, 0, 0], X)
    idle_foot_r_out = pack_rot([0, 0, 0, 0, 0], X)

    idle_channels = [
        ("Hips",     "translation", idle_hips_out),
        ("Spine",    "rotation",    idle_spine_out),
        ("Head",     "rotation",    idle_head_out),
        ("ArmL",     "rotation",    idle_arm_l_out),
        ("ArmR",     "rotation",    idle_arm_r_out),
        ("ForearmL", "rotation",    idle_forearm_l_out),
        ("ForearmR", "rotation",    idle_forearm_r_out),
        ("FistL",    "rotation",    idle_fist_l_out),
        ("FistR",    "rotation",    idle_fist_r_out),
        ("LegL",     "rotation",    idle_leg_l_out),
        ("LegR",     "rotation",    idle_leg_r_out),
        ("ShinL",    "rotation",    idle_shin_l_out),
        ("ShinR",    "rotation",    idle_shin_r_out),
        ("FootL",    "rotation",    idle_foot_l_out),
        ("FootR",    "rotation",    idle_foot_r_out),
    ]


    # ── SkateB animation (1.0s loop) ── mirrored skate, opposite leg leads ──
    sb_time_acc = time_acc  # reuse same 5-keyframe timing
    # Hips/Spine/Head: same as Skate
    sb_hips_out = hips_out
    sb_spine_out = spine_out
    sb_head_out = head_out
    # Legs: swapped — R leads forward, L trails back
    sb_leg_l_out   = pack_rot([      -55,   -50,  -55,   -50,  -55], X)
    sb_leg_r_out   = pack_rot([       15,    10,   15,    10,   15], X)
    sb_shin_l_out  = pack_rot([       75,    67,   75,    67,   75], X)
    sb_shin_r_out  = pack_rot([       30,    35,   30,    35,   30], X)
    # Arms: swapped X values, keep correct Z sign per side
    sb_arm_l_rots = [quat_mul(arm_l_abduct, quat_from_axis_angle(X, math.radians(a)))
                     for a in [28, 22, 28, 22, 28]]
    sb_arm_r_rots = [quat_mul(arm_r_abduct, quat_from_axis_angle(X, math.radians(a)))
                     for a in [-35, -30, -35, -30, -35]]
    sb_arm_l_out = bb.add_accessor(
        bb.add_view(b"".join(struct.pack("<4f", *r) for r in sb_arm_l_rots)),
        FLOAT, len(sb_arm_l_rots), "VEC4",
    )
    sb_arm_r_out = bb.add_accessor(
        bb.add_view(b"".join(struct.pack("<4f", *r) for r in sb_arm_r_rots)),
        FLOAT, len(sb_arm_r_rots), "VEC4",
    )
    sb_forearm_l_out = pack_rot([-70, -62, -70, -62, -70], X)
    sb_forearm_r_out = pack_rot([-65, -58, -65, -58, -65], X)
    # Feet: same spin
    sb_foot_l_out = foot_l_out
    sb_foot_r_out = foot_r_out

    skateb_channels = [
        ("Hips",     "translation", sb_hips_out),
        ("Spine",    "rotation",    sb_spine_out),
        ("Head",     "rotation",    sb_head_out),
        ("LegL",     "rotation",    sb_leg_l_out),
        ("LegR",     "rotation",    sb_leg_r_out),
        ("ShinL",    "rotation",    sb_shin_l_out),
        ("ShinR",    "rotation",    sb_shin_r_out),
        ("ArmL",     "rotation",    sb_arm_l_out),
        ("ArmR",     "rotation",    sb_arm_r_out),
        ("ForearmL", "rotation",    sb_forearm_l_out),
        ("ForearmR", "rotation",    sb_forearm_r_out),
        ("FootL",    "rotation",    sb_foot_l_out),
        ("FootR",    "rotation",    sb_foot_r_out),
        ("FistL",    "rotation",    pack_rot([0, 0, 0, 0, 0], X)),
        ("FistR",    "rotation",    pack_rot([0, 0, 0, 0, 0], X)),
    ]

    # ── JabLB (left jab from mirrored skate, 0.5s) ───────────────
    jlb_times = [0.0, 0.10, 0.22, 0.36, 0.5]
    jlb_time_acc = bb.add_accessor(
        bb.add_view(struct.pack(f"<{len(jlb_times)}f", *jlb_times)),
        FLOAT, len(jlb_times), "SCALAR", [0.0], [0.5],
    )
    # Same punch arm motion as JabL
    jlb_arm_r_out = pack_quat_keys(combined_xz([
        (28, 30), (45, 34), (-120, 5), (-55, 16), (28, 30)]))
    jlb_forearm_r_out = pack_rot([-70, -100, 5, -20, -70], X)
    jlb_fist_r_out = pack_quat_keys(combined_xz([
        (0, 0), (-5, -5), (8, 15), (3, 8), (0, 0)]))
    # Guard arm holds mirrored skate pose
    jlb_arm_l_out = pack_quat_keys(combined_xz([
        (28, -30), (28, -30), (28, -30), (28, -30), (28, -30)]))
    jlb_forearm_l_out = pack_rot([-70, -70, -70, -70, -70], X)
    jlb_fist_l_out = pack_rot([0, 0, 0, 0, 0], X)
    jlb_spine_out = pack_quat_keys(combined_xy([
        (25, 0), (27, -5), (22, 15), (24, 8), (25, 0)]))
    jlb_head_out = pack_rot([-18, -20, -24, -20, -18], X)
    jlb_hips_out = pack_vec3([
        (hb[0], crouch_y,        hb[2]),
        (hb[0], crouch_y,        hb[2]),
        (hb[0], crouch_y - 0.02, hb[2]),
        (hb[0], crouch_y - 0.01, hb[2]),
        (hb[0], crouch_y,        hb[2]),
    ])
    # Legs: hold mirrored skate pose
    jlb_leg_l_out   = pack_rot([-55, -55, -55, -55, -55], X)
    jlb_leg_r_out   = pack_rot([15, 15, 15, 15, 15], X)
    jlb_shin_l_out  = pack_rot([75, 75, 75, 75, 75], X)
    jlb_shin_r_out  = pack_rot([30, 30, 30, 30, 30], X)
    jlb_foot_l_out  = pack_rot([0, 0, 0, 0, 0], X)
    jlb_foot_r_out  = pack_rot([0, 0, 0, 0, 0], X)

    jablb_channels = [
        ("ArmL",     "rotation",    jlb_arm_l_out),
        ("ForearmL", "rotation",    jlb_forearm_l_out),
        ("FistL",    "rotation",    jlb_fist_l_out),
        ("ArmR",     "rotation",    jlb_arm_r_out),
        ("ForearmR", "rotation",    jlb_forearm_r_out),
        ("FistR",    "rotation",    jlb_fist_r_out),
        ("Spine",    "rotation",    jlb_spine_out),
        ("Head",     "rotation",    jlb_head_out),
        ("Hips",     "translation", jlb_hips_out),
        ("LegL",     "rotation",    jlb_leg_l_out),
        ("LegR",     "rotation",    jlb_leg_r_out),
        ("ShinL",    "rotation",    jlb_shin_l_out),
        ("ShinR",    "rotation",    jlb_shin_r_out),
        ("FootL",    "rotation",    jlb_foot_l_out),
        ("FootR",    "rotation",    jlb_foot_r_out),
    ]

    # ── JabRB (right jab from mirrored skate, 0.5s) ──────────────
    jrb_time_acc = jlb_time_acc  # same timing
    # Same punch arm motion as JabR
    jrb_arm_l_out = pack_quat_keys(combined_xz([
        (-35, -30), (-20, -34), (-120, -5), (-60, -16), (-35, -30)]))
    jrb_forearm_l_out = pack_rot([-65, -100, 5, -20, -65], X)
    jrb_fist_l_out = pack_quat_keys(combined_xz([
        (0, 0), (5, 5), (-8, -15), (-3, -8), (0, 0)]))
    # Guard arm holds mirrored skate pose
    jrb_arm_r_out = pack_quat_keys(combined_xz([
        (-35, 30), (-35, 30), (-35, 30), (-35, 30), (-35, 30)]))
    jrb_forearm_r_out = pack_rot([-65, -65, -65, -65, -65], X)
    jrb_fist_r_out = pack_rot([0, 0, 0, 0, 0], X)
    jrb_spine_out = pack_quat_keys(combined_xy([
        (25, 0), (27, 5), (22, -15), (24, -8), (25, 0)]))
    jrb_head_out = pack_rot([-18, -20, -24, -20, -18], X)
    jrb_hips_out = pack_vec3([
        (hb[0], crouch_y,        hb[2]),
        (hb[0], crouch_y,        hb[2]),
        (hb[0], crouch_y - 0.02, hb[2]),
        (hb[0], crouch_y - 0.01, hb[2]),
        (hb[0], crouch_y,        hb[2]),
    ])
    # Legs: hold mirrored skate pose
    jrb_leg_l_out   = pack_rot([-55, -55, -55, -55, -55], X)
    jrb_leg_r_out   = pack_rot([15, 15, 15, 15, 15], X)
    jrb_shin_l_out  = pack_rot([75, 75, 75, 75, 75], X)
    jrb_shin_r_out  = pack_rot([30, 30, 30, 30, 30], X)
    jrb_foot_l_out  = pack_rot([0, 0, 0, 0, 0], X)
    jrb_foot_r_out  = pack_rot([0, 0, 0, 0, 0], X)

    jabrb_channels = [
        ("ArmR",     "rotation",    jrb_arm_r_out),
        ("ForearmR", "rotation",    jrb_forearm_r_out),
        ("FistR",    "rotation",    jrb_fist_r_out),
        ("ArmL",     "rotation",    jrb_arm_l_out),
        ("ForearmL", "rotation",    jrb_forearm_l_out),
        ("FistL",    "rotation",    jrb_fist_l_out),
        ("Spine",    "rotation",    jrb_spine_out),
        ("Head",     "rotation",    jrb_head_out),
        ("Hips",     "translation", jrb_hips_out),
        ("LegL",     "rotation",    jrb_leg_l_out),
        ("LegR",     "rotation",    jrb_leg_r_out),
        ("ShinL",    "rotation",    jrb_shin_l_out),
        ("ShinR",    "rotation",    jrb_shin_r_out),
        ("FootL",    "rotation",    jrb_foot_l_out),
        ("FootR",    "rotation",    jrb_foot_r_out),
    ]

    # Collect all animations: (name, time_accessor, channels)
    all_animations = [
        ("Idle",   idle_time_acc, idle_channels),
        ("Skate",  time_acc,    skate_channels),
        ("JabL", hl_time_acc, hook_l_channels),
        ("JabR", hr_time_acc, hook_r_channels),
        ("SkateB", sb_time_acc, skateb_channels),
        ("JabLB", jlb_time_acc, jablb_channels),
        ("JabRB", jrb_time_acc, jabrb_channels),
    ]

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
        "animations": [
            {
                "name": name,
                "samplers": [
                    {"input": t_acc, "output": out, "interpolation": "LINEAR"}
                    for _, _, out in channels
                ],
                "channels": [
                    {"sampler": i, "target": {"node": bone_node[bone], "path": path}}
                    for i, (bone, path, _) in enumerate(channels)
                ],
            }
            for name, t_acc, channels in all_animations
        ],
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
    anim_names = [a["name"] for a in gltf["animations"]]
    print(f"   Animations: {len(anim_names)} ({', '.join(anim_names)})")
    print(f"\nDrop this into your Godot project and it'll auto-import!")


if __name__ == "__main__":
    main()
