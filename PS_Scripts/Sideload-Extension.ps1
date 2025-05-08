# Sideload-Extension.ps1
# Main script to perform the browser extension sideloading.
# VERSION WITH LONG PATH CHECK AT THE BEGINNING & STRING FIXES

# --- Configuration ---
$Global:LogFile = "$env:TEMP\sideload_extension_log.txt" 
$ExtensionName = "Site Performance Analyzer" 
$RemoteExtensionSourcePath_FromOrchestrator = "PLACEHOLDER_FOR_EXTENSION_PATH"
$ExtensionId = "aabbccddeeffgghhiijjkkllmmnnoopp" 
$ChromeUserDataPath = "$env:LOCALAPPDATA\Google\Chrome\User Data"
$EdgeUserDataPath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"

# --- Functions ---
function Write-Log {
    param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] $Message"
    Write-Host $LogEntry 
    Add-Content -Path $Global:LogFile -Value $LogEntry -ErrorAction SilentlyContinue
}

# --- Main Logic for Sideload-Extension.ps1 ---
Clear-Content -Path $Global:LogFile -ErrorAction SilentlyContinue 
Write-Log "Sideload-Extension.ps1 script entered."
Write-Log "Received initial source path from orchestrator: $RemoteExtensionSourcePath_FromOrchestrator"

# Resolve the potentially short path received from the orchestrator to its long form FIRST.
$ResolvedSourcePath = $null
if ($RemoteExtensionSourcePath_FromOrchestrator -ne "PLACEHOLDER_FOR_EXTENSION_PATH") {
    try {
        $item = Get-Item -LiteralPath $RemoteExtensionSourcePath_FromOrchestrator -Force -ErrorAction Stop
        if ($item) {
            $ResolvedSourcePath = $item.FullName
            Write-Log "Resolved source path to: $ResolvedSourcePath"
        } else {
             Write-Log "WARN: Get-Item returned null for initial path: $RemoteExtensionSourcePath_FromOrchestrator"
             $ResolvedSourcePath = $RemoteExtensionSourcePath_FromOrchestrator
        }
    } catch {
        Write-Log "WARN: Could not resolve long path for initial path '$RemoteExtensionSourcePath_FromOrchestrator': $($_.Exception.Message). Will attempt to use original."
        $ResolvedSourcePath = $RemoteExtensionSourcePath_FromOrchestrator
    }
}

# Critical check using the RESOLVED path
if ($RemoteExtensionSourcePath_FromOrchestrator -eq "PLACEHOLDER_FOR_EXTENSION_PATH" -or -not $ResolvedSourcePath -or -not (Test-Path -LiteralPath $ResolvedSourcePath)) {
    if ($RemoteExtensionSourcePath_FromOrchestrator -eq "PLACEHOLDER_FOR_EXTENSION_PATH") {
         Write-Log "CRITICAL ERROR: Exiting because RemoteExtensionSourcePath still contains the placeholder!"
    }
    if (-not $ResolvedSourcePath) {
         Write-Log "CRITICAL ERROR: Exiting because resolved source path is null."
    }
    if ($ResolvedSourcePath -and -not (Test-Path -LiteralPath $ResolvedSourcePath)) {
         Write-Log "CRITICAL ERROR: Exiting because resolved path does not exist according to Test-Path: $ResolvedSourcePath"
    }
    Write-Log "CRITICAL ERROR: Overall check failed for source path. Original: '$RemoteExtensionSourcePath_FromOrchestrator', Resolved Attempt: '$ResolvedSourcePath'"
    exit 1 
}

Write-Log "Initial path check passed. Using source path: $ResolvedSourcePath"
$LocalExtensionSourcePath = $ResolvedSourcePath # Rename for clarity

