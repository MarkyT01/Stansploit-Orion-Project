<#
    WinTool — Windows Optimization & Debloat Utility
    ---------------------------------------------------
    Entry point. Loads functions + JSON config, builds a WPF GUI,
    and wires up checkbox-driven tweak/app actions.

    Usage:
        powershell -ExecutionPolicy Bypass -File main.ps1
#>

param(
    [switch]$SkipElevationCheck
)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- Load function modules -------------------------------------------------
. (Join-Path $root "functions\Core.ps1")
. (Join-Path $root "functions\Tweaks.ps1")
. (Join-Path $root "functions\AppInstaller.ps1")
. (Join-Path $root "functions\ConfigProfile.ps1")

if (-not $SkipElevationCheck) { Assert-Admin }
Initialize-ToolLog | Out-Null

# --- Load JSON config --------------------------------------------------------
$tweaksData = Get-Content (Join-Path $root "tweaks.json") -Raw | ConvertFrom-Json
$appsData   = Get-Content (Join-Path $root "apps.json") -Raw | ConvertFrom-Json

# Flatten tweaks into a lookup by Id for quick access when applying/undoing
$tweakLookup = @{}
foreach ($category in $tweaksData.PSObject.Properties.Name) {
    foreach ($tweak in $tweaksData.$category) {
        $tweakLookup[$tweak.Id] = $tweak
    }
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore

# --- XAML UI -----------------------------------------------------------------
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Stansploit - Orion Project"
        Height="720" Width="980"
        WindowStartupLocation="CenterScreen">
    <Window.Background>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
            <GradientStop Color="#B2D5E5" Offset="0"/>
            <GradientStop Color="#020202" Offset="1"/>
        </LinearGradientBrush>
    </Window.Background>
    <Window.Resources>
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#e0e0e0"/>
            <Setter Property="Margin" Value="4,6,4,6"/>
            <Setter Property="FontSize" Value="13"/>
        </Style>
        <Style TargetType="TabItem">
            <Setter Property="Foreground" Value="Black"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
        </Style>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#0a7cff"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Padding" Value="12,6,12,6"/>
            <Setter Property="Margin" Value="6"/>
            <Setter Property="BorderThickness" Value="0"/>
        </Style>
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="#e0e0e0"/>
        </Style>
        <Style TargetType="GroupBox">
            <Setter Property="Foreground" Value="#e0e0e0"/>
            <Setter Property="Margin" Value="6"/>
        </Style>
        <Style TargetType="TabControl">
            <Setter Property="Background" Value="Black"/>
        </Style>
        <Style TargetType="TabPanel">
            <Setter Property="Background" Value="Black"/>
        </Style>
    </Window.Resources>
    <DockPanel Margin="10">
        <Border DockPanel.Dock="Top" Background="Black" Padding="12">
            <StackPanel Orientation="Vertical">
                <TextBlock Text="Stansploit" FontSize="22" FontWeight="Bold" Foreground="#E100FF"/>
                <TextBlock Text="Orion Project" FontSize="11" Foreground="#888888" Margin="1,2,0,0"/>
            </StackPanel>
        </Border>
        <Border DockPanel.Dock="Bottom" Background="Black" Padding="8">
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                <Button Name="BtnExportProfile" Content="Export Profile"/>
                <Button Name="BtnImportProfile" Content="Import Profile"/>
                <Button Name="BtnRestorePoint" Content="Create Restore Point"/>
                <Button Name="BtnApplySelected" Content="Apply Selected" Background="#2ea043"/>
            </StackPanel>
        </Border>
        <TabControl Name="MainTabs" Margin="8" Background="Black" BorderBrush="#3c3c3c">
            <TabItem Header="Tweaks" Name="TabTweaks"/>
            <TabItem Header="Debloater" Name="TabDebloat"/>
            <TabItem Header="Installer" Name="TabApps"/>
            <TabItem Header="Log" Name="TabLog"/>
        </TabControl>
    </DockPanel>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# --- Helper: build a single tweak's GroupBox (checkbox + description) -----
function New-TweakGroupBox {
    param([Parameter(Mandatory)][psobject]$Tweak)

    $group = New-Object System.Windows.Controls.GroupBox
    $group.Header = $Tweak.Name
    $group.Foreground = "#e0e0e0"
    $group.BorderBrush = "#3c3c3c"
    $group.Background = "Black"

    $inner = New-Object System.Windows.Controls.StackPanel
    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Content = "Enable this tweak"
    $cb.Tag = $Tweak.Id
    $cb.Name = "cb_$($Tweak.Id)"

    $desc = New-Object System.Windows.Controls.TextBlock
    $desc.Text = $Tweak.Description
    $desc.TextWrapping = "Wrap"
    $desc.Opacity = 0.75
    $desc.Margin = "24,0,4,6"
    $desc.FontSize = 11

    if ($Tweak.RequiresConfirmation) {
        $warn = New-Object System.Windows.Controls.TextBlock
        $warn.Text = "⚠ Requires confirmation before applying"
        $warn.Foreground = "#e5c07b"
        $warn.Margin = "24,0,4,6"
        $warn.FontSize = 11
        $inner.Children.Add($cb) | Out-Null
        $inner.Children.Add($desc) | Out-Null
        $inner.Children.Add($warn) | Out-Null
    }
    else {
        $inner.Children.Add($cb) | Out-Null
        $inner.Children.Add($desc) | Out-Null
    }

    $group.Content = $inner
    $global:AllTweakCheckboxes += $cb
    return $group
}

# --- Helper: single-category tab content (used by Debloater tab) ----------
function New-TweakTabContent {
    param([Parameter(Mandatory)][psobject[]]$Tweaks)

    $scroll = New-Object System.Windows.Controls.ScrollViewer
    $scroll.Background = "Black"
    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Margin = "10"
    $panel.Background = "Black"

    foreach ($tweak in $Tweaks) {
        $panel.Children.Add((New-TweakGroupBox -Tweak $tweak)) | Out-Null
    }

    $scroll.Content = $panel
    return $scroll
}

# --- Helper: multi-category tab content, with a header per category -------
# (used by the combined "Tweaks" tab: Performance, Privacy, Explorer, Updates)
function New-CombinedTweakTabContent {
    param([Parameter(Mandatory)][hashtable]$CategoryMap)

    $scroll = New-Object System.Windows.Controls.ScrollViewer
    $scroll.Background = "Black"
    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Margin = "10"
    $panel.Background = "Black"

    foreach ($categoryName in $CategoryMap.Keys) {
        $catHeader = New-Object System.Windows.Controls.TextBlock
        $catHeader.Text = $categoryName
        $catHeader.FontWeight = "Bold"
        $catHeader.FontSize = 15
        $catHeader.Foreground = "#E100FF"
        $catHeader.Margin = "4,14,4,4"
        $panel.Children.Add($catHeader) | Out-Null

        foreach ($tweak in $CategoryMap[$categoryName]) {
            $panel.Children.Add((New-TweakGroupBox -Tweak $tweak)) | Out-Null
        }
    }

    $scroll.Content = $panel
    return $scroll
}

$global:AllTweakCheckboxes = @()

$combinedCategories = [ordered]@{
    "Performance" = $tweaksData.Performance
    "Privacy"     = $tweaksData.Privacy
    "Explorer"    = $tweaksData.Explorer
    "Updates"     = $tweaksData.Updates
}
$window.FindName("TabTweaks").Content  = New-CombinedTweakTabContent -CategoryMap $combinedCategories
$window.FindName("TabDebloat").Content = New-TweakTabContent -Tweaks $tweaksData.Debloat

# --- App Installer tab -------------------------------------------------------
$appsScroll = New-Object System.Windows.Controls.ScrollViewer
$appsScroll.Background = "Black"
$appsPanel = New-Object System.Windows.Controls.StackPanel
$appsPanel.Margin = "10"
$appsPanel.Background = "Black"
$global:AllAppCheckboxes = @()

foreach ($category in $appsData.PSObject.Properties.Name) {
    $catHeader = New-Object System.Windows.Controls.TextBlock
    $catHeader.Text = $category
    $catHeader.FontWeight = "Bold"
    $catHeader.FontSize = 14
    $catHeader.Margin = "4,10,4,4"
    $appsPanel.Children.Add($catHeader) | Out-Null

    foreach ($app in $appsData.$category) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Content = $app.Name
        $cb.Tag = $app
        $appsPanel.Children.Add($cb) | Out-Null
        $global:AllAppCheckboxes += $cb
    }
}
$appsScroll.Content = $appsPanel
$window.FindName("TabApps").Content = $appsScroll

