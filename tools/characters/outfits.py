"""Victorian outfits, built on the body: shirts, waistcoats, frock coats, greatcoats,
police tunics, livery, trousers, boots, dresses with crinolines, cassocks, shawls,
collars and cravats, gloves; hats (top hat, bowler, flat cap, custodian helmet, bonnet,
kepi); hair, buns, beards, moustaches and mutton-chops.

Each outfit is a list of pieces plus the body parts that stay visible. Materials are
named slots (coat, trousers, shirt...) that the game colours per person."""
import numpy as np

from body import tri_faces
from pieces import Piece, body_piece, eyes_piece, helper_piece, shell_piece, recompute_normals, rigid_weights, layer_garments
from textures import region_faces

PART_OF_BONE = {
    "head": "head", "neck_01": "head",
    "spine_01": "torso", "spine_02": "torso", "spine_03": "torso", "clavicle_l": "torso", "clavicle_r": "torso",
    "pelvis": "pelvis", "Root": "pelvis",
    "upperarm_l": "upperarm", "upperarm_r": "upperarm",
    "lowerarm_l": "lowerarm", "lowerarm_r": "lowerarm",
    "thigh_l": "thigh", "thigh_r": "thigh", "calf_l": "calf", "calf_r": "calf",
    "foot_l": "foot", "foot_r": "foot", "ball_l": "foot", "ball_r": "foot",
}


def part_of(bone):
    if bone in PART_OF_BONE:
        return PART_OF_BONE[bone]
    return "hand"  # hand, fingers and thumbs


# Garment tubes: [bone a, bone b, body part, radius at a, radius at b, ramp] per limb
# segment (bones without their _l/_r). Cloth hangs round a limb at least this far from
# its bone, so trousers and sleeves read as cloth, not skin; `ramp` fades it in from
# the joint at a (the hip, the shoulder) so the garment joins the body smoothly.
TROUSER_LEGS = [("thigh", "calf", "thigh", 0.118, 0.096, 0.25), ("calf", "foot", "calf", 0.092, 0.084, 0.0)]
BREECHES = [("thigh", "calf", "thigh", 0.12, 0.085, 0.25)]
SHIRT_SLEEVES = [("upperarm", "lowerarm", "upperarm", 0.066, 0.058, 0.3), ("lowerarm", "hand", "lowerarm", 0.056, 0.048, 0.0)]
COAT_SLEEVES = [("upperarm", "lowerarm", "upperarm", 0.078, 0.07, 0.3), ("lowerarm", "hand", "lowerarm", 0.067, 0.06, 0.0)]
BODICE_SLEEVES = [("upperarm", "lowerarm", "upperarm", 0.07, 0.062, 0.3), ("lowerarm", "hand", "lowerarm", 0.058, 0.05, 0.0)]


class Anatomy:
    """Face-level facts about the base body, computed once on the standard body."""

    def __init__(self, state):
        lib = state.lib
        self.faces = lib.mesh.groups["body"]
        n = len(self.faces)
        self.centroid = np.zeros((n, 3))
        self.part = []
        for i, f in enumerate(self.faces):
            vs = [v for v, _ in f]
            self.centroid[i] = state.v[vs].mean(axis=0)
            parts = [part_of(lib.dominant[v]) for v in vs]
            self.part.append(max(set(parts), key=parts.count))
        self.part = np.array(self.part)
        self.lips = region_faces("lips_solid")
        self.face_region = region_faces("face_solid")
        self.scalp = region_faces("scalp_solid")
        self.eyelids = region_faces("eyelids_solid")
        j = state.joint
        self.hip_y = j("pelvis")[1]
        self.waist_y = self.hip_y + 0.1
        self.neck_y = j("neck_01")[1]
        self.head_y = j("head")[1]
        self.knee_y = j("calf_l")[1]
        self.ankle_y = j("foot_l")[1]
        self.wrist_y = j("hand_l")[1]
        self.elbow = j("lowerarm_l")
        self.shoulder = j("upperarm_l")
        self.eye_y = state.cube("joint-l-eye")[1]
        self.mouth = state.cube("joint-mouth")
        self.jaw = state.cube("joint-jaw")
        body = state.v[:13380]
        head_mask = np.isin(np.array([part_of(b) for b in lib.dominant[:13380]]), ["head"])
        hv = body[head_mask]
        self.head_top = hv[:, 1].max()
        top_band = hv[hv[:, 1] > self.head_top - 0.06]
        self.head_center = np.array([0.0, self.head_top - 0.085, top_band[:, 2].mean()])
        band = hv[(hv[:, 1] > self.eye_y + 0.02) & (hv[:, 1] < self.eye_y + 0.05)]
        self.head_half_width = np.abs(band[:, 0]).max()
        self.head_half_depth = (band[:, 2].max() - band[:, 2].min()) * 0.5
        self.head_mid_z = (band[:, 2].max() + band[:, 2].min()) * 0.5
        nose = body[head_mask & (body[:, 1] > self.mouth[1]) & (body[:, 1] < self.eye_y)]
        self.nose_base_y = nose[np.argmin(nose[:, 2]), 1] - 0.012

    def select(self, pred):
        """Faces (of the body) for which pred(index, centroid, part) is true."""
        return [f for i, f in enumerate(self.faces) if pred(i, self.centroid[i], self.part[i])]

    def ids(self, pred):
        return tuple(i for i in range(len(self.faces)) if pred(i, self.centroid[i], self.part[i]))


