# Runs the headless test suite. Uses the _console.exe variant because the
# plain exe detaches from the console and swallows stdout on Windows.
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

# Capture stdout+stderr merged, in order, streaming each line to this console
# as it arrives (so a human watching still sees normal progress) while also
# keeping a copy to scan afterward.
#
# This second pass matters because the test runner's own pass/fail count
# (tests/test_case.gd's checks/failures, totalled in tests/test_runner.gd)
# cannot see a test method whose coroutine crashed outright: an unhandled
# GDScript runtime error -- a bad property access, a call to a nonexistent
# method, a failed assert -- silently aborts that method and the runner
# moves on to the next one, recording zero checks and zero failures for it.
# `all_failures.size() > 0` (test_runner.gd's own exit-code gate) never sees
# it either. The engine's own error output is the only thing that reliably
# reports every such crash, so it is scanned directly rather than trusting
# the exit code alone.
$outputLines = New-Object System.Collections.Generic.List[string]
& $godot --headless --path $root --script res://tests/test_runner.gd 2>&1 | ForEach-Object {
    $text = $_.ToString()
    Write-Output $text
    $outputLines.Add($text)
}
$godotExitCode = $LASTEXITCODE

# Godot's console error printer prefixes every uncaught error with one of
# these depending on its origin: "SCRIPT ERROR:" for GDScript runtime
# failures (bad property access, nonexistent method calls, failed asserts --
# exactly the crashes the check counter cannot see), and "ERROR:" for an
# explicit push_error() call (empirically confirmed against this exact
# Godot 4.7.1 build: push_error() prints "ERROR:", not "USER ERROR:", but
# "USER ERROR:" is matched too in case a differently-configured error
# handler ever produces it). Matched at line start so a check() failure
# message that happens to contain the word "error" cannot trip this.
$errorPattern = '^(SCRIPT ERROR|USER ERROR|ERROR):'

# NARROW allowlist. tests/test_state_machine.gd's
# test_unknown_transition_leaves_the_machine_running deliberately drives
# StateMachine.physics_update() to an unregistered state name to prove the
# machine degrades safely instead of freezing (see the assert() in
# scripts/player/states/state_machine.gd's unknown-transition guard) --
# that assert failing IS the test passing, not a crash. Matched on the
# assert's exact message text, not the file name or the bogus state name,
# so a real new crash anywhere in test_state_machine.gd cannot hide behind
# this entry.
$allowlist = @(
    'Assertion failed: transition to unknown state: Nonexistent'
)

$unexpected = @()
foreach ($text in $outputLines) {
    if ($text -match $errorPattern) {
        $isAllowed = $false
        foreach ($entry in $allowlist) {
            if ($text -like "*$entry*") {
                $isAllowed = $true
                break
            }
        }
        if (-not $isAllowed) {
            $unexpected += $text
        }
    }
}

if ($unexpected.Count -gt 0) {
    Write-Output ""
    Write-Output "run_tests.ps1: $($unexpected.Count) unexpected engine error line(s) found -- these are invisible to the check counter, so they fail the run on their own:"
    foreach ($text in $unexpected) {
        Write-Output "  $text"
    }
    exit 1
}

exit $godotExitCode
