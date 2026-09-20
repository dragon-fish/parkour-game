"""Extract one Mirror's Edge level (config-selected packages) into a manifest.

    uv run --no-project --python 3.12 --with lzallright \\
        docs/mirrors-edge-deep-research/tools/level_extract/extract.py <config.json>

Writes _local/me-reference/level-extract/<id>/{manifest,meshes}.json. Both are
regenerable and never committed. The Godot side (tools/me_level/) builds the
mesh library, geometry scene and shell from them.
"""
import json
import math
import os
import sys

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from common import (UU, ExtractError, actor_scale, godot_basis, import_root_package, outer_class, pivot_offset,
                    point, ref_export, ref_import)
import annotations
import lights
import packages as pk
import materials as material_bake
import static_mesh
import matinee
import environment
import kismet
import streaming

# InterpActors are movers: placed like any mesh, moved by matinee.py's data.
PLACED_CLASSES = ('StaticMeshActor', 'InterpActor')
# Matched case-insensitively: Stormdrain spells it S_Skydome_Sunrise_Steel,
# and a dome that slipped through filled the sky with a flat pale shell, cut
# into a circle by the camera's far plane.
FX_MESH_MARKERS = ('_fx_', 'skydome', 'sunflare', 'godray')
# [ME:INFERRED] a lightmap-bake occluder: S_LightSquare_01 planes in the _Lgts
# packages, standing in doorways and over rooms to keep light out of them.
# None shows in the original. Built as shadow casters only -- no picture, no
# collision: drawn, they were black walls, several of them solid; left out,
# the live sun came in where the bake had kept it out.
BAKE_ONLY_MATERIAL = 'M_BakeBlack'
# Checkpoints are taken from the persistent level when they fall inside the
# section's own placements (no slices, no _Bac skyline), grown by this.
SECTION_MARGIN_M = 2.0


def project_root():
    here = os.path.abspath(os.path.dirname(__file__))
    while not os.path.exists(os.path.join(here, 'project.godot')):
        parent = os.path.dirname(here)
        if parent == here:
            raise ExtractError('project.godot not found above %s' % __file__)
        here = parent
    return here


