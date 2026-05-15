param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$InputPath,

    [Parameter(Mandatory = $false, Position = 1)]
    [string]$OutputPath,

    [ValidateSet(1, 2, 4)]
    [int]$Segments = 2,

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
    [string]$FfmpegConfig,
    [switch]$KeepTemp
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$CommonScript = Join-Path $ScriptDir "deface_common.ps1"
$OneScript = Join-Path $ScriptDir "deface_one.ps1"
. $CommonScript

function Join-DefaceProcessArguments {
    param([string[]]$Arguments)

    $Quoted = foreach ($Argument in $Arguments) {
        if ($null -eq $Argument) {
            '""'
            continue
        }

        $Value = [string]$Argument
        if ($Value -eq "") {
            '""'
        } elseif ($Value -notmatch '[\s"]') {
            $Value
        } else {
            $Escaped = $Value -replace '(\\*)"', '$1$1\"'
            $Escaped = $Escaped -replace '(\\+)$', '$1$1'
            '"' + $Escaped + '"'
        }
    }

    return ($Quoted -join " ")
}

function Format-DefaceSeconds {
    param([double]$Value)
    return $Value.ToString("0.###", [System.Globalization.CultureInfo]::InvariantCulture)
}

function Invoke-DefaceNativeCapture {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Command
    )

    $PreviousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        & $Command
    } finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
    }
}

function Get-DefaceVideoDurationSeconds {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FfmpegExe,

        [Parameter(Mandatory = $true)]
        [string]$VideoPath
    )

    $ProbeOutput = Invoke-DefaceNativeCapture { & $FfmpegExe -hide_banner -i $VideoPath 2>&1 }

    $Text = ($ProbeOutput | Out-String)
    if ($Text -match "Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)") {
        $Hours = [double]::Parse($Matches[1], [System.Globalization.CultureInfo]::InvariantCulture)
        $Minutes = [double]::Parse($Matches[2], [System.Globalization.CultureInfo]::InvariantCulture)
        $Seconds = [double]::Parse($Matches[3], [System.Globalization.CultureInfo]::InvariantCulture)
        return ($Hours * 3600.0) + ($Minutes * 60.0) + $Seconds
    }

    throw "Unable to read video duration from ffmpeg output."
}

function New-CommonDefaceArgs {
    $Args = @(
        "-Thresh", (Format-DefaceDouble $Thresh),
        "-MaskScale", (Format-DefaceDouble $MaskScale),
        "-Scale", $Scale,
        "-ReplaceWith", $ReplaceWith,
        "-MosaicSize", ([string]$MosaicSize),
        "-KeepAudio", ([string](ConvertTo-DefaceBool $KeepAudio $true)),
        "-KeepMetadata", ([string](ConvertTo-DefaceBool $KeepMetadata $false)),
        "-Boxes", ([string](ConvertTo-DefaceBool $Boxes $false)),
        "-DrawScores", ([string](ConvertTo-DefaceBool $DrawScores $false)),
        "-Preview", ([string](ConvertTo-DefaceBool $Preview $false)),
        "-Backend", $Backend,
        "-UseGpu", ([string](ConvertTo-DefaceBool $UseGpu $false)),
        "-Encoder", $Encoder
    )

    if ($ReplaceImg) {
        $Args += @("-ReplaceImg", $ReplaceImg)
    }
    if ($ExecutionProvider) {
        $Args += @("-ExecutionProvider", $ExecutionProvider)
    }
    if ($FfmpegConfig) {
        $Args += @("-FfmpegConfig", $FfmpegConfig)
    }

    return $Args
}

function Invoke-DefaceOneProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InPath,

        [Parameter(Mandatory = $true)]
        [string]$OutPath
    )

    $Args = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $OneScript,
        "-InputPath", $InPath,
        "-OutputPath", $OutPath,
        "-ExistingAction", "overwrite"
    ) + (New-CommonDefaceArgs)

    & powershell.exe @Args
    return $LASTEXITCODE
}

