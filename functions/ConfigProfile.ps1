# =========================================================
# ConfigProfile.ps1 — export/import selected tweak profiles
# so a chosen set of tweaks/apps can be replicated on another
# machine without re-clicking every checkbox.
# =========================================================

function Export-ToolProfile {
    param(
        [Parameter(Mandatory)][string[]]$SelectedTweakIds,
        [Parameter(Mandatory)][string[]]$SelectedAppIds,
        [Parameter(Mandatory)][string]$OutFile
    )
    $profile = [ordered]@{
        SchemaVersion = 1
        CreatedUtc    = (Get-Date).ToUniversalTime().ToString("o")
        Tweaks        = $SelectedTweakIds
        Apps          = $SelectedAppIds
    }
    try {
        $profile | ConvertTo-Json -Depth 4 | Set-Content -Path $OutFile -Encoding UTF8
        Write-ToolLog -Message "Profile exported to $OutFile" -Level "INFO"
        return $true
    }
    catch {
        Write-ToolLog -Message "Failed to export profile: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Import-ToolProfile {
    param([Parameter(Mandatory)][string]$InFile)
    try {
        $data = Get-Content -Path $InFile -Raw | ConvertFrom-Json
        Write-ToolLog -Message "Profile imported from $InFile ($($data.Tweaks.Count) tweaks, $($data.Apps.Count) apps)" -Level "INFO"
        return $data
    }
    catch {
        Write-ToolLog -Message "Failed to import profile: $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}
