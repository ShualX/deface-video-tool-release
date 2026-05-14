Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$Arguments = @(),

        [string]$DisplayName = $FilePath
    )

    Write-Host ("> " + $DisplayName + " " + ($Arguments -join " "))
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "命令执行失败，退出码 $LASTEXITCODE：$DisplayName $($Arguments -join ' ')"
    }
}

function Test-PythonCandidate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$PrefixArgs = @(),

        [string]$DisplayName = $FilePath
    )

    try {
        $Output = & $FilePath @PrefixArgs "--version" 2>&1
        if ($LASTEXITCODE -ne 0) {
            return $null
        }
        $Text = ($Output | Out-String).Trim()
        if ($Text -notmatch "Python\s+3\.(\d+)") {
            return $null
        }

        return [pscustomobject]@{
            FilePath = $FilePath
            PrefixArgs = @($PrefixArgs)
            DisplayName = $DisplayName
            VersionText = $Text
        }
    } catch {
        return $null
    }
}

function Get-SetupPython {
    $Candidates = @(
        @{ Name = "py"; Args = @("-3"); Label = "py" },
        @{ Name = "python"; Args = @(); Label = "python" },
        @{ Name = "python3"; Args = @(); Label = "python3" }
    )

    foreach ($Candidate in $Candidates) {
        $Command = Get-Command $Candidate.Name -ErrorAction SilentlyContinue
        if (-not $Command) {
            continue
        }

        $Python = Test-PythonCandidate -FilePath $Command.Source -PrefixArgs $Candidate.Args -DisplayName $Candidate.Label
        if ($Python) {
            return $Python
        }
    }

    throw "没有找到可用的 Python 3。请先安装 Python 3.10+，并勾选 Add Python to PATH，然后重新运行安装。"
}

try {
    $ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    Set-Location $ProjectRoot

    New-Item -ItemType Directory -Force -Path input_videos, output_videos, review_frames, scripts | Out-Null

    $VenvPython = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
    $DefaceExe = Join-Path $ProjectRoot ".venv\Scripts\deface.exe"

    if (-not (Test-Path -LiteralPath $VenvPython)) {
        $Python = Get-SetupPython
        Write-Host "使用 Python：$($Python.VersionText) ($($Python.DisplayName))"
        Invoke-CheckedCommand -FilePath $Python.FilePath `
            -Arguments (@($Python.PrefixArgs) + @("-m", "venv", ".venv")) `
            -DisplayName $Python.DisplayName
    }

    if (-not (Test-Path -LiteralPath $VenvPython)) {
        throw "虚拟环境创建失败：未找到 $VenvPython"
    }

    Invoke-CheckedCommand -FilePath $VenvPython -Arguments @("-m", "pip", "install", "--upgrade", "pip") -DisplayName ".venv\Scripts\python.exe"
    Invoke-CheckedCommand -FilePath $VenvPython -Arguments @("-m", "pip", "install", "deface", "onnx", "imageio-ffmpeg") -DisplayName ".venv\Scripts\python.exe"

    if (-not (Test-Path -LiteralPath $DefaceExe)) {
        throw "deface 安装失败：未找到 $DefaceExe"
    }

    Write-Host ""
    Write-Host "基础安装完成。"
    Write-Host "如需 GPU 加速，请在 GUI 中点击'安装 GPU 组件'，或运行："
    Write-Host ".\.venv\Scripts\python.exe -m pip install onnxruntime-gpu nvidia-cudnn-cu12 nvidia-cuda-runtime-cu12 nvidia-cublas-cu12"
} catch {
    Write-Error $_.Exception.Message
    throw
}
