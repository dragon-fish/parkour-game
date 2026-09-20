class_name KismetGraph
extends Resource

## A chapter's Kismet as the extractor's kismet.py writes it, for KismetRunner.
## A resource of its own so that thousands of nodes stay out of a scene file
## and load, compressed, with the rest of the level's dependencies.

## id -> {cls, package, name, ins, outs, vars?, props?, ...}
@export var nodes: Dictionary = {}
## id -> {cls, name?, value? | actor? | actors? | find?}
@export var variables: Dictionary = {}
## "<package key>.<actor>" -> {cls, package, trigger?}
@export var actors: Dictionary = {}
