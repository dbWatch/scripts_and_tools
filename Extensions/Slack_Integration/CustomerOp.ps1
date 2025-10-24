# Set variables
$LOCKFILE = "$env:TEMP\CustomerOp.lock"

# Check if script is already running
if (Test-Path $LOCKFILE) {
    Write-Host "Script is already running. Exiting."
    exit 1
}
# Create lock file and cleanup trap
New-Item -ItemType File -Path $LOCKFILE | Out-Null
$script:CleanupAction = {
    Remove-Item -Force $LOCKFILE -ErrorAction SilentlyContinue
}
Register-EngineEvent PowerShell.Exiting -Action $CleanupAction

# Get script directory
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Slack configuration
$SLACK_TOKEN = "xoxb-your-token-here"
$SLACK_CHANNEL = "#your-channel"  # or use channel ID like "C0123456789"
$LAST_MESSAGE_FILE = Join-Path $SCRIPT_DIR "lastMessageTimestamp.txt"

# Paths and files
$CONFIG_FILE = Join-Path $SCRIPT_DIR "customers.ini"
$FDL_SCRIPT = Join-Path $SCRIPT_DIR "fdlREMOTE.script"
$RESULT_FILE = Join-Path $SCRIPT_DIR "temp_result.log"
$CCC_PATH = "C:\Program Files\dbWatchControlCenter\ccc.exe"

# Check CCC_PATH
if (-not (Test-Path $CCC_PATH)) {
    Write-Host "Error: $CCC_PATH not found."
    & $CleanupAction
    exit 1
}

# Check config file
if (-not (Test-Path $CONFIG_FILE)) {
    Write-Host "Error: Configuration file '$CONFIG_FILE' not found."
    & $CleanupAction
    exit 1
}

# Create FDL script if it doesn't exist
if (-not (Test-Path $FDL_SCRIPT)) {
@'
## setup@properties
accesspoint?=localhost:7100
node?=
query?=versioninfo
domainName?=
delimiter?=:
result?=fdl.txt
token?=
timeout?=10

## join@Domain
join accesspoint={$accesspoint$} domain={$domainName$} token={$token$}

## add@Fdl
fdl accesspoint={$accesspoint$} node={$node$} query={$query$} timeout={$timeout$} delimiter={$delimiter$} result={$result$}
'@ | Set-Content $FDL_SCRIPT
}

# Initialize message
$MESSAGE_HEADER = "Combined Status Report:"
$COMBINED_MESSAGE = ""

# Process each line in customers.ini
Get-Content $CONFIG_FILE | ForEach-Object {
    $_ = $_.Trim()
    if ($_.StartsWith("#") -or $_ -eq "") { return } # skip comments or empty lines

    $fields = $_ -split ","
    if ($fields.Count -lt 4) {
        Write-Warning "Skipping invalid line: $_"
        return
    }

    $ACCESSPOINT = $fields[0].Trim()
    $TARGET = $fields[1].Trim()
    $DOMAINNAME = $fields[2].Trim()
    $TOKEN = $fields[3].Trim()

    Write-Host "Processing customer: $DOMAINNAME"
    Clear-Content -Path $RESULT_FILE -ErrorAction SilentlyContinue

    $QUERY = "server->s/name/id{}/`$s/slacksummary/id"
    $params = @(
        "`"$FDL_SCRIPT`"",
        "accesspoint=$ACCESSPOINT",
        "node=$TARGET",
        "query=$QUERY",
        "domainName=$DOMAINNAME",
        "token=$TOKEN",
        "result=$RESULT_FILE"
    )
    $COMMAND_OUTPUT = & "$CCC_PATH" $params 2>&1

    $STATUS_CIRCLES = ""
    $LOST_CONNECTIONS = ""
    $ALARMS = ""

    if (-not (Test-Path $RESULT_FILE) -or (Get-Content $RESULT_FILE | Measure-Object).Count -eq 0) {
        $COMBINED_MESSAGE += "`n${DOMAINNAME}: *Server lost connection*"
    } else {
        Get-Content $RESULT_FILE | ForEach-Object {
            if ($_ -like "*Lost connection:*") {
                $LOST_CONNECTIONS = $_ -replace "^.*?:", ""
            } elseif ($_ -like "*Alarm:*") {
                $ALARMS = $_ -replace "^.*?:", ""
            } else {
                $STATUS_CIRCLES = $_
            }
        }

        $COMBINED_MESSAGE += "`n$STATUS_CIRCLES"
        if ($LOST_CONNECTIONS) { $COMBINED_MESSAGE += "`n  :large_blue_circle:: $LOST_CONNECTIONS" }
        if ($ALARMS) { $COMBINED_MESSAGE += "`n  :red_circle:: $ALARMS" }
    }
}

$FINAL_MESSAGE = "$MESSAGE_HEADER`n$COMBINED_MESSAGE"

# Function to delete previous Slack message
function Delete-PreviousMessage {
    if (Test-Path $LAST_MESSAGE_FILE) {
        $LAST_TS = Get-Content $LAST_MESSAGE_FILE
        $body = @{
            channel = $SLACK_CHANNEL
            ts = $LAST_TS
        } | ConvertTo-Json

        $response = Invoke-RestMethod -Uri "https://slack.com/api/chat.delete" `
            -Headers @{ "Authorization" = "Bearer $SLACK_TOKEN" } `
            -Method Post -ContentType "application/json" -Body $body

        if ($response.ok) {
            Write-Host "Previous message deleted successfully."
        } else {
            Write-Warning "Failed to delete previous message: $($response | ConvertTo-Json -Depth 5)"
        }
    }
}

# Function to post to Slack
function Post-ToSlack {
    $body = @{
        channel = $SLACK_CHANNEL
        text    = $FINAL_MESSAGE
    } | ConvertTo-Json -Depth 5

    $response = Invoke-RestMethod -Uri "https://slack.com/api/chat.postMessage" `
        -Headers @{ "Authorization" = "Bearer $SLACK_TOKEN" } `
        -Method Post -ContentType "application/json" -Body $body

    if ($response.ok) {
        $response.ts | Out-File -FilePath $LAST_MESSAGE_FILE -Encoding utf8
        Write-Host "Message posted successfully."
    } else {
        Write-Error "Failed to post message: $($response | ConvertTo-Json -Depth 5)"
    }
}

# Do the Slack messaging
Delete-PreviousMessage
Post-ToSlack

# Cleanup lock file
& $CleanupAction