# ---------------------------------------------------------------------------
# Garment region predicates (on face centroids, standard body)
# ---------------------------------------------------------------------------
def arms_to(a, y_end):
    """Sleeves down to a height on the arm (the wrist, or the elbow for rolled sleeves)."""
    return lambda i, c, p: p in ("upperarm",) or (p == "lowerarm" and c[1] > y_end)


def torso_between(a, y_low, y_high=10.0):
    return lambda i, c, p: p in ("torso", "pelvis", "upperarm", "thigh") and y_low < c[1] < y_high and not (p in ("upperarm",)) and not (p == "thigh" and c[1] > y_high)


class Builder:
    """Builds the pieces of one outfit on a BodyState (called again for each morph)."""

    def __init__(self, anatomy):
        self.a = anatomy

    # --- body -----------------------------------------------------------------
    def body_parts(self, state, visible):
        a = self.a
        faces = [f for i, f in enumerate(a.faces) if a.part[i] in visible]
        key = "body:" + ",".join(sorted(visible))
        return body_piece(state, key, faces, "body", "skin")

    def face_extras(self, state):
        return [
            eyes_piece(state),
            helper_piece(state, ["helper-l-eyelashes-1", "helper-l-eyelashes-2", "helper-r-eyelashes-1", "helper-r-eyelashes-2"], "lashes", "lash"),
            helper_piece(state, ["helper-upper-teeth", "helper-lower-teeth"], "teeth", "teeth"),
        ]

    # --- shells ---------------------------------------------------------------
    def shell(self, state, key, pred, name, material, t, **kw):
        a = self.a
        ids = a.ids(pred) if not isinstance(pred, tuple) else pred
        faces = [a.faces[i] for i in ids]
        return shell_piece(state, key, faces, name, material, t, **kw)

    def tubes(self, state, piece, spec):
        """Lets a garment hang round each limb segment in `spec` (see TROUSER_LEGS)."""
        vids = getattr(piece, "base_vids", None)
        if vids is None or not spec:
            return piece
        nb = len(vids)
        P = piece.positions
        lib = state.lib
        parts = np.array([part_of(lib.dominant[v]) for v in vids])
        delta = np.zeros((nb, 3))
        for bone_a, bone_b, part, r0, r1, ramp in spec:
            for side in ("l", "r"):
                A = state.joint(bone_a + "_" + side)
                B = state.joint(bone_b + "_" + side)
                d = B - A
                L = float(np.linalg.norm(d))
                d = d / L
                sel = np.nonzero((parts == part) & (np.sign(state.v[vids][:, 0]) == np.sign(A[0])))[0]
                if len(sel) == 0:
                    continue
                p = P[sel] - A
                t = np.clip(p @ d / L, 0.0, 1.0)
                radial = p - np.outer(t * L, d)
                rlen = np.maximum(np.linalg.norm(radial, axis=1), 1e-6)
                want = r0 + (r1 - r0) * t
                w = np.clip(t / ramp, 0.0, 1.0) if ramp > 0 else np.ones_like(t)
                w = w * w * (3.0 - 2.0 * w)
                grow = np.maximum(want - rlen, 0.0) * w
                delta[sel] = radial / rlen[:, None] * grow[:, None]
        P[:nb] += delta
        if len(piece.hem_src):
            P[nb:nb + len(piece.hem_src)] += delta[piece.hem_src]
        piece.normals = recompute_normals(P, piece.tris)
        return piece

    def shirt(self, state, sleeves="wrist", key="shirt"):
        a = self.a
        y_end = a.wrist_y + 0.03 if sleeves == "wrist" else a.elbow[1] - 0.02
        pred = lambda i, c, p: (p in ("torso", "upperarm") or (p == "lowerarm" and c[1] > y_end) or (p == "pelvis" and c[1] > a.hip_y - 0.02) or (p == "head" and c[1] < a.neck_y + 0.03 and i not in a.face_region))
        piece = self.shell(state, key, pred, "shirt", "shirt", 0.008, uv_scale=8.0, drape_iterations=10)
        return self.tubes(state, piece, SHIRT_SLEEVES)

    def waistcoat(self, state):
        a = self.a
        pred = lambda i, c, p: p in ("torso", "pelvis") and a.hip_y - 0.03 < c[1] < a.neck_y - 0.04
        return self.shell(state, "waistcoat", pred, "waistcoat", "waistcoat", 0.016, uv_scale=8.0, drape_iterations=16, give=0.6)

    def coat_body(self, state, key, y_low, sleeve_end, material="coat", t_body=0.03, t_arm=0.018, drape_iterations=30, sleeves=None, open_front=0.0):
        a = self.a
        pred = lambda i, c, p: ((p in ("torso", "upperarm") or (p == "pelvis" and c[1] > y_low) or (p == "thigh" and c[1] > y_low)
                                 or (p == "lowerarm" and c[1] > sleeve_end)
                                 or (p == "head" and c[1] < a.neck_y + 0.01 and i not in a.face_region)))
        if open_front > 0.0:
            # Worn open: a V down the front from the collar to the hem shows what's under it.
            base_pred = pred
            chest_z = state.joint("spine_03")[2]

            def pred(i, c, p):
                if c[2] < chest_z - 0.03 and c[1] < a.neck_y - 0.03 and p in ("torso", "pelvis", "thigh"):
                    width = open_front * (0.45 + 0.55 * np.clip((a.neck_y - c[1]) / 0.35, 0.0, 1.0))
                    if abs(c[0]) < width:
                        return False
                return base_pred(i, c, p)

        def thick(st, vids):
            parts = np.array([part_of(st.lib.dominant[v]) for v in vids])
            return np.where(np.isin(parts, ["upperarm", "lowerarm", "hand"]), t_arm, t_body)
        piece = self.shell(state, key, pred, "coat", material, thick, uv_scale=7.0, drape_iterations=drape_iterations, give=0.75)
        return self.tubes(state, piece, sleeves if sleeves is not None else COAT_SLEEVES)

    def coat_skirt(self, state, key, hem_y, front_open=0.0, flare=0.18, material="coat"):
        """Coat tails from MakeHuman's skirt helper, cut at the hem and flared."""
        lib = state.lib
        a = self.a
        faces = lib.mesh.groups["helper-skirt"]
        # Keep rows between the hips and the hem (standard body).
        sel = []
        for f in faces:
            ys = [state.v[v][1] for v, _ in f]
            zs = [state.v[v][2] for v, _ in f]
            xs = [state.v[v][0] for v, _ in f]
            if min(ys) < hem_y - 0.01:
                continue
            if max(ys) > a.hip_y + 0.02:
                continue
            if front_open > 0.0 and np.mean(zs) < 0.0 and abs(np.mean(xs)) < front_open:
                continue
            sel.append(f)
        top = a.hip_y + 0.02

        def thick(st, vids):
            y = st.v[vids][:, 1]
            depth = np.clip((top - y) / max(top - hem_y, 0.1), 0.0, 1.0)
            return 0.012 + flare * depth ** 1.4 * 0.35
        return shell_piece(state, "skirt:" + key, sel, "coat_skirt", material, thick, uv_scale=7.0)

    def trousers(self, state, hem=None, loose=0.012, straight=True):
        a = self.a
        hem = hem if hem is not None else a.ankle_y + 0.035
        pred = lambda i, c, p: (p in ("thigh",) or (p == "calf" and c[1] > hem) or (p == "pelvis" and c[1] < a.waist_y))

        def thick(st, vids):
            y = st.v[vids][:, 1]
            return loose + 0.012 * np.clip((a.hip_y - y) / a.hip_y, 0, 1)
        piece = self.shell(state, "trousers:%.3f" % hem, pred, "trousers", "trousers", thick, uv_scale=8.0, drape_iterations=30)
        # Straight legs hanging from the hips (or breeches, full only to the knee).
        return self.tubes(state, piece, TROUSER_LEGS if straight else BREECHES)

    def boots(self, state, top=None, key="boots"):
        a = self.a
        top = top if top is not None else a.ankle_y + 0.16
        pred = lambda i, c, p: p == "foot" or (p == "calf" and c[1] < top)
        # Thick leather smoothed right over the toes: a boot, not a foot.
        piece = self.shell(state, key + ":%.3f" % top, pred, "boots", "boots", 0.013, uv_scale=6.0, hem=0.006, drape_iterations=60, give=0.3)
        if key == "riding_boots":
            piece.name = "riding_boots"  # worn over the breeches (see pieces.LAYER)
        return self._boot_last(state, piece)

    def _boot_last(self, state, piece):
        """Shapes the foot of a boot on a last: every slice across the foot becomes a smooth
        rounded outline (no toes), the sole stays flat."""
        vids = piece.base_vids
        nb = len(vids)
        P = piece.positions
        parts = np.array([part_of(state.lib.dominant[v]) for v in vids])
        delta = np.zeros((nb, 3))
        up = np.array([0.0, 1.0, 0.0])
        for side in ("l", "r"):
            A = state.joint("foot_" + side)
            B = state.joint("ball_" + side)
            f = B - A
            f[1] = 0.0
            f /= np.linalg.norm(f)
            lat = np.cross(up, f)
            sel = np.nonzero((parts == "foot") & (np.sign(state.v[vids][:, 0]) == np.sign(A[0])))[0]
            if len(sel) < 10:
                continue
            q = P[sel] - A
            u, v, w = q @ f, q @ lat, q[:, 1]
            bins = np.floor((u - u.min()) / 0.015).astype(int)
            nbins = bins.max() + 1
            ext = np.zeros((nbins, 4))  # vmin, vmax, wmin, wmax
            for k in range(nbins):
                m = bins == k
                if not np.any(m):
                    ext[k] = ext[k - 1] if k > 0 else [v.min(), v.max(), w.min(), w.max()]
                    continue
                ext[k] = [v[m].min(), v[m].max(), w[m].min(), w[m].max()]
            # Even out the slices along the foot (a last has no knuckles).
            sm = ext.copy()
            for _ in range(3):
                pad = np.vstack([sm[:1], sm, sm[-1:]])
                sm = (pad[:-2] + 2.0 * pad[1:-1] + pad[2:]) / 4.0
            sm[:, 2] = np.minimum(sm[:, 2], ext[:, 2])  # keep the sole down
            e = sm[bins]
            cv, av = (e[:, 0] + e[:, 1]) * 0.5, np.maximum((e[:, 1] - e[:, 0]) * 0.5, 0.005)
            cw, aw = (e[:, 2] + e[:, 3]) * 0.5, np.maximum((e[:, 3] - e[:, 2]) * 0.5, 0.005)
            ang = np.arctan2((w - cw) / aw, (v - cv) / av)
            c, s_ = np.cos(ang), np.sin(ang)
            nv = cv + av * np.sign(c) * np.abs(c) ** (2.0 / 3.0)
            nw = cw + aw * np.sign(s_) * np.abs(s_) ** (2.0 / 3.0)
            delta[sel] = np.outer(nv - v, lat) + np.outer(nw - w, up)
        P[:nb] += delta
        if len(piece.hem_src):
            P[nb:nb + len(piece.hem_src)] += delta[piece.hem_src]
        piece.normals = recompute_normals(P, piece.tris)
        return piece

    def stockings(self, state, top):
        """Knee stockings (boys in short trousers)."""
        pred = lambda i, c, p: p == "calf" and c[1] < top
        return self.shell(state, "stockings:%.3f" % top, pred, "stockings", "stockings", 0.003, uv_scale=8.0, hem=0.003)

    def gloves(self, state):
        a = self.a
        pred = lambda i, c, p: p == "hand" or (p == "lowerarm" and c[1] < a.wrist_y + 0.05)
        return self.shell(state, "gloves", pred, "gloves", "gloves", 0.003, uv_scale=6.0, hem=0.003)

    def band(self, state, key, y0, y1, name, material, t, parts=("torso", "pelvis")):
        pred = lambda i, c, p: p in parts and y0 < c[1] < y1
        return self.shell(state, key, pred, name, material, t, uv_scale=6.0, hem=0.006)

    def collar(self, state, key="collar", material="collar", height=0.035):
        a = self.a
        pred = lambda i, c, p: p == "head" and c[1] < a.neck_y + height and c[1] > a.neck_y - 0.03 and i not in a.face_region
        return self.shell(state, key, pred, "collar", material, 0.012, uv_scale=6.0, hem=0.006)

    def cravat(self, state):
        a = self.a
        pred = lambda i, c, p: p in ("head", "torso") and a.neck_y - 0.07 < c[1] < a.neck_y + 0.02 and c[2] < a.head_mid_z - 0.02 and abs(c[0]) < 0.05 and i not in a.face_region
        return self.shell(state, "cravat", pred, "cravat", "cravat", 0.02, uv_scale=6.0, hem=0.008)

    def shawl(self, state):
        a = self.a
        pred = lambda i, c, p: (p in ("torso", "upperarm") and c[1] > a.shoulder[1] - 0.27) or (p == "head" and c[1] < a.neck_y and i not in a.face_region)
        return self.shell(state, "shawl", pred, "shawl", "shawl", 0.034, uv_scale=6.0, drape_iterations=80)

    def bell_skirt(self, state, key, bell=1.1, hem_y=0.03, material="dress", name="dress_skirt", rigid=True):
        """A dress skirt from the skirt helper, belled out over a crinoline down to the floor."""
        lib = state.lib
        a = self.a
        faces = lib.mesh.groups["helper-skirt"]
        vids_all = sorted({v for f in faces for v, _ in f})
        piece = shell_piece(state, "bell:" + key, faces, name, material, 0.004, uv_scale=7.0)
        # Re-shape: bell out radially from the body axis and drop the hem to the floor.
        top = a.hip_y + 0.08
        base_bottom = min(state.v[v][1] for v in vids_all)
        p = piece.positions
        depth = np.clip((top - p[:, 1]) / max(top - base_bottom, 0.1), 0.0, 1.0)
        center = np.array([0.0, 0.0, state.joint("pelvis")[2]])
        radial = p - center
        radial[:, 1] = 0.0
        p[:, 0] = center[0] + radial[:, 0] * (1.0 + bell * depth ** 1.6)
        p[:, 2] = center[2] + radial[:, 2] * (1.0 + bell * depth ** 1.6)
        p[:, 1] = top - depth * (top - hem_y)
        piece.positions = p
        if rigid:
            j, w = rigid_weights(state, len(p), "pelvis")
            piece.joints, piece.weights = j, w
        piece.normals = recompute_normals(p, piece.tris)
        return piece

    # --- hair and beards --------------------------------------------------------
    def hair(self, state, key="hair", t=0.006):
        a = self.a
        pred = lambda i, c, p: i in a.scalp
        piece = self.shell(state, key, pred, "hair", "hair", t, uv_scale=3.0, hem=0.003, fade_rings=2)
        piece.joints, piece.weights = rigid_weights(state, piece.vertex_count, "head")
        return piece

    def beard(self, state, style):
        a = self.a
        nb = a.nose_base_y

        def full(i, c, p):
            return (i in a.face_region and c[1] < nb and i not in a.lips) or (p == "head" and a.jaw[1] - 0.05 < c[1] < a.jaw[1] + 0.01 and c[2] < a.head_mid_z + 0.02 and i not in a.lips)

        def moustache(i, c, p):
            return i in a.face_region and nb - 0.027 < c[1] < nb + 0.004 and abs(c[0]) < 0.043 and i not in a.lips and c[2] < a.mouth[2] + 0.004

        def chops(i, c, p):
            side = abs(c[0]) > 0.045 and i in a.face_region and a.jaw[1] - 0.01 < c[1] < a.eye_y - 0.02 and c[2] > a.mouth[2] - 0.01
            return side or moustache(i, c, p)
        pred = {"full": full, "moustache": moustache, "chops": chops}[style]
        piece = self.shell(state, "beard:" + style, pred, "beard_" + style, "beard", 0.0045, uv_scale=4.0, hem=0.003, drape_iterations=8, fade_rings={"full": 3, "chops": 2, "moustache": 1}[style])
        piece.joints, piece.weights = rigid_weights(state, piece.vertex_count, "head")
        return piece

    # --- hats (lathe meshes, riding the head) ------------------------------------
    def lathe(self, state, name, material, profile, segments=28, offset=(0.0, 0.0, 0.0), squash=1.14, tilt=0.0, arc=None):
        """Surface of revolution round the head's vertical axis. profile: [(radius, height)]
        from the brim up. The hat is oval (heads are longer than wide) and sits on the head."""
        a = self.a
        base = np.array([0.0, a.head_top - 0.055, a.head_mid_z]) + np.array(offset)
        scale_r = a.head_half_width / 0.078
        pos, uv = [], []
        a0, a1 = arc if arc else (0.0, 2 * np.pi)
        closed = arc is None
        nseg = segments if closed else segments + 1
        for k, (r, h) in enumerate(profile):
            for s in range(nseg):
                ang = a0 + (a1 - a0) * s / segments
                x = np.sin(ang) * r * scale_r
                z = np.cos(ang) * r * scale_r * squash
                y = h
                # tilt forward/back round X
                y2 = y * np.cos(tilt) - z * np.sin(tilt)
                z2 = y * np.sin(tilt) + z * np.cos(tilt)
                pos.append(base + np.array([x, y2, z2]))
                uv.append([s / segments * 4.0, k / max(len(profile) - 1, 1) * 2.0])
        tris = []
        for k in range(len(profile) - 1):
            for s in range(segments):
                i0 = k * nseg + s
                i1 = k * nseg + (s + 1) % nseg if closed else k * nseg + s + 1
                j0 = i0 + nseg
                j1 = i1 + nseg
                tris += [[i0, j0, i1], [i1, j0, j1]]
        pos = np.array(pos)
        tris = np.array(tris)
        j, w = rigid_weights(state, len(pos), "head")
        return Piece(name, material, pos, recompute_normals(pos, tris), np.array(uv), tris, j, w, double_sided=True)

    def top_hat(self, state):
        prof = [(0.0, 0.205), (0.092, 0.205), (0.097, 0.2), (0.1, 0.16), (0.097, 0.06), (0.098, 0.012), (0.12, 0.004), (0.155, 0.012), (0.16, 0.022), (0.152, 0.018), (0.12, 0.0), (0.098, 0.0)]
        prof.reverse()
        return [self.lathe(state, "hat_top", "hat", prof, tilt=0.04),
                self.lathe(state, "hat_top_band", "hatband", [(0.1, 0.012), (0.1005, 0.048)], tilt=0.04)]

    def bowler(self, state):
        prof = [(0.0, 0.135), (0.05, 0.13), (0.085, 0.105), (0.1, 0.06), (0.1, 0.015), (0.125, 0.006), (0.14, 0.02), (0.133, 0.014), (0.1, 0.0)]
        prof.reverse()
        return [self.lathe(state, "hat_bowler", "hat", prof, tilt=0.05),
                self.lathe(state, "hat_bowler_band", "hatband", [(0.1005, 0.012), (0.101, 0.032)], tilt=0.05)]

    def flat_cap(self, state):
        a = self.a
        prof = [(0.0, 0.07), (0.07, 0.068), (0.11, 0.05), (0.118, 0.03), (0.105, 0.012), (0.098, 0.0)]
        prof.reverse()
        cap = self.lathe(state, "hat_cap", "cap", prof, offset=(0.0, -0.012, -0.012), tilt=0.12)
        peak = self.lathe(state, "hat_cap_peak", "cap", [(0.098, 0.004), (0.128, 0.0), (0.14, -0.006)], offset=(0.0, -0.012, -0.012), tilt=0.12, arc=(np.pi * 0.72, np.pi * 1.28), segments=10)
        return [cap, peak]

    def custodian_helmet(self, state):
        prof = [(0.0, 0.25), (0.03, 0.248), (0.06, 0.23), (0.085, 0.19), (0.1, 0.12), (0.1, 0.05), (0.103, 0.0), (0.12, -0.012), (0.118, -0.018), (0.1, -0.008)]
        prof.reverse()
        return [self.lathe(state, "hat_helmet", "helmet", prof, offset=(0.0, -0.01, 0.0), tilt=0.03),
                self.lathe(state, "hat_helmet_plate", "badge", [(0.1045, 0.06), (0.1045, 0.12)], offset=(0.0, -0.01, 0.0), tilt=0.03, arc=(np.pi * 0.9, np.pi * 1.1), segments=4)]

    def kepi(self, state):
        prof = [(0.0, 0.1), (0.09, 0.1), (0.094, 0.06), (0.1, 0.0)]
        prof.reverse()
        cap = self.lathe(state, "hat_kepi", "hat", prof, tilt=0.16)
        peak = self.lathe(state, "hat_kepi_peak", "hatband", [(0.1, 0.0), (0.135, -0.01)], tilt=0.16, arc=(np.pi * 0.72, np.pi * 1.28), segments=10)
        return [cap, peak]

    def bonnet(self, state):
        # A coal-scuttle bonnet: open at the face, framing it.
        prof = [(0.0, 0.118), (0.05, 0.113), (0.085, 0.095), (0.105, 0.06), (0.112, 0.02), (0.112, -0.025), (0.106, -0.065), (0.118, -0.08)]
        brim = self.lathe(state, "hat_bonnet", "bonnet", prof, offset=(0.0, 0.0, 0.008), squash=1.1, arc=(-np.pi * 0.6, np.pi * 0.6), segments=22)
        return [brim]

    def bun(self, state):
        a = self.a
        c = np.array([0.0, a.head_top - 0.085, a.head_mid_z + a.head_half_depth + 0.01])
        pos, uv, tris = [], [], []
        rings, segs = 8, 12
        for r in range(rings + 1):
            th = np.pi * r / rings
            for s in range(segs):
                ph = 2 * np.pi * s / segs
                pos.append(c + np.array([np.sin(th) * np.cos(ph) * 0.045, np.cos(th) * 0.04, np.sin(th) * np.sin(ph) * 0.035]))
                uv.append([s / segs, r / rings])
        for r in range(rings):
            for s in range(segs):
                i0 = r * segs + s
                i1 = r * segs + (s + 1) % segs
                tris += [[i0, i0 + segs, i1], [i1, i0 + segs, i1 + segs]]
        pos = np.array(pos)
        tris = np.array(tris)
        j, w = rigid_weights(state, len(pos), "head")
        return Piece("hair_bun", "hair", pos, recompute_normals(pos, tris), np.array(uv), tris, j, w)

    def buttons(self, state, key, ys, material="buttons", column_x=(0.0,), bone="spine_02"):
        """Small domed buttons on the front of the torso at heights `ys`."""
        a = self.a
        body = state.v[:13380]
        pos, tris, uv = [], [], []
        for y in ys:
            for cx in column_x:
                near = body[(np.abs(body[:, 1] - y) < 0.01) & (np.abs(body[:, 0] - cx) < 0.015)]
                if len(near) == 0:
                    near = body[np.argsort(np.abs(body[:, 1] - y) + np.abs(body[:, 0] - cx))[:1]]
                front = near[np.argmin(near[:, 2])] + np.array([0.0, 0.0, -0.028])
                base = len(pos)
                segs = 8
                pos.append(front + np.array([0, 0, -0.004]))
                for s in range(segs):
                    ang = 2 * np.pi * s / segs
                    pos.append(front + np.array([np.cos(ang) * 0.007, np.sin(ang) * 0.007, 0.0]))
                    uv.append([0.5, 0.5])
                uv.append([0.5, 0.5])
                for s in range(segs):
                    tris.append([base, base + 1 + (s + 1) % segs, base + 1 + s])
        pos = np.array(pos)
        tris = np.array(tris)
        j, w = rigid_weights(state, len(pos), bone)
        return Piece(key, material, pos, recompute_normals(pos, tris), np.array(uv), tris, j, w)


