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

& $godot --headless --path $root --script res://tests/test_runner.gd
exit $LASTEXITCODE