class MeshTable:
    """Every referenced StaticMesh, parsed once and checked for consistency by name."""

    def __init__(self, packages, report, baker):
        self.packages = packages
        self.baker = baker
        self.bakes = {}
        self.report = report
        self.records = {}
        # Meshes sharing a name with a different one already in `records`.
        self.variants = []
        self._soft = {}
        self._parsed = {}
        self._materials = {}

    def get(self, mr, export_idx):
        key = (mr.label, export_idx)
        if key in self._parsed:
            return self._parsed[key]
        self._parsed[key] = self._load(mr, export_idx)
        return self._parsed[key]

    def _load(self, mr, export_idx):
        name = mr.pkg.exports[export_idx - 1]['name']
        record = static_mesh.parse_render(mr, export_idx)
        shapes, material = static_mesh.simple_collision(mr, record.pop('body_setup'))
        record['name'] = name
        record['source'] = mr.label
        record['path'] = mr.pkg.full_name(export_idx)
        record['simple_shapes'] = shapes
        record['soft_landing'] = self._soft_landing(material)
        for surface in record['surfaces']:
            ref = surface.pop('material_ref')
            surface.update(self._material(mr, ref))
            material_name = surface['material']
            if material_name and material_name not in self.bakes:
                rr, ri = self.baker.resolve(mr, ref)
                self.bakes[material_name] = self.baker.bake(rr, ri) if rr else None
        known = self.records.get(name)
        if known is None:
            self.records[name] = record
            return record
        for other in [known] + [v for v in self.variants if v['name'] == name]:
            if _same_mesh(other, record):
                return other
        # A DIFFERENT mesh under the same name: Subway_Bac holds B_Vista.SP03
        # and B_Vista.SP04's Vista_Mountains, Mall two packages' S_Policecar_01.
        # Both get their path as a suffix when the manifest is written
        # (finish_names); the library is keyed by name, and one name for both
        # would have one level drawing the other's mesh.
        known['variant'] = True
        record['variant'] = True
        self.variants.append(record)
        return record

    def finish_names(self):
        """Every mesh by its final name, variants suffixed with their path."""
        out = {}
        for record in list(self.records.values()) + self.variants:
            # Popped, not kept: the library hashes the whole record, and a new
            # key would rebuild every mesh of every level once for nothing.
            path = record.pop('path')
            if record.pop('variant', False):
                record['name'] = '%s@%s' % (record['name'], path.rsplit('.', 1)[0] if '.' in path else record['source'])
            out[record['name']] = record
        return out

    def override(self, mr, reference):
        """A component's per-placement material: its name and how it draws,
        baked like any mesh material."""
        name = mr.pkg.resolve(reference)
        entry = {'material': name}
        entry.update(self._material(mr, reference))
        if name and name not in self.bakes:
            rr, ri = self.baker.resolve(mr, reference)
            self.bakes[name] = self.baker.bake(rr, ri) if rr else None
        return entry

    def resolve(self, mr, reference):
        """(record) for a StaticMesh object property, local or imported."""
        if isinstance(reference, tuple) and len(reference) == 3 and reference[0] == 'ext':
            mr, reference = reference[1], ('obj', reference[2])
        local = ref_export(reference)
        if local:
            return self.get(mr, local)
        imported = ref_import(reference)
        if imported is None:
            return None
        name = mr.pkg.imports[imported]['name']
        root, path = pk.import_path(mr.pkg, imported)
        full = '.'.join([root] + path)
        # By path, not by name alone: two different meshes can share a name.
        for known in [self.records.get(name)] + self.variants:
            if known is not None and known['name'] == name                     and full in (known['path'], '%s.%s' % (known['source'], known['path'])):
                return known
        shared = self.packages.shared_reader(import_root_package(mr.pkg, imported))
        if shared is None:
            raise ExtractError('%s: mesh %s imports from a package that is not installed' % (mr.label, name))
        idx = next((i for i, e in enumerate(shared.pkg.exports, 1)
                    if e['name'] == name and shared.pkg.class_of(e) == 'StaticMesh'), None)
        if idx is None:
            raise ExtractError('%s: mesh %s not found in %s' % (mr.label, name, shared.label))
        return self.get(shared, idx)

    def _material(self, mr, reference):
        """Blend mode, lighting model and two-sidedness of a surface's material, following
        MaterialInstance parents to the root Material across packages. A light
        shaft is an additive unlit card; drawn opaque it becomes a grey slab."""
        if not reference:
            return {'blend': 'opaque', 'unlit': False, 'two_sided': False, 'uncontrolled_slide': False}
        key = (mr.label, reference)
        if key not in self._materials:
            reader, idx = mr, reference
            phys = None
            for _ in range(16):
                if idx < 0:
                    root, path = pk.import_path(reader.pkg, -idx - 1)
                    shared = self.packages.shared_reader(root)
                    target = pk.find_export(shared, path) if shared else None
                    if target is None:
                        raise ExtractError('%s: material %s not found' % (mr.label, '.'.join([root] + path)))
                    reader, idx = shared, target
                props = reader.props(idx)[0] or {}
                # The nearest PhysMaterial on the chain wins, as in the engine.
                if phys is None and props.get('PhysMaterial'):
                    phys = self._object_name(reader, props['PhysMaterial'])
                parent = props.get('Parent')
                if reader.pkg.class_of(reader.pkg.exports[idx - 1]) == 'Material' or not parent:
                    blend = str(props.get('BlendMode', 'BLEND_Opaque')).replace('BLEND_', '').lower()
                    unlit = props.get('LightingModel') == 'MLM_Unlit'
                    two_sided = props.get('TwoSided') is True
                    self._materials[key] = {'blend': blend, 'unlit': unlit, 'two_sided': two_sided,
                                            'uncontrolled_slide': self._phys_flag(phys, 'bEnableUncontrolledSlide')}
                    break
                idx = parent[1]
            else:
                raise ExtractError('%s: material parent chain too deep' % mr.label)
        return self._materials[key]

    @staticmethod
    def _object_name(reader, ref):
        """The bare name of an object reference, exported or imported."""
        idx = ref[1] if isinstance(ref, tuple) else ref
        if idx > 0:
            return reader.pkg.exports[idx - 1]['name']
        if idx < 0:
            return reader.pkg.imports[-idx - 1]['name']
        return None

    def _phys_flag(self, material, flag):
        """A boolean of the TdPhysicalMaterialProperty behind a PhysicalMaterial of
        TDPhysicalMaterials, by name. This is how the original marks a surface's
        behaviour: bEnableSoftLanding on a crash mat's material, and
        bEnableUncontrolledSlide (PM_ConcreteWetSlide, PM_Metal_Slide, PM_Water,
        ...) on the chutes the RumpSlide move runs down. Nothing on the level, the
        mesh or its collision says so; only the material's PhysMaterial does."""
        if not material:
            return False
        cache = self._soft.setdefault(flag, {})
        if material not in cache:
            library = self.packages.shared_reader('TDPhysicalMaterials')
            idx = next((i for i, e in enumerate(library.pkg.exports, 1) if e['name'] == material), None)
            value = False
            if idx is not None:
                prop = ref_export((library.props(idx)[0] or {}).get('PhysicalMaterialProperty'))
                value = bool(prop and (library.props(prop)[0] or {}).get(flag))
            cache[material] = value
        return cache[material]

    def _soft_landing(self, material):
        return self._phys_flag(material, 'bEnableSoftLanding')


