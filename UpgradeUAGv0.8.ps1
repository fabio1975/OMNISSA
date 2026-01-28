#Script for deploy UAG v.0.8
#The Script export the configuration from actual UAG
#Insert the infrastructure information from a UAG SETTINGS FILE 
#Deploy the UAG 
#
#STEP 1 Create credential file 
#UAG ADMIN/ROOT -> Get-Credential | Export-Clixml "C:\attimo\uag_admin.cred"
#vCentrt -> Get-Credential | Export-Clixml "C:\attimo\vcenter_admin.cred"
#STEP 2 OVF TOOLS
#Install OVF TOOLS https://developer.broadcom.com/tools/open-virtualization-format-ovf-tool/latest
#STEP 3 DOWNLOAD SCRIPT OMNISSA and UAG OVA
#Download Script poweshell deploy and UAG OVA form Omnissa Portal 
#STEP 4 CERTIFICATE PEM e KEY 
#STEP 5 download from my repository o crate file with infrastructure value like this (UAGVALORI.TXT):
#[General]
#diskMode=thin
#ds=nvme
#name=UAGINT02
#netBackendNetwork=LAB
#netInternet=LAB
#netManagementNetwork=LAB
#source=E:\OMNISSA\UAG\euc-unified-access-gateway-25.12.0.0-19824103628_OVF10.ova
#target=vi://administrator@corp.local:<password>@vcenter01.pollaio.lan/DC01/host/CLU04/viesxi05.pollaio.lan
#[SSLCert]
#pemPrivKey=E:\certificati\rsa_privatekey.pem
#pemCerts=E:\certificati\certificate.pem
#Command Example .\ScriptUpgradeUAGv7.ps1 -DstServer UAGINT02.pollaio.lan -tokenvalid 12 -UagCredPath C:\attimo\uag_admin.cred -VcenterCredPath C:\attimo\vcenter_admin.cred -PathScript E:\OMNISSA\UAG\uagdeploy2512 -PathValue C:\Attimo\UAGVALORI.txt -PathINI c:\Attimo\UAGAUTO.INI -vCenter vcenter01.pollaio.lan
param(
        [string]$DstServer,  [string]$tokenvalid,
        [string]$PathScript, [string]$PathValue,
        [string]$PathINI, [string]$vCenter,
        [string]$VcenterCredPath, [string]$UagCredPath,
        [string]$Verbose, [string]$LogPath = "C:\UAGDeploy_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
     )

# =========================================================
# PowerShell version detection + SSL handling
# =========================================================
$Script:PSMajorVersion = $PSVersionTable.PSVersion.Major

Write-Host "PowerShell version detected: $($PSVersionTable.PSVersion)"

if ($Script:PSMajorVersion -ge 7) {
    $Script:RestMode = "PS7"
}
else {
    $Script:RestMode = "PS5"
}


