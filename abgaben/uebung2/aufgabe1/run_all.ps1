# Fuehrt beide Mess-Sweeps aus und schreibt results/e1_scaling.csv + results/e2_divergence.csv
$ErrorActionPreference = "Stop"
$exe = Join-Path $PSScriptRoot "divergence_bench.exe"
$res = Join-Path $PSScriptRoot "results"
New-Item -ItemType Directory -Force $res | Out-Null

function Run-Bench([string]$csv, [string[]]$benchArgs, [bool]$writeHeader) {
    $allArgs = @($benchArgs) + @("--check")
    if ($writeHeader) { $allArgs += "--header" }
    Write-Host ">> $($allArgs -join ' ')"
    & $exe @allArgs | Add-Content $csv
    if ($LASTEXITCODE -ne 0) { throw "Benchmark fehlgeschlagen: $($allArgs -join ' ')" }
}

# ---- E1: Skalierung ueber n (d=1, k=4096) -----------------------------------
$e1 = Join-Path $res "e1_scaling.csv"
Remove-Item $e1 -ErrorAction SilentlyContinue
$first = $true
$nsGpu = 1024, 4096, 16384, 65536, 262144, 1048576, 4194304, 16777216, 67108864
foreach ($n in $nsGpu) {
    Run-Bench $e1 @("--mode","gpu-intra","--n",$n,"--k",4096,"--d",1,"--reps",10) $first
    $first = $false
}
foreach ($n in $nsGpu | Where-Object { $_ -le 4194304 }) {
    Run-Bench $e1 @("--mode","cpu-omp","--n",$n,"--k",4096,"--d",1,"--reps",3) $false
}
foreach ($n in $nsGpu | Where-Object { $_ -le 1048576 }) {
    Run-Bench $e1 @("--mode","cpu","--n",$n,"--k",4096,"--d",1,"--reps",3) $false
}

# ---- E2: Divergenz-Sweep (n=16M, k=4096) ------------------------------------
$e2 = Join-Path $res "e2_divergence.csv"
Remove-Item $e2 -ErrorAction SilentlyContinue
$first = $true
$ds = 1, 2, 4, 8, 16, 32
foreach ($d in $ds) {
    Run-Bench $e2 @("--mode","gpu-intra","--n",16777216,"--k",4096,"--d",$d,"--reps",10) $first
    $first = $false
}
foreach ($d in $ds) {
    Run-Bench $e2 @("--mode","gpu-warpuniform","--n",16777216,"--k",4096,"--d",$d,"--reps",10) $false
}
foreach ($d in $ds) {
    Run-Bench $e2 @("--mode","cpu-omp","--n",16777216,"--k",4096,"--d",$d,"--reps",2) $false
}

Write-Host "Fertig: $e1, $e2"
