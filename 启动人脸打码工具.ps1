$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$GuiScript = Join-Path $ScriptDir "scripts\deface_gui.ps1"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File $GuiScript