def _same_mesh(a, b):
    return all(a[k] == b[k] for k in ('vertex_count', 'triangle_count')) and         all(abs(x - y) <= 0.01 for x, y in zip(a['bounds']['extent'], b['bounds']['extent']))


def collision_class(actor, component, record, switched_on=False):
    # BlockNonZeroExtent off: only zero-extent traces (weapons, a kick's hit
    # test) stop here, never a capsule. Stormdrain's kick targets are hidden
    # InterpActors like this, standing in front of the doors they open.
    if component.get('BlockNonZeroExtent') is False:
        return 'none'
    # The rest are the switches SeqAct_ChangeCollision throws, on the actor and
    # its component both. `switched_on` asks what the thing is once it has.
    switched_off = (actor.get('bCollideActors') is False or component.get('CollideActors') is False
                    or component.get('BlockActors') is False)
    if switched_off and not switched_on:
        return 'none'
    if record['simple_shapes'] and record['use_simple_box_collision'] is not False:
        return 'simple'
    if record['collide_triangles'] == 0:
        return 'none'
    return 'per_poly'


COLLISION_CLASSES = ('none', 'simple', 'per_poly')


def override_collision(name, wanted, record):
    """The config's collision class for a mesh, refused when the mesh has
    nothing to build it from."""
    if wanted not in COLLISION_CLASSES:
        raise ExtractError('collision_overrides: %s -> %r is not one of %s' % (name, wanted, COLLISION_CLASSES))
    if wanted == 'simple' and not record['simple_shapes']:
        raise ExtractError('collision_overrides: %s has no simple collision' % name)
    if wanted == 'per_poly' and record['collide_triangles'] == 0:
        raise ExtractError('collision_overrides: %s has no colliding triangles' % name)
    return wanted


def world_aabb(record, position, basis):
    origin, extent = record['bounds']['origin'], record['bounds']['extent']
    lo, hi = [math.inf] * 3, [-math.inf] * 3
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                local = [origin[0] + sx * extent[0], origin[1] + sy * extent[1], origin[2] + sz * extent[2]]
                world = [position[k] + sum(basis[c][k] * local[c] for c in range(3)) for k in range(3)]
                lo = [min(lo[k], world[k]) for k in range(3)]
                hi = [max(hi[k], world[k]) for k in range(3)]
    return lo, hi


def component_props(packages, mr, reference):
    if isinstance(reference, tuple) and len(reference) == 3 and reference[0] == 'ext':
        return pk.resolved_props(packages, reference[1], reference[2])[0]
    idx = ref_export(reference)
    return pk.resolved_props(packages, mr, idx)[0] if idx else {}