function Read-NewLogText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [hashtable]$Offsets,

        [Parameter(Mandatory = $true)]
        [string]$Prefix
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    if (-not $Offsets.ContainsKey($Path)) {
        $Offsets[$Path] = 0
    }

    $FileInfo = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $FileInfo -or $FileInfo.Length -le $Offsets[$Path]) {
        return
    }

    $Reader = $null
    $Stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $Stream.Seek($Offsets[$Path], [System.IO.SeekOrigin]::Begin) | Out-Null
        $Reader = New-Object System.IO.StreamReader($Stream, [System.Text.Encoding]::UTF8, $true)
        $Text = $Reader.ReadToEnd()
        $Offsets[$Path] = $Stream.Position
    } finally {
        if ($Reader) {
            $Reader.Dispose()
        } else {
            $Stream.Dispose()
        }
    }

    if (-not $Text) {
        return
    }

    $CleanText = $Text -replace "`r", "`n"
    $CleanText = $CleanText -replace "[`u001b]\[[0-9;]*[A-Za-z]", ""
    foreach ($Line in ($CleanText -split "`n")) {
        $Trimmed = $Line.Trim()
        if ($Trimmed) {
            Write-Host "$Prefix $Trimmed"
        }
    }
}

function Stop-ChildProcessTree {
    param([int]$ProcessId)

    try {
        $Children = Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcessId" -ErrorAction SilentlyContinue
        foreach ($Child in $Children) {
            Stop-ChildProcessTree -ProcessId ([int]$Child.ProcessId)
        }
        Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
    } catch {}
}

