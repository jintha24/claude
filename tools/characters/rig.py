"""The skeleton: MakeHuman's "game engine" rig (bone names like Unreal/Unity: pelvis,
spine_01..03, neck_01, head, clavicle_l, upperarm_l, lowerarm_l, hand_l, fingers, thigh_l,
calf_l, foot_l, ball_l) placed on the shaped body, with its CC0 skin weights."""
import json
import os

import numpy as np

from mh import DATA


class Rig:
    def __init__(self):
        self.defs = json.load(open(os.path.join(DATA, "rig", "rig.game_engine.json")))
        w = json.load(open(os.path.join(DATA, "rig", "weights.game_engine.json")))["weights"]
        # Parent-first order.
        order, seen = [], set()

        def visit(name):
            if name in seen:
                return
            parent = self.defs[name]["parent"]
            if parent:
                visit(parent)
            seen.add(name)
            order.append(name)

        for name in self.defs:
            visit(name)
        self.bones = order
        self.index = {n: i for i, n in enumerate(order)}
        self.parent = [self.index[self.defs[n]["parent"]] if self.defs[n]["parent"] else -1 for n in order]
        self.raw_weights = w

    def joint_positions(self, mesh, verts):
        """Head position of every bone (MakeHuman units)."""
        heads = np.zeros((len(self.bones), 3))
        for i, name in enumerate(self.bones):
            spec = self.defs[name]["head"]
            heads[i] = self._point(mesh, verts, spec)
        return heads

    def tail_positions(self, mesh, verts):
        tails = np.zeros((len(self.bones), 3))
        for i, name in enumerate(self.bones):
            tails[i] = self._point(mesh, verts, self.defs[name]["tail"])
        return tails

    @staticmethod
    def _point(mesh, verts, spec):
        if spec["strategy"] == "CUBE":
            return mesh.cube_center(verts, spec["cube_name"])
        if spec["strategy"] == "MEAN":
            return verts[spec["vertex_indices"]].mean(axis=0)
        if spec["strategy"] == "VERTEX":
            return verts[spec["vertex_index"]]
        return np.array(spec["default_position"])

    def vertex_weights(self, n_verts, max_influences=4):
        """(joints, weights) arrays of shape (n_verts, 4), normalised."""
        lists = [[] for _ in range(n_verts)]
        for bone, pairs in self.raw_weights.items():
            b = self.index[bone]
            for v, wt in pairs:
                if v < n_verts and wt > 0.0:
                    lists[v].append((wt, b))
        joints = np.zeros((n_verts, max_influences), dtype=np.uint16)
        weights = np.zeros((n_verts, max_influences), dtype=np.float32)
        for v, lst in enumerate(lists):
            lst.sort(reverse=True)
            lst = lst[:max_influences]
            total = sum(wt for wt, _ in lst)
            if total <= 0.0:
                joints[v, 0] = self.index["head"]
                weights[v, 0] = 1.0
                continue
            for k, (wt, b) in enumerate(lst):
                joints[v, k] = b
                weights[v, k] = wt / total
        return joints, weights

    def dominant_bone(self, joints, weights):
        return np.array([self.bones[joints[v, int(np.argmax(weights[v]))]] for v in range(len(joints))])
