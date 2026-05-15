param(
    [string]$InputDir,
    [string]$OutputDir,

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
    [string]$ExistingAction = "skip",
    [string]$FfmpegConfig,

    [ValidateSet(1, 2, 4)]
    [int]$ParallelSegments = 1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$OneScript = Join-Path $ScriptDir "deface_one.ps1"
$ParallelScript = Join-Path $ScriptDir "deface_parallel.ps1"
. (Join-Path $ScriptDir "deface_common.ps1")

if (-not $InputDir) {
    $InputDir = Join-Path $ProjectRoot "input_videos"
}
if (-not $OutputDir) {
    $OutputDir = Join-Path $ProjectRoot "output_videos"
}

New-Item -ItemType Directory -Force -Path $InputDir, $OutputDir | Out-Null

$KeepAudioValue = ConvertTo-DefaceBool $KeepAudio $true
$KeepMetadataValue = ConvertTo-DefaceBool $KeepMetadata $false
$BoxesValue = ConvertTo-DefaceBool $Boxes $false
$DrawScoresValue = ConvertTo-DefaceBool $DrawScores $false
$PreviewValue = ConvertTo-DefaceBool $Preview $false
$UseGpuValue = ConvertTo-DefaceBool $UseGpu $false

$Extensions = @(".mp4", ".mov", ".mkv", ".avi", ".wmv", ".m4v", ".webm")
$Videos = Get-ChildItem -LiteralPath $InputDir -File |
    Where-Object { $Extensions -contains $_.Extension.ToLowerInvariant() } |
    Sort-Object Name

if (-not $Videos) {
    Write-Host "No videos found in $InputDir"
    exit 0
}

foreach ($Video in $Videos) {
    $OutputPath = Join-Path $OutputDir ("{0}_defaced{1}" -f $Video.BaseName, $Video.Extension)
    $OutputDecision = Resolve-DefaceOutputPath -OutputPath $OutputPath -ExistingAction $ExistingAction
    if ($OutputDecision.Skip) {
        Write-Host ""
        Write-Host "Skipping existing output: $OutputPath"
        continue
    }
    $OutputPath = $OutputDecision.Path

    Write-Host ""
    Write-Host "Processing $($Video.Name)"

    $WorkerScript = if ($ParallelSegments -gt 1) { $ParallelScript } else { $OneScript }

    $CommandArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $WorkerScript,
        "-InputPath", $Video.FullName,
        "-OutputPath", $OutputPath,
        "-Thresh", (Format-DefaceDouble $Thresh),
        "-MaskScale", (Format-DefaceDouble $MaskScale),
        "-Scale", $Scale,
        "-ReplaceWith", $ReplaceWith,
        "-MosaicSize", ([string]$MosaicSize),
        "-KeepAudio", ([string]$KeepAudioValue),
        "-KeepMetadata", ([string]$KeepMetadataValue),
        "-Boxes", ([string]$BoxesValue),
        "-DrawScores", ([string]$DrawScoresValue),
        "-Preview", ([string]$PreviewValue),
        "-Backend", $Backend,
        "-UseGpu", ([string]$UseGpuValue),
        "-Encoder", $Encoder,
        "-ExistingAction", "overwrite"
    )

    if ($ParallelSegments -gt 1) {
        $CommandArgs += @("-Segments", ([string]$ParallelSegments))
    }
    if ($ReplaceImg) {
        $CommandArgs += @("-ReplaceImg", $ReplaceImg)
    }
    if ($ExecutionProvider) {
        $CommandArgs += @("-ExecutionProvider", $ExecutionProvider)
    }
    if ($FfmpegConfig) {
        $CommandArgs += @("-FfmpegConfig", $FfmpegConfig)
    }

    & powershell.exe @CommandArgs

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to process $($Video.FullName)"
    }
}

Write-Host ""
Write-Host "Done. Output videos are in $OutputDir"
