# SPDX-License-Identifier: 0BSD
param([string]$Godot, [switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$candidates = [Collections.Generic.List[string]]::new()
if ($Godot) { $candidates.Add($Godot) }
if ($env:GODOT_EXE) { $candidates.Add($env:GODOT_EXE) }
$steamRoots = [Collections.Generic.List[string]]::new()
try { $steam = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam').SteamPath; if ($steam) { $steamRoots.Add($steam) } } catch {}
$steamRoots.Add((Join-Path ${env:ProgramFiles(x86)} 'Steam'))
foreach ($steamRoot in @($steamRoots.ToArray())) {
    $libraries = Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $libraries) {
        foreach ($match in [regex]::Matches([IO.File]::ReadAllText($libraries), '"path"\s+"([^"]+)"')) {
            $steamRoots.Add($match.Groups[1].Value.Replace('\\','\'))
        }
    }
}
foreach ($steamRoot in $steamRoots) { $candidates.Add((Join-Path $steamRoot 'steamapps\common\Godot Engine\Godot Engine.exe')) }
$engine = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $engine) { throw 'Godot was not found. Set GODOT_EXE to your installed Godot executable.' }
if ($CheckOnly) { Write-Output $engine; exit 0 }
& $engine --path $projectRoot --fullscreen --resolution 1920x1080 --max-fps 60 res://demo/worlds.tscn
