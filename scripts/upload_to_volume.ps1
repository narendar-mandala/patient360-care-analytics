<#
.SYNOPSIS
  Upload local landing files to the Unity Catalog Volume /Volumes/healthcare/landing/raw.

.DESCRIPTION
  Sources and where they land:
    epic_fhir     data\raw\epic_fhir\...                  -> raw/epic_fhir/extract_date=.../run_id=.../<Resource>.ndjson
    synthea_fhir  data\raw\synthea\run_id=<run>\fhir\     -> raw/synthea_fhir/run_id=<run>/<Resource>.ndjson
    synthea_csv   data\raw\synthea\run_id=<run>\csv\      -> raw/synthea_csv/<table>/run_id=<run>/<table>.csv
    reference     reference\*.csv                          -> raw/reference/<name>/<name>.csv

  Each Synthea CSV table gets its own folder so Bronze can load it as its own table.
  Synthea FHIR Claim/ExplanationOfBenefit/Provenance files are skipped: claims come from the CSVs.

.EXAMPLE
  .\upload_to_volume.ps1 -Source epic_fhir
  .\upload_to_volume.ps1 -Source synthea_fhir -RunId p1000_s42_massachusetts
  .\upload_to_volume.ps1 -Source synthea_csv -RunId p1000_s42_massachusetts
  .\upload_to_volume.ps1 -Source reference
#>
param(
    [Parameter(Mandatory)][ValidateSet("epic_fhir", "synthea_fhir", "synthea_csv", "reference")][string]$Source,
    [string]$RunId = "",
    [string]$Profile = "",   # Databricks CLI profile; leave empty to use your default profile
    [string]$VolumeRoot = "dbfs:/Volumes/healthcare/landing/raw"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$skipFhir = @("Claim", "ExplanationOfBenefit", "Provenance")
# Synthea CSV tables used in Phase 1.
$syntheaTables = @("patients", "organizations", "providers", "payers", "payer_transitions", "encounters", "conditions",
                   "procedures", "observations", "medications", "immunizations", "allergies", "claims", "claims_transactions")

switch ($Source) {
    "epic_fhir" {
        $localRoot = Join-Path $repoRoot "data\raw\epic_fhir"
        $files = Get-ChildItem $localRoot -Recurse -File
        $targetFor = { param($f) "$VolumeRoot/epic_fhir/" + $f.FullName.Substring($localRoot.Length + 1).Replace('\', '/') }
    }
    "synthea_fhir" {
        if (-not $RunId) { throw "-RunId is required for synthea_fhir" }
        $localRoot = Join-Path $repoRoot "data\raw\synthea\run_id=$RunId\fhir"
        $files = Get-ChildItem $localRoot -File -Filter *.ndjson | Where-Object { ($_.Name -split '\.')[0] -notin $skipFhir }
        $targetFor = { param($f) "$VolumeRoot/synthea_fhir/run_id=$RunId/$($f.Name)" }
    }
    "synthea_csv" {
        if (-not $RunId) { throw "-RunId is required for synthea_csv" }
        $localRoot = Join-Path $repoRoot "data\raw\synthea\run_id=$RunId\csv"
        $files = Get-ChildItem $localRoot -File -Filter *.csv | Where-Object { $_.BaseName -in $syntheaTables }
        $missing = $syntheaTables | Where-Object { $_ -notin $files.BaseName }
        if ($missing) { throw "Missing Synthea CSVs: $($missing -join ', ')" }
        $targetFor = { param($f) "$VolumeRoot/synthea_csv/$($f.BaseName)/run_id=$RunId/$($f.Name)" }
    }
    "reference" {
        $localRoot = Join-Path $repoRoot "reference"
        $files = Get-ChildItem $localRoot -File -Filter *.csv
        $targetFor = { param($f) "$VolumeRoot/reference/$($f.BaseName)/$($f.Name)" }
    }
}

$totalMB = [math]::Round(($files | Measure-Object Length -Sum).Sum / 1MB, 1)
Write-Host "Uploading $($files.Count) files ($totalMB MB) from $localRoot"

$profileArgs = if ($Profile) { @("--profile", $Profile) } else { @() }
$createdDirs = @{}
foreach ($f in $files) {
    $target = & $targetFor $f
    $dir = $target.Substring(0, $target.LastIndexOf('/'))
    if (-not $createdDirs.ContainsKey($dir)) {
        databricks fs mkdir $dir @profileArgs
        if ($LASTEXITCODE -ne 0) { throw "mkdir failed: $dir" }
        $createdDirs[$dir] = $true
    }
    $started = Get-Date
    databricks fs cp $f.FullName $target --overwrite @profileArgs | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Upload failed: $($f.FullName)" }
    Write-Host ("  {0,-30} {1,9:N1} MB  {2,5:N0}s" -f $f.Name, ($f.Length / 1MB), ((Get-Date) - $started).TotalSeconds)
}
Write-Host "Done."
