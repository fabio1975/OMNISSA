##SCRIPT RESTAPI OMNISSA INTELLIGENCE API
<#
.SYNOPSIS
Script for running and downloading reports from Omnissa Intelligence API.

.DESCRIPTION
This script allows you to authenticate with the Omnissa Intelligence API using a service account, run a specified report, and download the latest execution result of that report.

.PARAMETER ServiceAccount
Parameter description

.PARAMETER ClientSecret
Parameter description

.PARAMETER AuthUrl
Parameter description

.EXAMPLE
& '.\OMNISSA - INTELLIGENCE API RUN-DOWNLOAD REPORT-AUTO.ps1' -ServiceAccount service_account@4327e213-dceb-4e7a-8d19-3f6xadc8da14.workspaceone.com 
-ClientSecret 7A6BF0FCC3B09377592E4520625FBB8Fx1490E9C95C5DBECA440D465697A7992 
-ReportId 1525846c-bf15-4345-994b-4a03fe5d3911 -OutputPath "C:\Attimo\"

'.\OMNISSA - INTELLIGENCE API RUN-DOWNLOAD REPORT-AUTO.ps1' -ServiceAccount service_account@4327e213-d8d19-3f6aadc8da14.workspaceone.com -ClientSecret 7A6BF0FCC3B520625FBB8F71490E9C95C5DBECA440D465697A7992 -ReportId 1525846c-bf15-4345-994b-4a03fe5d3911 -OutputPath "C:\Attimo\"
'.\OMNISSA - INTELLIGENCE API RUN-DOWNLOAD REPORT-AUTO.ps1' -ServiceAccount <Account> -ClientSecret <Secret> -ReportId <ReportID> -OutputPath "<PATH>"
.NOTES
General notes
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ServiceAccount,

    [Parameter(Mandatory=$true)]
    [string]$ClientSecret,

    [Parameter(Mandatory=$true)]
    [string]$ReportId,

    [Parameter()]
    [string]$AuthUrl = "https://auth.eu1.data.workspaceone.com/oauth/token",

    [Parameter()]
    [string]$ApiBaseUrl = "https://api.eu1.data.workspaceone.com",

    [Parameter()]
    [string]$OutputPath = "C:\attimo"
)
function Get-OmnissaIntelligenceToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ServiceAccount,

        [Parameter(Mandatory=$true)]
        [string]$ClientSecret,

        [Parameter()]
        [string]$AuthUrl = "https://auth.eu1.data.workspaceone.com/oauth/token"
    )

    try {
        # Costruzione header Basic Auth
        $pair = "$ServiceAccount`:$ClientSecret"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($pair)
        $encodedCreds = [Convert]::ToBase64String($bytes)

        $headers = @{
            Authorization = "Basic $encodedCreds"
            "Content-Type" = "application/x-www-form-urlencoded"
        }

        $body = @{
            grant_type = "client_credentials"
        }

        $response = Invoke-RestMethod -Method Post `
                                      -Uri $AuthUrl `
                                      -Headers $headers `
                                      -Body $body

        return $response
    }
    catch {
        Write-Error "Errore durante l'autenticazione: $_"
    }
}

function Invoke-OmnissaIntelligenceReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$AccessToken,

        [Parameter(Mandatory=$true)]
        [string]$ReportId,

        [Parameter()]
        [string]$ApiBaseUrl = "https://api.eu1.data.workspaceone.com",

        [Parameter()]
        [hashtable]$Body = @{}
    )

    try {
        $uri = "$ApiBaseUrl/v2/reports/$ReportId/run"

        $headers = @{
            Authorization = "Bearer $AccessToken"
            "Content-Type" = "application/json"
        }

        # Se serve un body JSON
        $jsonBody = if ($Body.Count -gt 0) {
            $Body | ConvertTo-Json -Depth 5
        } else {
            $null
        }

        $response = Invoke-RestMethod -Method Post `
                                      -Uri $uri `
                                      -Headers $headers `
                                      -Body $jsonBody

        return $response
    }
    catch {
        Write-Error "Errore durante l'esecuzione del report: $_"
    }
}

function Get-OmnissaReportLastScheduleId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$AccessToken,

        [Parameter(Mandatory=$true)]
        [string]$ReportId,

        [Parameter()]
        [string]$ApiBaseUrl = "https://api.eu1.data.workspaceone.com"
    )

    try {
        $uri = "$ApiBaseUrl/v2/reports/$ReportId/downloads/search"

        $headers = @{
            Authorization = "Bearer $AccessToken"
            "Content-Type" = "application/json"
        }

        # Body con ordinamento per ultima esecuzione
        $body = @{
            page_size = 1
            offset    = 0
        } | ConvertTo-Json -Depth 5

        $response = Invoke-RestMethod -Method Post `
                                      -Uri $uri `
                                      -Headers $headers `
                                      -Body $body

        if ($response.data.results.Count -gt 0) {
            return $response.data.results[0].id
        }
        else {
            Write-Warning "Nessuna esecuzione trovata per il report."
            return $null
        }
    }
    catch {
        Write-Error "Errore durante il recupero dello status del report: $_"
    }
}




function Get-OmnissaReportDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$AccessToken,

        [Parameter(Mandatory=$true)]
        [string]$ScheduleId,

        [Parameter()]
        [string]$ApiBaseUrl = "https://api.eu1.data.workspaceone.com"
    )

    try {
        $uri = "$ApiBaseUrl/v2/reports/tracking/$ScheduleId/download"

        $headers = @{
            Authorization = "Bearer $AccessToken"
            "Content-Type" = "application/json"
        }
        
        $response = Invoke-RestMethod -Method Get `
                                      -Uri $uri `
                                      -Headers $headers 
        return $response
    }
    catch {
        Write-Error "Errore durante il recupero dello status del report: $_"
    }
}

###MAIN PROGRAM 
Write-Host "Avvio esecuzione report Omnissa Intelligence..." -ForegroundColor Cyan

# Get Access Token
$tokenResponse = Get-OmnissaIntelligenceToken `
    -ServiceAccount $ServiceAccount `
    -ClientSecret $ClientSecret `
    -AuthUrl $AuthUrl

if (-not $tokenResponse.access_token) {
    Write-Error "Token non ottenuto. Interruzione script."
    exit 1
}

# Run Report
$reportResponse = Invoke-OmnissaIntelligenceReport `
    -AccessToken $tokenResponse.access_token `
    -ReportId $ReportId `
    -ApiBaseUrl $ApiBaseUrl

Write-Host "Report avviato." -ForegroundColor Green

Start-Sleep -Seconds 5

# Get Last Schedule ID
$lastScheduleId = Get-OmnissaReportLastScheduleId `
    -AccessToken $tokenResponse.access_token `
    -ReportId $ReportId `
    -ApiBaseUrl $ApiBaseUrl

if (-not $lastScheduleId) {
    Write-Error "Nessuna esecuzione trovata. Interruzione."
    exit 1
}

# Download Report
$report = Get-OmnissaReportDownload `
    -AccessToken $tokenResponse.access_token `
    -ScheduleId $lastScheduleId `
    -ApiBaseUrl $ApiBaseUrl

# Ensure output directory exists
if (!(Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$fullPath = Join-Path $OutputPath "report_Intelligence_$timestamp.json"

$report | ConvertTo-Json -Depth 10 | Set-Content -Path $fullPath -Encoding utf8


Write-Host "Report salvato in: $fullPath" -ForegroundColor Green
