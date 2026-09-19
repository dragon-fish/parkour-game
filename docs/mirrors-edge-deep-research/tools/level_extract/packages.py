"""Level config, package inference, decompression cache and shared-package index."""
import json
import os
import re
import struct
import subprocess
import sys

from common import ExtractError, TOOLS
from mapdump import MapReader

# Config schema. Every key the extractor reads is listed here with its default;
# a key not in this table is an error, so a typo cannot silently do nothing.
#
#   id              str   required   output names default from it
#   chapter         str   required   directory under CookedPC/Maps
#   sections        list  []         [{name: "StdP"}]; each infers its packages
#   packages        list  []         extra package file names, loaded as-is
#   exclude_meshes  list  []         mesh names never placed
#   anchor_filter   dict  null       {radius_m: 20}: keep placements near anchors
#   interior        bool  false      first shell build: Sun off, SDFGI on
#   initial_spawn   str   null       object name of the starting checkpoint/spawn
#   outputs         dict  {}         {geometry: res path, shell: res path}
#   texture_max_px  int   64         largest inline mip a material bake may use
#   persistent      str   null       the chapter's *_p.me1; required only when the
#                                    directory holds two maps (SP01: Edge_p, Escape_p)
#   split_sections  bool  false      tag everything with the section it belongs to;
#                                    the builder then writes one scene per section
#   lifts           list  []         hand-configured lifts for the builder (Lift):
#                                    {car, car_doors, stop_doors, travel, travel_time,
#                                     door_open_offset, door_time}; actors as package.name
CONFIG_DEFAULTS = {
    'sections': [], 'packages': [], 'exclude_meshes': [], 'anchor_filter': None,
    'interior': False, 'initial_spawn': None, 'outputs': {}, 'texture_max_px': 64,
    'persistent': None, 'split_sections': False, 'lifts': [],
}
CONFIG_REQUIRED = ('id', 'chapter')

# Suffixes that belong to a streaming section. Audio and localisation carry no
# geometry; TT_* packages are the time-trial mode, not the story level.
SECTION_SKIP = re.compile(r'(_aud|_loc_)', re.IGNORECASE)


def load_config(path):
    with open(path, encoding='utf-8') as fh:
        raw = json.load(fh)
    unknown = set(raw) - set(CONFIG_DEFAULTS) - set(CONFIG_REQUIRED)
    if unknown:
        raise ExtractError('unknown config keys %s in %s' % (sorted(unknown), path))
    for key in CONFIG_REQUIRED:
        if not raw.get(key):
            raise ExtractError('config %s lacks required key %r' % (path, key))
    config = dict(CONFIG_DEFAULTS)
    config.update(raw)
    for section in config['sections']:
        if not isinstance(section, dict) or not section.get('name'):
            raise ExtractError('every section must be a dict with a name: %r' % (section,))
    if not config['sections'] and not config['packages']:
        raise ExtractError('config %s names no sections and no packages' % path)
    return config


def find_install(project_root):
    root = os.path.join(project_root, '_local', 'mirrors edge', 'TdGame', 'CookedPC')
    if not os.path.isdir(root):
        raise ExtractError('Mirror\'s Edge install not found at %s' % root)
    return root


def persistent_package(chapter_dir, named=None):
    """The chapter's persistent level, e.g. Stormdrain_p.me1."""
    found = [f for f in os.listdir(chapter_dir)
             if f.lower().endswith('_p.me1') and not f.startswith('TT_')]
    if named is not None:
        if named not in found:
            raise ExtractError('persistent %r is not one of %s in %s' % (named, found, chapter_dir))
        return named
    if len(found) != 1:
        raise ExtractError('expected one persistent *_p.me1 in %s, found %s' % (chapter_dir, found))
    return found[0]


def infer_section_packages(chapter_dir, prefix, section):
    """Packages of one streaming section plus the slices that touch it.

    `Stormdrain_StdP_Art.me1` belongs to StdP; `Stormdrain_Std-StdP_Slc.me1`
    is a slice between Std and StdP, so it belongs to both.
    """
    wanted = []
    head = (prefix + '_').lower()
    for name in sorted(os.listdir(chapter_dir)):
        low = name.lower()
        if not low.endswith('.me1') or not low.startswith(head) or SECTION_SKIP.search(low):
            continue
        stem = name[len(head):-4]
        first = stem.split('_', 1)[0]
        if first.lower() == section.lower() or section.lower() in [s.lower() for s in first.split('-')]:
            wanted.append(name)
    if not wanted:
        raise ExtractError('section %r matches no package under %s' % (section, chapter_dir))
    return wanted


def section_of(package, prefix, sections):
    """The one section a package belongs to, or '' for the chapter-wide layer.

    A slice `A-B_Slc` belongs to A, the section it leads out of; anything else
    to the section its name starts with. infer_section_packages() counts a
    slice on both sides because both sides LOAD it; ownership is a separate
    question with one answer, or the slice would be built twice.
    """
    stem = package[len(prefix):].rsplit('.', 1)[0]
    head = stem.split('_', 1)[0].split('-', 1)[0].lower()
    for name in sections:
        if head == name.lower():
            return name
    return ''


