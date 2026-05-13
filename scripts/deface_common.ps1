Set-StrictMode -Version Latest

function Get-DefaceProjectRoot {
    param(
        [string]$ScriptPath
    )

    $ScriptDir = Split-Path -Parent $ScriptPath
    return Split-Path -Parent $ScriptDir
}

function Format-DefaceDouble {
    param(
        [double]$Value
    )

    return $Value.ToString("0.########", [System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertTo-DefaceBool {
    param(
        [object]$Value,
        [bool]$Default = $false
    )

    if ($null -eq $Value) {
        return $Default
    }
    if ($Value -is [bool]) {
        return [bool]$Value
    }

    $Text = ([string]$Value).Trim().ToLowerInvariant()
    if (-not $Text) {
        return $Default
    }

    switch ($Text) {
        "true" { return $true }
        '$true' { return $true }
        "1" { return $true }
        "yes" { return $true }
        "y" { return $true }
        "on" { return $true }
        "false" { return $false }
        '$false' { return $false }
        "0" { return $false }
        "no" { return $false }
        "n" { return $false }
        "off" { return $false }
        default { throw "Cannot convert '$Value' to Boolean." }
    }
}

function Test-DefaceBaseEnvironment {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $PythonExe = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
    $DefaceExe = Join-Path $ProjectRoot ".venv\Scripts\deface.exe"
    $PythonReady = Test-Path -LiteralPath $PythonExe
    $DefaceReady = Test-Path -LiteralPath $DefaceExe
    $Ready = $PythonReady -and $DefaceReady
    $Message = "基础环境已安装。"

    if (-not $PythonReady) {
        $Message = "未找到 .venv 中的 Python。请先运行 setup.ps1，或在 GUI 中点击'安装基础环境'。"
    } elseif (-not $DefaceReady) {
        $Message = "未找到 deface.exe。请重新运行 setup.ps1 完成基础安装。"
    }

    return [pscustomobject]@{
        Ready = $Ready
        PythonExe = $PythonExe
        DefaceExe = $DefaceExe
        PythonReady = $PythonReady
        DefaceReady = $DefaceReady
        Message = $Message
    }
}

function Get-DefaceFfmpegExe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $FfmpegCommand = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($FfmpegCommand) {
        return $FfmpegCommand.Source
    }

    $PythonExe = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
    if (-not (Test-Path -LiteralPath $PythonExe)) {
        throw "未找到 ffmpeg，也未找到 .venv 中的 Python。请先运行 setup.ps1，或在 GUI 中点击'安装基础环境'。"
    }

    $FfmpegExe = & $PythonExe -c "import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())"
    if ($LASTEXITCODE -ne 0 -or -not $FfmpegExe -or -not (Test-Path -LiteralPath $FfmpegExe)) {
        throw "未找到 ffmpeg，并且无法从 imageio-ffmpeg 获取内置 ffmpeg。请重新运行 setup.ps1。"
    }

    return $FfmpegExe
}

function Test-DefaceFfmpegEncoder {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FfmpegExe,

        [Parameter(Mandatory = $true)]
        [string]$Encoder
    )

    $TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("deface_encoder_test_{0}" -f ([guid]::NewGuid().ToString("N")))
    $OutputPath = Join-Path $TempDir "test.mp4"
    $ErrorMessage = ""
    $Available = $false

    try {
        New-Item -ItemType Directory -Force -Path $TempDir | Out-Null
        $Output = & $FfmpegExe -hide_banner -loglevel error `
            -f lavfi -i "color=c=black:s=320x240:r=1:d=1" `
            -an -frames:v 1 -pix_fmt yuv420p -c:v $Encoder -y $OutputPath 2>&1
        $Available = ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $OutputPath))
        if (-not $Available) {
            $ErrorMessage = ($Output | Out-String).Trim()
            if (-not $ErrorMessage) {
                $ErrorMessage = "ffmpeg exited with code $LASTEXITCODE."
            }
        }
    } catch {
        $ErrorMessage = $_.Exception.Message
    } finally {
        Remove-Item -LiteralPath $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    return [pscustomobject]@{
        Available = $Available
        Error = $ErrorMessage
    }
}

