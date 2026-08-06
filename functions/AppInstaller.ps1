# =========================================================
# AppInstaller.ps1 — winget-based batch install/uninstall
# =========================================================

function Test-WingetAvailable {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    return [bool]$winget
}

function Install-ToolApp {
    param([Parameter(Mandatory)][psobject]$App)
    try {
        Write-ToolLog -Message "Installing $($App.Name) ($($App.WingetId))..." -Level "ACTION"
        $proc = Start-Process winget -ArgumentList "install --id $($App.WingetId) -e --accept-source-agreements --accept-package-agreements -h" -Wait -PassThru -NoNewWindow
        if ($proc.ExitCode -eq 0) {
            Write-ToolLog -Message "$($App.Name) installed successfully." -Level "INFO"
            return $true
        }
        else {
            Write-ToolLog -Message "$($App.Name) install exited with code $($proc.ExitCode)." -Level "WARN"
            return $false
        }
    }
    catch {
        Write-ToolLog -Message "Failed to install $($App.Name): $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Uninstall-ToolApp {
    param([Parameter(Mandatory)][psobject]$App)
    try {
        Write-ToolLog -Message "Uninstalling $($App.Name) ($($App.WingetId))..." -Level "ACTION"
        $proc = Start-Process winget -ArgumentList "uninstall --id $($App.WingetId) -e -h" -Wait -PassThru -NoNewWindow
        if ($proc.ExitCode -eq 0) {
            Write-ToolLog -Message "$($App.Name) uninstalled successfully." -Level "INFO"
            return $true
        }
        else {
            Write-ToolLog -Message "$($App.Name) uninstall exited with code $($proc.ExitCode)." -Level "WARN"
            return $false
        }
    }
    catch {
        Write-ToolLog -Message "Failed to uninstall $($App.Name): $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Install-ToolAppBatch {
    <#
        Installs a list of app objects sequentially, returning a
        hashtable of Name -> success bool for the UI to report on.
    #>
    param([Parameter(Mandatory)][psobject[]]$Apps)
    if (-not (Test-WingetAvailable)) {
        Write-ToolLog -Message "winget is not available on this system." -Level "ERROR"
        return @{}
    }
    $results = @{}
    foreach ($app in $Apps) {
        $results[$app.Name] = Install-ToolApp -App $app
    }
    return $results
}
