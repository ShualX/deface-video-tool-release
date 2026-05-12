param(
    [string]$VideoPath,
    [string]$VideoDir,
    [string]$ReviewDir,
    [int]$EverySeconds = 5,
    [object]$GenerateHtml = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
. (Join-Path $ScriptDir "deface_common.ps1")

if (-not $VideoDir) {
    $VideoDir = Join-Path $ProjectRoot "output_videos"
}
if (-not $ReviewDir) {
    $ReviewDir = Join-Path $ProjectRoot "review_frames"
}

New-Item -ItemType Directory -Force -Path $VideoDir, $ReviewDir | Out-Null

$GenerateHtmlValue = ConvertTo-DefaceBool $GenerateHtml $true
$FfmpegExe = Get-DefaceFfmpegExe -ProjectRoot $ProjectRoot

if ($VideoPath) {
    $Videos = @((Get-Item -LiteralPath $VideoPath))
} else {
    $Extensions = @(".mp4", ".mov", ".mkv", ".avi", ".wmv", ".m4v", ".webm")
    $Videos = Get-ChildItem -LiteralPath $VideoDir -File |
        Where-Object { $Extensions -contains $_.Extension.ToLowerInvariant() } |
        Sort-Object Name
}

if (-not $Videos) {
    Write-Host "No videos found in $VideoDir"
    exit 0
}

foreach ($Video in $Videos) {
    $VideoReviewDir = Join-Path $ReviewDir $Video.BaseName
    New-Item -ItemType Directory -Force -Path $VideoReviewDir | Out-Null
    $FramePattern = Join-Path $VideoReviewDir "frame_%06d.jpg"

    Write-Host "Extracting one frame every $EverySeconds seconds from $($Video.Name)"
    & $FfmpegExe -hide_banner -y -i $Video.FullName -vf "fps=1/$EverySeconds" -q:v 2 $FramePattern
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to extract review frames from $($Video.FullName)"
    }
}

Write-Host ""
Write-Host "Done. Review frames are in $ReviewDir"

if ($GenerateHtmlValue) {
    $ReportPath = Join-Path $ReviewDir "review.html"
    $GeneratedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Html = New-Object System.Collections.Generic.List[string]
    $Html.Add("<!doctype html>")
    $Html.Add("<html lang=""zh-CN"">")
    $Html.Add("<head>")
    $Html.Add("<meta charset=""utf-8"">")
    $Html.Add("<title>打码复查报告</title>")
    $Html.Add("<style>")
    $Html.Add("body{font-family:'Microsoft YaHei UI',Arial,sans-serif;margin:24px;background:#f6f7f9;color:#222}h1{font-size:24px;margin:0 0 8px}h2{font-size:18px;margin:28px 0 12px}.meta{color:#666;margin-bottom:24px}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:14px}.frame{background:#fff;border:1px solid #ddd;border-radius:6px;padding:8px}.frame img{width:100%;height:auto;display:block}.name{font-size:12px;color:#555;margin-top:6px;word-break:break-all}")
    $Html.Add("</style>")
    $Html.Add("</head>")
    $Html.Add("<body>")
    $Html.Add("<h1>打码复查报告</h1>")
    $Html.Add("<div class=""meta"">生成时间：$GeneratedAt；抽帧间隔：每 $EverySeconds 秒 1 张</div>")

    foreach ($Video in $Videos) {
        $VideoReviewDir = Join-Path $ReviewDir $Video.BaseName
        $Title = [System.Net.WebUtility]::HtmlEncode($Video.BaseName)
        $Html.Add("<h2>$Title</h2>")
        $Html.Add("<div class=""grid"">")
        $Frames = Get-ChildItem -LiteralPath $VideoReviewDir -File -Filter "*.jpg" | Sort-Object Name
        foreach ($Frame in $Frames) {
            $Relative = Join-Path $Video.BaseName $Frame.Name
            $Relative = $Relative.Replace("\", "/")
            $FrameName = [System.Net.WebUtility]::HtmlEncode($Frame.Name)
            $Src = [System.Net.WebUtility]::HtmlEncode($Relative)
            $Html.Add("<div class=""frame""><img src=""$Src"" alt=""$FrameName""><div class=""name"">$FrameName</div></div>")
        }
        $Html.Add("</div>")
    }

    $Html.Add("</body>")
    $Html.Add("</html>")
    Set-Content -LiteralPath $ReportPath -Value $Html -Encoding UTF8
    Write-Host "HTML review report: $ReportPath"
}