# --- Function Definition ---
function Sideload-ExtensionToBrowserFromLocal {
    param(
        [string]$BrowserUserDataPath,
        [string]$BrowserName,
        [string]$CurrentLocalExtensionSourcePath 
    )
    Write-Log "Attempting to sideload extension to $BrowserName from $CurrentLocalExtensionSourcePath"
    if (-not (Test-Path $BrowserUserDataPath)) {
        Write-Log "$BrowserName User Data path not found: $BrowserUserDataPath"; return $false
    }
    if (-not (Test-Path $CurrentLocalExtensionSourcePath)) {
        Write-Log "Local extension source path check failed within function: $CurrentLocalExtensionSourcePath"; return $false
    }

    $ProfileNames = @("Default", "Profile 1", "Profile 2", "Profile 3")
    $ProfilePathFound = $false
    $ProfilePath = $null 

    foreach ($ProfileName in $ProfileNames) {
        $CurrentProfilePath = Join-Path -Path $BrowserUserDataPath -ChildPath $ProfileName
        if (Test-Path $CurrentProfilePath) {
            Write-Log "Found profile path: $CurrentProfilePath"
            $ProfilePath = $CurrentProfilePath
            $ProfilePathFound = $true
            break
        }
    }

    if (-not $ProfilePathFound) {
        # <<< FIX 1: Use ${} for variable followed by colon >>>
        Write-Log "${BrowserName}: No common profile paths (Default, Profile 1-3) found under $BrowserUserDataPath."
        return $false
    }

    $ExtensionsDir = Join-Path -Path $ProfilePath -ChildPath "Extensions"
    $TargetExtensionPath = Join-Path -Path $ExtensionsDir -ChildPath $ExtensionId
    $VersionFolder = Join-Path -Path $TargetExtensionPath -ChildPath "1.1_0" 

    Write-Log "Target extension installation path: $VersionFolder"

    try {
        if (Test-Path $VersionFolder) {
            Write-Log "Extension folder $VersionFolder already exists. Removing to ensure fresh copy."
            Remove-Item -Path $VersionFolder -Recurse -Force -ErrorAction Stop
        }
        New-Item -Path $VersionFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
        Copy-Item -Path "$CurrentLocalExtensionSourcePath\*" -Destination $VersionFolder -Recurse -Force -ErrorAction Stop
        Write-Log "Extension files copied to $VersionFolder"
    }
    catch { Write-Log "ERROR copying extension files: $($_.Exception.Message)"; return $false }

    $PreferencesFile = Join-Path -Path $ProfilePath -ChildPath "Preferences"
    
    if (-not (Test-Path $PreferencesFile)) {
        Write-Log "Preferences file not found: $PreferencesFile"; return $false
    }
    Write-Log "Attempting to modify Preferences file: $PreferencesFile (Browser should ideally be closed)"

    try {
        $PrefsContent = Get-Content -Path $PreferencesFile -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction SilentlyContinue
        if (-not $PrefsContent) { Write-Log "Could not parse Preferences JSON from $PreferencesFile."; return $false }

        if (-not $PrefsContent.extensions) { $PrefsContent | Add-Member -MemberType NoteProperty -Name "extensions" -Value (New-Object PSObject) -Force }
        if (-not $PrefsContent.extensions.settings) { $PrefsContent.extensions | Add-Member -MemberType NoteProperty -Name "settings" -Value (New-Object PSObject) -Force }

        if ($PrefsContent.extensions.settings.PSObject.Properties[$ExtensionId]) {
            $PrefsContent.extensions.settings.PSObject.Properties.Remove($ExtensionId)
            Write-Log "Removed existing preferences for $ExtensionId"
        }
        
        $EscapedTargetExtensionPath = $TargetExtensionPath.Replace('\', '\\') 
        
        $ExtensionSettingsEntry = @{
            path = $EscapedTargetExtensionPath
            manifest = @{ 
                name = $ExtensionName
                version = "1.1" 
            }
            state = 1 
            location = 4 
            was_installed_by_default = $false
            was_installed_by_oem = $false
            install_time = ([long](Get-Date (Get-Date).ToUniversalTime() -UFormat %s) * 1000).ToString() 
        }
        
        $PrefsContent.extensions.settings | Add-Member -MemberType NoteProperty -Name $ExtensionId -Value $ExtensionSettingsEntry -Force
        Write-Log "Added new settings for $ExtensionId to in-memory preferences."

        $PrefsContent | ConvertTo-Json -Depth 100 -Compress | Set-Content -Path $PreferencesFile -Force -Encoding UTF8 -NoNewline -ErrorAction Stop
        Write-Log "Preferences file updated for $BrowserName."
        
        return $true
    }
    # <<< FIX 2: Use ${} for variable followed by colon >>>
    catch { Write-Log "ERROR modifying Preferences file for ${BrowserName}: $($_.Exception.Message)"; return $false }
}

# --- Continue Main Logic ---
$ChromeSideloaded = $false
$EdgeSideloaded = $false

# Attempt for Chrome
if (Test-Path $ChromeUserDataPath) {
    Write-Log "Attempting Chrome sideload..."
    $ChromeSideloaded = Sideload-ExtensionToBrowserFromLocal -BrowserUserDataPath $ChromeUserDataPath -BrowserName "Google Chrome" -CurrentLocalExtensionSourcePath $LocalExtensionSourcePath
    if ($ChromeSideloaded) { Write-Log "Chrome sideload attempt finished successfully (check browser)." } else { Write-Log "Chrome sideload attempt failed or partially failed."}
} else { Write-Log "Google Chrome User Data path not found."}

# Attempt for Edge
if (Test-Path $EdgeUserDataPath) {
    Write-Log "Attempting Edge sideload..."
    $EdgeSideloaded = Sideload-ExtensionToBrowserFromLocal -BrowserUserDataPath $EdgeUserDataPath -BrowserName "Microsoft Edge" -CurrentLocalExtensionSourcePath $LocalExtensionSourcePath
    if ($EdgeSideloaded) { Write-Log "Edge sideload attempt finished successfully (check browser)." } else { Write-Log "Edge sideload attempt failed or partially failed."}
} else { Write-Log "Microsoft Edge User Data path not found."}

# Final Exit Code Logic
if ($ChromeSideloaded -or $EdgeSideloaded) {
    Write-Log "Sideload-Extension.ps1 Finished. One or more browsers attempted. Browser(s) may need a restart."
    exit 0 
} else {
    Write-Log "Sideload-Extension.ps1 Finished. No browsers were successfully targeted or paths not found, or initial path check failed."
    exit 1 
}