def collect_placements(mr, meshes, config, report, keep=frozenset()):
    pkg = mr.pkg
    out = []
    for i, e in enumerate(pkg.exports, 1):
        if pkg.class_of(e) not in PLACED_CLASSES or outer_class(pkg, e) != 'Level':
            continue
        actor, _ = pk.resolved_props(meshes.packages, mr, i)
        if 'Location' not in actor:
            continue
        component_ref = actor.get('StaticMeshComponent')
        component = component_props(meshes.packages, mr, component_ref)
        mesh_ref = component.get('StaticMesh')
        # A component that lives in ANOTHER package (an InterpActor's class
        # default in Engine.u) reports its references as indices into that
        # package; read against this one they name an unrelated object -- a
        # tutorial InterpActor resolved to a DecalComponent this way.
        foreign = isinstance(component_ref, tuple) and len(component_ref) == 3 and component_ref[0] == 'ext'
        plain = isinstance(mesh_ref, tuple) and len(mesh_ref) == 2 and mesh_ref[0] == 'obj'
        if foreign and plain:
            mesh_ref = ('ext', component_ref[1], mesh_ref[1])
        record = meshes.resolve(mr, mesh_ref)
        if record is None:
            # No StaticMesh anywhere in the archetype chain: an empty actor that
            # renders nothing in the original either. A reference that cannot be
            # FOUND raises inside resolve().
            report['counts']['empty_actor'] += 1
            continue
        name = record['name']
        if name in config['exclude_meshes'] or '%s.%s' % (mr.label, e['name']) in config['exclude_actors']:
            report['counts']['excluded_by_config'] += 1
            continue
        # A breakable pane is no effect, whatever its mesh is called: Factory's
        # outside glass is S_FX_OutsideGlassPlane_01.
        if e['name'] not in keep and any(marker in name.lower() for marker in FX_MESH_MARKERS):
            report['counts']['excluded_fx'] += 1
            continue
        shadow_only = bool(record['surfaces']) and all(BAKE_ONLY_MATERIAL in (s['material'] or '') for s in record['surfaces'])
        report['counts']['shadow_only'] = report['counts'].get('shadow_only', 0) + shadow_only
        position = point(actor['Location'])
        basis = godot_basis(actor.get('Rotation') or (0, 0, 0), actor_scale(actor))
        # UE3 draws an actor at Location + R*(S*v - PrePivot): the mesh sits
        # PrePivot off the actor's origin, turned with it but NOT scaled, and
        # the origin stays the pivot a matinee turns it about. Stormdrain's
        # and the Prologue's red doors stood 2.24 m in the air without it; the
        # tutorial's kick target, stretched 28x on Z, went 71 m underground
        # when the offset was scaled too.
        pre_pivot = point(actor['PrePivot']) if actor.get('PrePivot') else [0.0, 0.0, 0.0]
        turned = pivot_offset(actor)
        lo, hi = world_aabb(record, [position[k] - turned[k] for k in range(3)], basis)
        collision = 'none' if shadow_only else collision_class(actor, component, record)
        if name in config['collision_overrides']:
            collision = override_collision(name, config['collision_overrides'][name], record)
            report['counts']['collision_overridden'] = report['counts'].get('collision_overridden', 0) + 1
        # What it would be with its collision switched on, for the actors
        # Kismet switches: see switch_on_collision().
        if_on = 'none'
        if collision == 'none' and not shadow_only and name not in config['collision_overrides']:
            if_on = collision_class(actor, component, record, switched_on=True)
        report['collision'][collision] += 1
        # bHidden actors are designer-placed invisible collision (group
        # Dummy_Collisions): they still block, they are just never drawn.
        # A HiddenGame component is the same, set on the component instead.
        hidden = bool(actor.get('bHidden', False) or component.get('HiddenGame', False))
        # What this actor is hard-attached to: it moves with that actor. A
        # Stormdrain gate rides a Trigger_Dynamic that its Matinee raises.
        # The component's own Materials: one entry per mesh element, 0 where the
        # mesh's material stands. A third of Stormdrain's placements carry one;
        # its orange containers and green pipes are these on white meshes.
        overrides = []
        component_idx = None if foreign else ref_export(component_ref)
        if component_idx:
            for tag in mr.chain_of(component_idx)[0]:
                if tag[0] == 'Materials':
                    refs = matinee._int_array(mr, matinee._value(mr, tag))
                    overrides = [meshes.override(mr, r) if r else None for r in refs]
        base_idx = ref_export(actor.get('Base')) if actor.get('bHardAttach') else None
        base = '%s.%s' % (mr.label, pkg.exports[base_idx - 1]['name']) if base_idx else None
        report['counts']['hidden'] += hidden
        out.append({'name': e['name'], 'package': mr.label, 'mesh': name, '_record': record, 'position': position,
                    'basis': basis, 'collision': collision, 'soft_landing': record['soft_landing'],
                    'hidden': hidden, 'mover': pkg.class_of(e) == 'InterpActor',
                    'base': base, 'aabb': {'min': lo, 'max': hi}}
                   | ({'pre_pivot': pre_pivot} if any(abs(c) > 1e-4 for c in pre_pivot) else {})
                   | ({'collision_if_on': if_on} if if_on != 'none' else {})
                   | ({'materials': overrides} if any(overrides) else {})
                   | ({'shadow_only': True} if shadow_only else {})
                   | ({'runner_vision': runner_vision(actor)} if actor.get('bLOIObject') else {}))
    return out


# A ladder line is moved onto the mesh it climbs only this far, at most.
LADDER_SNAP_MAX_M = 0.5
LADDER_SNAP_SEARCH_M = 1.0
LADDER_MESH_TOKENS = ('ladder', 'pipe')


# A checkpoint belongs to the section of the floor under it, within this far
# below. A checkpoint stands on the ground it respawns the body onto; one with
# nothing under it (the Edge's "Cops", dropped on purpose) stays chapter-wide.
CHECKPOINT_FLOOR_DROP_M = 12.0
# A floor may also be this far ABOVE the checkpoint's own origin: the origin is
# the body's centre, and a checkpoint sunk into a step reads as below it.
CHECKPOINT_FLOOR_RISE_M = 1.0


