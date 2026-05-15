param(
    [string]$Version,
    [string]$OutputDir,
    [string]$PythonSource,
    [switch]$SkipPortablePython
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
Set-Location $ProjectRoot

if (-not $Version) {
    $Version = (Get-Content -LiteralPath (Join-Path $ProjectRoot "VERSION") -Raw -Encoding UTF8).Trim()
}
if (-not $Version) {
    throw "VERSION 文件为空。"
}
if (-not $OutputDir) {
    $OutputDir = Split-Path -Parent $ProjectRoot
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

function Invoke-ReleaseCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [string[]]$Arguments = @()
    )

    Write-Host ("> " + $FilePath + " " + ($Arguments -join " "))
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "命令失败，退出码 $LASTEXITCODE：$FilePath $($Arguments -join ' ')"
    }
}

function Get-DefaultPythonSource {
    $Candidates = @(
        @{ Name = "py"; Args = @("-3"); Label = "py -3" },
        @{ Name = "python"; Args = @(); Label = "python" },
        @{ Name = "python3"; Args = @(); Label = "python3" }
    )

    foreach ($Candidate in $Candidates) {
        $Command = Get-Command $Candidate.Name -ErrorAction SilentlyContinue
        if (-not $Command) {
            continue
        }

        try {
            $Code = "import sys, os; print(sys.base_prefix or sys.prefix)"
            $Output = & $Command.Source @($Candidate.Args) "-c" $Code 2>$null
            if ($LASTEXITCODE -eq 0 -and $Output) {
                $Path = ([string]$Output).Trim()
                if ((Test-Path -LiteralPath (Join-Path $Path "python.exe")) -and (Test-Path -LiteralPath (Join-Path $Path "Lib\venv"))) {
                    Write-Host "使用本机 Python 作为便携 Python 来源：$Path"
                    return $Path
                }
            }
        } catch {}
    }

    throw "没有找到可复制的本机 Python。请用 -PythonSource 指定 Python 安装目录。"
}

function Copy-PortablePython {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    $Source = (Resolve-Path -LiteralPath $Source).ProviderPath
    if (-not (Test-Path -LiteralPath (Join-Path $Source "python.exe"))) {
        throw "PythonSource 必须指向包含 python.exe 的目录：$Source"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $Source "Lib\venv"))) {
        throw "PythonSource 缺少 Lib\venv，无法用于创建 .venv：$Source"
    }

    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null

    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }

    Remove-Item -LiteralPath (Join-Path $Destination "Lib\site-packages") -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $Destination "Lib\test") -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $Destination "Doc") -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath $Destination -Recurse -Force -Directory -Filter "__pycache__" -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    $PortablePython = Join-Path $Destination "python.exe"
    $ProbeVenv = Join-Path ([System.IO.Path]::GetTempPath()) ("deface_portable_python_probe_{0}" -f ([guid]::NewGuid().ToString("N")))
    try {
        Invoke-ReleaseCommand -FilePath $PortablePython -Arguments @("-m", "venv", $ProbeVenv)
        $ProbePython = Join-Path $ProbeVenv "Scripts\python.exe"
        Invoke-ReleaseCommand -FilePath $ProbePython -Arguments @("-m", "pip", "--version")
    } finally {
        Remove-Item -LiteralPath $ProbeVenv -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function New-ZipFromDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceDirectory,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    if (Test-Path -LiteralPath $DestinationPath) {
        Remove-Item -LiteralPath $DestinationPath -Force
    }
    Compress-Archive -LiteralPath $SourceDirectory -DestinationPath $DestinationPath -CompressionLevel Optimal
}

$ScriptZip = Join-Path $OutputDir ("deface-video-tool-release-{0}-script.zip" -f $Version)
$ScriptPrefix = "deface-video-tool-release-{0}-script/" -f $Version
if (Test-Path -LiteralPath $ScriptZip) {
    Remove-Item -LiteralPath $ScriptZip -Force
}
Invoke-ReleaseCommand -FilePath "git" -Arguments @("archive", "--format=zip", "--output", $ScriptZip, "--prefix=$ScriptPrefix", "HEAD")

$Outputs = @($ScriptZip)

if (-not $SkipPortablePython) {
    if (-not $PythonSource) {
        $PythonSource = Get-DefaultPythonSource
    }

    $TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("deface_release_{0}" -f ([guid]::NewGuid().ToString("N")))
    $PortableRootName = "deface-video-tool-release-{0}-portable-python" -f $Version
    $PortableRoot = Join-Path $TempRoot $PortableRootName
    $PortableZip = Join-Path $OutputDir ("{0}.zip" -f $PortableRootName)

    try {
        New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
        Invoke-ReleaseCommand -FilePath "git" -Arguments @("archive", "--format=zip", "--output", (Join-Path $TempRoot "source.zip"), "--prefix=$PortableRootName/", "HEAD")
        Expand-Archive -LiteralPath (Join-Path $TempRoot "source.zip") -DestinationPath $TempRoot -Force
        Copy-PortablePython -Source $PythonSource -Destination (Join-Path $PortableRoot "portable_python")
        New-ZipFromDirectory -SourceDirectory $PortableRoot -DestinationPath $PortableZip
        $Outputs += $PortableZip
    } finally {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "Release packages:"
foreach ($Output in $Outputs) {
    $Item = Get-Item -LiteralPath $Output
    $Hash = Get-FileHash -LiteralPath $Output -Algorithm SHA256
    "{0}  {1:N2} MB  SHA256={2}" -f $Item.FullName, ($Item.Length / 1MB), $Hash.Hash
}
