# Baut divergence_bench.exe mit nvcc (neueste installierte CUDA-Version) + MSVC-Host-Compiler.
# Sucht CUDA und cl.exe automatisch, damit der Build nach einem CUDA-Upgrade ohne
# Pfadanpassung durchlaeuft.
$ErrorActionPreference = "Stop"

# --- nvcc finden: PATH zuerst, sonst neueste v* unter dem Standard-Toolkit-Pfad ---
$nvcc = (Get-Command nvcc -ErrorAction SilentlyContinue).Source
if (-not $nvcc) {
    $nvcc = Get-ChildItem "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v*\bin\nvcc.exe" -ErrorAction SilentlyContinue |
            Sort-Object { [version](($_.Directory.Parent.Name) -replace '^v','') } |
            Select-Object -Last 1 -ExpandProperty FullName
}
if (-not $nvcc) { throw "nvcc nicht gefunden. Ist das CUDA Toolkit installiert?" }
$cudaVer = (& $nvcc --version | Select-String -Pattern "release ([\d.]+)").Matches.Groups[1].Value
Write-Host "nvcc: $nvcc (CUDA $cudaVer)"

# --- MSVC-Host-Compiler finden (irgendeine installierte VS-Ausgabe/Toolset-Version) ---
$cl = Get-ChildItem "C:\Program Files\Microsoft Visual Studio\*\*\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe" -ErrorAction SilentlyContinue |
      Sort-Object { [version]$_.Directory.Parent.Parent.Parent.Name } |
      Select-Object -Last 1 -ExpandProperty FullName
if (-not $cl) { throw "cl.exe (MSVC-Host-Compiler) nicht gefunden." }
Write-Host "Host-Compiler: $cl"

# nvcc parst das cl-Banner und versteht nur Englisch ("for x64", nicht "fuer x64")
$env:VSLANG = "1033"

$src = Join-Path $PSScriptRoot "src\divergence_bench.cu"
$out = Join-Path $PSScriptRoot "divergence_bench.exe"

& $nvcc -O3 -arch=sm_86 -ccbin "$cl" -Xcompiler "/openmp /O2 /EHsc" -o "$out" "$src"
if ($LASTEXITCODE -ne 0) { throw "nvcc fehlgeschlagen (Exit $LASTEXITCODE)" }
Write-Host "OK: $out"
