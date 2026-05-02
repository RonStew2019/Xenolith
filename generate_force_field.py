"""
Generate a hollow-sphere force-field mesh as a .glb file.
No external dependencies — just Python stdlib.

Double-walled sphere: outer shell (normals out) + inner shell (normals in)
gives a volumetric translucent look when rendered with alpha blending.

Author: Blufus the Code Puppy 🐶
"""
import struct
import json
import math


# ─── Mesh Parameters ─────────────────────────────────────────────────────────
OUTER_RADIUS = 20.0
INNER_RADIUS = 18.95   # 0.05m wall thickness
N_SEGMENTS = 32       # horizontal slices (longitude)
N_RINGS = 24          # vertical slices (latitude, pole to pole)


# ─── Buffer Builder ──────────────────────────────────────────────────────────

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
ARRAY_BUFFER = 34962
ELEMENT_ARRAY = 34963


# ─── Sphere Generator ────────────────────────────────────────────────────────

def make_sphere(radius, n_seg=N_SEGMENTS, n_ring=N_RINGS):
    """Generate a UV-sphere at the origin with analytically correct normals.

    Returns (positions, normals, indices) — normals point outward.
    Topology: top pole + ring bands + bottom pole, same as make_ellipsoid
    in generate_character.py but with uniform radius.
    """
    positions = []
    normals = []
    indices = []

    # ── Top pole ──────────────────────────────────────────────────
    positions.append((0.0, radius, 0.0))
    normals.append((0.0, 1.0, 0.0))

    # ── Ring bands ────────────────────────────────────────────────
    for i in range(1, n_ring):
        phi = math.pi * i / n_ring
        sp = math.sin(phi)
        cp = math.cos(phi)
        for j in range(n_seg):
            theta = 2.0 * math.pi * j / n_seg
            # Unit direction on the sphere
            nx = sp * math.cos(theta)
            ny = cp
            nz = sp * math.sin(theta)
            positions.append((radius * nx, radius * ny, radius * nz))
            normals.append((nx, ny, nz))

    # ── Bottom pole ───────────────────────────────────────────────
    positions.append((0.0, -radius, 0.0))
    normals.append((0.0, -1.0, 0.0))

    # ── Triangulation: top fan ────────────────────────────────────
    for j in range(n_seg):
        indices.extend([0, 1 + j, 1 + (j + 1) % n_seg])

    # ── Quad strips between ring bands ────────────────────────────
    for i in range(n_ring - 2):
        for j in range(n_seg):
            cur = 1 + i * n_seg + j
            nxt = 1 + i * n_seg + (j + 1) % n_seg
            below = cur + n_seg
            nxt_below = nxt + n_seg
            indices.extend([cur, below, nxt_below, cur, nxt_below, nxt])

    # ── Bottom fan ────────────────────────────────────────────────
    bottom = len(positions) - 1
    ring_start = 1 + (n_ring - 2) * n_seg
    for j in range(n_seg):
        indices.extend([bottom, ring_start + (j + 1) % n_seg, ring_start + j])

    return positions, normals, indices


def build_hollow_sphere():
    """Build combined vertex/index data for a double-walled hollow sphere.

    Outer shell: standard normals (outward), standard winding.
    Inner shell: negated normals (inward), reversed triangle winding.
    Both shells are merged into a single vertex/index set.
    """
    # Generate both shells
    outer_pos, outer_norm, outer_idx = make_sphere(OUTER_RADIUS, N_SEGMENTS, N_RINGS)
    inner_pos, inner_norm, inner_idx = make_sphere(INNER_RADIUS, N_SEGMENTS, N_RINGS)

    # Inner shell: negate normals, reverse triangle winding
    inner_norm = [(-nx, -ny, -nz) for (nx, ny, nz) in inner_norm]
    inner_idx_reversed = []
    for i in range(0, len(inner_idx), 3):
        a, b, c = inner_idx[i], inner_idx[i + 1], inner_idx[i + 2]
        inner_idx_reversed.extend([a, c, b])

    # Combine — offset inner indices by outer vertex count
    offset = len(outer_pos)
    all_pos = outer_pos + inner_pos
    all_norm = outer_norm + inner_norm
    all_idx = outer_idx + [i + offset for i in inner_idx_reversed]

    return all_pos, all_norm, all_idx


# ─── glTF / GLB Assembly ─────────────────────────────────────────────────────

