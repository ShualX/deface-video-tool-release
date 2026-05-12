Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ProjectRoot

New-Item -ItemType Directory -Force -Path input_videos, output_videos, review_frames, scripts | Out-Null

if (-not (Test-Path -LiteralPath ".\.venv\Scripts\python.exe")) {
    $PythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if (-not $PythonCommand) {
        $PythonCommand = Get-Command py -ErrorAction SilentlyContinue
    }
    if (-not $PythonCommand) {
        throw "没有找到 Python。请先安装 Python 3.10+，并勾选 Add Python to PATH。"
    }

    if ($PythonCommand.Name -eq "py.exe") {
        & $PythonCommand.Source -3 -m venv .venv
    } else {
        & $PythonCommand.Source -m venv .venv
    }
}

.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install deface onnx imageio-ffmpeg

Write-Host ""
Write-Host "基础安装完成。"
Write-Host "如需 GPU 加速，请在 GUI 中点击'安装 GPU 组件'，或运行："
Write-Host ".\.venv\Scripts\python.exe -m pip install onnxruntime-gpu nvidia-cudnn-cu12 nvidia-cuda-runtime-cu12 nvidia-cublas-cu12"
