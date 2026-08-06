# =========================================================
# Core.ps1 — elevation check, restore point, logging
# =========================================================

function Test-IsAdmin {
    <#
        Returns $true if the current process is running elevated.
    #>
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Admin {
    <#
        Relaunches the script elevated if it is not already running as admin,
        then exits the current (non-elevated) process.
    #>
    if (-not (Test-IsAdmin)) {
        $scriptPath = $PSCommandPath
        if (-not $scriptPath) { $scriptPath = $MyInvocation.MyCommand.Path }
        Write-Host "Not running as Administrator. Relaunching elevated..." -ForegroundColor Yellow
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
        exit
    }
}

function New-ToolRestorePoint {
    <#
        Creates a System Restore point before any tweaks are applied.
        Silently continues if System Restore is disabled or throttled
        (Windows only allows one checkpoint per 24h by default outside of driver installs).
    #>
    param(
        [string]$Description = "WinTool - Before Optimization"
    )
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description $Description -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-ToolLog -Message "System Restore point created: '$Description'" -Level "INFO"
        return $true
    }
    catch {
        Write-ToolLog -Message "Could not create restore point: $($_.Exception.Message)" -Level "WARN"
        return $false
    }
}

function Initialize-ToolLog {
    param(
        [string]$LogPath = "$env:USERPROFILE\Documents\WinTool-Logs"
    )
    if (-not (Test-Path $LogPath)) {
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
    }
    $global:ToolLogFile = Join-Path $LogPath ("WinTool_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
    Write-ToolLog -Message "=== WinTool session started ===" -Level "INFO"
    return $global:ToolLogFile
}

function Write-ToolLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("INFO","WARN","ERROR","ACTION")][string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    if ($global:ToolLogFile) {
        Add-Content -Path $global:ToolLogFile -Value $line -ErrorAction SilentlyContinue
    }
    switch ($Level) {
        "ERROR" { Write-Host $line -ForegroundColor Red }
        "WARN"  { Write-Host $line -ForegroundColor Yellow }
        "ACTION"{ Write-Host $line -ForegroundColor Cyan }
        default { Write-Host $line -ForegroundColor Gray }
    }
}
