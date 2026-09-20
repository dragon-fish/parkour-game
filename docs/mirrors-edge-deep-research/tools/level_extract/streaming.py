"""Which of a chapter's packages come and go, and how they are spelt.

[ME:CONFIRMED] a chapter's packages are loaded and unloaded by
SeqAct_MultiLevelStreaming (and a few SeqAct_LevelStreaming) in Kismet, and a
TdCheckpoint lists the packages a restore there loads. The
LevelStreamingVolumes are all bDisabled and nothing activates a
SeqAct_StreamingZone anywhere in the game; neither is read.

WHEN they come and go is not decided here. It was, once: every streaming
action was walked up to the touch or button that fires it and written as a
flat step. The graph between the two holds state -- a Gate that starts shut, a
Switch routed by a variable, a door that waits for a load's Finished -- and
walked through as though it held none, a button unloaded the floor the player
stood on. kismet.py exports the graph and the level runs it.
See docs/superpowers/specs/2026-09-21-me-level-streaming-design.md for the
presence half, docs/kismet-runtime.md for the rest.
"""

STREAMING_ACTIONS = ('SeqAct_MultiLevelStreaming', 'SeqAct_LevelStreaming')
# Packages with no geometry: nothing of them is built, so nothing of them is
# governed. Their Kismet still runs -- Convoy unloads a corridor from a music
# package.
NO_GEOMETRY = ('_aud', '_mus')


def package_key(name):
    """A package as every table here spells it: lower case, no extension. The
    original's own spelling varies (Convoy_Roof-Conv_slc_lgts). The builder's
    MeLevelCommon.package_key() is the same rule."""
    name = str(name)
    return (name[:-4] if name.lower().endswith('.me1') else name).lower()


def has_geometry(key):
    return not key.endswith(NO_GEOMETRY)


def managed(checkpoints, graph):
    """Packages something loads or unloads: named by a checkpoint's snapshot or
    by a streaming action. Any other package is in the level throughout."""
    found = set()
    for c in checkpoints:
        found.update(c.get('streaming', []))
    for node in graph['nodes'].values():
        if node['cls'] in STREAMING_ACTIONS:
            found.update(node.get('levels', []))
    return sorted(k for k in found if has_geometry(k))
