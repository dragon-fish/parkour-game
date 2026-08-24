#!/usr/bin/env bash
#
# Runs the headless test suite through GUT (addons/gut, MIT). The macOS/Linux
# twin of run_tests.ps1 -- same flags, same filtering, same exit code.
#
#   tools/run_tests.sh                  every test
#   tools/run_tests.sh slide            only files whose name contains "slide"
#   tools/run_tests.sh slide crouch     either of them
#
# Filtering matters day to day: the suite spends most of its time awaiting
# physics frames, so narrowing to the area under change turns minutes into
# seconds. Unfiltered runs are for CI and for a pre-release check.
#
# No _console variant is needed here, unlike on Windows: the macOS binary
# inside the .app bundle writes to stdout directly.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot="$root/.engine/Godot_v4.7.1-stable_macos.universal.app/Contents/MacOS/Godot"

if [ ! -x "$godot" ]; then
    echo "run_tests.sh: Godot not found at $godot (is .engine/ populated?)" >&2
    exit 1
fi

# Refresh .godot/global_script_class_cache.cfg first. Without this, any
# class_name declared since the last editor scan fails to resolve and every
# test dies with 'Identifier "Xxx" not declared in the current scope'.
"$godot" --headless --path "$root" --import >/dev/null

# -gdir without -ginclude_subdirs, so tests/legacy/ stays archived rather than
# running. -gexit returns control (and an exit code) instead of leaving a
# window open.
# --fixed-fps is the difference between a suite that takes minutes and one that
# takes seconds: "This setting disables real-time synchronization" (Godot's own
# command line docs), so the main loop runs as fast as the CPU allows instead of
# pacing itself against a wall clock. The delta each frame sees is unchanged, so
# every physics measurement in these tests reads exactly the same -- verified
# against test_turn_deceleration.gd, which went from 56 s to 0.96 s with
# identical results.
#
# 60 to match physics/common/physics_ticks_per_second, so one main-loop frame is
# one physics tick and await get_tree().physics_frame advances by one.
gut_args=(
    --headless --fixed-fps 60 --path "$root"
    -s res://addons/gut/gut_cmdln.gd
    -gprefix=test_
    -gexit
)

if [ "$#" -eq 0 ]; then
    gut_args+=(-gdir=res://tests)
else
    # -gselect takes a single filename substring, so several filters are
    # resolved to explicit paths here instead. -gtest accepts a list.
    #
    # Deliberately NOT recursive, matching the .ps1: only tests/ itself, so
    # tests/legacy/ stays archived even when a filter would have matched a
    # file down there.
    # Both declared up front: under `set -u`, macOS's stock bash 3.2 treats a
    # never-assigned array as unbound even in ${#...}.
    matched=()
    unique=()
    for needle in "$@"; do
        for path in "$root"/tests/test_*.gd; do
            [ -e "$path" ] || continue
            name="$(basename "$path")"
            case "$name" in
                *"$needle"*) matched+=("res://tests/$name") ;;
            esac
        done
    done

    if [ "${#matched[@]}" -gt 0 ]; then
        # Sort/unique the same way the .ps1 does, so two filters matching one
        # file do not run it twice.
        while IFS= read -r line; do
            unique+=("$line")
        done < <(printf '%s\n' "${matched[@]}" | sort -u)
    fi

    if [ "${#unique[@]}" -eq 0 ]; then
        echo "run_tests.sh: no test file matched: $*" >&2
        exit 1
    fi

    echo "run_tests.sh: ${#unique[@]} file(s) matching $*"
    for path in "${unique[@]}"; do
        gut_args+=("-gtest=$path")
    done
fi

"$godot" "${gut_args[@]}"