def build_gltf_and_bin():
    """Assemble the glTF JSON dict and binary buffer for the force field."""
    bb = BufferBuilder()

    positions, normals, indices = build_hollow_sphere()

    # ── Pack vertex attributes ────────────────────────────────────
    p_min = [min(p[i] for p in positions) for i in range(3)]
    p_max = [max(p[i] for p in positions) for i in range(3)]

    p_acc = bb.add_accessor(
        bb.add_view(
            b"".join(struct.pack("<3f", *p) for p in positions),
            ARRAY_BUFFER,
        ),
        FLOAT, len(positions), "VEC3", p_min, p_max,
    )
    n_acc = bb.add_accessor(
        bb.add_view(
            b"".join(struct.pack("<3f", *n) for n in normals),
            ARRAY_BUFFER,
        ),
        FLOAT, len(normals), "VEC3",
    )
    i_acc = bb.add_accessor(
        bb.add_view(
            b"".join(struct.pack("<H", i) for i in indices),
            ELEMENT_ARRAY,
        ),
        USHORT, len(indices), "SCALAR", [min(indices)], [max(indices)],
    )

    final_buf = bb.finalize()

    # ── Material ──────────────────────────────────────────────────
    material = {
        "name": "ForceField",
        "alphaMode": "BLEND",
        "doubleSided": True,
        "emissiveFactor": [0.3, 0.5, 1.0],
        "pbrMetallicRoughness": {
            "baseColorFactor": [0.3, 0.5, 1.0, 0.15],
            "metallicFactor": 0.0,
            "roughnessFactor": 0.3,
        },
        "extensions": {
            "KHR_materials_emissive_strength": {
                "emissiveStrength": 0.8,
            },
        },
    }

    # ── glTF JSON ─────────────────────────────────────────────────
    gltf = {
        "asset": {
            "version": "2.0",
            "generator": "Blufus the Code Puppy 🐶 — Force Field Generator",
        },
        "extensionsUsed": ["KHR_materials_emissive_strength"],
        "scene": 0,
        "scenes": [{"name": "ForceFieldScene", "nodes": [0]}],
        "nodes": [
            {"name": "ForceField", "mesh": 0},
        ],
        "meshes": [
            {
                "name": "HollowSphere",
                "primitives": [
                    {
                        "attributes": {
                            "POSITION": p_acc,
                            "NORMAL": n_acc,
                        },
                        "indices": i_acc,
                        "material": 0,
                    }
                ],
            }
        ],
        "materials": [material],
        "accessors": bb.accessors,
        "bufferViews": bb.views,
        "buffers": [{"byteLength": len(final_buf)}],
    }

    return gltf, final_buf


def write_glb(path, gltf_dict, bin_data):
    """Write a GLB (binary glTF) file.

    GLB layout:
      12-byte header:  magic + version + total length
      JSON chunk:      length + type(0x4E4F534A) + padded JSON
      BIN  chunk:      length + type(0x004E4942) + padded binary
    """
    # ── JSON chunk ────────────────────────────────────────────────
    json_bytes = json.dumps(gltf_dict, separators=(",", ":")).encode("utf-8")
    # Pad JSON to 4-byte alignment with spaces (0x20)
    json_pad = (4 - len(json_bytes) % 4) % 4
    json_bytes += b" " * json_pad
    json_chunk_length = len(json_bytes)

    # ── BIN chunk ─────────────────────────────────────────────────
    bin_pad = (4 - len(bin_data) % 4) % 4
    bin_data_padded = bin_data + b"\x00" * bin_pad
    bin_chunk_length = len(bin_data_padded)

    # ── Header ────────────────────────────────────────────────────
    total_length = 12 + 8 + json_chunk_length + 8 + bin_chunk_length

    with open(path, "wb") as f:
        # GLB header
        f.write(struct.pack("<I", 0x46546C67))  # magic: "glTF"
        f.write(struct.pack("<I", 2))            # version
        f.write(struct.pack("<I", total_length))  # total length

        # JSON chunk
        f.write(struct.pack("<I", json_chunk_length))
        f.write(struct.pack("<I", 0x4E4F534A))   # "JSON"
        f.write(json_bytes)

        # BIN chunk
        f.write(struct.pack("<I", bin_chunk_length))
        f.write(struct.pack("<I", 0x004E4942))    # "BIN\0"
        f.write(bin_data_padded)


# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    gltf, bin_data = build_gltf_and_bin()
    output = "force_field.glb"

    write_glb(output, gltf, bin_data)

    # ── Summary ───────────────────────────────────────────────────
    acc = gltf["accessors"]
    prim = gltf["meshes"][0]["primitives"][0]
    n_verts = acc[prim["attributes"]["POSITION"]]["count"]
    n_tris = acc[prim["indices"]]["count"] // 3
    buf_size = gltf["buffers"][0]["byteLength"]

    print(f"[OK] Generated {output}")
    print(f"   Outer radius: {OUTER_RADIUS}m")
    print(f"   Inner radius: {INNER_RADIUS}m")
    print(f"   Wall thickness: {OUTER_RADIUS - INNER_RADIUS}m")
    print(f"   Segments: {N_SEGMENTS}  Rings: {N_RINGS}")
    print(f"   Vertices:  {n_verts}  (2 shells × {n_verts // 2})")
    print(f"   Triangles: {n_tris}  (2 shells × {n_tris // 2})")
    print(f"   Material:  ForceField (alpha={0.15}, emissive blue)")
    print(f"   Buffer:    {buf_size} bytes")
    print(f"\nDrop force_field.glb into your Godot project and it'll auto-import!")


if __name__ == "__main__":
    main()