function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO","WARN","ERROR","DEBUG")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine   = "$timestamp [$Level] $Message"

    # Scrittura su file
    Add-Content -Path $LogPath -Value $logLine

    # Output console
    switch ($Level) {
        "INFO"  { Write-Host $logLine -ForegroundColor Cyan }
        "WARN"  { Write-Host $logLine -ForegroundColor Yellow }
        "ERROR" { Write-Host $logLine -ForegroundColor Red }
        "DEBUG" {
            if ($Verbose) {
                Write-Host $logLine -ForegroundColor Gray
            }
        }
    }
}
function Invoke-RestSafe {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("GET","POST","PUT","DELETE")]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Uri,

        [hashtable]$Headers,

        [object]$Body,

        [string]$ContentType = "application/json",

        [string]$OutFile  # <- nuovo parametro
    )

    if ($Script:RestMode -eq "PS7") {
        # PowerShell 7+ → SkipCertificateCheck
        if ($OutFile) {
            Invoke-WebRequest `
                -Method $Method `
                -Uri $Uri `
                -Headers $Headers `
                -Body $Body `
                -ContentType $ContentType `
                -SkipCertificateCheck `
                -OutFile $OutFile
        }
        else {
            Invoke-RestMethod `
                -Method $Method `
                -Uri $Uri `
                -Headers $Headers `
                -Body $Body `
                -ContentType $ContentType `
                -SkipCertificateCheck
        }
    }
    else {
        # PowerShell 5.1 → HttpClient
        $handler = New-Object System.Net.Http.HttpClientHandler
        $handler.ServerCertificateCustomValidationCallback = { $true }

        $client = [System.Net.Http.HttpClient]::new($handler)

        if ($Headers) {
            foreach ($key in $Headers.Keys) {
                $client.DefaultRequestHeaders.Add($key, $Headers[$key])
            }
        }

        if ($Body) {
            $json = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 5 }
            $content = New-Object System.Net.Http.StringContent(
                $json,
                [System.Text.Encoding]::UTF8,
                $ContentType
            )
        }

        switch ($Method) {
            "GET" {
                $response = $client.GetAsync($Uri).Result
            }
            "POST" {
                $response = $client.PostAsync($Uri, $content).Result
            }
            "PUT" {
                $response = $client.PutAsync($Uri, $content).Result
            }
            "DELETE" {
                $response = $client.DeleteAsync($Uri).Result
            }
        }

        if (-not $response.IsSuccessStatusCode) {
            throw "REST call failed: $($response.StatusCode)"
        }

        if ($OutFile) {
            # salva direttamente su file
            $bytes = $response.Content.ReadAsByteArrayAsync().Result
            [System.IO.File]::WriteAllBytes($OutFile, $bytes)
            return $OutFile
        }
        else {
            $response.Content.ReadAsStringAsync().Result | ConvertFrom-Json
        }
    }
}


function Get-HRToken {
    param([string]$Server, [System.Management.Automation.PSCredential]$Credential, [string]$RefreshTokenExpiry)
    $body = @{ username=$Credential.UserName; password=$Credential.GetNetworkCredential().Password; refreshTokenExpiryInHours=$RefreshTokenExpiry} | ConvertTo-Json
    $uri  = "https://$Server/rest/v1/jwt/login"   # POST /rest/login :contentReference[oaicite:0]{index=0}  
    (Invoke-RestSafe -Method Post -Uri $uri -Body $body).accessToken
}

function Get-HRTokenPS5 {
    param(
        [string]$Server,
        [System.Management.Automation.PSCredential]$Credential,
        [string]$RefreshTokenExpiry
    )

    $uri = "https://$Server/rest/v1/jwt/login"

    $bodyObj = @{
        username = $Credential.UserName
        password = $Credential.GetNetworkCredential().Password
        refreshTokenExpiryInHours = [int]$RefreshTokenExpiry
    }

    $body = $bodyObj | ConvertTo-Json -Depth 3

    try {
        $response = Invoke-WebRequest `
            -Method Post `
            -Uri $uri `
            -Body $body `
            -ContentType "application/json" `
            -UseBasicParsing `
            -ErrorAction Stop

        if (-not $response.Content) {
            throw "Login UAG riuscito ma nessun body restituito (StatusCode=$($response.StatusCode))"
        }

        $json = $response.Content | ConvertFrom-Json

        if (-not $json.accessToken) {
            throw "accessToken non presente nella risposta UAG"
        }

        return $json.accessToken
    }
    catch {
        throw "Errore login UAG: $($_.Exception.Message)"
    }
}

function Get-VMByIP {
    param(
        [Parameter(Mandatory)]
        [string]$IP
    )

    Get-VM | Where-Object {
        $_.Guest.IPAddress -contains $IP
    }
}
function FileINI {
param (
    [Parameter(Mandatory = $true)]
    [string]$SourceFile,

    [Parameter(Mandatory = $true)]
    [string]$TargetFile,

    [switch]$OverwriteExisting
)

# ===============================
# 1. Parse SOURCE INI
# ===============================
$SourceData = @{}
$CurrentSection = ""
Write-Log "=== Avvio script deploy UAG ==="
Write-Log "PowerShell version: $($PSVersionTable.PSVersion)"
Write-Log "Log file: $LogPath"

Get-Content $SourceFile | ForEach-Object {

    if ($_ -match '^\s*\[(.+?)\]\s*$') {
        $CurrentSection = $matches[1]
        if (-not $SourceData.ContainsKey($CurrentSection)) {
            $SourceData[$CurrentSection] = @{}
        }
        return
    }

    if ($_ -match '^\s*([^=]+)\s*=\s*(.*)$' -and $CurrentSection) {
        $Key = $matches[1].Trim()
        $Value = $matches[2].Trim()
        $SourceData[$CurrentSection][$Key] = $Value
    }
}

# ===============================
# 2. Update TARGET INI
# ===============================
$CurrentSection = ""

$UpdatedContent = Get-Content $TargetFile | ForEach-Object {

    if ($_ -match '^\s*\[(.+?)\]\s*$') {
        $CurrentSection = $matches[1]
        return $_
    }

    if ($_ -match '^\s*([^=]+)\s*=\s*(.*)$' -and $CurrentSection) {

        $Key = $matches[1].Trim()
        $CurrentValue = $matches[2].Trim()

        if (
            $SourceData.ContainsKey($CurrentSection) -and
            $SourceData[$CurrentSection].ContainsKey($Key)
        ) {
            if ($OverwriteExisting -or [string]::IsNullOrEmpty($CurrentValue)) {
                return "$Key=$($SourceData[$CurrentSection][$Key])"
            }
        }
    }

    return $_
}

# ===============================
# 3. Write updated file
# ===============================
$UpdatedContent | Set-Content $TargetFile -Encoding UTF8


}

[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
$UagCred     = Import-Clixml $UagCredPath
$VcenterCred = Import-Clixml $VcenterCredPath
Write-Log "Connessione a vCenter $vCenter"
Connect-VIServer -Server $vCenter -Credential $VcenterCred
Write-Log "Controllo se la $DstServer esiste"
#$ips = ([System.Net.Dns]::GetHostAddresses("$DstServer")).IPAddressToString $null
try {
    $ips = [System.Net.Dns]::GetHostAddresses($DstServer).IPAddressToString
}
catch {
    $ips = $null
    Write-Log "Impossibile risolvere $DstServer" "ERROR"
    Exit
}
Write-Log "IP UAG rilevato: $ips"
$vm = Get-VMByIP -IP $ips -ErrorAction SilentlyContinue
If (!$vm){
	Write-Log "VM $vm non esiste controllare i parametri" "ERROR"
    Exit    
}
$vm

$vmnew = $vm.name + "OLD"
$Exists = get-vm -name $vmnew -ErrorAction SilentlyContinue
If ($Exists){
	Write-Log "VM $vmnew esiste" "ERROR"
    Exit
}


$DstServerPort = $DstServer + ":9443"
$DstServerPort
Write-Log "Richiesta token UAG su $DstServerPort"
if ($PSVersionTable.PSVersion.Major -ge 7) {
$token = Get-HRToken $DstServerPort $UagCred $tokenvalid
}
else {$token = Get-HRTokenPS5 $DstServerPort $UagCred $tokenvalid
}
if (-not $token) {
    Write-Log "Errore durante l'ottenimento del token UAG" "ERROR"
    exit 1
}
Write-Log "Token ottenuto correttamente"
$token
if ($verbose) {
Read-Host -Prompt "Press Enter to continue - EXPORT UAG CONFIGURATION"
}
Write-Log "Export configurazione UAG in formato INI"

if ($PSVersionTable.PSVersion.Major -ge 7) {

    Invoke-RestSafe -Method GET `
        -Uri "https://$DstServerPort/rest/v1/config/settings?format=INI" `
        -Headers @{ Authorization = "Bearer $token" } `
        -OutFile $PathINI

}
else {

    Invoke-WebRequest `
        -Uri "https://$DstServerPort/rest/v1/config/settings?format=INI" `
        -Headers @{ Authorization = "Bearer $token" } `
        -UseBasicParsing `
        -OutFile $PathINI
}

Write-Log "Configurazione esportata in $PathINI"


if ($verbose) { 
Read-Host -Prompt "Press Enter to continue - CHANGE VALUE"
}
# Percorsi file
$InputFile  = $PathValue
$ConfigFile = $PathINI
Write-Log "Applicazione valori da $PathValue a $PathINI"
FileIni -SourceFile $InputFile -TargetFile $PathINI -OverwriteExisting
Write-Log "Aggiornamento INI completato"
#Read Value
#$PathScript = "E:\OMNISSA\UAG\uagdeploy2506"
#E:\OMNISSA\UAG\uagdeploy2506\uagdeploy.ps1 -iniFile C:\Attimo\UAGAUTO.INI
if ($verbose) { 
Read-Host -Prompt "Press Enter to continue - RENAME OLD UAG"
}

if ($verbose) { 
Read-Host -Prompt "procedo con il rename di $vm"
}
if ($vm.PowerState -ne "PoweredOff") {
    Write-Host "VM $VMName accesa → spegnimento in corso..."
    Write-Log "VM $($vm.Name) accesa → spegnimento in corso" "WARN"

    Stop-VM -VM $vm -Confirm:$false

    do {
        Start-Sleep -Seconds 5
        $vm = Get-VM -Id $vm.Id
        Write-Log "Attendo spegnimento VM..." "DEBUG"
    } while ($vm.PowerState -ne "PoweredOff")
    Write-Log "VM spenta correttamente"
    Write-Host "VM $VMName spenta correttamente."
}
else {
    Write-Host "VM $VMName è già spenta."
    Write-Log "VM già spenta"
}


Set-VM -VM $vm -Name $vmnew -Confirm:$false
if ($verbose) { 
Read-Host -Prompt "Press Enter to continue - Deploy UAG"
}
Write-Log "Avvio deploy nuovo UAG"
& $PathScript\uagdeploy.ps1 -iniFile $PathINI -rootPwd $UagCred.GetNetworkCredential().Password -adminPwd $UagCred.GetNetworkCredential().Password -ceipEnabled "no"
Write-Log "Deploy UAG completato"
Disconnect-VIServer -Confirm:$false
Write-Log "Disconnessione da vCenter"
Write-Log "=== Script completato con successo ==="