$installBtn = New-Object System.Windows.Controls.Button
$installBtn.Content = "Install Selected Apps"
$installBtn.Background = "#2ea043"
$installBtn.Foreground = "White"
$installBtn.Margin = "6,16,6,6"
$installBtn.HorizontalAlignment = "Left"
$installBtn.Padding = "12,6,12,6"
$installBtn.Add_Click({
    $selected = $global:AllAppCheckboxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag }
    if ($selected.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Select at least one app first.", "WinTool") | Out-Null
        return
    }
    $results = Install-ToolAppBatch -Apps $selected
    $summary = ($results.GetEnumerator() | ForEach-Object { "$($_.Key): $(if ($_.Value) {'OK'} else {'FAILED'})" }) -join "`n"
    [System.Windows.MessageBox]::Show($summary, "Install Results") | Out-Null
})
$appsPanel.Children.Insert(0, $installBtn)

# --- Log tab -----------------------------------------------------------------
$logBox = New-Object System.Windows.Controls.TextBox
$logBox.IsReadOnly = $true
$logBox.TextWrapping = "Wrap"
$logBox.VerticalScrollBarVisibility = "Auto"
$logBox.Background = "#111111"
$logBox.Foreground = "#00ff88"
$logBox.FontFamily = "Consolas"
$logBox.Text = "Log file: $global:ToolLogFile`n`nActions will appear here after you click 'Apply Selected'."
$window.FindName("TabLog").Content = $logBox