def assign_checkpoint_sections(checkpoints, placements, bsp, report):
    """Give each checkpoint the section of the nearest surface straight below
    it, so its shell is the one whose geometry it stands on and can be dragged
    against. Vertical only: a section is a stretch of the route, and a
    checkpoint's floor decides which stretch it is in.

    Placements are tested by their bounds rather than their triangles. A floor
    is thin and lies under the point; a building whose bounds also contain it
    reaches far above it and is not a floor under anything.
    """
    report['checkpoint_sections'] = {}
    for c in checkpoints:
        x, y, z = c['position']
        best = None
        for p in placements:
            if p['collision'] == 'none' or p.get('hidden'):
                continue
            lo, hi = p['aabb']['min'], p['aabb']['max']
            if not (lo[0] <= x <= hi[0] and lo[2] <= z <= hi[2]):
                continue
            gap = y - hi[1]
            if gap < -CHECKPOINT_FLOOR_RISE_M or gap > CHECKPOINT_FLOOR_DROP_M:
                continue
            if best is None or gap < best[0]:
                best = (gap, p['section'], p['mesh'])
        for face in bsp:
            xs = [v[0] for v in face['vertices']]
            zs = [v[2] for v in face['vertices']]
            if not (min(xs) <= x <= max(xs) and min(zs) <= z <= max(zs)):
                continue
            gap = y - max(v[1] for v in face['vertices'])
            if gap < -CHECKPOINT_FLOOR_RISE_M or gap > CHECKPOINT_FLOOR_DROP_M:
                continue
            if best is None or gap < best[0]:
                best = (gap, face['section'], 'BSP')
        # '' is the chapter-wide layer, as section_of() spells it: a checkpoint
        # over nothing has no section's floor to be dragged against.
        c['section'] = best[1] if best else ''
        report['checkpoint_sections'][c.get('label') or c['name']] = \
            '%s (%.2f m over %s)' % (c['section'], best[0], best[2]) if best else 'nothing under it'


# ECollisionType values that stop a player; kismet_runner.gd's COLLISION_MODES
# is the same table.
BLOCKING_TYPES = ('COLLIDE_CustomDefault', 'COLLIDE_BlockAll', 'COLLIDE_BlockAllButWeapons')


def switch_on_collision(placements, graph, report):
    """A placement with no collision ONLY because its collision starts switched
    off gets its shapes after all when the chapter's Kismet switches it on:
    [ME:CONFIRMED] Stormdrain's `construction` respawn un-hides the girder's
    twin and sets it COLLIDE_BlockAll, and with no shapes to turn on the twin
    was a picture of a girder the player fell through. It starts off, as the
    original's does; the graph's actor says so for the level."""
    switched = set()
    if graph:
        for node in graph['nodes'].values():
            if node['cls'] != 'SeqAct_ChangeCollision':
                continue
            if node.get('props', {}).get('CollisionType', 'COLLIDE_CustomDefault') not in BLOCKING_TYPES:
                continue
            for var in node.get('vars', {}).get('Target', []):
                actor = graph['vars'].get(var, {}).get('actor')
                if actor:
                    switched.add(actor)
    count = 0
    for p in placements:
        if_on = p.pop('collision_if_on', None)
        actor = '%s.%s' % (streaming.package_key(p['package']), p['name'])
        if if_on and actor in switched:
            report['collision'][p['collision']] -= 1
            report['collision'][if_on] += 1
            p['collision'] = if_on
            graph['actors'][actor]['starts_off'] = True
            count += 1
    report['counts']['collision_switched_on_by_kismet'] = count


def names_of(records):
    """Either identity of a checkpoint or spawn: its own name is
    TdCheckpoint_15, its label is what the shell names the node and what a
    person reads."""
    return [r['name'] for r in records] + [r['label'] for r in records if r.get('label')]


# [ME:CONFIRMED] LOIDistance's class default, in uu: a placement that leaves it
# at 0 means this rather than "never".
LOI_DEFAULT_DISTANCE_UU = 1500.0


def runner_vision(actor):
    """An actor's Runner Vision settings, as RunnerVisionTarget's fields.
    See docs/mirrors-edge-deep-research/14-信使视觉LOI.md."""
    distance = float(actor.get('LOIDistance') or LOI_DEFAULT_DISTANCE_UU)
    return {'distance_m': round(distance / UU, 3),
            'flat_distance': bool(actor.get('LOIUse2DDistance')),
            'proximity_delay': round(float(actor.get('LOIProximityDelay') or 0.0), 3),
            'min_duration': round(float(actor.get('LOIMinDuration', 1.5)), 3)}