function Get-DefaceEncoderStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $FfmpegExe = ""
    $Encoders = ""
    $ErrorMessage = ""
    $H264NvencListed = $false
    $HevcNvencListed = $false
    $H264NvencStatus = [pscustomobject]@{ Available = $false; Error = "" }
    $HevcNvencStatus = [pscustomobject]@{ Available = $false; Error = "" }
    try {
        $FfmpegExe = Get-DefaceFfmpegExe -ProjectRoot $ProjectRoot
        $Encoders = (& $FfmpegExe -hide_banner -encoders 2>&1 | Out-String)
        $H264NvencListed = ($Encoders -match "\bh264_nvenc\b")
        $HevcNvencListed = ($Encoders -match "\bhevc_nvenc\b")
        if ($H264NvencListed) {
            $H264NvencStatus = Test-DefaceFfmpegEncoder -FfmpegExe $FfmpegExe -Encoder "h264_nvenc"
        }
        if ($HevcNvencListed) {
            $HevcNvencStatus = Test-DefaceFfmpegEncoder -FfmpegExe $FfmpegExe -Encoder "hevc_nvenc"
        }
    } catch {
        $ErrorMessage = $_.Exception.Message
    }

    return [pscustomobject]@{
        FfmpegExe = $FfmpegExe
        Libx264 = ($Encoders -match "\blibx264\b")
        H264NvencListed = $H264NvencListed
        HevcNvencListed = $HevcNvencListed
        H264Nvenc = [bool]$H264NvencStatus.Available
        HevcNvenc = [bool]$HevcNvencStatus.Available
        Av1Nvenc = ($Encoders -match "\bav1_nvenc\b")
        H264NvencError = [string]$H264NvencStatus.Error
        HevcNvencError = [string]$HevcNvencStatus.Error
        Error = $ErrorMessage
    }
}

function New-DefaceFfmpegConfig {
    param(
        [ValidateSet("libx264", "h264_nvenc", "hevc_nvenc", "custom")]
        [string]$Encoder = "libx264"
    )

    if ($Encoder -eq "custom") {
        return ""
    }

    return (@{ codec = $Encoder } | ConvertTo-Json -Compress)
}

function Get-DefaceNvidiaDllDirs {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $NvidiaRoot = Join-Path $ProjectRoot ".venv\Lib\site-packages\nvidia"
    if (-not (Test-Path -LiteralPath $NvidiaRoot)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $NvidiaRoot -Directory -ErrorAction SilentlyContinue |
        ForEach-Object {
            $BinDir = Join-Path $_.FullName "bin"
            if (Test-Path -LiteralPath $BinDir) {
                $BinDir
            }
        })
}

function Add-DefaceNvidiaDllPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $Dirs = Get-DefaceNvidiaDllDirs -ProjectRoot $ProjectRoot
    foreach ($Dir in $Dirs) {
        if ($env:PATH -notlike "*$Dir*") {
            $env:PATH = "$Dir;$env:PATH"
        }
    }
    return $Dirs
}

function Resolve-DefaceOutputPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [ValidateSet("overwrite", "skip", "rename")]
        [string]$ExistingAction = "overwrite"
    )

    if (-not (Test-Path -LiteralPath $OutputPath)) {
        return [pscustomobject]@{
            Path = $OutputPath
            Skip = $false
            WasRenamed = $false
        }
    }

    if ($ExistingAction -eq "skip") {
        return [pscustomobject]@{
            Path = $OutputPath
            Skip = $true
            WasRenamed = $false
        }
    }

    if ($ExistingAction -eq "rename") {
        $Directory = Split-Path -Parent $OutputPath
        $Name = [System.IO.Path]::GetFileNameWithoutExtension($OutputPath)
        $Extension = [System.IO.Path]::GetExtension($OutputPath)
        for ($Index = 2; $Index -lt 10000; $Index++) {
            $Candidate = Join-Path $Directory ("{0}_{1}{2}" -f $Name, $Index, $Extension)
            if (-not (Test-Path -LiteralPath $Candidate)) {
                return [pscustomobject]@{
                    Path = $Candidate
                    Skip = $false
                    WasRenamed = $true
                }
            }
        }
        throw "Unable to find a free output filename near $OutputPath."
    }

    return [pscustomobject]@{
        Path = $OutputPath
        Skip = $false
        WasRenamed = $false
    }
}

