<# 
    SetupStatus.ps1 — PowerShell port of SetupStatus.sh
    - Logs to setup_debug.log
    - Expects customers.ini (CSV with 4 columns: ACCESSPOINT, TARGET, DOMAINNAME, TOKEN)
    - Creates setupREMOTE.script if it doesn't exist
    - Invokes ccc.exe with the right arguments
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Config ---
$DEBUG_LOG   = "setup_debug.log"
$CCC_PATH    = "C:\Program Files\dbWatchControlCenter\ccc.exe"
$CONFIG_FILE = "customers.ini"
$SETUP_SCRIPT = "setupREMOTE.script"

# --- Start log ---
"Starting Debug Log: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -FilePath $DEBUG_LOG -Encoding UTF8

# --- Validate ccc.exe path ---
if (-not (Test-Path -LiteralPath $CCC_PATH)) {
    "Error: $CCC_PATH not found." | Tee-Object -FilePath $DEBUG_LOG -Append
    exit 1
}

# --- Validate customers.ini ---
if (-not (Test-Path -LiteralPath $CONFIG_FILE)) {
    "Error: Configuration file '$CONFIG_FILE' not found." | Tee-Object -FilePath $DEBUG_LOG -Append
    exit 1
}

# --- Create setupREMOTE.script if missing ---
if (-not (Test-Path -LiteralPath $SETUP_SCRIPT)) {
@'
## setup@properties
accesspoint?=localhost:7100
domainName?=
name?=
token?=

## join@Domain
clear
join accesspoint={$accesspoint$} domain={$domainName$} name={$name$} token={$token$}
'@ | Out-File -FilePath $SETUP_SCRIPT -Encoding UTF8
    "Created $SETUP_SCRIPT file." | Tee-Object -FilePath $DEBUG_LOG -Append
}

# --- Load customers.ini (4 columns: ACCESSPOINT, TARGET, DOMAINNAME, TOKEN) ---
# Handles files with or without a header row, and ignores blank/comment lines.
$rawLines = Get-Content -LiteralPath $CONFIG_FILE | Where-Object {
    $_ -and ($_.Trim() -ne "") -and ($_.Trim().StartsWith("#") -eq $false)
}

# If file has a header row, drop it safely
if ($rawLines.Count -gt 0 -and ($rawLines[0] -match 'accesspoint|domain|token|target')) {
    $rawLines = $rawLines | Select-Object -Skip 1
}

# Parse lines to objects
$rows = foreach ($line in $rawLines) {
    $parts = $line.Split(',', 4)
    if ($parts.Count -lt 4) {
        "Skipping malformed line: $line" | Tee-Object -FilePath $DEBUG_LOG -Append
        continue
    }
    [pscustomobject]@{
        ACCESSPOINT = $parts[0].Trim()
        TARGET      = $parts[1].Trim()   # Not used by the original script
        DOMAINNAME  = $parts[2].Trim()
        TOKEN       = $parts[3].Trim()
    }
}

if (-not $rows -or $rows.Count -eq 0) {
    "No valid rows found in $CONFIG_FILE." | Tee-Object -FilePath $DEBUG_LOG -Append
    exit 1
}

# --- Process each customer ---
foreach ($row in $rows) {
    $ACCESSPOINT = $row.ACCESSPOINT
    $DOMAINNAME  = $row.DOMAINNAME
    $TOKEN       = $row.TOKEN
    $NAME        = 'ccc(Slack integration)'  # Fixed name, as in the Bash script

    "Processing: Accesspoint=$ACCESSPOINT, Domain=$DOMAINNAME, Name=$NAME, Token=$TOKEN" | `
        Tee-Object -FilePath $DEBUG_LOG -Append

    # Build arguments to match: ccc.exe "setupREMOTE.script" accesspoint="..." domainName="..." name="..." token="..."
    $args = @(
        $SETUP_SCRIPT
        "accesspoint=`"$ACCESSPOINT`""
        "domainName=`"$DOMAINNAME`""
        "name=`"$NAME`""
        "token=`"$TOKEN`""
    )

    try {
        # Invoke the executable and capture exit code
        & "$CCC_PATH" @args
        $exit = $LASTEXITCODE

        if ($exit -eq 0 -or $null -eq $exit) {
            "Setup successful for domain: $DOMAINNAME" | Tee-Object -FilePath $DEBUG_LOG -Append
        } else {
            "Setup failed for domain: $DOMAINNAME (exit code $exit). Check logs." | Tee-Object -FilePath $DEBUG_LOG -Append
        }
    }
    catch {
        "Setup failed for domain: $DOMAINNAME. Error: $($_.Exception.Message)" | Tee-Object -FilePath $DEBUG_LOG -Append
    }
}

"Script execution completed." | Tee-Object -FilePath $DEBUG_LOG -Append