def snap_ladders(placements, annotations, report):
    """Move each ladder line, along its WallNormal only, onto the centre of
    the ladder or pipe mesh it runs up.

    Measured in four levels: the cooked Start/End sit 0.18-0.27 m BEHIND a
    pipe's centre and up to 0.19 m behind a ladder's, toward the wall.
    LadderMove hangs the body stand_off in FRONT of the line, so a line that
    far back puts the climber into the wall. The mesh with the most height
    in common with the line wins, not the nearest: a ladder's top piece
    curves back over the lip and its bounds sit elsewhere.
    """
    report['ladders_snapped'] = []
    for a in annotations:
        if a['kind'] != 'ladder' or 'start' not in a or 'end' not in a or 'wall' not in a:
            continue
        low, high = sorted((a['start'][1], a['end'][1]))
        mid = [(a['start'][k] + a['end'][k]) / 2 for k in range(3)]
        normal = a['wall']
        best = None
        for p in placements:
            name = p['mesh'].lower()
            if not any(t in name for t in LADDER_MESH_TOKENS):
                continue
            lo, hi = p['aabb']['min'], p['aabb']['max']
            # Upright pieces only. An elbow or a horizontal run of the same
            # pipe system can share more height with the line than the
            # straight it runs up, and its centre is nowhere near the grip:
            # a tutorial pipe was pulled 0.31 m INTO its wall that way.
            tall = hi[1] - lo[1]
            if tall < 1.0 or tall < 2.0 * max(hi[0] - lo[0], hi[2] - lo[2]):
                continue
            overlap = min(high, hi[1]) - max(low, lo[1])
            if overlap <= 0.0:
                continue
            centre = [(lo[k] + hi[k]) / 2 for k in range(3)]
            if math.hypot(centre[0] - mid[0], centre[2] - mid[2]) > LADDER_SNAP_SEARCH_M:
                continue
            if best is None or overlap > best[0]:
                best = (overlap, p['mesh'], centre)
        if best is None:
            continue
        delta = (best[2][0] - mid[0]) * normal[0] + (best[2][2] - mid[2]) * normal[2]
        if abs(delta) > LADDER_SNAP_MAX_M or abs(delta) < 0.01:
            continue
        shift = [normal[0] * delta, 0.0, normal[2] * delta]
        for key in ('start', 'end', 'middle'):
            if key in a:
                a[key] = [round(a[key][k] + shift[k], 4) for k in range(3)]
        if 'spline' in a:
            a['spline'] = [[round(v[k] + shift[k], 4) for k in range(3)] for v in a['spline']]
        report['ladders_snapped'].append('%s.%s onto %s by %+.2f m' % (a['package'], a['name'], best[1], delta))


def distance_to_box(p, lo, hi):
    return math.sqrt(sum(max(lo[k] - p[k], 0.0, p[k] - hi[k]) ** 2 for k in range(3)))