# --- Button wiring -------------------------------------------------------------
$window.FindName("BtnRestorePoint").Add_Click({
    $ok = New-ToolRestorePoint -Description "WinTool - Manual Checkpoint"
    $msg = if ($ok) { "Restore point created." } else { "Could not create a restore point (see log)." }
    [System.Windows.MessageBox]::Show($msg, "WinTool") | Out-Null
})

$window.FindName("BtnApplySelected").Add_Click({
    $selectedCheckboxes = $global:AllTweakCheckboxes | Where-Object { $_.IsChecked }
    if ($selectedCheckboxes.Count -eq 0) {
        [System.Windows.MessageBox]::Show("No tweaks selected.", "WinTool") | Out-Null
        return
    }

    $needsConfirm = $selectedCheckboxes | Where-Object { $tweakLookup[$_.Tag].RequiresConfirmation }
    if ($needsConfirm.Count -gt 0) {
        $names = ($needsConfirm | ForEach-Object { $tweakLookup[$_.Tag].Name }) -join "`n - "
        $result = [System.Windows.MessageBox]::Show(
            "The following tweaks require extra confirmation because they can be risky:`n - $names`n`nContinue?",
            "Confirm Risky Tweaks",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning)
        if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }
    }

    New-ToolRestorePoint -Description "WinTool - Before Applying Tweaks" | Out-Null

    $failCount = 0
    foreach ($cb in $selectedCheckboxes) {
        $tweak = $tweakLookup[$cb.Tag]
        $ok = Invoke-Tweak -Tweak $tweak -Direction "Apply"
        if (-not $ok) { $failCount++ }
    }

    $logBox.Text = Get-Content $global:ToolLogFile -Raw
    $msg = if ($failCount -eq 0) { "All selected tweaks applied successfully." } else { "$failCount tweak(s) had errors. Check the Log tab." }
    [System.Windows.MessageBox]::Show($msg, "WinTool") | Out-Null
})

$window.FindName("BtnExportProfile").Add_Click({
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = "WinTool Profile (*.json)|*.json"
    $dlg.FileName = "wintool-profile.json"
    if ($dlg.ShowDialog()) {
        $tweakIds = ($global:AllTweakCheckboxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
        $appIds   = ($global:AllAppCheckboxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag.Id })
        Export-ToolProfile -SelectedTweakIds $tweakIds -SelectedAppIds $appIds -OutFile $dlg.FileName
        [System.Windows.MessageBox]::Show("Profile exported.", "WinTool") | Out-Null
    }
})

$window.FindName("BtnImportProfile").Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = "WinTool Profile (*.json)|*.json"
    if ($dlg.ShowDialog()) {
        $profileData = Import-ToolProfile -InFile $dlg.FileName
        if ($null -eq $profileData) { return }
        foreach ($cb in $global:AllTweakCheckboxes) {
            $cb.IsChecked = $profileData.Tweaks -contains $cb.Tag
        }
        foreach ($cb in $global:AllAppCheckboxes) {
            $cb.IsChecked = $profileData.Apps -contains $cb.Tag.Id
        }
        [System.Windows.MessageBox]::Show("Profile imported and applied to checkboxes.", "WinTool") | Out-Null
    }
})

# --- Show window ---------------------------------------------------------------
$window.ShowDialog() | Out-Null
