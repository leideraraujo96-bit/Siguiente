# Arma el zip que WowUp descarga: dist\Siguiente-v<version>-forever.zip (con la carpeta Siguiente\ adentro)
# y dist\release.json, que le dice a WowUp que el zip es para WoW Forever.
# Uso: powershell -ExecutionPolicy Bypass -File tools\empaquetar.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$toc = Join-Path $root "Siguiente.toc"

$version = (Select-String -Path $toc -Pattern '^## Version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()
$interface = (Select-String -Path $toc -Pattern '^## Interface:\s*(\d+)').Matches[0].Groups[1].Value.Trim()
$tag = "v$version"
$zipName = "Siguiente-$tag-forever.zip"

$dist = Join-Path $root "dist"
if (Test-Path $dist) { Remove-Item -Recurse -Force $dist }
New-Item -ItemType Directory -Force $dist | Out-Null

# Solo los archivos del addon: el .toc y los .lua que lista.
$files = @("Siguiente.toc") + (Get-Content $toc | Where-Object { $_ -match '^[^#\s].*\.lua\s*$' } | ForEach-Object { $_.Trim() })

# Zip con rutas "Siguiente/archivo" (barra normal; Compress-Archive de PowerShell 5 usa "\", que rompe algunos descompresores).
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipPath = Join-Path $dist $zipName
$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($f in $files) {
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, (Join-Path $root $f), "Siguiente/$f") | Out-Null
    }
} finally {
    $zip.Dispose()
}

$release = @{
    releases = @(@{
        name     = "Siguiente"
        version  = $tag
        filename = $zipName
        nolib    = $false
        metadata = @(@{ flavor = "forever"; interface = [int]$interface })
    })
}
$release | ConvertTo-Json -Depth 5 | Set-Content -Encoding ascii (Join-Path $dist "release.json")

Write-Output "TAG=$tag"
Write-Output "ZIP=$(Join-Path $dist $zipName)"
Write-Output "JSON=$(Join-Path $dist 'release.json')"
