"""A small, dependency-free writer for skinned glTF 2.0 binaries (.glb): one skeleton,
several meshes (one primitive each) with normals, UVs, vertex colours, skin weights and
morph targets, and named materials (the game replaces them with its own)."""
import json
import struct

import numpy as np

UBYTE, FLOAT, USHORT, UINT = 5121, 5126, 5123, 5125
ARRAY_BUFFER, ELEMENT_ARRAY_BUFFER = 34962, 34963


class GLB:
    def __init__(self):
        self.bin = bytearray()
        self.accessors, self.views = [], []
        self.nodes, self.meshes, self.materials = [], [], []
        self.material_index = {}
        self.skins = []

    def _view(self, data: bytes, target=None):
        while len(self.bin) % 4:
            self.bin.append(0)
        view = {"buffer": 0, "byteOffset": len(self.bin), "byteLength": len(data)}
        if target:
            view["target"] = target
        self.bin.extend(data)
        self.views.append(view)
        return len(self.views) - 1

    def accessor(self, arr, kind, component=FLOAT, target=ARRAY_BUFFER, minmax=False, normalized=False):
        arr = np.ascontiguousarray(arr)
        view = self._view(arr.tobytes(), target)
        acc = {"bufferView": view, "componentType": component, "count": int(arr.shape[0]), "type": kind}
        if normalized:
            acc["normalized"] = True
        if minmax:
            acc["min"] = [float(x) for x in arr.min(axis=0)]
            acc["max"] = [float(x) for x in arr.max(axis=0)]
        self.accessors.append(acc)
        return len(self.accessors) - 1

    def material(self, name, color=(0.8, 0.8, 0.8, 1.0), double_sided=False):
        if name in self.material_index:
            return self.material_index[name]
        self.materials.append({
            "name": name,
            "pbrMetallicRoughness": {"baseColorFactor": list(color), "metallicFactor": 0.0, "roughnessFactor": 0.8},
            "doubleSided": double_sided,
        })
        self.material_index[name] = len(self.materials) - 1
        return self.material_index[name]

    def add_skeleton(self, names, parents, heads):
        """Joints with translation-only rest transforms (every bone axis-aligned)."""
        first = len(self.nodes)
        for i, name in enumerate(names):
            p = parents[i]
            local = heads[i] - (heads[p] if p >= 0 else 0.0)
            self.nodes.append({"name": name, "translation": [float(x) for x in local]})
        for i, p in enumerate(parents):
            if p >= 0:
                self.nodes[first + p].setdefault("children", []).append(first + i)
        ibm = np.zeros((len(names), 16), dtype=np.float32)
        for i in range(len(names)):
            m = np.eye(4, dtype=np.float32)
            m[:3, 3] = -heads[i]
            ibm[i] = m.T.reshape(16)  # column-major
        acc = self.accessor(ibm, "MAT4", target=None)
        self.skins.append({"joints": list(range(first, first + len(names))), "inverseBindMatrices": acc, "skeleton": first})
        self.skeleton_root = first
        return first

    def add_mesh(self, name, positions, normals, uvs, indices, joints, weights, material, colors=None, morphs=None, morph_names=None, uv2=None):
        attrs = {
            "POSITION": self.accessor(positions.astype(np.float32), "VEC3", minmax=True),
            "NORMAL": self.accessor(normals.astype(np.float32), "VEC3"),
            "TEXCOORD_0": self.accessor(uvs.astype(np.float32), "VEC2"),
            "JOINTS_0": self._joints(joints),
            "WEIGHTS_0": self._weights(weights),
        }
        if uv2 is not None:
            attrs["TEXCOORD_1"] = self.accessor(uv2.astype(np.float32), "VEC2")
        if colors is not None:
            rgba = np.clip(np.rint(colors * 255.0), 0, 255).astype(np.uint8)
            attrs["COLOR_0"] = self.accessor(rgba, "VEC4", UBYTE, normalized=True)
        if positions.shape[0] < 65536:
            idx = self.accessor(indices.astype(np.uint16).reshape(-1), "SCALAR", USHORT, ELEMENT_ARRAY_BUFFER)
        else:
            idx = self.accessor(indices.astype(np.uint32).reshape(-1), "SCALAR", UINT, ELEMENT_ARRAY_BUFFER)
        prim = {"attributes": attrs, "indices": idx, "material": material}
        mesh = {"name": name, "primitives": [prim]}
        if morphs:
            prim["targets"] = [{"POSITION": self._delta(d)} for d in morphs]
            mesh["weights"] = [0.0] * len(morphs)
            mesh["extras"] = {"targetNames": list(morph_names)}
        self.meshes.append(mesh)
        self.nodes.append({"name": name, "mesh": len(self.meshes) - 1, "skin": 0})
        return len(self.nodes) - 1

    def _joints(self, joints):
        if joints.max() < 256:
            return self.accessor(joints.astype(np.uint8), "VEC4", UBYTE)
        return self.accessor(joints.astype(np.uint16), "VEC4", USHORT)

    def _weights(self, weights):
        """Normalised bytes, rounded so every vertex still sums to exactly 255."""
        w = np.clip(np.rint(weights * 255.0), 0, 255).astype(np.int32)
        top = np.argmax(w, axis=1)
        w[np.arange(len(w)), top] += 255 - w.sum(axis=1)
        return self.accessor(np.clip(w, 0, 255).astype(np.uint8), "VEC4", UBYTE, normalized=True)

    def _delta(self, d):
        """A morph target's offsets; sparse when most vertices do not move (faces, builds
        that leave the hat alone...), so only the moving ones are stored."""
        d = d.astype(np.float32)
        d[np.abs(d) < 2e-4] = 0.0
        moving = np.nonzero(np.any(d != 0.0, axis=1))[0].astype(np.uint32)
        acc = {"componentType": FLOAT, "count": int(d.shape[0]), "type": "VEC3",
               "min": [float(x) for x in d.min(axis=0)], "max": [float(x) for x in d.max(axis=0)]}
        if len(moving) > 0.66 * len(d):
            acc["bufferView"] = self._view(np.ascontiguousarray(d).tobytes(), ARRAY_BUFFER)
        else:
            acc["sparse"] = {"count": max(int(len(moving)), 0),
                             "indices": {"bufferView": self._view(moving.tobytes()), "componentType": UINT},
                             "values": {"bufferView": self._view(np.ascontiguousarray(d[moving]).tobytes())}}
            if len(moving) == 0:
                acc.pop("sparse")
                acc["bufferView"] = self._view(np.ascontiguousarray(d).tobytes(), ARRAY_BUFFER)
        self.accessors.append(acc)
        return len(self.accessors) - 1

    def write(self, path, root_name="Character"):
        mesh_nodes = [i for i, n in enumerate(self.nodes) if "mesh" in n]
        root = {"name": root_name, "children": [self.skeleton_root] + mesh_nodes}
        self.nodes.append(root)
        doc = {
            "asset": {"version": "2.0", "generator": "The Thief of London character builder"},
            "scene": 0,
            "scenes": [{"nodes": [len(self.nodes) - 1]}],
            "nodes": self.nodes,
            "meshes": self.meshes,
            "materials": self.materials,
            "skins": self.skins,
            "accessors": self.accessors,
            "bufferViews": self.views,
            "buffers": [{"byteLength": len(self.bin)}],
        }
        js = json.dumps(doc, separators=(",", ":")).encode()
        while len(js) % 4:
            js += b" "
        binary = bytes(self.bin)
        while len(binary) % 4:
            binary += b"\0"
        with open(path, "wb") as f:
            f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(binary)))
            f.write(struct.pack("<II", len(js), 0x4E4F534A))
            f.write(js)
            f.write(struct.pack("<II", len(binary), 0x004E4942))
            f.write(binary)
