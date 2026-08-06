# =========================================================
# Tweaks.ps1 — generic engine that applies/undoes tweak actions
# defined in tweaks.json. One action type = one small function,
# so adding a new action type later is a one-function change.
# =========================================================

function Set-RegistryAction {
    param([Parameter(Mandatory)][psobject]$Action)
    try {
        if (-not (Test-Path $Action.Path)) {
            New-Item -Path $Action.Path -Force | Out-Null
        }
        $valueType = if ($Action.ValueType) { $Action.ValueType } else { "DWord" }
        Set-ItemProperty -Path $Action.Path -Name $Action.Name -Value $Action.Value -Type $valueType -Force -ErrorAction Stop
        Write-ToolLog -Message "Registry set: $($Action.Path) [$($Action.Name)] = $($Action.Value)" -Level "ACTION"
        return $true
    }
    catch {
        Write-ToolLog -Message "Registry action failed on $($Action.Path): $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Set-ServiceAction {
    param([Parameter(Mandatory)][psobject]$Action)
    try {
        switch ($Action.Action) {
            "Disable"   { Set-Service -Name $Action.Name -StartupType Disabled -ErrorAction Stop; Stop-Service -Name $Action.Name -Force -ErrorAction SilentlyContinue }
            "Enable"    { Set-Service -Name $Action.Name -StartupType Automatic -ErrorAction Stop; Start-Service -Name $Action.Name -ErrorAction SilentlyContinue }
            "Manual"    { Set-Service -Name $Action.Name -StartupType Manual -ErrorAction Stop }
            "Automatic" { Set-Service -Name $Action.Name -StartupType Automatic -ErrorAction Stop }
        }
        Write-ToolLog -Message "Service '$($Action.Name)' set to $($Action.Action)" -Level "ACTION"
        return $true
    }
    catch {
        Write-ToolLog -Message "Service action failed on $($Action.Name): $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Invoke-CommandAction {
    param([Parameter(Mandatory)][psobject]$Action)
    try {
        Invoke-Expression $Action.Command
        Write-ToolLog -Message "Command executed: $($Action.Command)" -Level "ACTION"
        return $true
    }
    catch {
        Write-ToolLog -Message "Command failed [$($Action.Command)]: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Remove-AppxAction {
    param([Parameter(Mandatory)][psobject]$Action)
    $allOk = $true
    foreach ($pkg in $Action.Packages) {
        try {
            Get-AppxPackage -Name $pkg -AllUsers -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction Stop
            Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                Where-Object { $_.PackageName -like "$pkg*" } |
                ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue }
            Write-ToolLog -Message "Removed Appx package: $pkg" -Level "ACTION"
        }
        catch {
            Write-ToolLog -Message "Appx removal failed for $pkg`: $($_.Exception.Message)" -Level "ERROR"
            $allOk = $false
        }
    }
    return $allOk
}

function Invoke-TweakAction {
    <#
        Dispatches a single action object (from tweaks.json) to the
        correct handler based on its "Type" field.
    #>
    param([Parameter(Mandatory)][psobject]$Action)
    switch ($Action.Type) {
        "Registry"   { return Set-RegistryAction -Action $Action }
        "Service"    { return Set-ServiceAction -Action $Action }
        "Command"    { return Invoke-CommandAction -Action $Action }
        "AppxRemove" { return Remove-AppxAction -Action $Action }
        "Note"       { Write-ToolLog -Message "Note: $($Action.Message)" -Level "WARN"; return $true }
        default      { Write-ToolLog -Message "Unknown action type: $($Action.Type)" -Level "ERROR"; return $false }
    }
}

function Invoke-Tweak {
    <#
        Applies every action under a tweak's "Apply" list.
        Stops on first failure within that tweak but continues
        the overall run (caller loops over multiple tweaks).
    #>
    param(
        [Parameter(Mandatory)][psobject]$Tweak,
        [ValidateSet("Apply","Undo")][string]$Direction = "Apply"
    )
    Write-ToolLog -Message "Applying tweak: $($Tweak.Name)" -Level "INFO"
    $actions = if ($Direction -eq "Apply") { $Tweak.Apply } else { $Tweak.Undo }
    $success = $true
    foreach ($action in $actions) {
        $ok = Invoke-TweakAction -Action $action
        if (-not $ok) { $success = $false }
    }
    return $success
}
