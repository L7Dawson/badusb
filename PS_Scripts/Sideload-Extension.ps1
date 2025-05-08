# Sideload-Extension.ps1
# Main script to perform the browser extension sideloading.
# VERSION WITH ENHANCED PATH RESOLUTION & DEBUG LOGGING

# --- Configuration ---
$Global:LogFile = "$env:TEMP\sideload_extension_log.txt"
$ExtensionName = "Site Performance Analyzer" # Must match the "name" in manifest.json

# This placeholder value is expected to be replaced by the orchestrator script
# with the actual path (which might be a short 8.3 path initially).
$RemoteExtensionSourcePath_FromOrchestrator = "PLACEHOLDER_FOR_EXTENSION_PATH"

$ExtensionId = "aabbccddeeffgghhiijjkkllmmnnoopp" # Example - keep consistent
$ChromeUserDataPath = "$env:LOCALAPPDATA\Google\Chrome\User Data"
$EdgeUserDataPath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"

# --- Functions ---
function Write-Log {
    param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] $Message"
    Write-Host $LogEntry # For immediate feedback if window is visible
    Add-Content -Path $Global:LogFile -Value $LogEntry -ErrorAction SilentlyContinue
}

# --- Main Logic for Sideload-Extension.ps1 ---
Clear-Content -Path $Global:LogFile -ErrorAction SilentlyContinue # Clear log at start
Write-Log "Sideload-Extension.ps1 script entered."
Write-Log "Received initial source path from orchestrator: $RemoteExtensionSourcePath_FromOrchestrator"

# --- BEGIN REVISED PATH RESOLUTION SECTION ---
$ResolvedSourcePath = $null
$PathResolutionError = $null # Variable to store specific error

if ($RemoteExtensionSourcePath_FromOrchestrator -ne "PLACEHOLDER_FOR_EXTENSION_PATH") {
    Write-Log "Attempting to resolve path: $RemoteExtensionSourcePath_FromOrchestrator"
    try {
        # Use Get-Item, capture errors explicitly using SilentlyContinue and checking $Error
        $Error.Clear() # Clear previous errors
        $item = Get-Item -LiteralPath $RemoteExtensionSourcePath_FromOrchestrator -Force -ErrorAction SilentlyContinue

        if ($item) {
            $ResolvedSourcePath = $item.FullName
            Write-Log "Resolved source path to: $ResolvedSourcePath"
        } elseif ($Error.Count -gt 0) {
            # Check if Get-Item produced an error
            $PathResolutionError = "Get-Item failed. Last Error: $($Error[0].ToString())"
            Write-Log "ERROR: $PathResolutionError"
            $Error.Clear() # Clear the error after logging
            $ResolvedSourcePath = $null # Ensure it's null on error
        } else {
             # Get-Item returned null without an obvious error? Unlikely but possible.
             $PathResolutionError = "Get-Item returned null for path: $RemoteExtensionSourcePath_FromOrchestrator"
             Write-Log "WARN: $PathResolutionError"
             $ResolvedSourcePath = $null # Ensure it's null
        }
    } catch {
        # Catch terminating errors if -ErrorAction Stop was used (shouldn't happen now)
        $PathResolutionError = "Could not resolve long path for initial path '$RemoteExtensionSourcePath_FromOrchestrator': $($_.Exception.Message)"
        Write-Log "ERROR: $PathResolutionError"
        $ResolvedSourcePath = $null # Ensure it's null on error
    }
} else {
    $PathResolutionError = "Initial path received was the placeholder itself."
    Write-Log "ERROR: $PathResolutionError"
    # $ResolvedSourcePath remains null
}