function Get-DefaceGpuStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $PythonExe = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
    $NvidiaSmiCommand = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    $NvidiaAvailable = $null -ne $NvidiaSmiCommand
    $NvidiaName = ""
    $OrtInstalled = $false
    $Providers = @()
    $ActiveProviders = @()
    $CudaTest = $false
    $CudaError = ""
    $DllDirs = @()
    $ErrorMessage = ""

    if ($NvidiaAvailable) {
        try {
            $NvidiaName = (& $NvidiaSmiCommand.Source --query-gpu=name --format=csv,noheader 2>$null | Select-Object -First 1)
        } catch {
            $NvidiaName = "NVIDIA GPU"
        }
    }

    if (Test-Path -LiteralPath $PythonExe) {
        $DllDirs = Add-DefaceNvidiaDllPath -ProjectRoot $ProjectRoot
        $StatusPath = [System.IO.Path]::GetTempFileName()
        $Code = @"
import json
import sys
result = {'installed': False, 'providers': [], 'error': '', 'cuda_test': False, 'active_providers': [], 'cuda_error': ''}
try:
    import onnxruntime as ort
    result['installed'] = True
    result['providers'] = list(ort.get_available_providers())
    if 'CUDAExecutionProvider' in result['providers']:
        try:
            import importlib.util
            import os
            spec = importlib.util.find_spec('deface')
            model = os.path.join(os.path.dirname(spec.origin), 'centerface.onnx')
            sess = ort.InferenceSession(model, providers=['CUDAExecutionProvider'])
            result['active_providers'] = list(sess.get_providers())
            result['cuda_test'] = 'CUDAExecutionProvider' in result['active_providers']
        except Exception as cuda_exc:
            result['cuda_error'] = str(cuda_exc)
except Exception as exc:
    result['error'] = str(exc)
with open(sys.argv[1], 'w', encoding='utf-8') as f:
    json.dump(result, f)
"@

        $PreviousErrorActionPreference = $null
        try {
            $PreviousErrorActionPreference = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            $ProbeOutput = & $PythonExe -c $Code $StatusPath 2>&1
            $ErrorActionPreference = $PreviousErrorActionPreference
            if ((Test-Path -LiteralPath $StatusPath) -and (Get-Item -LiteralPath $StatusPath).Length -gt 0) {
                $Parsed = Get-Content -LiteralPath $StatusPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $OrtInstalled = [bool]$Parsed.installed
                $Providers = @($Parsed.providers)
                $CudaTest = [bool]$Parsed.cuda_test
                $ActiveProviders = @($Parsed.active_providers)
                $CudaError = [string]$Parsed.cuda_error
                $ErrorMessage = [string]$Parsed.error
            } else {
                $ErrorMessage = ($ProbeOutput | Out-String).Trim()
            }
        } catch {
            if ($null -ne $PreviousErrorActionPreference) {
                $ErrorActionPreference = $PreviousErrorActionPreference
            }
            $ErrorMessage = $_.Exception.Message
        } finally {
            if ($null -ne $PreviousErrorActionPreference) {
                $ErrorActionPreference = $PreviousErrorActionPreference
            }
            Remove-Item -LiteralPath $StatusPath -Force -ErrorAction SilentlyContinue
        }
    } else {
        $ErrorMessage = "Python executable not found in .venv."
    }

    $CudaAvailable = $OrtInstalled -and ($Providers -contains "CUDAExecutionProvider") -and $CudaTest
    if ($CudaAvailable -and -not $NvidiaName) {
        $NvidiaName = "CUDA GPU"
    }

    return [pscustomobject]@{
        NvidiaAvailable = $NvidiaAvailable
        NvidiaName = $NvidiaName
        OnnxRuntimeInstalled = $OrtInstalled
        Providers = $Providers
        ActiveProviders = $ActiveProviders
        CudaAvailable = $CudaAvailable
        CudaError = $CudaError
        NvidiaDllDirs = $DllDirs
        Error = $ErrorMessage
    }
}
