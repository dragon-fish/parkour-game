# Runs the headless test suite through GUT (addons/gut, MIT).
#
# Uses the _console.exe variant because the plain exe detaches from the console
# and swallows stdout on Windows.
#
#   tools\run_tests.ps1                 every test
#   tools\run_tests.ps1 slide           only files whose name contains "slide"
#   tools\run_tests.ps1 slide crouch    either of them
#
# Filtering matters day to day: the suite spends most of its time awaiting
# physics frames, so narrowing to the area under change turns minutes into
# seconds. Unfiltered runs are for CI and for a pre-release check.
#
# Arguments are read from $args rather than a param() block, which did not
# receive positional arguments under this file's comment header.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $root '.engine\Godot_v4.7.1-stable_win64_console.exe'

if (-not (Test-Path $godot)) {
    Write-Error "Godot not found at $godot (is the .engine junction present?)"
}

# Refresh .godot/global_script_class_cache.cfg first. Without this, any
# class_name declared since the last editor scan fails to resolve and every
# test dies with 'Identifier "Xxx" not declared in the current scope'.
& $godot --headless --path $root --import | Out-Null

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
$gutArgs = @(
    '--headless', '--fixed-fps', '60', '--path', $root,
    '-s', 'res://addons/gut/gut_cmdln.gd',
    '-gdir=res://tests',
    '-gprefix=test_',
    '-gexit'
)

if ($args.Count -gt 0) {
    # -gselect takes a single filename substring, so several filters are
    # resolved to explicit paths here instead. -gtest accepts a list.
    $matched = @()
    foreach ($needle in $args) {
        $matched += Get-ChildItem -Path (Join-Path $root 'tests') -Filter 'test_*.gd' |
            Where-Object { $_.Name -like "*$needle*" } |
            ForEach-Object { "res://tests/$($_.Name)" }
    }
    $matched = $matched | Sort-Object -Unique
    if ($matched.Count -eq 0) {
        Write-Error "no test file matched: $($args -join ', ')"
    }
    Write-Output "run_tests.ps1: $($matched.Count) file(s) matching $($args -join ', ')"
    $gutArgs = $gutArgs | Where-Object { $_ -ne '-gdir=res://tests' }
    foreach ($path in $matched) { $gutArgs += "-gtest=$path" }
}

& $godot @gutArgs
exit $LASTEXITCODE