class PackageSet:
    """Decompressed map packages for one level, plus lazily indexed shared .upk files."""

    def __init__(self, project_root, config, cache_dir):
        self.cooked = find_install(project_root)
        self.chapter_dir = os.path.join(self.cooked, 'Maps', config['chapter'])
        if not os.path.isdir(self.chapter_dir):
            raise ExtractError('chapter directory not found: %s' % self.chapter_dir)
        self.cache_dir = cache_dir
        os.makedirs(cache_dir, exist_ok=True)
        self.persistent = persistent_package(self.chapter_dir, config['persistent'])
        prefix = self.persistent[:-len('_p.me1')]
        names = []
        for section in config['sections']:
            names += infer_section_packages(self.chapter_dir, prefix, section['name'])
        names += config['packages']
        self.names = list(dict.fromkeys(names))
        for name in self.names:
            if not os.path.exists(os.path.join(self.chapter_dir, name)):
                raise ExtractError('package not found: %s' % name)
        self._readers = {}
        self._upk_index = None

    def reader(self, name):
        """MapReader over a map package in this chapter, decompressing once."""
        if name not in self._readers:
            self._readers[name] = _labelled(MapReader(self._decompressed(os.path.join(self.chapter_dir, name))), name)
        return self._readers[name]

    def shared_reader(self, package_name):
        """MapReader over a shared package by name (e.g. P_Renovation), or None."""
        key = 'upk:' + package_name.lower()
        if key not in self._readers:
            if self._upk_index is None:
                self._upk_index = {}
                for root, _dirs, files in os.walk(self.cooked):
                    for f in files:
                        stem, ext = os.path.splitext(f)
                        if ext.lower() in ('.upk', '.u'):
                            self._upk_index.setdefault(stem.lower(), os.path.join(root, f))
            path = self._upk_index.get(package_name.lower())
            self._readers[key] = _labelled(MapReader(self._decompressed(path)), package_name) if path else None
        return self._readers[key]

    def cooked_reader(self, file_name):
        """MapReader over a top-level CookedPC file such as Engine.u."""
        key = 'cooked:' + file_name.lower()
        if key not in self._readers:
            self._readers[key] = _labelled(MapReader(self._decompressed(os.path.join(self.cooked, file_name))), file_name)
        return self._readers[key]

    def _decompressed(self, path):
        # Shared packages ship uncompressed (CompressionFlags 0); maps are LZO.
        if compression_flags(path) == 0:
            return path
        out = os.path.join(self.cache_dir, os.path.basename(path) + '.dec')
        if not os.path.exists(out):
            subprocess.run([sys.executable, os.path.join(TOOLS, 'ue3_decompress.py'), path, out],
                           check=True, capture_output=True)
        return out


def compression_flags(path):
    """CompressionFlags out of a UE3 package header (same walk as ue3_decompress.py)."""
    with open(path, 'rb') as fh:
        raw = fh.read(4096)
    off = 12
    slen, = struct.unpack_from('<i', raw, off); off += 4
    off += slen if slen >= 0 else -slen * 2
    off += 4 + 28 + 16
    gencount, = struct.unpack_from('<i', raw, off); off += 4
    off += gencount * 12 + 8
    return struct.unpack_from('<I', raw, off)[0]


def _labelled(reader, label):
    from lights import install_color_decoding
    reader.label = label
    install_color_decoding(reader)
    return reader


def import_path(pkg, index):
    """(root package, [outer names..., name]) of import #index (0-based)."""
    names = []
    entry = pkg.imports[index]
    while True:
        names.append(entry['name'])
        outer = entry.get('outer', 0)
        if outer < 0:
            entry = pkg.imports[-outer - 1]
            continue
        if outer > 0:
            raise ExtractError('import %s has an export as outer' % entry['name'])
        root = names.pop()
        return root, list(reversed(names))


def resolved_props(packages, mr, idx, depth=0):
    """Properties of export #idx with its WHOLE archetype chain merged, crossing
    into shared packages. Prefab instances (PF_*_Arc) keep their StaticMesh on
    an archetype component that lives in a prefab package; reading only the
    level package loses the mesh."""
    if depth > 16:
        raise ExtractError('%s: archetype chain too deep at export %d' % (mr.label, idx))
    chain, cur = [], idx
    while cur > 0:
        chain.append(cur)
        cur = mr.pkg.exports[cur - 1]['archetype']
    merged = {}
    if cur < 0:
        root, path = import_path(mr.pkg, -cur - 1)
        shared = packages.shared_reader(root)
        if shared is None:
            raise ExtractError('%s: archetype package %s is not installed' % (mr.label, root))
        target = find_export(shared, path)
        if target is None:
            raise ExtractError('%s: archetype %s not found in %s' % (mr.label, '.'.join(path), root))
        for key, value in resolved_props(packages, shared, target, depth + 1)[0].items():
            # Object references are indices into the package that wrote them.
            if isinstance(value, tuple) and len(value) == 2 and value[0] == 'obj' and value[1]:
                value = ('ext', shared, value[1])
            merged[key] = value
    for i in reversed(chain):
        props, _ = mr.props(i)
        if props:
            merged.update(props)
    return merged, mr


def find_export(mr, path):
    """1-based export index whose outer chain spells `path`, or None."""
    pkg = mr.pkg
    for i, e in enumerate(pkg.exports, 1):
        if e['name'] != path[-1]:
            continue
        names, outer = [e['name']], e['outer_idx']
        while outer > 0:
            names.append(pkg.exports[outer - 1]['name'])
            outer = pkg.exports[outer - 1]['outer_idx']
        if list(reversed(names)) == path:
            return i
    return None