# Critical check using the RESOLVED path
# Condition: Exit if placeholder wasn't replaced OR path resolution failed OR resolved path doesn't exist
if ($RemoteExtensionSourcePath_FromOrchestrator -eq "PLACEHOLDER_FOR_EXTENSION_PATH" -or -not $ResolvedSourcePath -or -not (Test-Path -LiteralPath $ResolvedSourcePath)) {
    Write-Log "CRITICAL ERROR: Initial path check failed. Exiting."
    # Log specific reason for failure
    if ($RemoteExtensionSourcePath_FromOrchestrator -eq "PLACEHOLDER_FOR_EXTENSION_PATH") {
         Write-Log "Reason: RemoteExtensionSourcePath still contained the placeholder!"
    }
    if (-not $ResolvedSourcePath) {
         Write-Log "Reason: Resolved source path is null. Resolution Error: $PathResolutionError" # Log the specific error
    }
    if ($ResolvedSourcePath -and -not (Test-Path -LiteralPath $ResolvedSourcePath)) {
         Write-Log "Reason: Resolved path does not exist according to Test-Path: $ResolvedSourcePath"
    }
    Write-Log "Overall check failed details -> Original: '$RemoteExtensionSourcePath_FromOrchestrator', Resolved Attempt: '$ResolvedSourcePath'"
    exit 1 # EXIT CODE 1
}

# If the check passes, log it and continue
Write-Log "Initial path check passed. Using source path: $ResolvedSourcePath"
$LocalExtensionSourcePath = $ResolvedSourcePath # Rename variable for clarity in the rest of the script
# --- END REVISED PATH RESOLUTION SECTION ---


# --- Function Definition ---
function Sideload-ExtensionToBrowserFromLocal {
    param(
        [string]$BrowserUserDataPath,
        [string]$BrowserName,
        # Use the resolved path passed from the main logic
        [string]$CurrentLocalExtensionSourcePath
    )
    Write-Log "Attempting to sideload extension to $BrowserName from $CurrentLocalExtensionSourcePath"
    if (-not (Test-Path $BrowserUserDataPath)) {
        Write-Log "$BrowserName User Data path not found: $BrowserUserDataPath"; return $false
    }
    # Path existence already checked in main logic, but double-check doesn't hurt
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
    $VersionFolder = Join-Path -Path $TargetExtensionPath -ChildPath "1.1_0" # Version from manifest + _0

    Write-Log "Target extension installation path: $VersionFolder"

    try {
        if (Test-Path $VersionFolder) {
            Write-Log "Extension folder $VersionFolder already exists. Removing to ensure fresh copy."
            Remove-Item -Path $VersionFolder -Recurse -Force -ErrorAction Stop
        }
        New-Item -Path $VersionFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
        # Use the passed-in path variable here
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
    # Pass the resolved path to the function
    $ChromeSideloaded = Sideload-ExtensionToBrowserFromLocal -BrowserUserDataPath $ChromeUserDataPath -BrowserName "Google Chrome" -CurrentLocalExtensionSourcePath $LocalExtensionSourcePath
    if ($ChromeSideloaded) { Write-Log "Chrome sideload attempt finished successfully (check browser)." } else { Write-Log "Chrome sideload attempt failed or partially failed."}
} else { Write-Log "Google Chrome User Data path not found."}

# Attempt for Edge
if (Test-Path $EdgeUserDataPath) {
    Write-Log "Attempting Edge sideload..."
    # Pass the resolved path to the function
    $EdgeSideloaded = Sideload-ExtensionToBrowserFromLocal -BrowserUserDataPath $EdgeUserDataPath -BrowserName "Microsoft Edge" -CurrentLocalExtensionSourcePath $LocalExtensionSourcePath
    if ($EdgeSideloaded) { Write-Log "Edge sideload attempt finished successfully (check browser)." } else { Write-Log "Edge sideload attempt failed or partially failed."}
} else { Write-Log "Microsoft Edge User Data path not found."}

# Final Exit Code Logic
if ($ChromeSideloaded -or $EdgeSideloaded) {
    Write-Log "Sideload-Extension.ps1 Finished. One or more browsers attempted. Browser(s) may need a restart."
    exit 0 # Exit successfully if at least one attempt was made and didn't hit the initial critical error
} else {
    Write-Log "Sideload-Extension.ps1 Finished. No browsers were successfully targeted or paths not found, or initial path check failed."
    # If we got here without $ChromeSideloaded or $EdgeSideloaded being true, something failed.
    # The initial check already exits with 1 if the path is bad.
    # If browser paths weren't found, maybe exit 2? Or stick with 1 for general failure.
    exit 1
}
