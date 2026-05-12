Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ProjectRoot

New-Item -ItemType Directory -Force -Path input_videos, output_videos, review_frames, scripts | Out-Null

if (-not (Test-Path -LiteralPath ".\.venv\Scripts\python.exe")) {
    python -m venv .venv
}

.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install deface onnx

Write-Host ""
Write-Host "基础安装完成。"
Write-Host "如需 GPU 加速，请在 GUI 中点击“安装 GPU 组件”，或运行："
Write-Host ".\.venv\Scripts\python.exe -m pip install onnxruntime-gpu nvidia-cudnn-cu12 nvidia-cuda-runtime-cu12 nvidia-cublas-cu12"
