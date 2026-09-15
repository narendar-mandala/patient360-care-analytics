<#
.SYNOPSIS
  Generate a reproducible synthetic patient population with Synthea.

.DESCRIPTION
  Exports both FHIR R4 Bulk NDJSON (same shape as Epic Bulk FHIR $export) and CSV
  (source for the Clarity-style and claims tables in Phase 2).

.EXAMPLE
  .\generate_population.ps1 -Population 1000                  # dev tier
  .\generate_population.ps1 -Population 25000 -HeapGB 12      # demo tier
#>
param(
    [int]$Population = 1000,
    [int]$Seed = 42,
    [string]$State = "Massachusetts",
    [string]$City = "",
    [int]$YearsOfHistory = 10,
    [string]$ReferenceDate = "20260831",   # YYYYMMDD: "today" inside the simulation
    [int]$HeapGB = 8,
    [string]$RepoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
)

$ErrorActionPreference = "Stop"

$jarDir = Join-Path $PSScriptRoot "bin"
$jar = Join-Path $jarDir "synthea-with-dependencies.jar"
$jarUrl = "https://github.com/synthetichealth/synthea/releases/download/master-branch-latest/synthea-with-dependencies.jar"

if (-not (Test-Path $jar)) {
    New-Item -ItemType Directory -Force $jarDir | Out-Null
    Write-Host "Downloading Synthea from $jarUrl"
    Invoke-WebRequest -Uri $jarUrl -OutFile $jar
}

$runLabel = "p${Population}_s${Seed}_$($State.ToLower() -replace '\s','_')"
$runDir = Join-Path $RepoRoot "data\raw\synthea\run_id=$runLabel"
if (Test-Path $runDir) {
    throw "$runDir already exists. Same seed + params = same data; delete the folder to regenerate."
}
New-Item -ItemType Directory -Force $runDir | Out-Null

$synthArgs = @(
    "-Xmx${HeapGB}g", "-jar", $jar,
    "-p", $Population,
    "-s", $Seed,
    "-cs", $Seed,
    "-r", $ReferenceDate,
    "--exporter.baseDirectory=$runDir",
    "--exporter.years_of_history=$YearsOfHistory",
    "--exporter.csv.export=true",
    "--exporter.fhir.export=true",
    "--exporter.fhir.bulk_data=true",
    "--exporter.hospital.fhir.export=true",
    "--exporter.practitioner.fhir.export=true",
    "--exporter.clinical_note.export=true",
    $State
)
if ($City) { $synthArgs += $City }

$started = Get-Date
Write-Host "Generating $Population patients -> $runDir"
& java @synthArgs
if ($LASTEXITCODE -ne 0) { throw "Synthea exited with code $LASTEXITCODE" }

[ordered]@{
    source_system    = "synthea"
    run_id           = $runLabel
    population       = $Population
    seed             = $Seed
    state            = $State
    city             = $City
    years_of_history = $YearsOfHistory
    reference_date   = $ReferenceDate
    started_local    = $started.ToString("o")
    duration_minutes = [math]::Round(((Get-Date) - $started).TotalMinutes, 1)
} | ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $runDir "_manifest.json")

Write-Host "Done. Profile it with: python data_generation/synthea/profile_output.py `"$runDir`""
