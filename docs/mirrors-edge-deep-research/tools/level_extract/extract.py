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

from common import ExtractError, actor_scale, godot_basis, outer_class, point, ref_export, ref_import, import_root_package
import annotations
import lights
import packages as pk
import materials as material_bake
import static_mesh
import matinee

# InterpActors are movers: placed like any mesh, moved by matinee.py's data.
PLACED_CLASSES = ('StaticMeshActor', 'InterpActor')
FX_MESH_MARKERS = ('_FX_', 'SkyDome', 'Sunflare', 'GodRay')
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
        for key in ('vertex_count', 'triangle_count'):
            if known[key] != record[key]:
                raise ExtractError('mesh %s differs between %s and %s (%s %s vs %s)'
                                   % (name, known['source'], record['source'], key, known[key], record[key]))
        for a, b in zip(known['bounds']['extent'], record['bounds']['extent']):
            if abs(a - b) > 0.01:
                raise ExtractError('mesh %s bounds differ between %s and %s'
                                   % (name, known['source'], record['source']))
        return known

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
        if name in self.records:
            return self.records[name]
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
            return {'blend': 'opaque', 'unlit': False, 'two_sided': False}
        key = (mr.label, reference)
        if key not in self._materials:
            reader, idx = mr, reference
            for _ in range(16):
                if idx < 0:
                    root, path = pk.import_path(reader.pkg, -idx - 1)
                    shared = self.packages.shared_reader(root)
                    target = pk.find_export(shared, path) if shared else None
                    if target is None:
                        raise ExtractError('%s: material %s not found' % (mr.label, '.'.join([root] + path)))
                    reader, idx = shared, target
                props = reader.props(idx)[0] or {}
                parent = props.get('Parent')
                if reader.pkg.class_of(reader.pkg.exports[idx - 1]) == 'Material' or not parent:
                    blend = str(props.get('BlendMode', 'BLEND_Opaque')).replace('BLEND_', '').lower()
                    unlit = props.get('LightingModel') == 'MLM_Unlit'
                    two_sided = props.get('TwoSided') is True
                    self._materials[key] = {'blend': blend, 'unlit': unlit, 'two_sided': two_sided}
                    break
                idx = parent[1]
            else:
                raise ExtractError('%s: material parent chain too deep' % mr.label)
        return self._materials[key]

    def _soft_landing(self, material):
        if not material:
            return False
        if material not in self._soft:
            library = self.packages.shared_reader('TDPhysicalMaterials')
            idx = next((i for i, e in enumerate(library.pkg.exports, 1) if e['name'] == material), None)
            soft = False
            if idx is not None:
                prop = ref_export((library.props(idx)[0] or {}).get('PhysicalMaterialProperty'))
                soft = bool(prop and (library.props(prop)[0] or {}).get('bEnableSoftLanding'))
            self._soft[material] = soft
        return self._soft[material]


def collision_class(actor, component, record):
    if actor.get('bCollideActors') is False or component.get('CollideActors') is False \
            or component.get('BlockActors') is False:
        return 'none'
    if record['simple_shapes'] and record['use_simple_box_collision'] is not False:
        return 'simple'
    if record['collide_triangles'] == 0:
        return 'none'
    return 'per_poly'


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


def collect_placements(mr, meshes, config, report):
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
        if name in config['exclude_meshes']:
            report['counts']['excluded_by_config'] += 1
            continue
        if any(marker in name for marker in FX_MESH_MARKERS):
            report['counts']['excluded_fx'] += 1
            continue
        position = point(actor['Location'])
        basis = godot_basis(actor.get('Rotation') or (0, 0, 0), actor_scale(actor))
        lo, hi = world_aabb(record, position, basis)
        collision = collision_class(actor, component, record)
        report['collision'][collision] += 1
        # bHidden actors are designer-placed invisible collision (group
        # Dummy_Collisions): they still block, they are just never drawn.
        hidden = bool(actor.get('bHidden', False))
        # What this actor is hard-attached to: it moves with that actor. A
        # Stormdrain gate rides a Trigger_Dynamic that its Matinee raises.
        base_idx = ref_export(actor.get('Base')) if actor.get('bHardAttach') else None
        base = '%s.%s' % (mr.label, pkg.exports[base_idx - 1]['name']) if base_idx else None
        report['counts']['hidden'] += hidden
        out.append({'name': e['name'], 'package': mr.label, 'mesh': name, 'position': position,
                    'basis': basis, 'collision': collision, 'soft_landing': record['soft_landing'],
                    'hidden': hidden, 'mover': pkg.class_of(e) == 'InterpActor',
                    'base': base, 'aabb': {'min': lo, 'max': hi}})
    return out


# A ladder line is moved onto the mesh it climbs only this far, at most.
LADDER_SNAP_MAX_M = 0.5
LADDER_SNAP_SEARCH_M = 1.0
LADDER_MESH_TOKENS = ('ladder', 'pipe')


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
    report = {'packages': packages.names, 'unmapped': {},
              'collision': {'none': 0, 'simple': 0, 'per_poly': 0},
              'counts': {'empty_actor': 0, 'excluded_by_config': 0, 'excluded_fx': 0,
                         'excluded_by_anchor': 0, 'hidden': 0}}
    meshes = MeshTable(packages, report, material_bake.MaterialBaker(packages, int(config['texture_max_px']), report))
    defaults = annotations.blocking_defaults(packages)
    placements, found_lights, bsp, matinees = [], [], [], []
    notes = {'annotations': [], 'spawns': [], 'anchors': [], 'checkpoints': []}
    for name in packages.names:
        mr = packages.reader(name)
        placements += collect_placements(mr, meshes, config, report)
        for key, values in annotations.collect(mr, defaults, report).items():
            notes[key] += values
        found_lights += lights.collect_lights(mr)
        matinees += matinee.collect(packages, mr, report)
        for face in lights.collect_bsp(mr):
            face['package'] = name
            bsp.append(face)
        print('%-36s placements so far %5d' % (name, len(placements)))

    if config['sections']:
        persistent = annotations.collect(packages.reader(packages.persistent), defaults, {'unmapped': {}})
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
        names = [s['name'] for s in notes['spawns'] + notes['checkpoints']]
        if config['initial_spawn'] not in names:
            raise ExtractError('initial_spawn %r is not among %s' % (config['initial_spawn'], names))

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
        for record in placements:
            report['sections'][record['section'] or '(chapter)']['placements'] =                 report['sections'][record['section'] or '(chapter)'].get('placements', 0) + 1

    used = {p['mesh'] for p in placements}
    mesh_out = {n: r for n, r in meshes.records.items() if n in used}
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

    os.makedirs(out_dir, exist_ok=True)
    manifest = {'config': config, 'placements': placements, 'bsp': bsp, 'lights': found_lights,
                'annotations': notes['annotations'], 'spawns': notes['spawns'],
                'checkpoints': notes['checkpoints'], 'matinees': matinees, 'report': report}
    with open(os.path.join(out_dir, 'manifest.json'), 'w', encoding='utf-8') as fh:
        json.dump(manifest, fh, ensure_ascii=False, separators=(',', ':'))
    with open(os.path.join(out_dir, 'meshes.json'), 'w', encoding='utf-8') as fh:
        json.dump(mesh_out, fh, ensure_ascii=False, separators=(',', ':'))
    used_materials = {s['material'] for r in mesh_out.values() for s in r['surfaces']}
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
