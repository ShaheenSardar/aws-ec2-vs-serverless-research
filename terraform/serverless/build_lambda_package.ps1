$ErrorActionPreference = "Stop"

$ModuleDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Resolve-Path (Join-Path $ModuleDir "..\..")

$PackageDir = Join-Path $ModuleDir "package"
$ZipPath    = Join-Path $ModuleDir "lambda_package.zip"

Remove-Item $PackageDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue

New-Item -ItemType Directory -Path $PackageDir -Force | Out-Null

Copy-Item `
    (Join-Path $RepoRoot "application\lambda\lambda_function.py") `
    (Join-Path $PackageDir "lambda_function.py")

Copy-Item `
    (Join-Path $RepoRoot "application\lambda\compute_logic.py") `
    (Join-Path $PackageDir "compute_logic.py")

Compress-Archive `
    -Path (Join-Path $PackageDir "*") `
    -DestinationPath $ZipPath `
    -CompressionLevel Optimal

$Hash = Get-FileHash $ZipPath -Algorithm SHA256

[PSCustomObject]@{
    Package = $ZipPath
    Bytes   = (Get-Item $ZipPath).Length
    SHA256  = $Hash.Hash
} | Format-List
