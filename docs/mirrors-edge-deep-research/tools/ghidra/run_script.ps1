# Usage: run_script.ps1 <Script.java> <out_name> <depth> <args> ...
param([string]$Script, [string]$Out, [int]$Depth, [Parameter(ValueFromRemainingArguments)][string[]]$Targets)
$env:JAVA_HOME = 'C:\Program Files\Microsoft\jdk-21.0.9.10-hotspot'
if (-not $env:GHIDRA_HEADLESS_MAXMEM) { $env:GHIDRA_HEADLESS_MAXMEM = '12G' }
# Workspace: _local/me-re at the repository root (gitignored). Ghidra project in ghidra/, output in native/.
$r = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..\_local\me-re')).Path
# ME_GHIDRA_PROJECT selects another copy of the project, so several runs can go in parallel.
$proj = if ($env:ME_GHIDRA_PROJECT) { $env:ME_GHIDRA_PROJECT } else { "$r\ghidra" }
& 'D:\ghidra_12.1.4_PUBLIC\support\analyzeHeadless.bat' $proj 'MirrorsEdge' -process 'MirrorsEdge.exe' -noanalysis -readOnly -scriptPath $PSScriptRoot -postScript $Script "$r\native\$Out" $Depth @Targets *> "$r\native\$Out.log"
Select-String -Path "$r\native\$Out.log" -Pattern 'SCRIPT ERROR|Exception' | Select-Object -First 3
"{0} bytes" -f (Get-Item "$r\native\$Out").Length
