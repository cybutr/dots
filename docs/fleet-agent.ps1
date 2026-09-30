[CmdletBinding()]
param(
    [switch]$Setup,
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Once,
    [string]$HubUrl = "http://basecamp:8780",
    [string]$Device = "windows",
    [int]$IntervalSec = 30
)

$ErrorActionPreference = "Stop"
$ConfDir = Join-Path $env:LOCALAPPDATA "fleet-agent"
$TokenFile = Join-Path $ConfDir "token.xml"
$ConfFile = Join-Path $ConfDir "config.json"
$TaskName = "FleetAgent"

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class FleetNative {
    [StructLayout(LayoutKind.Sequential)]
    struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    public static uint IdleMs() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
        if (!GetLastInputInfo(ref lii)) return 0;
        return unchecked((uint)Environment.TickCount - lii.dwTime);
    }
    public static uint ForegroundPid() {
        IntPtr h = GetForegroundWindow();
        if (h == IntPtr.Zero) return 0;
        uint pid;
        GetWindowThreadProcessId(h, out pid);
        return pid;
    }
}
"@

function Save-Config {
    New-Item -ItemType Directory -Force -Path $ConfDir | Out-Null
    $sec = Read-Host -AsSecureString "Paste the fleet token for device '$Device'"
    $sec | Export-Clixml -Path $TokenFile
    @{ hubUrl = $HubUrl; device = $Device; intervalSec = $IntervalSec } | ConvertTo-Json | Set-Content -Path $ConfFile -Encoding UTF8
    Write-Host "Saved token (DPAPI, current user only) to $TokenFile and config to $ConfFile"
}

function Get-Config {
    if (-not (Test-Path $TokenFile) -or -not (Test-Path $ConfFile)) {
        throw "Not configured. Run: powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Setup"
    }
    $cfg = Get-Content -Raw -Path $ConfFile | ConvertFrom-Json
    $sec = Import-Clixml -Path $TokenFile
    $tok = [System.Net.NetworkCredential]::new("", $sec).Password
    [pscustomobject]@{ HubUrl = $cfg.hubUrl.TrimEnd("/"); Device = $cfg.device; IntervalSec = [int]$cfg.intervalSec; Token = $tok }
}

function Get-Gpu {
    $smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if (-not $smi) { return $null }
    try {
        $line = & $smi.Source --query-gpu=name,utilization.gpu,temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>$null | Select-Object -First 1
        if (-not $line) { return $null }
        $p = $line -split ",\s*"
        [ordered]@{ name = $p[0]; util_pct = [int]$p[1]; temp_c = [int]$p[2]; mem_used_mb = [int]$p[3]; mem_total_mb = [int]$p[4] }
    } catch { $null }
}

function Get-Status {
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
    $totalKb = [double]$os.TotalVisibleMemorySize
    $freeKb = [double]$os.FreePhysicalMemory
    $disks = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
        [ordered]@{
            drive    = $_.DeviceID
            total_gb = [math]::Round($_.Size / 1GB, 1)
            free_gb  = [math]::Round($_.FreeSpace / 1GB, 1)
            used_pct = if ($_.Size) { [math]::Round(100 * (1 - $_.FreeSpace / $_.Size), 1) } else { 0 }
        }
    })
    $fg = $null
    $fgPid = [FleetNative]::ForegroundPid()
    if ($fgPid -gt 0) { $fg = (Get-Process -Id $fgPid -ErrorAction SilentlyContinue).ProcessName }
    [ordered]@{
        host         = $env:COMPUTERNAME
        os           = "$($os.Caption) $($os.Version)"
        cpu_pct      = [math]::Round([double]$cpu, 1)
        ram_total_gb = [math]::Round($totalKb / 1MB, 1)
        ram_used_pct = [math]::Round(100 * (1 - $freeKb / $totalKb), 1)
        disks        = $disks
        uptime_s     = [int]((Get-Date) - $os.LastBootUpTime).TotalSeconds
        idle_s       = [int]([FleetNative]::IdleMs() / 1000)
        foreground   = $fg
        gpu          = Get-Gpu
        agent_ts     = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    }
}

function Send-Status($cfg) {
    $body = Get-Status | ConvertTo-Json -Depth 4 -Compress
    Invoke-RestMethod -Method Post -Uri "$($cfg.HubUrl)/ingest/$($cfg.Device)" `
        -Headers @{ Authorization = "Bearer $($cfg.Token)" } `
        -ContentType "application/json; charset=utf-8" -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 10
}

if ($Setup) { Save-Config; return }

if ($Uninstall) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Removed scheduled task $TaskName"
    return
}

if ($Install) {
    $script = $PSCommandPath
    $action = New-ScheduledTaskAction -Execute "conhost.exe" -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$script`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew `
        -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
        -Description "Push-only status report to the fleet hub over Tailscale. Accepts no commands." -Force | Out-Null
    Start-ScheduledTask -TaskName $TaskName
    Write-Host "Registered and started scheduled task $TaskName"
    return
}

$cfg = Get-Config

if ($Once) {
    Get-Status | ConvertTo-Json -Depth 4
    Send-Status $cfg
    return
}

while ($true) {
    try { Send-Status $cfg | Out-Null } catch { }
    Start-Sleep -Seconds $cfg.IntervalSec
}
