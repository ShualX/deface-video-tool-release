param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$InputPath,

    [Parameter(Mandatory = $false, Position = 1)]
    [string]$OutputPath,

    [ValidateRange(0.0, 1.0)]
    [double]$Thresh = 0.15,

    [ValidateRange(0.1, 10.0)]
    [double]$MaskScale = 1.45,

    [ValidatePattern("^\d+x\d+$")]
    [string]$Scale = "1280x720",

    [ValidateSet("blur", "solid", "none", "img", "mosaic")]
    [string]$ReplaceWith = "mosaic",

    [ValidateRange(1, 200)]
    [int]$MosaicSize = 20,

    [string]$ReplaceImg,

    [object]$KeepAudio = $true,
    [object]$KeepMetadata = $false,
    [object]$Boxes = $false,
    [object]$DrawScores = $false,
    [object]$Preview = $false,

    [ValidateSet("auto", "onnxrt", "opencv")]
    [string]$Backend = "auto",

    [string]$ExecutionProvider,
    [object]$UseGpu = $false,
    [ValidateSet("libx264", "h264_nvenc", "hevc_nvenc", "custom")]
    [string]$Encoder = "libx264",
    [ValidateSet("overwrite", "skip", "rename")]
    [string]$ExistingAction = "overwrite",
    [string]$FfmpegConfig
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$CommonScript = Join-Path $ScriptDir "deface_common.ps1"
. $CommonScript

$DefaceExe = Join-Path $ProjectRoot ".venv\Scripts\deface.exe"
$OutputDir = Join-Path $ProjectRoot "output_videos"

if (-not (Test-Path -LiteralPath $DefaceExe)) {
    throw "deface.exe not found: $DefaceExe. Please install deface in .venv first."
}

$ResolvedInput = (Resolve-Path -LiteralPath $InputPath).ProviderPath
if (-not $OutputPath) {
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    $InputItem = Get-Item -LiteralPath $ResolvedInput
    $OutputName = "{0}_defaced{1}" -f $InputItem.BaseName, $InputItem.Extension
    $OutputPath = Join-Path $OutputDir $OutputName
}

$OutputParent = Split-Path -Parent $OutputPath
if ($OutputParent) {
    New-Item -ItemType Directory -Force -Path $OutputParent | Out-Null
}

$OutputDecision = Resolve-DefaceOutputPath -OutputPath $OutputPath -ExistingAction $ExistingAction
if ($OutputDecision.Skip) {
    Write-Host "Skipping existing output: $OutputPath"
    exit 0
}
if ($OutputDecision.WasRenamed) {
    Write-Host "Output exists, using a new filename: $($OutputDecision.Path)"
}
$OutputPath = $OutputDecision.Path

$KeepAudioValue = ConvertTo-DefaceBool $KeepAudio $true
$KeepMetadataValue = ConvertTo-DefaceBool $KeepMetadata $false
$BoxesValue = ConvertTo-DefaceBool $Boxes $false
$DrawScoresValue = ConvertTo-DefaceBool $DrawScores $false
$PreviewValue = ConvertTo-DefaceBool $Preview $false
$UseGpuValue = ConvertTo-DefaceBool $UseGpu $false

$Args = @(
    "--output", $OutputPath,
    "--thresh", (Format-DefaceDouble $Thresh),
    "--mask-scale", (Format-DefaceDouble $MaskScale),
    "--scale", $Scale,
    "--replacewith", $ReplaceWith
)

if ($ReplaceWith -eq "mosaic") {
    $Args += @("--mosaicsize", ([string]$MosaicSize))
}

if ($ReplaceWith -eq "img") {
    if (-not $ReplaceImg) {
        throw "ReplaceWith=img requires -ReplaceImg."
    }
    $Args += @("--replaceimg", $ReplaceImg)
}

if ($KeepAudioValue) {
    $Args += "--keep-audio"
}
if ($KeepMetadataValue) {
    $Args += "--keep-metadata"
}
if ($BoxesValue) {
    $Args += "--boxes"
}
if ($DrawScoresValue) {
    $Args += "--draw-scores"
}
if ($PreviewValue) {
    $Args += "--preview"
}
if (-not $FfmpegConfig -and $Encoder -ne "custom") {
    $FfmpegConfig = New-DefaceFfmpegConfig -Encoder $Encoder
}
if ($FfmpegConfig) {
    $NativeFfmpegConfig = $FfmpegConfig -replace '"', '\"'
    $Args += @("--ffmpeg-config", $NativeFfmpegConfig)
}

$GpuEnabled = $false
if ($UseGpuValue) {
    Add-DefaceNvidiaDllPath -ProjectRoot $ProjectRoot | Out-Null
    $GpuStatus = Get-DefaceGpuStatus -ProjectRoot $ProjectRoot
    if ($GpuStatus.CudaAvailable) {
        $Args += @("--backend", "onnxrt", "--execution-provider", "CUDAExecutionProvider")
        $GpuEnabled = $true
    } else {
        Write-Warning "GPU was requested, but CUDAExecutionProvider is not available. Falling back to backend=$Backend. Providers=$($GpuStatus.Providers -join ','); Active=$($GpuStatus.ActiveProviders -join ','); Error=$($GpuStatus.CudaError)$($GpuStatus.Error)"
    }
}

if (-not $GpuEnabled) {
    if ($Backend -ne "auto") {
        $Args += @("--backend", $Backend)
    }
    if ($ExecutionProvider) {
        $Args += @("--execution-provider", $ExecutionProvider)
    }
}

$Args += $ResolvedInput

Write-Host "Input : $ResolvedInput"
Write-Host "Output: $OutputPath"
Write-Host "Mode  : $ReplaceWith, THRESH=$Thresh, MASK_SCALE=$MaskScale, SCALE=$Scale, keep audio=$KeepAudioValue, GPU=$GpuEnabled, encoder=$Encoder"

& $DefaceExe @Args
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