function Invoke-ParallelDeface {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$SegmentItems
    )

    $LogOffsets = @{}
    $Processes = New-Object System.Collections.Generic.List[object]
    $CommonArgs = New-CommonDefaceArgs

    foreach ($Item in $SegmentItems) {
        $Args = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", $OneScript,
            "-InputPath", $Item.InputPath,
            "-OutputPath", $Item.OutputPath,
            "-ExistingAction", "overwrite"
        ) + $CommonArgs

        $ArgumentString = Join-DefaceProcessArguments $Args
        $Process = Start-Process -FilePath "powershell.exe" `
            -ArgumentList $ArgumentString `
            -PassThru `
            -WindowStyle Hidden `
            -RedirectStandardOutput $Item.StdOutPath `
            -RedirectStandardError $Item.StdErrPath

        $Processes.Add([pscustomobject]@{
            Index = $Item.Index
            Process = $Process
            StdOutPath = $Item.StdOutPath
            StdErrPath = $Item.StdErrPath
            Done = $false
            ExitCode = $null
        }) | Out-Null

        Write-Host ("Started segment {0}/{1}, process id {2}." -f $Item.Index, $SegmentItems.Count, $Process.Id)
    }

    $LastTick = Get-Date
    while ($true) {
        $Finished = 0
        $FailedProcess = $null

        foreach ($Entry in $Processes) {
            Read-NewLogText -Path $Entry.StdOutPath -Offsets $LogOffsets -Prefix ("[{0}/{1}]" -f $Entry.Index, $Processes.Count)
            Read-NewLogText -Path $Entry.StdErrPath -Offsets $LogOffsets -Prefix ("[{0}/{1}]" -f $Entry.Index, $Processes.Count)

            if (-not $Entry.Done -and $Entry.Process.HasExited) {
                $Entry.Process.Refresh()
                $Entry.ExitCode = [int]$Entry.Process.ExitCode
                $Entry.Done = $true
                Write-Host ("Segment {0}/{1} exited with code {2}." -f $Entry.Index, $Processes.Count, $Entry.ExitCode)
                if ($Entry.ExitCode -ne 0) {
                    $FailedProcess = $Entry
                }
            }

            if ($Entry.Done) {
                $Finished++
            }
        }

        if ($FailedProcess) {
            foreach ($Entry in $Processes) {
                if (-not $Entry.Done -and -not $Entry.Process.HasExited) {
                    Stop-ChildProcessTree -ProcessId $Entry.Process.Id
                }
            }
            throw ("Segment {0} failed with exit code {1}." -f $FailedProcess.Index, $FailedProcess.ExitCode)
        }

        if ($Finished -eq $Processes.Count) {
            break
        }

        if (((Get-Date) - $LastTick).TotalSeconds -ge 5) {
            Write-Host ("Parallel progress: {0}/{1} segments finished." -f $Finished, $Processes.Count)
            $LastTick = Get-Date
        }

        Start-Sleep -Milliseconds 500
    }

    foreach ($Entry in $Processes) {
        Read-NewLogText -Path $Entry.StdOutPath -Offsets $LogOffsets -Prefix ("[{0}/{1}]" -f $Entry.Index, $Processes.Count)
        Read-NewLogText -Path $Entry.StdErrPath -Offsets $LogOffsets -Prefix ("[{0}/{1}]" -f $Entry.Index, $Processes.Count)
    }
}

function ConvertTo-ConcatFileLine {
    param([string]$Path)
    $Normalized = $Path.Replace("\", "/")
    $Escaped = $Normalized -replace "'", "'\''"
    return "file '$Escaped'"
}

$BaseEnv = Test-DefaceBaseEnvironment -ProjectRoot $ProjectRoot
if (-not $BaseEnv.Ready) {
    throw $BaseEnv.Message
}

$ResolvedInput = (Resolve-Path -LiteralPath $InputPath).ProviderPath
if (-not $OutputPath) {
    $OutputDir = Join-Path $ProjectRoot "output_videos"
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

$PreviewValue = ConvertTo-DefaceBool $Preview $false
if ($PreviewValue -and $Segments -gt 1) {
    throw "Preview cannot be used with segmented parallel processing. Disable Preview or set Segments=1."
}

if ($Segments -le 1) {
    exit (Invoke-DefaceOneProcess -InPath $ResolvedInput -OutPath $OutputPath)
}

$FfmpegExe = Get-DefaceFfmpegExe -ProjectRoot $ProjectRoot
$DurationSeconds = Get-DefaceVideoDurationSeconds -FfmpegExe $FfmpegExe -VideoPath $ResolvedInput
if ($DurationSeconds -le 0) {
    throw "Video duration is not valid."
}

$EffectiveSegments = $Segments
if ($DurationSeconds -lt $EffectiveSegments) {
    $EffectiveSegments = [Math]::Max(1, [int][Math]::Floor($DurationSeconds))
}
if ($EffectiveSegments -le 1) {
    Write-Host "Video is too short for segmented processing; falling back to single process."
    exit (Invoke-DefaceOneProcess -InPath $ResolvedInput -OutPath $OutputPath)
}

$UseGpuValue = ConvertTo-DefaceBool $UseGpu $false
if ($UseGpuValue -and $EffectiveSegments -gt 2) {
    Write-Warning "GPU parallel processing with 4 segments may be slower or run out of VRAM. Try 2 segments first if this fails."
}

$InputItemInfo = Get-Item -LiteralPath $ResolvedInput
$InputExtension = $InputItemInfo.Extension
$OutputExtension = [System.IO.Path]::GetExtension($OutputPath)
if (-not $OutputExtension) {
    $OutputExtension = $InputExtension
}

$TempParent = if ($OutputParent) { $OutputParent } else { $ProjectRoot }
$TempDir = Join-Path $TempParent (".deface_segments_{0}_{1}" -f ([System.IO.Path]::GetFileNameWithoutExtension($OutputPath)), ([guid]::NewGuid().ToString("N")))
$SplitDir = Join-Path $TempDir "split"
$ProcessedDir = Join-Path $TempDir "processed"
$LogDir = Join-Path $TempDir "logs"
New-Item -ItemType Directory -Force -Path $SplitDir, $ProcessedDir, $LogDir | Out-Null

$CleanupTemp = $false
try {
    Write-Host "Input : $ResolvedInput"
    Write-Host "Output: $OutputPath"
    Write-Host ("Mode  : segmented parallel, segments={0}, duration={1}s, replace={2}, THRESH={3}, MASK_SCALE={4}, SCALE={5}, GPU={6}, encoder={7}" -f $EffectiveSegments, (Format-DefaceSeconds $DurationSeconds), $ReplaceWith, $Thresh, $MaskScale, $Scale, $UseGpuValue, $Encoder)
    Write-Host "Temp  : $TempDir"

    $SegmentItems = New-Object System.Collections.Generic.List[object]
    for ($Index = 0; $Index -lt $EffectiveSegments; $Index++) {
        $StartSeconds = ($DurationSeconds / $EffectiveSegments) * $Index
        $EndSeconds = if ($Index -eq ($EffectiveSegments - 1)) { $DurationSeconds } else { ($DurationSeconds / $EffectiveSegments) * ($Index + 1) }
        $SegmentSeconds = $EndSeconds - $StartSeconds
        if ($SegmentSeconds -le 0) {
            throw "Calculated segment duration is not valid."
        }

        $DisplayIndex = $Index + 1
        $SegmentInput = Join-Path $SplitDir ("segment_{0:000}{1}" -f $DisplayIndex, $InputExtension)
        $SegmentOutput = Join-Path $ProcessedDir ("segment_{0:000}_defaced{1}" -f $DisplayIndex, $OutputExtension)
        $StartText = Format-DefaceSeconds $StartSeconds
        $LengthText = Format-DefaceSeconds $SegmentSeconds

        Write-Host ("Splitting segment {0}/{1}: start={2}s, duration={3}s" -f $DisplayIndex, $EffectiveSegments, $StartText, $LengthText)
        $SplitOutput = Invoke-DefaceNativeCapture { & $FfmpegExe -hide_banner -y `
            -ss $StartText `
            -i $ResolvedInput `
            -t $LengthText `
            -map "0:v:0" -map "0:a?" -sn -dn `
            -c:v libx264 -preset ultrafast -crf 16 -c:a aac -b:a 192k `
            -avoid_negative_ts make_zero `
            $SegmentInput 2>&1 }

        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $SegmentInput)) {
            Write-Warning "Segment split failed while encoding AAC audio; retrying with copied audio."
            $SplitOutput | ForEach-Object { Write-Host $_ }
            $SplitOutput = Invoke-DefaceNativeCapture { & $FfmpegExe -hide_banner -y `
                -ss $StartText `
                -i $ResolvedInput `
                -t $LengthText `
                -map "0:v:0" -map "0:a?" -sn -dn `
                -c:v libx264 -preset ultrafast -crf 16 -c:a copy `
                -avoid_negative_ts make_zero `
                $SegmentInput 2>&1 }
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $SegmentInput)) {
                $Message = ($SplitOutput | Out-String).Trim()
                throw "Failed to split segment $DisplayIndex. $Message"
            }
        }

        $SegmentItems.Add([pscustomobject]@{
            Index = $DisplayIndex
            InputPath = $SegmentInput
            OutputPath = $SegmentOutput
            StdOutPath = Join-Path $LogDir ("segment_{0:000}.stdout.log" -f $DisplayIndex)
            StdErrPath = Join-Path $LogDir ("segment_{0:000}.stderr.log" -f $DisplayIndex)
        }) | Out-Null
    }

    Invoke-ParallelDeface -SegmentItems $SegmentItems.ToArray()

    $MissingOutputs = @($SegmentItems | Where-Object { -not (Test-Path -LiteralPath $_.OutputPath) })
    if ($MissingOutputs.Count -gt 0) {
        throw "One or more processed segments are missing."
    }

    $ConcatList = Join-Path $TempDir "concat.txt"
    $ConcatLines = foreach ($Item in $SegmentItems) {
        ConvertTo-ConcatFileLine $Item.OutputPath
    }
    [System.IO.File]::WriteAllLines($ConcatList, [string[]]$ConcatLines, (New-Object System.Text.UTF8Encoding($false)))

    Write-Host "Merging processed segments..."
    $MergeOutput = Invoke-DefaceNativeCapture { & $FfmpegExe -hide_banner -y `
        -f concat `
        -safe 0 `
        -i $ConcatList `
        -c copy `
        $OutputPath 2>&1 }
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $OutputPath)) {
        $Message = ($MergeOutput | Out-String).Trim()
        throw "Failed to merge processed segments. $Message"
    }

    Write-Host "Done. Output: $OutputPath"
    $CleanupTemp = $true
} finally {
    if ($CleanupTemp -and -not $KeepTemp) {
        Remove-Item -LiteralPath $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    } elseif (-not $CleanupTemp -or $KeepTemp) {
        Write-Host "Temporary files kept at: $TempDir"
    }
}
