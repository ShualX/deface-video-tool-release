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
        throw "ffmpeg was not found in PATH, and .venv Python was not found."
    }

    $FfmpegExe = & $PythonExe -c "import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())"
    if ($LASTEXITCODE -ne 0 -or -not $FfmpegExe -or -not (Test-Path -LiteralPath $FfmpegExe)) {
        throw "ffmpeg was not found in PATH, and bundled imageio-ffmpeg could not be located."
    }

    return $FfmpegExe
}

function Get-DefaceEncoderStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $FfmpegExe = ""
    $Encoders = ""
    $ErrorMessage = ""
    try {
        $FfmpegExe = Get-DefaceFfmpegExe -ProjectRoot $ProjectRoot
        $Encoders = (& $FfmpegExe -hide_banner -encoders 2>&1 | Out-String)
    } catch {
        $ErrorMessage = $_.Exception.Message
    }

    return [pscustomobject]@{
        FfmpegExe = $FfmpegExe
        Libx264 = ($Encoders -match "\blibx264\b")
        H264Nvenc = ($Encoders -match "\bh264_nvenc\b")
        HevcNvenc = ($Encoders -match "\bhevc_nvenc\b")
        Av1Nvenc = ($Encoders -match "\bav1_nvenc\b")
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

    $CudaAvailable = $NvidiaAvailable -and $OrtInstalled -and ($Providers -contains "CUDAExecutionProvider") -and $CudaTest

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
