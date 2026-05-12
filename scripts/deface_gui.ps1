param(
    [switch]$SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $SelfTest -and [System.Threading.Thread]::CurrentThread.ApartmentState -ne "STA") {
    Start-Process powershell.exe -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-STA",
        "-File", $MyInvocation.MyCommand.Path
    )
    exit
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
. (Join-Path $ScriptDir "deface_common.ps1")

$OneScript = Join-Path $ScriptDir "deface_one.ps1"
$BatchScript = Join-Path $ScriptDir "deface_batch.ps1"
$ReviewScript = Join-Path $ScriptDir "review_frames.ps1"
$PythonExe = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
$SettingsPath = Join-Path $ProjectRoot ".deface_gui_settings.json"
$GuiLogPath = Join-Path $ProjectRoot "deface_gui.log"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Control]::CheckForIllegalCrossThreadCalls = $false

[System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
[System.Windows.Forms.Application]::add_ThreadException({
    param($Sender, $EventArgs)
    $Message = $EventArgs.Exception.Message
    try {
        Write-Log ("界面异常：" + $Message)
    } catch {}
    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        "界面异常",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
})
[AppDomain]::CurrentDomain.add_UnhandledException({
    param($Sender, $EventArgs)
    $Exception = $EventArgs.ExceptionObject
    if ($Exception -is [System.Exception]) {
        $Message = $Exception.Message
    } else {
        $Message = [string]$Exception
    }
    try {
        Write-Log ("未处理异常：" + $Message)
    } catch {}
})

function New-UiFont {
    param(
        [float]$Size = 9,
        [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular
    )
    return New-Object System.Drawing.Font("Microsoft YaHei UI", $Size, $Style)
}

function Add-Label {
    param(
        [System.Windows.Forms.Control]$Parent,
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W = 96,
        [int]$H = 24
    )
    $Label = New-Object System.Windows.Forms.Label
    $Label.Text = $Text
    $Label.Location = New-Object System.Drawing.Point($X, $Y)
    $Label.Size = New-Object System.Drawing.Size($W, $H)
    $Label.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $Parent.Controls.Add($Label)
    return $Label
}

function Add-TextBox {
    param(
        [System.Windows.Forms.Control]$Parent,
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W = 420,
        [int]$H = 24
    )
    $Box = New-Object System.Windows.Forms.TextBox
    $Box.Text = $Text
    $Box.Location = New-Object System.Drawing.Point($X, $Y)
    $Box.Size = New-Object System.Drawing.Size($W, $H)
    $Parent.Controls.Add($Box)
    return $Box
}

function Add-Button {
    param(
        [System.Windows.Forms.Control]$Parent,
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W = 92,
        [int]$H = 28
    )
    $Button = New-Object System.Windows.Forms.Button
    $Button.Text = $Text
    $Button.Location = New-Object System.Drawing.Point($X, $Y)
    $Button.Size = New-Object System.Drawing.Size($W, $H)
    $Parent.Controls.Add($Button)
    return $Button
}

function Add-CheckBox {
    param(
        [System.Windows.Forms.Control]$Parent,
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W = 130,
        [bool]$Checked = $false
    )
    $Check = New-Object System.Windows.Forms.CheckBox
    $Check.Text = $Text
    $Check.Checked = $Checked
    $Check.Location = New-Object System.Drawing.Point($X, $Y)
    $Check.Size = New-Object System.Drawing.Size($W, 24)
    $Parent.Controls.Add($Check)
    return $Check
}

function Add-Combo {
    param(
        [System.Windows.Forms.Control]$Parent,
        [string[]]$Items,
        [string]$Selected,
        [int]$X,
        [int]$Y,
        [int]$W = 120,
        [bool]$DropDown = $false
    )
    $Combo = New-Object System.Windows.Forms.ComboBox
    if ($DropDown) {
        $Combo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
    } else {
        $Combo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    }
    $Combo.Items.AddRange($Items)
    $Combo.Text = $Selected
    if (-not $DropDown) {
        $Combo.SelectedItem = $Selected
    }
    $Combo.Location = New-Object System.Drawing.Point($X, $Y)
    $Combo.Size = New-Object System.Drawing.Size($W, 24)
    $Parent.Controls.Add($Combo)
    return $Combo
}

function Add-Number {
    param(
        [System.Windows.Forms.Control]$Parent,
        [decimal]$Value,
        [decimal]$Minimum,
        [decimal]$Maximum,
        [decimal]$Increment,
        [int]$DecimalPlaces,
        [int]$X,
        [int]$Y,
        [int]$W = 88
    )
    $Number = New-Object System.Windows.Forms.NumericUpDown
    $Number.DecimalPlaces = $DecimalPlaces
    $Number.Increment = $Increment
    $Number.Minimum = $Minimum
    $Number.Maximum = $Maximum
    $Number.Value = $Value
    $Number.Location = New-Object System.Drawing.Point($X, $Y)
    $Number.Size = New-Object System.Drawing.Size($W, 24)
    $Parent.Controls.Add($Number)
    return $Number
}

function Show-Info {
    param([string]$Message, [string]$Title = "提示")
    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}

function Show-Warning {
    param([string]$Message, [string]$Title = "注意")
    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
}

function Show-Error {
    param([string]$Message, [string]$Title = "错误")
    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
}

function Format-UiNumber {
    param([decimal]$Value)
    return $Value.ToString("0.########", [System.Globalization.CultureInfo]::InvariantCulture)
}

function Write-Log {
    param([string]$Message)
    $Time = Get-Date -Format "HH:mm:ss"
    $Line = "[$Time] $Message"

    try {
        Add-Content -LiteralPath $GuiLogPath -Value $Line -Encoding UTF8
    } catch {}

    $Variable = Get-Variable -Name LogBox -Scope Script -ErrorAction SilentlyContinue
    if (-not $Variable -or -not $script:LogBox) {
        return
    }

    $Append = {
        try {
            $script:LogBox.AppendText("$Line`r`n")
            $script:LogBox.SelectionStart = $script:LogBox.TextLength
            $script:LogBox.ScrollToCaret()
        } catch {}
    }

    if ($script:LogBox.InvokeRequired) {
        try {
            $script:LogBox.BeginInvoke([System.Action]$Append) | Out-Null
        } catch {}
        return
    }

    & $Append
}

function Join-ProcessArguments {
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

function Stop-ProcessTree {
    param([int]$ProcessId)

    try {
        $Children = Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcessId" -ErrorAction SilentlyContinue
        foreach ($Child in $Children) {
            Stop-ProcessTree -ProcessId ([int]$Child.ProcessId)
        }
        Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Log ("停止进程失败：" + $_.Exception.Message)
    }
}

function Invoke-GuiCommand {
    param(
        [string]$Exe,
        [string[]]$Arguments
    )

    Write-Log ("> " + $Exe + " " + ($Arguments -join " "))

    $OutPath = Join-Path $env:TEMP ("deface_gui_stdout_{0}.log" -f ([guid]::NewGuid().ToString("N")))
    $ErrPath = Join-Path $env:TEMP ("deface_gui_stderr_{0}.log" -f ([guid]::NewGuid().ToString("N")))

    try {
        $ArgumentString = Join-ProcessArguments $Arguments
        $Process = Start-Process -FilePath $Exe `
            -ArgumentList $ArgumentString `
            -PassThru `
            -WindowStyle Hidden `
            -RedirectStandardOutput $OutPath `
            -RedirectStandardError $ErrPath
        $script:CurrentProcess = $Process
        $ReadOffsets = @{}
        $ReadOffsets[$OutPath] = 0
        $ReadOffsets[$ErrPath] = 0
        $LastProgressTick = Get-Date

        while (-not $Process.HasExited) {
            if ($script:CancelRequested) {
                Write-Log "收到停止请求，正在结束当前任务..."
                Stop-ProcessTree -ProcessId $Process.Id
                return 130
            }

            foreach ($Path in @($OutPath, $ErrPath)) {
                if (Test-Path -LiteralPath $Path) {
                    $FileInfo = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
                    if ($FileInfo -and $FileInfo.Length -gt $ReadOffsets[$Path]) {
                        $Stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                        try {
                            $Stream.Seek($ReadOffsets[$Path], [System.IO.SeekOrigin]::Begin) | Out-Null
                            $Reader = New-Object System.IO.StreamReader($Stream, [System.Text.Encoding]::Default)
                            $Text = $Reader.ReadToEnd()
                            $ReadOffsets[$Path] = $Stream.Position
                        } finally {
                            if ($Reader) {
                                $Reader.Dispose()
                            } else {
                                $Stream.Dispose()
                            }
                        }

                        if ($Text) {
                            $CleanText = $Text -replace "`r", "`n"
                            $CleanText = $CleanText -replace "[`u001b]\[[0-9;]*[A-Za-z]", ""
                            foreach ($Line in ($CleanText -split "`n")) {
                                $Trimmed = $Line.Trim()
                                if ($Trimmed) {
                                    Write-Log $Trimmed
                                    if ($Trimmed -match "(\d+)%") {
                                        $script:ProgressLabel.Text = "处理中：$($Matches[1])%"
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if (((Get-Date) - $LastProgressTick).TotalSeconds -ge 5) {
                Write-Log "仍在处理中，请稍等..."
                $LastProgressTick = Get-Date
            }

            Start-Sleep -Milliseconds 250
            [System.Windows.Forms.Application]::DoEvents()
        }

        $Process.Refresh()
        $ExitCode = $Process.ExitCode
        if ($null -eq $ExitCode) {
            $ExitCode = 0
        }

        foreach ($Path in @($OutPath, $ErrPath)) {
            if (Test-Path -LiteralPath $Path) {
                $AlreadyRead = 0
                if ($ReadOffsets.ContainsKey($Path)) {
                    $AlreadyRead = $ReadOffsets[$Path]
                }
                $FileInfo = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
                if ($FileInfo -and $FileInfo.Length -gt $AlreadyRead) {
                    $Stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                    try {
                        $Stream.Seek($AlreadyRead, [System.IO.SeekOrigin]::Begin) | Out-Null
                        $Reader = New-Object System.IO.StreamReader($Stream, [System.Text.Encoding]::Default)
                        $Text = $Reader.ReadToEnd()
                    } finally {
                        if ($Reader) {
                            $Reader.Dispose()
                        } else {
                            $Stream.Dispose()
                        }
                    }

                    if ($Text) {
                        $CleanText = $Text -replace "`r", "`n"
                        $CleanText = $CleanText -replace "[`u001b]\[[0-9;]*[A-Za-z]", ""
                        foreach ($Line in ($CleanText -split "`n")) {
                            $Trimmed = $Line.Trim()
                            if ($Trimmed) {
                                Write-Log $Trimmed
                            }
                        }
                    }
                }
            }
        }

        return $ExitCode
    } finally {
        $script:CurrentProcess = $null
        Remove-Item -LiteralPath $OutPath, $ErrPath -Force -ErrorAction SilentlyContinue
    }
}

function Get-VideoExtensions {
    return @(".mp4", ".mov", ".mkv", ".avi", ".wmv", ".m4v", ".webm")
}

function Get-DefaultVideoPath {
    $InputDir = Join-Path $ProjectRoot "input_videos"
    if (-not (Test-Path -LiteralPath $InputDir)) {
        return ""
    }
    $Extensions = Get-VideoExtensions
    $Video = Get-ChildItem -LiteralPath $InputDir -File |
        Where-Object { $Extensions -contains $_.Extension.ToLowerInvariant() } |
        Sort-Object Name |
        Select-Object -First 1
    if ($Video) {
        return $Video.FullName
    }
    return ""
}

function Get-SingleOutputPath {
    $InputFile = Get-Item -LiteralPath $script:InputFileBox.Text
    return Join-Path $script:OutputDirBox.Text ("{0}_defaced{1}" -f $InputFile.BaseName, $InputFile.Extension)
}

function Get-OutputPathForVideo {
    param([System.IO.FileInfo]$Video)
    return Join-Path $script:OutputDirBox.Text ("{0}_defaced{1}" -f $Video.BaseName, $Video.Extension)
}

function Resolve-GuiOutputPath {
    param([string]$OutputPath)

    if (-not (Test-Path -LiteralPath $OutputPath)) {
        return [pscustomobject]@{ Path = $OutputPath; Skip = $false; Cancel = $false }
    }

    $Action = [string]$script:ExistingActionCombo.SelectedItem
    switch ($Action) {
        "跳过已处理" {
            return [pscustomobject]@{ Path = $OutputPath; Skip = $true; Cancel = $false }
        }
        "直接覆盖" {
            return [pscustomobject]@{ Path = $OutputPath; Skip = $false; Cancel = $false }
        }
        "自动改名" {
            $Decision = Resolve-DefaceOutputPath -OutputPath $OutputPath -ExistingAction "rename"
            return [pscustomobject]@{ Path = $Decision.Path; Skip = $false; Cancel = $false }
        }
        default {
            $Text = "输出文件已经存在：`r`n$OutputPath`r`n`r`n是 = 覆盖`r`n否 = 跳过`r`n取消 = 停止"
            $Choice = [System.Windows.Forms.MessageBox]::Show(
                $Text,
                "输出文件已存在",
                [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
            if ($Choice -eq [System.Windows.Forms.DialogResult]::Yes) {
                return [pscustomobject]@{ Path = $OutputPath; Skip = $false; Cancel = $false }
            }
            if ($Choice -eq [System.Windows.Forms.DialogResult]::No) {
                return [pscustomobject]@{ Path = $OutputPath; Skip = $true; Cancel = $false }
            }
            return [pscustomobject]@{ Path = $OutputPath; Skip = $false; Cancel = $true }
        }
    }
}

function Update-ModeControls {
    $SingleMode = $script:SingleRadio.Checked
    $script:InputFileBox.Enabled = $SingleMode
    $script:BrowseInputFileButton.Enabled = $SingleMode
    $script:InputDirBox.Enabled = -not $SingleMode
    $script:BrowseInputDirButton.Enabled = -not $SingleMode
}

function Update-ReplaceControls {
    $Mode = [string]$script:ReplaceCombo.SelectedItem
    $script:MosaicSizeBox.Enabled = ($Mode -eq "mosaic")
    $script:ReplaceImgBox.Enabled = ($Mode -eq "img")
    $script:BrowseReplaceImgButton.Enabled = ($Mode -eq "img")
}

function Apply-Preset {
    $Preset = [string]$script:PresetCombo.SelectedItem
    switch ($Preset) {
        "薄码（细颗粒）" {
            $script:ReplaceCombo.SelectedItem = "mosaic"
            $script:MosaicSizeBox.Value = 6
            $script:MaskScaleBox.Value = 1.15
            $script:ThreshBox.Value = 0.15
            $script:ScaleCombo.Text = "1280x720"
        }
        "标准马赛克" {
            $script:ReplaceCombo.SelectedItem = "mosaic"
            $script:MosaicSizeBox.Value = 20
            $script:MaskScaleBox.Value = 1.45
            $script:ThreshBox.Value = 0.15
            $script:ScaleCombo.Text = "1280x720"
        }
        "强遮挡" {
            $script:ReplaceCombo.SelectedItem = "mosaic"
            $script:MosaicSizeBox.Value = 36
            $script:MaskScaleBox.Value = 1.70
            $script:ThreshBox.Value = 0.12
            $script:ScaleCombo.Text = "1280x720"
        }
        "速度优先" {
            $script:ReplaceCombo.SelectedItem = "mosaic"
            $script:MosaicSizeBox.Value = 20
            $script:MaskScaleBox.Value = 1.35
            $script:ThreshBox.Value = 0.18
            $script:ScaleCombo.Text = "640x360"
        }
    }
    Update-ReplaceControls
    Update-PresetDescription
}

function Update-PresetDescription {
    $Preset = [string]$script:PresetCombo.SelectedItem
    switch ($Preset) {
        "薄码（细颗粒）" {
            $script:PresetDescriptionLabel.Text = "薄码：颗粒细、观感轻，但匿名强度较弱，务必抽帧复查。"
        }
        "标准马赛克" {
            $script:PresetDescriptionLabel.Text = "标准：默认推荐，遮挡范围和识别稳定性比较均衡。"
        }
        "强遮挡" {
            $script:PresetDescriptionLabel.Text = "强遮挡：更重的马赛克和更大遮罩，适合优先保护隐私。"
        }
        "速度优先" {
            $script:PresetDescriptionLabel.Text = "速度优先：降低推理分辨率，处理更快，但小脸更可能漏检。"
        }
        default {
            $script:PresetDescriptionLabel.Text = "自定义：手动调整所有参数。"
        }
    }
}

function Update-GpuStatus {
    try {
        $script:GpuStatus = Get-DefaceGpuStatus -ProjectRoot $ProjectRoot
    } catch {
        $script:GpuStatus = [pscustomobject]@{
            NvidiaAvailable = $false
            NvidiaName = ""
            OnnxRuntimeInstalled = $false
            Providers = @()
            ActiveProviders = @()
            CudaAvailable = $false
            CudaError = $_.Exception.Message
            NvidiaDllDirs = @()
            Error = $_.Exception.Message
        }
        Write-Log ("GPU 检测失败：" + $_.Exception.Message)
    }

    if ($script:GpuStatus.CudaAvailable) {
        $Name = $script:GpuStatus.NvidiaName
        if (-not $Name) {
            $Name = "NVIDIA GPU"
        }
        $script:GpuStatusLabel.Text = "可用：$Name，CUDA 后端已就绪"
        $script:GpuStatusLabel.ForeColor = [System.Drawing.Color]::DarkGreen
        $script:UseGpuCheck.Enabled = $true
        if (-not $script:GpuWasTouched) {
            $script:UseGpuCheck.Checked = $true
        }
        $script:InstallGpuButton.Enabled = $false
    } elseif ($script:GpuStatus.NvidiaAvailable -and -not $script:GpuStatus.OnnxRuntimeInstalled) {
        $script:GpuStatusLabel.Text = "检测到 NVIDIA 显卡，但还没安装 onnxruntime-gpu"
        $script:GpuStatusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
        $script:UseGpuCheck.Checked = $false
        $script:UseGpuCheck.Enabled = $false
        $script:InstallGpuButton.Enabled = $true
    } elseif ($script:GpuStatus.NvidiaAvailable) {
        $Providers = ($script:GpuStatus.Providers -join ", ")
        if (-not $Providers) {
            $Providers = "无"
        }
        if ($script:GpuStatus.CudaError) {
            $script:GpuStatusLabel.Text = "检测到 NVIDIA 显卡，但 CUDA 实测失败；请安装 GPU 组件"
        } else {
            $script:GpuStatusLabel.Text = "检测到 NVIDIA 显卡，但 CUDA Provider 不可用；当前：$Providers"
        }
        $script:GpuStatusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
        $script:UseGpuCheck.Checked = $false
        $script:UseGpuCheck.Enabled = $false
        $script:InstallGpuButton.Enabled = $true
    } else {
        $script:GpuStatusLabel.Text = "未检测到可用 NVIDIA GPU，将使用 CPU"
        $script:GpuStatusLabel.ForeColor = [System.Drawing.Color]::Firebrick
        $script:UseGpuCheck.Checked = $false
        $script:UseGpuCheck.Enabled = $false
        $script:InstallGpuButton.Enabled = $false
    }
}

function Update-EncoderStatus {
    $script:EncoderStatus = Get-DefaceEncoderStatus -ProjectRoot $ProjectRoot
    if ($script:EncoderStatus.H264Nvenc -or $script:EncoderStatus.HevcNvenc) {
        $script:EncoderStatusLabel.Text = "NVENC 可用"
        $script:EncoderStatusLabel.ForeColor = [System.Drawing.Color]::DarkGreen
    } elseif ($script:EncoderStatus.Error) {
        $script:EncoderStatusLabel.Text = "编码检测失败"
        $script:EncoderStatusLabel.ForeColor = [System.Drawing.Color]::Firebrick
    } else {
        $script:EncoderStatusLabel.Text = "NVENC 不可用"
        $script:EncoderStatusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
    }
}

function Get-CommonDefaceArgs {
    $Args = @(
        "-Thresh", (Format-UiNumber $script:ThreshBox.Value),
        "-MaskScale", (Format-UiNumber $script:MaskScaleBox.Value),
        "-Scale", $script:ScaleCombo.Text.Trim(),
        "-ReplaceWith", ([string]$script:ReplaceCombo.SelectedItem),
        "-MosaicSize", ([string][int]$script:MosaicSizeBox.Value),
        "-KeepAudio", ([string][bool]$script:KeepAudioCheck.Checked),
        "-KeepMetadata", ([string][bool]$script:KeepMetadataCheck.Checked),
        "-Boxes", ([string][bool]$script:BoxesCheck.Checked),
        "-DrawScores", ([string][bool]$script:DrawScoresCheck.Checked),
        "-Preview", ([string][bool]$script:PreviewCheck.Checked),
        "-Backend", ([string]$script:BackendCombo.SelectedItem),
        "-UseGpu", ([string][bool]$script:UseGpuCheck.Checked),
        "-Encoder", ([string]$script:EncoderCombo.SelectedItem)
    )
    if ($script:ReplaceImgBox.Text.Trim()) {
        $Args += @("-ReplaceImg", $script:ReplaceImgBox.Text.Trim())
    }
    if ($script:ExecutionProviderBox.Text.Trim()) {
        $Args += @("-ExecutionProvider", $script:ExecutionProviderBox.Text.Trim())
    }
    if ($script:FfmpegConfigBox.Text.Trim()) {
        $Args += @("-FfmpegConfig", $script:FfmpegConfigBox.Text.Trim())
    }
    return $Args
}

function Validate-Inputs {
    if ($script:ScaleCombo.Text.Trim() -notmatch "^\d+x\d+$") {
        Show-Warning "推理分辨率必须类似 1280x720。"
        return $false
    }
    if ($script:SingleRadio.Checked) {
        if (-not (Test-Path -LiteralPath $script:InputFileBox.Text)) {
            Show-Warning "请选择一个存在的视频文件。"
            return $false
        }
    } else {
        if (-not (Test-Path -LiteralPath $script:InputDirBox.Text)) {
            Show-Warning "请选择一个存在的输入文件夹。"
            return $false
        }
    }
    if (-not $script:OutputDirBox.Text.Trim()) {
        Show-Warning "请选择输出文件夹。"
        return $false
    }
    if (([string]$script:ReplaceCombo.SelectedItem) -eq "img" -and -not (Test-Path -LiteralPath $script:ReplaceImgBox.Text)) {
        Show-Warning "替换模式为 img 时，必须选择替换图片。"
        return $false
    }
    return $true
}

function Set-RunUiState {
    param([bool]$Running)

    $StartButton.Enabled = -not $Running
    $ReviewOnlyButton.Enabled = -not $Running
    $StopButton.Enabled = $Running
    $script:CancelRequested = $false
}

function Set-Progress {
    param(
        [int]$Value,
        [int]$Maximum,
        [string]$Text
    )

    if ($Maximum -lt 1) {
        $Maximum = 1
    }
    if ($Value -lt 0) {
        $Value = 0
    }
    if ($Value -gt $Maximum) {
        $Value = $Maximum
    }
    $script:ProgressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    $script:ProgressBar.Maximum = $Maximum
    $script:ProgressBar.Value = $Value
    $script:ProgressLabel.Text = $Text
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-SelectedVideos {
    if ($script:SingleRadio.Checked) {
        return @((Get-Item -LiteralPath $script:InputFileBox.Text))
    }

    $Extensions = Get-VideoExtensions
    return @(Get-ChildItem -LiteralPath $script:InputDirBox.Text -File |
        Where-Object { $Extensions -contains $_.Extension.ToLowerInvariant() } |
        Sort-Object Name)
}

function Confirm-ThinMosaicRisk {
    if ([string]$script:PresetCombo.SelectedItem -ne "薄码（细颗粒）") {
        return $true
    }

    $Choice = [System.Windows.Forms.MessageBox]::Show(
        "薄码遮挡更轻，可能无法完全匿名。建议保留自动抽帧复查。是否继续？",
        "薄码风险提示",
        [System.Windows.Forms.MessageBoxButtons]::OKCancel,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    return ($Choice -eq [System.Windows.Forms.DialogResult]::OK)
}

function Select-FolderForBox {
    param([System.Windows.Forms.TextBox]$Box)
    $Dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($Box.Text -and (Test-Path -LiteralPath $Box.Text)) {
        $Dialog.SelectedPath = $Box.Text
    }
    if ($Dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $Box.Text = $Dialog.SelectedPath
    }
}

function Get-GuiSettings {
    return [ordered]@{
        InputFile = $script:InputFileBox.Text
        InputDir = $script:InputDirBox.Text
        OutputDir = $script:OutputDirBox.Text
        ReviewDir = $script:ReviewDirBox.Text
        SingleMode = [bool]$script:SingleRadio.Checked
        Preset = [string]$script:PresetCombo.SelectedItem
        Thresh = [double]$script:ThreshBox.Value
        MaskScale = [double]$script:MaskScaleBox.Value
        Scale = $script:ScaleCombo.Text
        ReplaceWith = [string]$script:ReplaceCombo.SelectedItem
        MosaicSize = [int]$script:MosaicSizeBox.Value
        KeepAudio = [bool]$script:KeepAudioCheck.Checked
        KeepMetadata = [bool]$script:KeepMetadataCheck.Checked
        Boxes = [bool]$script:BoxesCheck.Checked
        DrawScores = [bool]$script:DrawScoresCheck.Checked
        Preview = [bool]$script:PreviewCheck.Checked
        Backend = [string]$script:BackendCombo.SelectedItem
        ExecutionProvider = $script:ExecutionProviderBox.Text
        Encoder = [string]$script:EncoderCombo.SelectedItem
        FfmpegConfig = $script:FfmpegConfigBox.Text
        ExistingAction = [string]$script:ExistingActionCombo.SelectedItem
        AutoReview = [bool]$script:AutoReviewCheck.Checked
        ReviewSeconds = [int]$script:ReviewSecondsBox.Value
        UseGpu = [bool]$script:UseGpuCheck.Checked
    }
}

function Save-GuiSettings {
    try {
        $Settings = Get-GuiSettings
        $Settings | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
        Write-Log "已保存本次参数。"
    } catch {
        Write-Log ("保存参数失败：" + $_.Exception.Message)
    }
}

function Set-ComboValue {
    param(
        [System.Windows.Forms.ComboBox]$Combo,
        [string]$Value
    )
    if (-not $Value) {
        return
    }
    if ($Combo.Items.Contains($Value)) {
        $Combo.SelectedItem = $Value
    } else {
        $Combo.Text = $Value
    }
}

function Load-GuiSettings {
    if (-not (Test-Path -LiteralPath $SettingsPath)) {
        return
    }

    try {
        $Settings = Get-Content -LiteralPath $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($Settings.InputFile) { $script:InputFileBox.Text = [string]$Settings.InputFile }
        if ($Settings.InputDir) { $script:InputDirBox.Text = [string]$Settings.InputDir }
        if ($Settings.OutputDir) { $script:OutputDirBox.Text = [string]$Settings.OutputDir }
        if ($Settings.ReviewDir) { $script:ReviewDirBox.Text = [string]$Settings.ReviewDir }
        if ($null -ne $Settings.SingleMode) {
            $script:SingleRadio.Checked = [bool]$Settings.SingleMode
            $script:BatchRadio.Checked = -not [bool]$Settings.SingleMode
        }
        Set-ComboValue $script:PresetCombo ([string]$Settings.Preset)
        if ($null -ne $Settings.Thresh) { $script:ThreshBox.Value = [decimal]$Settings.Thresh }
        if ($null -ne $Settings.MaskScale) { $script:MaskScaleBox.Value = [decimal]$Settings.MaskScale }
        if ($Settings.Scale) { $script:ScaleCombo.Text = [string]$Settings.Scale }
        Set-ComboValue $script:ReplaceCombo ([string]$Settings.ReplaceWith)
        if ($null -ne $Settings.MosaicSize) { $script:MosaicSizeBox.Value = [decimal]$Settings.MosaicSize }
        if ($null -ne $Settings.KeepAudio) { $script:KeepAudioCheck.Checked = [bool]$Settings.KeepAudio }
        if ($null -ne $Settings.KeepMetadata) { $script:KeepMetadataCheck.Checked = [bool]$Settings.KeepMetadata }
        if ($null -ne $Settings.Boxes) { $script:BoxesCheck.Checked = [bool]$Settings.Boxes }
        if ($null -ne $Settings.DrawScores) { $script:DrawScoresCheck.Checked = [bool]$Settings.DrawScores }
        if ($null -ne $Settings.Preview) { $script:PreviewCheck.Checked = [bool]$Settings.Preview }
        Set-ComboValue $script:BackendCombo ([string]$Settings.Backend)
        if ($Settings.ExecutionProvider) { $script:ExecutionProviderBox.Text = [string]$Settings.ExecutionProvider }
        Set-ComboValue $script:EncoderCombo ([string]$Settings.Encoder)
        if ($Settings.FfmpegConfig) { $script:FfmpegConfigBox.Text = [string]$Settings.FfmpegConfig }
        Set-ComboValue $script:ExistingActionCombo ([string]$Settings.ExistingAction)
        if ($null -ne $Settings.AutoReview) { $script:AutoReviewCheck.Checked = [bool]$Settings.AutoReview }
        if ($null -ne $Settings.ReviewSeconds) { $script:ReviewSecondsBox.Value = [decimal]$Settings.ReviewSeconds }
        if ($null -ne $Settings.UseGpu) {
            $script:GpuWasTouched = $true
            $script:UseGpuCheck.Checked = [bool]$Settings.UseGpu
        }
        Write-Log "已加载上次参数。"
    } catch {
        Write-Log ("加载参数失败：" + $_.Exception.Message)
    }
}

$Form = New-Object System.Windows.Forms.Form
$Form.Text = "本地视频人脸打码工具"
$Form.StartPosition = "CenterScreen"
$Form.Size = New-Object System.Drawing.Size(1000, 920)
$Form.MinimumSize = New-Object System.Drawing.Size(1000, 920)
$Form.Font = New-UiFont 9

$Title = New-Object System.Windows.Forms.Label
$Title.Text = "本地视频人脸打码工具"
$Title.Font = New-UiFont 15 ([System.Drawing.FontStyle]::Bold)
$Title.Location = New-Object System.Drawing.Point(16, 12)
$Title.Size = New-Object System.Drawing.Size(420, 34)
$Form.Controls.Add($Title)

$Tip = New-Object System.Windows.Forms.Label
$Tip.Text = "薄码就是更细的马赛克颗粒；遮挡更弱，处理后建议抽帧检查。"
$Tip.Location = New-Object System.Drawing.Point(440, 18)
$Tip.Size = New-Object System.Drawing.Size(520, 24)
$Tip.ForeColor = [System.Drawing.Color]::DimGray
$Form.Controls.Add($Tip)

$GpuGroup = New-Object System.Windows.Forms.GroupBox
$GpuGroup.Text = "GPU 加速"
$GpuGroup.Location = New-Object System.Drawing.Point(16, 54)
$GpuGroup.Size = New-Object System.Drawing.Size(950, 88)
$Form.Controls.Add($GpuGroup)

Add-Label $GpuGroup "GPU 状态：" 16 24 82 24 | Out-Null
$script:GpuStatusLabel = Add-Label $GpuGroup "正在检测..." 98 24 610 24
$script:UseGpuCheck = Add-CheckBox $GpuGroup "使用 GPU 加速" 18 54 150 $false
$script:UseGpuCheck.Enabled = $false
$RefreshGpuButton = Add-Button $GpuGroup "重新检测" 720 22 92 28
$script:InstallGpuButton = Add-Button $GpuGroup "安装 GPU 组件" 822 22 120 28

$PathGroup = New-Object System.Windows.Forms.GroupBox
$PathGroup.Text = "处理任务"
$PathGroup.Location = New-Object System.Drawing.Point(16, 152)
$PathGroup.Size = New-Object System.Drawing.Size(950, 170)
$Form.Controls.Add($PathGroup)

$script:SingleRadio = New-Object System.Windows.Forms.RadioButton
$script:SingleRadio.Text = "处理单个视频"
$script:SingleRadio.Checked = $true
$script:SingleRadio.Location = New-Object System.Drawing.Point(18, 26)
$script:SingleRadio.Size = New-Object System.Drawing.Size(130, 24)
$PathGroup.Controls.Add($script:SingleRadio)

$script:BatchRadio = New-Object System.Windows.Forms.RadioButton
$script:BatchRadio.Text = "批量处理文件夹"
$script:BatchRadio.Location = New-Object System.Drawing.Point(160, 26)
$script:BatchRadio.Size = New-Object System.Drawing.Size(150, 24)
$PathGroup.Controls.Add($script:BatchRadio)

Add-Label $PathGroup "输出已存在：" 330 26 92 24 | Out-Null
$script:ExistingActionCombo = Add-Combo $PathGroup @("询问", "跳过已处理", "直接覆盖", "自动改名") "跳过已处理" 424 26 126 $false

Add-Label $PathGroup "单个视频：" 18 60 82 24 | Out-Null
$script:InputFileBox = Add-TextBox $PathGroup (Get-DefaultVideoPath) 104 60 690 24
$script:BrowseInputFileButton = Add-Button $PathGroup "浏览..." 808 58 88 28

Add-Label $PathGroup "输入文件夹：" 18 94 82 24 | Out-Null
$script:InputDirBox = Add-TextBox $PathGroup (Join-Path $ProjectRoot "input_videos") 104 94 690 24
$script:BrowseInputDirButton = Add-Button $PathGroup "浏览..." 808 92 88 28

Add-Label $PathGroup "输出文件夹：" 18 128 82 24 | Out-Null
$script:OutputDirBox = Add-TextBox $PathGroup (Join-Path $ProjectRoot "output_videos") 104 128 690 24
$BrowseOutputDirButton = Add-Button $PathGroup "浏览..." 808 126 88 28

$ParamGroup = New-Object System.Windows.Forms.GroupBox
$ParamGroup.Text = "打码参数"
$ParamGroup.Location = New-Object System.Drawing.Point(16, 332)
$ParamGroup.Size = New-Object System.Drawing.Size(950, 286)
$Form.Controls.Add($ParamGroup)

Add-Label $ParamGroup "预设：" 18 28 70 24 | Out-Null
$script:PresetCombo = Add-Combo $ParamGroup @("自定义", "薄码（细颗粒）", "标准马赛克", "强遮挡", "速度优先") "标准马赛克" 86 28 150 $false

Add-Label $ParamGroup "检测阈值：" 260 28 82 24 | Out-Null
$script:ThreshBox = Add-Number $ParamGroup 0.15 0 1 0.01 2 344 28 82

Add-Label $ParamGroup "遮罩放大：" 450 28 82 24 | Out-Null
$script:MaskScaleBox = Add-Number $ParamGroup 1.45 0.1 10 0.05 2 536 28 82

Add-Label $ParamGroup "推理分辨率：" 642 28 92 24 | Out-Null
$script:ScaleCombo = Add-Combo $ParamGroup @("1280x720", "960x540", "640x360", "1920x1080") "1280x720" 738 28 126 $true

Add-Label $ParamGroup "替换模式：" 18 66 82 24 | Out-Null
$script:ReplaceCombo = Add-Combo $ParamGroup @("mosaic", "blur", "solid", "none", "img") "mosaic" 104 66 120 $false

Add-Label $ParamGroup "马赛克块：" 250 66 82 24 | Out-Null
$script:MosaicSizeBox = Add-Number $ParamGroup 20 1 200 1 0 336 66 82

$script:KeepAudioCheck = Add-CheckBox $ParamGroup "保留原视频音频" 450 66 140 $true
$script:KeepMetadataCheck = Add-CheckBox $ParamGroup "保留元数据" 604 66 110 $false
$script:BoxesCheck = Add-CheckBox $ParamGroup "方框遮罩" 724 66 96 $false
$script:DrawScoresCheck = Add-CheckBox $ParamGroup "显示检测分数" 822 66 120 $false

$script:PreviewCheck = Add-CheckBox $ParamGroup "实时预览" 18 104 96 $false

Add-Label $ParamGroup "替换图片：" 132 104 82 24 | Out-Null
$script:ReplaceImgBox = Add-TextBox $ParamGroup "" 218 104 576 24
$script:BrowseReplaceImgButton = Add-Button $ParamGroup "浏览..." 808 102 88 28

Add-Label $ParamGroup "后端：" 18 142 70 24 | Out-Null
$script:BackendCombo = Add-Combo $ParamGroup @("auto", "onnxrt", "opencv") "auto" 86 142 120 $false

Add-Label $ParamGroup "Provider：" 230 142 82 24 | Out-Null
$script:ExecutionProviderBox = Add-TextBox $ParamGroup "" 316 142 220 24

Add-Label $ParamGroup "视频编码：" 558 142 82 24 | Out-Null
$script:EncoderCombo = Add-Combo $ParamGroup @("libx264", "h264_nvenc", "hevc_nvenc", "custom") "libx264" 642 142 118 $false
$script:EncoderStatusLabel = Add-Label $ParamGroup "检测中..." 774 142 120 24

Add-Label $ParamGroup "FFmpeg JSON：" 18 178 100 24 | Out-Null
$script:FfmpegConfigBox = Add-TextBox $ParamGroup "" 122 178 772 24

$ThinHint = New-Object System.Windows.Forms.Label
$ThinHint.Text = "薄码建议：马赛克块 6-10，遮罩 1.10-1.25；想更稳就增大遮罩或改回标准。"
$ThinHint.Location = New-Object System.Drawing.Point(18, 214)
$ThinHint.Size = New-Object System.Drawing.Size(860, 24)
$ThinHint.ForeColor = [System.Drawing.Color]::DimGray
$ParamGroup.Controls.Add($ThinHint)

$script:PresetDescriptionLabel = New-Object System.Windows.Forms.Label
$script:PresetDescriptionLabel.Text = ""
$script:PresetDescriptionLabel.Location = New-Object System.Drawing.Point(18, 242)
$script:PresetDescriptionLabel.Size = New-Object System.Drawing.Size(860, 24)
$script:PresetDescriptionLabel.ForeColor = [System.Drawing.Color]::DimGray
$ParamGroup.Controls.Add($script:PresetDescriptionLabel)

$ReviewGroup = New-Object System.Windows.Forms.GroupBox
$ReviewGroup.Text = "复查与执行"
$ReviewGroup.Location = New-Object System.Drawing.Point(16, 628)
$ReviewGroup.Size = New-Object System.Drawing.Size(950, 126)
$Form.Controls.Add($ReviewGroup)

$script:AutoReviewCheck = Add-CheckBox $ReviewGroup "处理完成后自动抽帧复查" 18 28 210 $true
Add-Label $ReviewGroup "每隔秒数：" 244 28 82 24 | Out-Null
$script:ReviewSecondsBox = Add-Number $ReviewGroup 5 1 3600 1 0 330 28 78
Add-Label $ReviewGroup "复查目录：" 430 28 82 24 | Out-Null
$script:ReviewDirBox = Add-TextBox $ReviewGroup (Join-Path $ProjectRoot "review_frames") 510 28 284 24
$BrowseReviewDirButton = Add-Button $ReviewGroup "浏览..." 808 26 88 28

$StartButton = Add-Button $ReviewGroup "开始处理" 18 68 110 32
$StopButton = Add-Button $ReviewGroup "停止处理" 140 68 110 32
$StopButton.Enabled = $false
$ReviewOnlyButton = Add-Button $ReviewGroup "只抽帧复查" 262 68 110 32
$OpenOutputButton = Add-Button $ReviewGroup "打开输出目录" 384 68 118 32
$OpenReviewButton = Add-Button $ReviewGroup "打开复查目录" 514 68 118 32
$ExitButton = Add-Button $ReviewGroup "退出" 644 68 90 32

$script:ProgressBar = New-Object System.Windows.Forms.ProgressBar
$script:ProgressBar.Location = New-Object System.Drawing.Point(746, 70)
$script:ProgressBar.Size = New-Object System.Drawing.Size(184, 18)
$script:ProgressBar.Minimum = 0
$script:ProgressBar.Maximum = 100
$ReviewGroup.Controls.Add($script:ProgressBar)

$script:ProgressLabel = New-Object System.Windows.Forms.Label
$script:ProgressLabel.Text = "就绪"
$script:ProgressLabel.Location = New-Object System.Drawing.Point(746, 94)
$script:ProgressLabel.Size = New-Object System.Drawing.Size(184, 22)
$script:ProgressLabel.ForeColor = [System.Drawing.Color]::DimGray
$ReviewGroup.Controls.Add($script:ProgressLabel)

$LogGroup = New-Object System.Windows.Forms.GroupBox
$LogGroup.Text = "运行日志"
$LogGroup.Location = New-Object System.Drawing.Point(16, 764)
$LogGroup.Size = New-Object System.Drawing.Size(950, 110)
$Form.Controls.Add($LogGroup)

$script:LogBox = New-Object System.Windows.Forms.TextBox
$script:LogBox.Multiline = $true
$script:LogBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$script:LogBox.ReadOnly = $true
$script:LogBox.Location = New-Object System.Drawing.Point(12, 22)
$script:LogBox.Size = New-Object System.Drawing.Size(926, 78)
$LogGroup.Controls.Add($script:LogBox)

$script:GpuWasTouched = $false
$script:UseGpuCheck.Add_CheckedChanged({ $script:GpuWasTouched = $true })
$script:SingleRadio.Add_CheckedChanged({ Update-ModeControls })
$script:BatchRadio.Add_CheckedChanged({ Update-ModeControls })
$script:ReplaceCombo.Add_SelectedIndexChanged({ Update-ReplaceControls })
$script:PresetCombo.Add_SelectedIndexChanged({ Apply-Preset })

$script:BrowseInputFileButton.Add_Click({
    $Dialog = New-Object System.Windows.Forms.OpenFileDialog
    $Dialog.Filter = "视频文件|*.mp4;*.mov;*.mkv;*.avi;*.wmv;*.m4v;*.webm|所有文件|*.*"
    if ($script:InputDirBox.Text -and (Test-Path -LiteralPath $script:InputDirBox.Text)) {
        $Dialog.InitialDirectory = $script:InputDirBox.Text
    }
    if ($Dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:InputFileBox.Text = $Dialog.FileName
    }
})

$script:BrowseReplaceImgButton.Add_Click({
    $Dialog = New-Object System.Windows.Forms.OpenFileDialog
    $Dialog.Filter = "图片文件|*.png;*.jpg;*.jpeg;*.bmp;*.webp|所有文件|*.*"
    if ($Dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:ReplaceImgBox.Text = $Dialog.FileName
    }
})

$script:BrowseInputDirButton.Add_Click({ Select-FolderForBox $script:InputDirBox })
$BrowseOutputDirButton.Add_Click({ Select-FolderForBox $script:OutputDirBox })
$BrowseReviewDirButton.Add_Click({ Select-FolderForBox $script:ReviewDirBox })

$RefreshGpuButton.Add_Click({
    $RefreshGpuButton.Enabled = $false
    try {
        Write-Log "重新检测 GPU 状态。"
        $script:GpuStatusLabel.Text = "正在检测 GPU，请稍等..."
        [System.Windows.Forms.Application]::DoEvents()
        Update-GpuStatus
        if ($script:GpuStatus.Error) {
            Write-Log ("GPU 检测信息：" + $script:GpuStatus.Error)
        }
        if ($script:GpuStatus.CudaError) {
            Write-Log ("CUDA 检测信息：" + $script:GpuStatus.CudaError)
        }
    } catch {
        Write-Log ("重新检测失败：" + $_.Exception.Message)
        Show-Error $_.Exception.Message "GPU 检测失败"
    } finally {
        $RefreshGpuButton.Enabled = $true
    }
})

$StopButton.Add_Click({
    $script:CancelRequested = $true
    Write-Log "正在请求停止..."
    if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
        Stop-ProcessTree -ProcessId $script:CurrentProcess.Id
    }
})

$script:InstallGpuButton.Add_Click({
    if (-not (Test-Path -LiteralPath $PythonExe)) {
        Show-Error "没有找到 .venv 中的 Python。"
        return
    }
    $script:InstallGpuButton.Enabled = $false
    $StartButton.Enabled = $false
    try {
        Write-Log "开始安装 GPU 推理组件，首次安装可能需要几分钟。"
        $ExitCode = Invoke-GuiCommand $PythonExe @(
            "-m", "pip", "install",
            "onnxruntime-gpu",
            "onnx",
            "nvidia-cudnn-cu12",
            "nvidia-cuda-runtime-cu12",
            "nvidia-cublas-cu12"
        )
        if ($ExitCode -eq 0) {
            Write-Log "GPU 组件安装完成，正在重新检测。"
        } else {
            Write-Log "GPU 组件安装失败，退出码：$ExitCode"
        }
        try {
            Update-GpuStatus
        } catch {
            Write-Log ("安装后重新检测失败：" + $_.Exception.Message)
            Show-Error $_.Exception.Message "GPU 检测失败"
        }
    } catch {
        Write-Log ("安装失败：" + $_.Exception.Message)
        Show-Error $_.Exception.Message
    } finally {
        $StartButton.Enabled = $true
        if (-not $script:GpuStatus.CudaAvailable) {
            $script:InstallGpuButton.Enabled = $true
        }
    }
})

$StartButton.Add_Click({
    try {
        if (-not (Validate-Inputs)) {
            return
        }
        if (-not (Confirm-ThinMosaicRisk)) {
            return
        }

        New-Item -ItemType Directory -Force -Path $script:OutputDirBox.Text, $script:ReviewDirBox.Text | Out-Null
        Save-GuiSettings
        Set-RunUiState $true

        if ($script:UseGpuCheck.Checked) {
            Update-GpuStatus
            if (-not $script:GpuStatus.CudaAvailable) {
                Show-Info "当前 GPU 后端不可用，已自动改用 CPU。"
                $script:UseGpuCheck.Checked = $false
            }
        }

        Update-EncoderStatus
        $SelectedEncoder = [string]$script:EncoderCombo.SelectedItem
        if ($SelectedEncoder -eq "h264_nvenc" -and -not $script:EncoderStatus.H264Nvenc) {
            Show-Warning "当前 ffmpeg 不支持 h264_nvenc，请改用 libx264 或 custom。"
            return
        }
        if ($SelectedEncoder -eq "hevc_nvenc" -and -not $script:EncoderStatus.HevcNvenc) {
            Show-Warning "当前 ffmpeg 不支持 hevc_nvenc，请改用 libx264 或 custom。"
            return
        }

        $Videos = @(Get-SelectedVideos)
        if (-not $Videos -or $Videos.Count -eq 0) {
            Show-Warning "没有找到要处理的视频。"
            return
        }

        $CommonArgs = Get-CommonDefaceArgs
        $CompletedOutputs = New-Object System.Collections.Generic.List[string]
        $DoneCount = 0
        Set-Progress 0 $Videos.Count "准备处理"

        foreach ($Video in $Videos) {
            if ($script:CancelRequested) {
                Write-Log "用户已停止处理。"
                break
            }

            $DefaultOutputPath = Get-OutputPathForVideo $Video
            $OutputDecision = Resolve-GuiOutputPath $DefaultOutputPath
            if ($OutputDecision.Cancel) {
                $script:CancelRequested = $true
                Write-Log "用户取消了任务。"
                break
            }
            if ($OutputDecision.Skip) {
                $DoneCount++
                Write-Log "跳过已处理：$($Video.Name)"
                Set-Progress $DoneCount $Videos.Count ("已跳过 $DoneCount / $($Videos.Count)")
                continue
            }

            $Args = @(
                "-NoProfile",
                "-ExecutionPolicy", "Bypass",
                "-File", $OneScript,
                "-InputPath", $Video.FullName,
                "-OutputPath", $OutputDecision.Path,
                "-ExistingAction", "overwrite"
            ) + $CommonArgs
            Write-Log "开始处理：$($Video.Name)"
            Set-Progress $DoneCount $Videos.Count ("处理中：$($Video.Name)")
            $ExitCode = Invoke-GuiCommand "powershell.exe" $Args
            if ($ExitCode -eq 130 -or $script:CancelRequested) {
                Write-Log "处理已停止。"
                break
            }
            if ($ExitCode -ne 0) {
                Write-Log "处理失败，退出码：$ExitCode"
                return
            }
            $CompletedOutputs.Add([string]$OutputDecision.Path) | Out-Null
            $DoneCount++
            Write-Log "处理完成：$($OutputDecision.Path)"
            Set-Progress $DoneCount $Videos.Count ("已完成 $DoneCount / $($Videos.Count)")
        }

        if (-not $script:CancelRequested -and $script:AutoReviewCheck.Checked -and $CompletedOutputs.Count -gt 0) {
            Write-Log "开始抽帧复查并生成 HTML 报告。"
            Set-Progress $Videos.Count $Videos.Count "抽帧复查中"

            if ($CompletedOutputs.Count -eq 1) {
                $ReviewArgs = @(
                    "-NoProfile",
                    "-ExecutionPolicy", "Bypass",
                    "-File", $ReviewScript,
                    "-VideoPath", $CompletedOutputs[0],
                    "-ReviewDir", $script:ReviewDirBox.Text,
                    "-EverySeconds", ([string][int]$script:ReviewSecondsBox.Value),
                    "-GenerateHtml", "True"
                )
                Invoke-GuiCommand "powershell.exe" $ReviewArgs | Out-Null
            } else {
                $ReviewArgs = @(
                    "-NoProfile",
                    "-ExecutionPolicy", "Bypass",
                    "-File", $ReviewScript,
                    "-VideoDir", $script:OutputDirBox.Text,
                    "-ReviewDir", $script:ReviewDirBox.Text,
                    "-EverySeconds", ([string][int]$script:ReviewSecondsBox.Value),
                    "-GenerateHtml", "True"
                )
                Invoke-GuiCommand "powershell.exe" $ReviewArgs | Out-Null
            }
        }

        if ($script:CancelRequested) {
            Set-Progress $DoneCount $Videos.Count "已停止"
            Show-Info "处理已停止。"
        } else {
            Set-Progress $Videos.Count $Videos.Count "全部完成"
            Write-Log "全部完成。"
            Show-Info "处理完成。"
        }
    } catch {
        Write-Log ("发生错误：" + $_.Exception.Message)
        Show-Error $_.Exception.Message
    } finally {
        Set-RunUiState $false
        Save-GuiSettings
    }
})

$ReviewOnlyButton.Add_Click({
    New-Item -ItemType Directory -Force -Path $script:ReviewDirBox.Text | Out-Null
    Set-RunUiState $true
    try {
        if ($script:SingleRadio.Checked -and (Test-Path -LiteralPath $script:InputFileBox.Text)) {
            $OutputPath = Get-SingleOutputPath
            if (-not (Test-Path -LiteralPath $OutputPath)) {
                Show-Warning "还没有找到单个视频对应的输出文件。"
                return
            }
            $Args = @(
                "-NoProfile",
                "-ExecutionPolicy", "Bypass",
                "-File", $ReviewScript,
                "-VideoPath", $OutputPath,
                "-ReviewDir", $script:ReviewDirBox.Text,
                "-EverySeconds", ([string][int]$script:ReviewSecondsBox.Value),
                "-GenerateHtml", "True"
            )
        } else {
            $Args = @(
                "-NoProfile",
                "-ExecutionPolicy", "Bypass",
                "-File", $ReviewScript,
                "-VideoDir", $script:OutputDirBox.Text,
                "-ReviewDir", $script:ReviewDirBox.Text,
                "-EverySeconds", ([string][int]$script:ReviewSecondsBox.Value),
                "-GenerateHtml", "True"
            )
        }
        Set-Progress 0 1 "抽帧复查中"
        Invoke-GuiCommand "powershell.exe" $Args | Out-Null
        if ($script:CancelRequested) {
            Set-Progress 0 1 "已停止"
            Write-Log "抽帧复查已停止。"
        } else {
            Set-Progress 1 1 "复查完成"
            Write-Log "抽帧复查完成。"
        }
    } catch {
        Write-Log ("发生错误：" + $_.Exception.Message)
        Show-Error $_.Exception.Message
    } finally {
        Set-RunUiState $false
    }
})

$OpenOutputButton.Add_Click({
    New-Item -ItemType Directory -Force -Path $script:OutputDirBox.Text | Out-Null
    Start-Process explorer.exe $script:OutputDirBox.Text
})

$OpenReviewButton.Add_Click({
    New-Item -ItemType Directory -Force -Path $script:ReviewDirBox.Text | Out-Null
    Start-Process explorer.exe $script:ReviewDirBox.Text
})

$ExitButton.Add_Click({ $Form.Close() })

$Form.Add_FormClosing({
    if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
        $script:CancelRequested = $true
        Stop-ProcessTree -ProcessId $script:CurrentProcess.Id
    }
    Save-GuiSettings
})

$script:CancelRequested = $false
$script:CurrentProcess = $null
$script:GpuWasTouched = $false
Load-GuiSettings
Update-ModeControls
Update-ReplaceControls
try {
    Update-GpuStatus
} catch {
    Write-Log ("启动时 GPU 检测失败：" + $_.Exception.Message)
}
Update-EncoderStatus
Update-PresetDescription
Write-Log "准备就绪。"

if ($SelfTest) {
    Write-Output "GUI self-test OK"
    return
}

[void]$Form.ShowDialog()