# ---------------------------------------------------------------------------
# The outfits
# ---------------------------------------------------------------------------
MALE = {"gender": 1.0, "age": 0.58, "muscle": 0.5, "weight": 0.5, "height": 0.5, "proportions": 0.55, "race": {"caucasian": 0.9, "african": 0.05, "asian": 0.05}}
FEMALE = {"gender": 0.0, "age": 0.56, "muscle": 0.45, "weight": 0.5, "height": 0.5, "proportions": 0.6, "race": {"caucasian": 0.9, "african": 0.05, "asian": 0.05}}
CHILD = {"gender": 0.85, "age": 0.21, "muscle": 0.4, "weight": 0.35, "height": 0.5, "proportions": 0.5, "race": {"caucasian": 1.0}}
HARRY = {"gender": 1.0, "age": 0.53, "muscle": 0.72, "weight": 0.42, "height": 0.9, "proportions": 0.85, "race": {"caucasian": 1.0}}


def outfit_pieces(name, builder, state, male=True):
    b = builder
    a = b.a
    P = []
    extras = b.face_extras(state)
    if name == "gentleman":
        P += [b.body_parts(state, {"head", "hand"}), b.shirt(state), b.waistcoat(state), b.coat_body(state, "frock", a.hip_y - 0.12, a.wrist_y + 0.035),
              b.coat_skirt(state, "frock", a.knee_y + 0.02, flare=0.12), b.trousers(state), b.boots(state, a.ankle_y + 0.05, "shoes"), b.collar(state), b.cravat(state), b.hair(state)]
        P += b.top_hat(state) + b.bowler(state)
        P += [b.beard(state, s) for s in ("full", "moustache", "chops")]
        P.append(b.buttons(state, "waistcoat_buttons", [a.hip_y + 0.06 + k * 0.045 for k in range(5)], bone="spine_02"))
    elif name == "worker":
        P += [b.body_parts(state, {"head", "hand", "lowerarm"}), b.shirt(state, "elbow", "shirt_rolled"), b.waistcoat(state), b.trousers(state, loose=0.016),
              b.boots(state), b.band(state, "neckerchief", a.neck_y - 0.035, a.neck_y + 0.02, "neckerchief", "cravat", 0.014, parts=("head", "torso")), b.hair(state)]
        P += b.flat_cap(state)
        P += [b.beard(state, s) for s in ("full", "moustache", "chops")]
        P.append(b.buttons(state, "waistcoat_buttons", [a.hip_y + 0.06 + k * 0.045 for k in range(5)], bone="spine_02"))
    elif name == "ragged":
        P += [b.body_parts(state, {"head", "hand", "lowerarm"}), b.shirt(state, "elbow", "shirt_rolled"), b.coat_body(state, "ragcoat", a.hip_y - 0.1, a.elbow[1] - 0.06, t_body=0.02, t_arm=0.016),
              b.trousers(state, hem=a.ankle_y + 0.12, loose=0.015), b.boots(state, a.ankle_y + 0.07, "shoes"), b.band(state, "neckerchief", a.neck_y - 0.035, a.neck_y + 0.02, "neckerchief", "cravat", 0.014, parts=("head", "torso")), b.hair(state)]
        P += b.flat_cap(state)
        P += [b.beard(state, s) for s in ("full", "moustache", "chops")]
    elif name == "constable":
        P += [b.body_parts(state, {"head", "hand"}), b.coat_body(state, "tunic", a.hip_y - 0.16, a.wrist_y + 0.035, material="coat", t_body=0.02, t_arm=0.016),
              b.trousers(state), b.boots(state), b.band(state, "belt", a.hip_y + 0.04, a.hip_y + 0.1, "belt", "belt", 0.03), b.collar(state, "tunic_collar", "coat", 0.045), b.hair(state)]
        P += b.custodian_helmet(state)
        P += [b.beard(state, s) for s in ("full", "moustache", "chops")]
        P.append(b.buttons(state, "tunic_buttons", [a.hip_y + 0.13 + k * 0.06 for k in range(5)], bone="spine_02"))
    elif name == "house_guard":
        P += [b.body_parts(state, {"head", "hand"}), b.shirt(state), b.coat_body(state, "livery", a.hip_y - 0.12, a.wrist_y + 0.035, material="coat"),
              b.coat_skirt(state, "livery", a.knee_y + 0.12, flare=0.1), b.trousers(state), b.boots(state), b.collar(state, "livery_collar", "trim", 0.04),
              b.band(state, "cuffs_l", a.wrist_y + 0.035, a.wrist_y + 0.1, "cuffs", "trim", 0.022, parts=("lowerarm",)), b.hair(state)]
        P += b.kepi(state)
        P += [b.beard(state, s) for s in ("moustache", "chops")]
        P.append(b.buttons(state, "livery_buttons", [a.hip_y + 0.1 + k * 0.06 for k in range(5)], bone="spine_02"))
    elif name == "priest":
        P += [b.body_parts(state, {"head", "hand"}), b.coat_body(state, "cassock", a.hip_y - 0.05, a.wrist_y + 0.035, material="cassock", t_body=0.016, t_arm=0.014),
              b.bell_skirt(state, "cassock", bell=0.28, hem_y=0.05, material="cassock", name="cassock_skirt", rigid=False), b.boots(state, a.ankle_y + 0.05, "shoes"),
              b.collar(state, "clerical_collar", "collar", 0.03), b.hair(state)]
        P.append(b.buttons(state, "cassock_buttons", [a.hip_y + 0.05 + k * 0.05 for k in range(8)], bone="spine_02"))
    elif name == "lady":
        P += [b.body_parts(state, {"head", "hand"}), b.coat_body(state, "bodice", a.hip_y + 0.02, a.wrist_y + 0.03, material="dress", t_body=0.012, t_arm=0.007, drape_iterations=30, sleeves=BODICE_SLEEVES),
              b.bell_skirt(state, "crinoline", bell=1.15), b.shawl(state), b.collar(state, "lace_collar", "collar", 0.03), b.hair(state), b.bun(state)]
        P += b.bonnet(state)
    elif name == "child":
        P += [b.body_parts(state, {"head", "hand", "lowerarm"}), b.shirt(state, "elbow", "shirt_rolled"), b.coat_body(state, "jacket", a.hip_y - 0.05, a.elbow[1] - 0.04, t_body=0.018, t_arm=0.015),
              b.trousers(state, hem=a.knee_y - 0.08, loose=0.016), b.stockings(state, a.knee_y - 0.04), b.boots(state, a.ankle_y + 0.07, "shoes"), b.hair(state)]
        P += b.flat_cap(state)
    elif name == "harry":
        P += [b.body_parts(state, {"head"}), b.shirt(state), b.waistcoat(state), b.coat_body(state, "greatcoat:open", a.hip_y - 0.14, a.wrist_y + 0.03, material="greatcoat", t_body=0.036, t_arm=0.022, open_front=0.085),
              b.coat_skirt(state, "greatcoat", a.knee_y - 0.2, front_open=0.06, flare=0.24, material="greatcoat"), b.trousers(state, straight=False), b.boots(state, a.knee_y - 0.03, "riding_boots"),
              b.gloves(state), b.band(state, "belt", a.hip_y + 0.03, a.hip_y + 0.08, "belt", "belt", 0.034), b.cravat(state), b.hair(state), b.beard(state, "chops")]
        P += b.top_hat(state)
    else:
        raise ValueError(name)
    return layer_garments(state, P) + extras


OUTFITS = {
    # name: (base parameters, male, morphs)
    "gentleman": (MALE, True),
    "worker": (MALE, True),
    "ragged": (MALE, True),
    "constable": (MALE, True),
    "house_guard": (MALE, True),
    "priest": (MALE, True),
    "lady": (FEMALE, False),
    "child": (CHILD, True),
    "harry": (HARRY, True),
}
