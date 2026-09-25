# ============================================================
# dbWatch -> Microsoft Teams Status Integration
#
# Reads two dbWatch web-export JSON URLs per customer:
#
#   1. Instance status counts
#   2. ALARM / LOST CONNECTION instance list
#
# Displays the result in the PowerShell console and posts an
# Adaptive Card to a Microsoft Teams webhook/Workflow.
#
# By default, Teams is only updated when the dbWatch status
# has changed since the previous run.
# ============================================================


# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition

$CONFIG_FILE = Join-Path $SCRIPT_DIR "customers.ini"
$LOCKFILE = Join-Path $env:TEMP "dbWatchTeamsIntegration.lock"
$STATE_FILE = Join-Path $SCRIPT_DIR "lastTeamsState.txt"

# Teams Workflow / Incoming Webhook URL
$TEAMS_WEBHOOK_URL = "https://YOUR-TEAMS-WEBHOOK-URL"

# Only send a Teams message when dbWatch status changes
$POST_ONLY_ON_CHANGE = $true

# Prevent very large Teams cards.
# Counts always show the complete numbers, but detail lists
# will be shortened after this number of instances.
$MAX_DETAILS_PER_STATUS = 20

# HTTP timeout for each dbWatch URL
$HTTP_TIMEOUT = 30


# ------------------------------------------------------------
# Emoji
#
# Generated from Unicode code points so the script does not
# depend on the .ps1 file itself being saved with emoji support.
# ------------------------------------------------------------

$RED    = [char]::ConvertFromUtf32(0x1F534)   # Red circle
$BLUE   = [char]::ConvertFromUtf32(0x1F535)   # Blue circle
$ORANGE = [char]::ConvertFromUtf32(0x1F7E0)   # Orange circle
$GREEN  = [char]::ConvertFromUtf32(0x1F7E2)   # Green circle
$BLACK  = [char]::ConvertFromUtf32(0x26AB)    # Black circle
$WHITE  = [char]::ConvertFromUtf32(0x26AA)    # White circle


# ------------------------------------------------------------
# Lock file
# ------------------------------------------------------------

if (Test-Path $LOCKFILE) {
    Write-Host "Script is already running. Exiting."
    exit 1
}

New-Item -ItemType File -Path $LOCKFILE -Force | Out-Null


# ------------------------------------------------------------
# Functions
# ------------------------------------------------------------

function Get-DbWatchJson {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    return Invoke-RestMethod `
        -Uri $Url `
        -Method Get `
        -TimeoutSec $HTTP_TIMEOUT `
        -ErrorAction Stop
}


function Get-StatusCounts {

    param (
        [Parameter(Mandatory = $true)]
        $Json
    )

    $status = @{
        "LOST CONNECTION" = 0
        "NOT CONNECTED"   = 0
        "ALARM"           = 0
        "WARNING"         = 0
        "OK"              = 0
        "NO STATUS"       = 0
    }

    foreach ($row in $Json.data) {

        if ($row.Count -ge 2) {

            $statusName = [string]$row[0]

            $count = 0
            [int]::TryParse([string]$row[1], [ref]$count) | Out-Null

            $status[$statusName] = $count
        }
    }

    return [PSCustomObject]@{
        LostConnection = $status["LOST CONNECTION"]
        NotConnected   = $status["NOT CONNECTED"]
        Alarm          = $status["ALARM"]
        Warning        = $status["WARNING"]
        OK             = $status["OK"]
        NoStatus       = $status["NO STATUS"]
    }
}


function Get-ProblemInstances {

    param (
        [Parameter(Mandatory = $true)]
        $Json
    )

    $items = @()

    foreach ($row in $Json.data) {

        if ($row.Count -ge 3) {

            $items += [PSCustomObject]@{
                Status   = [string]$row[0]
                Instance = [string]$row[1]
                Group    = [string]$row[2]
            }
        }
    }

    return $items
}


function Format-InstanceList {

    param (
        $Instances,
        [int]$Maximum
    )

    if (-not $Instances -or $Instances.Count -eq 0) {
        return "None"
    }

    $lines = @()

    $shown = $Instances |
        Select-Object -First $Maximum

    foreach ($item in $shown) {
        $lines += "- $($item.Instance) [$($item.Group)]"
    }

    if ($Instances.Count -gt $Maximum) {

        $remaining = $Instances.Count - $Maximum

        $lines += "- ... and $remaining more"
    }

    return ($lines -join "`n")
}


function Get-Sha256 {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $sha = [System.Security.Cryptography.SHA256]::Create()

    try {

        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hashBytes = $sha.ComputeHash($bytes)

        return (
            [System.BitConverter]::ToString($hashBytes)
        ).Replace("-", "").ToLower()

    }
    finally {
        $sha.Dispose()
    }
}