def main(config_path):
    config = pk.load_config(config_path)
    root = project_root()
    out_dir = os.path.join(root, '_local', 'me-reference', 'level-extract', config['id'])
    packages = pk.PackageSet(root, config, os.path.join(root, '_local', 'me-reference', 'level-extract', '_cache'))
    report = {'packages': packages.names, 'unstreamed': packages.unstreamed, 'unmapped': {},
              'collision': {'none': 0, 'simple': 0, 'per_poly': 0},
              'counts': {'empty_actor': 0, 'excluded_by_config': 0, 'excluded_fx': 0,
                         'excluded_by_anchor': 0, 'hidden': 0}}
    meshes = MeshTable(packages, report, material_bake.MaterialBaker(packages, int(config['texture_max_px']), report))
    defaults = annotations.blocking_defaults(packages)
    placements, found_lights, bsp, matinees, end_links = [], [], [], [], []
    notes = {'annotations': [], 'spawns': [], 'anchors': [], 'checkpoints': []}
    # Actors named by a checkpoint's `play`: their sequence is kept even with
    # no start this module can read, because a remote event is what plays it.
    wanted_sequences = frozenset(
        actor for entry in config['checkpoint_restores'].values()
        for actor in entry.get('play', []))
    for name in packages.names:
        mr = packages.reader(name)
        glass = matinee.collect_glass(packages, mr, report)
        panes = frozenset(g['name'] for g in glass)
        placements += collect_placements(mr, meshes, config, report, panes)
        collected = annotations.collect(packages, mr, defaults, report)
        once = matinee.self_disabling(mr)
        for a in collected['annotations']:
            if a['kind'] == 'pain' and a['name'] in once:
                a['once'] = True
        # What the volumes riding a mover do when touched. Read per package:
        # a Base never crosses one, so neither does the sequence behind it.
        effects = matinee.rider_effects(mr, {a['name'] for a in collected['annotations']
                                             if a.get('base')}, report)
        for a in collected['annotations']:
            if a['name'] in effects:
                a['effects'] = effects[a['name']]
        for key, values in collected.items():
            notes[key] += values
        found_lights += lights.collect_lights(mr)
        matinees += matinee.collect(packages, mr, report, wanted_sequences, keep_all=config['split_sections'])
        notes['annotations'] += glass
        end_links.append((name, matinee.level_end_links(packages, mr)))
        for face in lights.collect_bsp(mr):
            face['package'] = name
            bsp.append(face)
        print('%-36s placements so far %5d' % (name, len(placements)))

    if packages.persistent:
        end_links.append((packages.persistent, matinee.level_end_links(packages, packages.reader(packages.persistent))))
    for label, trigger in matinee.level_ends(end_links):
        notes['annotations'].append({'kind': 'level_end', 'name': trigger['name'], 'package': label,
                                     'position': trigger.get('position', [0.0, 0.0, 0.0]), 'trigger': trigger})
    report['level_ends'] = sum(1 for a in notes['annotations'] if a['kind'] == 'level_end')

    # A rider is only a rider if something actually moves what it rides. A
    # Trigger bolted to a door frame nobody animates is an ordinary trigger,
    # and an `effect` volume no sequence listens to is nothing at all: each
    # Mall train hangs some forty 0.4 m Triggers of that kind.
    driven = {actor for m in matinees for g in m['groups'] for actor in g['actors']}
    kept, dropped = [], 0
    for a in notes['annotations']:
        base = a.get('base')
        if base is None:
            kept.append(a)
        elif base not in driven:
            if a['kind'] in annotations.RIDER_ONLY_KINDS.values():
                dropped += 1
                continue
            # A volume that is what it is wherever it stands: it simply does
            # not move, so the attachment is not worth carrying.
            a.pop('base', None)
            a.pop('hard', None)
            kept.append(a)
        elif a['kind'] == 'effect' and not a.get('effects'):
            dropped += 1
        else:
            kept.append(a)
    notes['annotations'] = kept
    report['counts']['riders_dropped'] = dropped
    report['counts']['riders'] = sum(1 for a in kept if a.get('base'))

    unused = set(config['collision_overrides']) - {p['mesh'] for p in placements}
    if unused:
        raise ExtractError('collision_overrides name meshes placed nowhere: %s' % sorted(unused))

    for a in notes['annotations']:
        if a.get('physical_material'):
            a['uncontrolled_slide'] = meshes._phys_flag(a['physical_material'], 'bEnableUncontrolledSlide')
            a['soft_landing'] = meshes._phys_flag(a['physical_material'], 'bEnableSoftLanding')

    if config['sections']:
        persistent = annotations.collect(packages, packages.reader(packages.persistent), defaults, {'unmapped': {}})
        prefix = packages.persistent[:-len('_p.me1')].lower() + '_'
        own = tuple(prefix + s['name'].lower() for s in config['sections'])
        # The section's own packages only: slices reach deep into the
        # neighbouring sections, and _Bac is the skyline.
        section = [p for p in placements
                   if any(p['package'].lower() == o + '.me1' or p['package'].lower().startswith(o + '_') for o in own)
                   and '_bac' not in p['package'].lower()]
        if not section:
            raise ExtractError('no non-background placements to bound the section')
        lo = [min(p['position'][k] for p in section) - SECTION_MARGIN_M for k in range(3)]
        hi = [max(p['position'][k] for p in section) + SECTION_MARGIN_M for k in range(3)]
        notes['checkpoints'] += [c for c in persistent['checkpoints']
                                 if all(lo[k] <= c['position'][k] <= hi[k] for k in range(3))]

    # What a respawn onto each named checkpoint has to put the level into.
    # Carried on the checkpoint rather than kept as a side table: the builder
    # already walks these, and a name that matches nothing is a typo worth
    # hearing about now instead of as a silent no-op in the shell.
    restores = dict(config['checkpoint_restores'])
    for c in notes['checkpoints']:
        entry = restores.pop(c.get('label', ''), None)
        if entry:
            c['restores'] = {key: list(entry.get(key, [])) for key in ('hide', 'show', 'play')}
    if restores:
        raise ExtractError('checkpoint_restores names no such checkpoint: %s' % sorted(restores))

    notes['checkpoints'].sort(key=lambda c: c.get('weight', 0))

    if config['anchor_filter']:
        radius = float(config['anchor_filter']['radius_m'])
        anchors = notes['anchors'] + [s['position'] for s in notes['spawns']] \
            + [a['position'] for a in notes['annotations']] + [c['position'] for c in notes['checkpoints']]
        kept = [p for p in placements
                if min(distance_to_box(a, p['aabb']['min'], p['aabb']['max']) for a in anchors) <= radius]
        report['counts']['excluded_by_anchor'] = len(placements) - len(kept)
        placements = kept

    if config['initial_spawn']:
        names = names_of(notes['spawns'] + notes['checkpoints'])
        if config['initial_spawn'] not in names:
            raise ExtractError('initial_spawn %r is not among %s' % (config['initial_spawn'], names))

    for spot in config['teleports']:
        if spot['to'] not in names_of(notes['checkpoints']):
            raise ExtractError('teleport destination %r is not among %s'
                               % (spot['to'], names_of(notes['checkpoints'])))

    snap_ladders(placements, notes['annotations'], report)

    if config['split_sections']:
        prefix = packages.persistent[:-len('p.me1')]
        names = [s['name'] for s in config['sections']]
        report['sections'] = {}
        for record in placements + found_lights + notes['annotations'] + bsp + matinees:
            record['section'] = pk.section_of(record['package'], prefix, names)
            counts = report['sections'].setdefault(record['section'] or '(chapter)', {'packages': []})
            if record['package'] not in counts['packages']:
                counts['packages'].append(record['package'])
        assign_checkpoint_sections(notes['checkpoints'], placements, bsp, report)
        for record in placements:
            report['sections'][record['section'] or '(chapter)']['placements'] =                report['sections'][record['section'] or '(chapter)'].get('placements', 0) + 1

    records = meshes.finish_names()
    for p in placements:
        p['mesh'] = p.pop('_record')['name']
    report['mesh_variants'] = sorted(n for n in records if '@' in n)
    used = {p['mesh'] for p in placements}
    mesh_out = {n: r for n, r in records.items() if n in used}
    report['meshes'] = len(mesh_out)
    report['meshes_without_normals'] = sorted(n for n, r in mesh_out.items() if r['normals'] is None)
    report['kdop_mismatch'] = sorted(n for n, r in mesh_out.items() if r['kdop_triangles'] != r['collide_triangles'])
    report['lights'] = {}
    for light in found_lights:
        report['lights'][light['class']] = report['lights'].get(light['class'], 0) + 1
    report['annotations'] = {}
    for a in notes['annotations']:
        report['annotations'][a['kind']] = report['annotations'].get(a['kind'], 0) + 1
    report['spawns'] = len(notes['spawns'])
    report['checkpoints'] = len(notes['checkpoints'])
    report['placements'] = len(placements)
    report['bsp_polygons'] = len(bsp)

    # The persistent package's WorldInfo is the chapter's; a level without one
    # (the tutorial lists its packages by hand) takes the first that has a sun.
    look = None
    for name in ([packages.persistent] if packages.persistent else []) + packages.names:
        look = environment.collect(packages.reader(name))
        if look and look.get('sun_direction'):
            break
    # The sun the lightmaps were baked from, wherever its _Lgts package is;
    # its direction replaces the haze's approximation of it.
    for name in packages.names:
        sun = environment.baked_sun(packages.reader(name))
        if sun:
            look = look or {'package': None, 'post_process': {}, 'haze': {}}
            look['sun'] = sun
            look['sun_direction'] = sun['direction']
            break
    report['environment'] = look.get('package') if look else None
    report['sun'] = '%s.%s' % (look['sun']['package'], look['sun']['name']) if look and look.get('sun') else None

    # Only a chapter built section by section runs the original's Kismet and
    # streams: a single-scene level names the packages it wants, keeps them
    # all, and is scripted by hand.
    built_actors = {'%s.%s' % (streaming.package_key(r['package']), r['name'])
                    for r in placements + found_lights + notes['annotations']}
    graph = kismet.collect(packages, report, built_actors, {m['name'] for m in matinees}) \
        if config['split_sections'] else None
    flow = {'managed': streaming.managed(notes['checkpoints'], graph)} if graph else None
    switch_on_collision(placements, graph, report)

    os.makedirs(out_dir, exist_ok=True)
    manifest = {'config': config, 'streaming': flow, 'environment': look, 'placements': placements, 'bsp': bsp, 'lights': found_lights,
                'annotations': notes['annotations'], 'spawns': notes['spawns'],
                'checkpoints': notes['checkpoints'], 'matinees': matinees, 'report': report}
    with open(os.path.join(out_dir, 'manifest.json'), 'w', encoding='utf-8') as fh:
        json.dump(manifest, fh, ensure_ascii=False, separators=(',', ':'))
    # Its own file: a chapter's graph is thousands of nodes, and nothing that
    # reads the manifest for geometry wants to parse them.
    kismet_path = os.path.join(out_dir, 'kismet.json')
    if graph:
        with open(kismet_path, 'w', encoding='utf-8') as fh:
            json.dump(graph, fh, ensure_ascii=False, separators=(',', ':'))
    elif os.path.exists(kismet_path):
        os.remove(kismet_path)
    with open(os.path.join(out_dir, 'meshes.json'), 'w', encoding='utf-8') as fh:
        json.dump(mesh_out, fh, ensure_ascii=False, separators=(',', ':'))
    used_materials = {s['material'] for r in mesh_out.values() for s in r['surfaces']}
    used_materials |= {o['material'] for p in placements for o in p.get('materials', []) if o}
    with open(os.path.join(out_dir, 'materials.json'), 'w', encoding='utf-8') as fh:
        json.dump({n: b for n, b in meshes.bakes.items() if b and n in used_materials}, fh, separators=(',', ':'))
    print(json.dumps(report, ensure_ascii=False, indent=1))
    print('-> %s' % out_dir)


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    try:
        main(sys.argv[1])
    except ExtractError as error:
        print('EXTRACT FAILED: %s' % error)
        sys.exit(1)