function Send-ToTeams {

    param (
        [Parameter(Mandatory = $true)]
        $Reports
    )

    $cardBody = @()

    # Main heading
    $cardBody += @{
        type   = "TextBlock"
        text   = "dbWatch Status Report"
        size   = "Large"
        weight = "Bolder"
        wrap   = $true
    }

    $cardBody += @{
        type     = "TextBlock"
        text     = "Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        isSubtle = $true
        spacing  = "None"
        wrap     = $true
    }


    foreach ($report in $Reports) {

        # Customer heading
        $cardBody += @{
            type      = "TextBlock"
            text      = $report.Customer
            size      = "Medium"
            weight    = "Bolder"
            separator = $true
            wrap      = $true
        }


        # dbWatch server/export unavailable
        if ($report.Error) {

            $cardBody += @{
                type  = "TextBlock"
                text  = "$RED Unable to retrieve dbWatch status"
                wrap  = $true
            }

            $cardBody += @{
                type     = "TextBlock"
                text     = $report.Error
                isSubtle = $true
                wrap     = $true
            }

            continue
        }


        # Status counters
        $cardBody += @{
            type = "FactSet"

            facts = @(
                @{
                    title = "$BLUE Lost connection"
                    value = [string]$report.Status.LostConnection
                },
                @{
                    title = "$BLACK Not connected"
                    value = [string]$report.Status.NotConnected
                },
                @{
                    title = "$RED Alarm"
                    value = [string]$report.Status.Alarm
                },
                @{
                    title = "$ORANGE Warning"
                    value = [string]$report.Status.Warning
                },
                @{
                    title = "$GREEN OK"
                    value = [string]$report.Status.OK
                },
                @{
                    title = "$WHITE No status"
                    value = [string]$report.Status.NoStatus
                }
            )
        }


        # Lost connection details
        if ($report.LostConnections.Count -gt 0) {

            $lostText = Format-InstanceList `
                -Instances $report.LostConnections `
                -Maximum $MAX_DETAILS_PER_STATUS

            $cardBody += @{
                type   = "TextBlock"
                text   = "$BLUE Lost connection"
                weight = "Bolder"
                spacing = "Medium"
                wrap   = $true
            }

            $cardBody += @{
                type = "TextBlock"
                text = $lostText
                wrap = $true
            }
        }


        # Alarm details
        if ($report.Alarms.Count -gt 0) {

            $alarmText = Format-InstanceList `
                -Instances $report.Alarms `
                -Maximum $MAX_DETAILS_PER_STATUS

            $cardBody += @{
                type    = "TextBlock"
                text    = "$RED Alarm"
                weight  = "Bolder"
                spacing = "Medium"
                wrap    = $true
            }

            $cardBody += @{
                type = "TextBlock"
                text = $alarmText
                wrap = $true
            }
        }


        # Problem-detail query failed but status count query worked
        if ($report.DetailError) {

            $cardBody += @{
                type     = "TextBlock"
                text     = "Detailed ALARM / LOST CONNECTION information could not be retrieved."
                isSubtle = $true
                wrap     = $true
            }
        }
    }


    # Adaptive Card payload
    $payload = @{
        type = "message"

        attachments = @(
            @{
                contentType = "application/vnd.microsoft.card.adaptive"
                contentUrl  = $null

                content = @{
                    '$schema' = "http://adaptivecards.io/schemas/adaptive-card.json"
                    type      = "AdaptiveCard"
                    version   = "1.2"
                    body      = $cardBody
                }
            }
        )
    }


    $jsonBody = $payload | ConvertTo-Json -Depth 20

    # Explicit UTF-8 encoding is useful when sending the circle symbols.
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)

    Invoke-RestMethod `
        -Uri $TEAMS_WEBHOOK_URL `
        -Method Post `
        -ContentType "application/json; charset=utf-8" `
        -Body $bodyBytes `
        -ErrorAction Stop
}


# ------------------------------------------------------------
# Main processing
# ------------------------------------------------------------

try {

    if (-not (Test-Path $CONFIG_FILE)) {
        throw "Configuration file not found: $CONFIG_FILE"
    }

    if (
        [string]::IsNullOrWhiteSpace($TEAMS_WEBHOOK_URL) -or
        $TEAMS_WEBHOOK_URL -like "*YOUR-TEAMS-WEBHOOK-URL*"
    ) {
        throw "Teams webhook URL has not been configured."
    }


    $reports = @()


    Get-Content $CONFIG_FILE | ForEach-Object {

        $line = $_.Trim()

        # Ignore comments and empty lines
        if ($line -eq "" -or $line.StartsWith("#")) {
            return
        }


        # Maximum of three fields:
        #
        # Customer,StatusURL,DetailsURL
        #
        $fields = $line -split ",", 3

        if ($fields.Count -lt 3) {

            Write-Warning "Skipping invalid configuration line:"
            Write-Warning $line

            return
        }


        $customer   = $fields[0].Trim()
        $statusUrl  = $fields[1].Trim()
        $detailsUrl = $fields[2].Trim()


        Write-Host ""
        Write-Host "============================================================"
        Write-Host "Processing: $customer"
        Write-Host "============================================================"


        # ----------------------------------------------------
        # Status counters
        # ----------------------------------------------------

        try {

            Write-Host "Reading status summary..."

            $statusJson = Get-DbWatchJson -Url $statusUrl

            $status = Get-StatusCounts -Json $statusJson
        }
        catch {

            $errorMessage = $_.Exception.Message

            Write-Warning "Unable to retrieve status information:"
            Write-Warning $errorMessage


            $reports += [PSCustomObject]@{
                Customer       = $customer
                Error          = $errorMessage
                DetailError    = $null
                Status         = $null
                Alarms         = @()
                LostConnections = @()
            }

            return
        }


        # ----------------------------------------------------
        # ALARM / LOST CONNECTION details
        # ----------------------------------------------------

        $alarms = @()
        $lostConnections = @()
        $detailError = $null


        try {

            Write-Host "Reading ALARM / LOST CONNECTION details..."

            $detailsJson = Get-DbWatchJson -Url $detailsUrl

            $problemInstances = Get-ProblemInstances -Json $detailsJson


            $alarms = @(
                $problemInstances |
                    Where-Object {
                        $_.Status -eq "ALARM"
                    } |
                    Sort-Object Group, Instance
            )


            $lostConnections = @(
                $problemInstances |
                    Where-Object {
                        $_.Status -eq "LOST CONNECTION"
                    } |
                    Sort-Object Group, Instance
            )
        }
        catch {

            $detailError = $_.Exception.Message

            Write-Warning "Unable to retrieve detailed information:"
            Write-Warning $detailError
        }


        # ----------------------------------------------------
        # Console preview
        # ----------------------------------------------------

        Write-Host ""
        Write-Host "STATUS"
        Write-Host "------"

        Write-Host "$BLUE LOST CONNECTION : $($status.LostConnection)"
        Write-Host "$BLACK NOT CONNECTED   : $($status.NotConnected)"
        Write-Host "$RED ALARM           : $($status.Alarm)"
        Write-Host "$ORANGE WARNING         : $($status.Warning)"
        Write-Host "$GREEN OK              : $($status.OK)"
        Write-Host "$WHITE NO STATUS       : $($status.NoStatus)"


        Write-Host ""
        Write-Host "LOST CONNECTION"
        Write-Host "---------------"

        if ($lostConnections.Count -eq 0) {

            Write-Host "None"
        }
        else {

            foreach ($item in $lostConnections) {

                Write-Host "  $($item.Instance) [$($item.Group)]"
            }
        }


        Write-Host ""
        Write-Host "ALARM"
        Write-Host "-----"

        if ($alarms.Count -eq 0) {

            Write-Host "None"
        }
        else {

            foreach ($item in $alarms) {

                Write-Host "  $($item.Instance) [$($item.Group)]"
            }
        }


        # ----------------------------------------------------
        # Add customer to combined Teams report
        # ----------------------------------------------------

        $reports += [PSCustomObject]@{
            Customer        = $customer
            Error           = $null
            DetailError     = $detailError

            Status = [PSCustomObject]@{
                LostConnection = $status.LostConnection
                NotConnected   = $status.NotConnected
                Alarm          = $status.Alarm
                Warning        = $status.Warning
                OK             = $status.OK
                NoStatus       = $status.NoStatus
            }

            Alarms = @(
                $alarms | ForEach-Object {

                    [PSCustomObject]@{
                        Instance = $_.Instance
                        Group    = $_.Group
                    }
                }
            )

            LostConnections = @(
                $lostConnections | ForEach-Object {

                    [PSCustomObject]@{
                        Instance = $_.Instance
                        Group    = $_.Group
                    }
                }
            )
        }
    }


    if ($reports.Count -eq 0) {

        throw "No valid customer configuration entries were found."
    }


    # --------------------------------------------------------
    # Determine whether anything has changed
    #
    # Timestamp is deliberately NOT included here.
    # --------------------------------------------------------

    $stateJson = $reports |
        ConvertTo-Json -Depth 10 -Compress

    $currentHash = Get-Sha256 -Text $stateJson

    $previousHash = $null

    if (Test-Path $STATE_FILE) {

        $previousHash = (
            Get-Content $STATE_FILE -Raw
        ).Trim()
    }


    Write-Host ""
    Write-Host "============================================================"


    if (
        $POST_ONLY_ON_CHANGE -and
        $previousHash -eq $currentHash
    ) {

        Write-Host "No status changes since previous run."
        Write-Host "Nothing posted to Teams."
    }
    else {

        Write-Host "Status changed or this is the first run."
        Write-Host "Posting report to Teams..."


        Send-ToTeams -Reports $reports


        $currentHash |
            Set-Content `
                -Path $STATE_FILE `
                -Encoding ASCII


        Write-Host "Teams message posted successfully."
    }


    Write-Host "============================================================"
}
catch {

    Write-Error $_
    exit 1
}
finally {

    Remove-Item `
        -Path $LOCKFILE `
        -Force `
        -ErrorAction SilentlyContinue
}