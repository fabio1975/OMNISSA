# Script per esportare e importare Application Pools e le loro entitlements da un HCS ad un altro.
# Si basa sulle API REST di Omnissa (HCS) e richiede le credenziali di un utente con privilegi di amministratore.
# Il file JSON esportato contiene i pool e le entitlements associate, che possono essere importati in un altro HCS.
# Le API utilizzate sono documentate nella sezione "API Reference" della documentazione di Omnissa. 
# https://developer.omnissa.com/horizon-apis/
# https://retouw.nl/2021/10/02/horizon-rest-api-powershell-7-paging-and-filtering-with-samples/
#Requires -Version 5.1
#Requires -Modules ActiveDirectory

[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
function Show-Menu
 {
            param (
            [string]$Title = 'Export/Import Application Pool'
            )
            cls
            Write-Host "================ $Title ================"
    
            Write-Host "1: Press '1' for set variabale"
            Write-Host "2: Press '2' for export application pool"
            Write-Host "3: Press '3' for import application pool"
            Write-Host "4: Press '4' for show application pool name on source Horizon POD"
            Write-Host "5: Press '5' for show the variable"
            Write-Host "Q: Press 'Q' to quit."
 }
# === LOGIN & TOKEN ===
function Get-HRToken {
    param([string]$Server, [string]$Domain, [string]$User, [string]$Password)
    $body = @{ domain=$Domain; username=$User; password=$Password } | ConvertTo-Json
    $uri  = "https://$Server/rest/login"   # POST /rest/login :contentReference[oaicite:0]{index=0}
    (Invoke-RestMethod -Method Post -Uri $uri -Body $body -ContentType 'application/json').access_token
}

# === UTILITY: remove read only value form application pool ===
function Sanitize-Pool {
    param($Pool)
    $Pool | Select-Object * -ExcludeProperty id, avm_shortcut_id, global_application_entitlement_id
}
function List-AppPools {
    param(
        [string]$SrcServer,  [string]$Domain,
        [string]$User,       [string]$Password,
        [string]$OutFile 
    )
    
    $token = Get-HRToken $SrcServer $Domain $User $Password

    # Export application pool list (max 1000) – GET /inventory/v4/application-pools :contentReference[oaicite:1]{index=1}
    $pools = Invoke-RestMethod -Method Get `
              -Uri "https://$SrcServer/rest/inventory/v3/application-pools?size=1000" `
              -Headers @{Authorization="Bearer $token"} 
    Write-Host "✓ Find $($pools.Count) pool on $SrcServer"
    foreach ($p in $pools) {
        Write-Host " - $($p.name)"
    }
}
function Export-AppPoolsWithEntitlements {
    param(
        [string]$SrcServer,  [string]$Domain,
        [string]$User,       [string]$Password,
        [string]$OutFile 
    )
    
    $token = Get-HRToken $SrcServer $Domain $User $Password

    # Export application pool list (max 1000) – GET /inventory/v4/application-pools :contentReference[oaicite:1]{index=1}
    $pools = Invoke-RestMethod -Method Get `
              -Uri "https://$SrcServer/rest/inventory/v3/application-pools?size=1000" `
              -Headers @{Authorization="Bearer $token"} 
    if ($appvalue -eq "ALL") {
    $export = foreach ($p in $pools) {
        # Entitlement all pool – GET /entitlements/v1/application-pools/{id} :contentReference[oaicite:2]{index=2}
        $ents = Invoke-RestMethod -Method Get `
                -Uri "https://$SrcServer/rest/entitlements/v1/application-pools/$($p.id)" `
                -Headers @{Authorization="Bearer $token"} 

        [PSCustomObject]@{
            pool         = Sanitize-Pool $p
            entitlements = $ents.ad_user_or_group_ids
        }
    }

   
    } else {
    $export = foreach ($p in $pools) {
        if ($p.name -eq $appvalue) {
        # Entitlement single pool – GET /entitlements/v1/application-pools/{id} :contentReference[oaicite:2]{index=2}
        $ents = Invoke-RestMethod -Method Get `
                -Uri "https://$SrcServer/rest/entitlements/v1/application-pools/$($p.id)" `
                -Headers @{Authorization="Bearer $token"} 

        [PSCustomObject]@{
            pool         = Sanitize-Pool $p
            entitlements = $ents.ad_user_or_group_ids
        }
    }
    }
  }
    $export | ConvertTo-Json -Depth 15 | Out-File $OutFile -Encoding UTF8
    Write-Host "✓ Exported $($export.Count) pool to $OutFile"
}




function Import-AppPoolsWithEntitlements {
    param(
        [string]$DstServer,  [string]$Domain,
        [string]$User,       [string]$Password,
        [string]$JsonFile 
    )

    $token = Get-HRToken $DstServer $Domain $User $Password
    $data  = Get-Content $JsonFile | ConvertFrom-Json

    foreach ($item in $data) {
    Write-Host "Single item $item"
    $item.pool
    Read-Host -Prompt "Press Enter to continue"
        $bodyPool = $item.pool | ConvertTo-Json -Depth 15
        $newPool  = Invoke-RestMethod -Method Post `
                     -Uri "https://$DstServer/rest/inventory/v1/application-pools" `
                     -Headers @{Authorization="Bearer $token"} `
                     -ContentType 'application/json' -Body $bodyPool 
        Write-Host "$newPool created"
        $nomepool = $($item.pool.name)
        Write-Host "Name of application pool - $nomepool"
        $poolid = Invoke-RestMethod -Method Get `
                     -Uri "https://$DstServer/rest/inventory/v1/application-pools?filter=%7B%0A%09%22type%22%3A%20%22Equals%22%2C%0A%09%22name%22%3A%20%22name%22%2C%0A%09%22value%22%3A%20%22$nomepool%22%0A%7D" `
                     -Headers @{Authorization="Bearer $token"} `
                     -ContentType 'application/json' 
        $poolid
        $poolid.id

    Read-Host -Prompt "Press Enter to continue"
        Write-Host "✓ Create pool '$($item.pool.name)' (new id $($poolid.id))"
        if ($item.entitlements.Count) {
            $Psobj=New-Object -Type psobject
            $Psobj | Add-Member -MemberType NoteProperty -Name "id" -Value $poolid.id -Force
            $Psobj | Add-Member -MemberType NoteProperty -Name "ad_user_or_group_ids" -Value $item.entitlements -Force
            $entSpec ="["
            $entSpec += $Psobj | ConvertTo-Json
            $entSpec += "]"
        
            Invoke-RestMethod -Method Post `
                -Uri "https://$DstServer/rest/entitlements/v1/application-pools" `
                -Headers @{Authorization="Bearer $token"} `
                -ContentType 'application/json' -Body $entSpec -SkipCertificateCheck

            Write-Host "  └─► Entitlement restored: $($item.entitlements.Count) SID - APP ID $($newPool.id)"
        }
    }
}
function DestListFarmsID {
    param(
        [string]$DstServer,  [string]$Domain,
        [string]$User,       [string]$Password,
        [string]$FarmDest
    )
    
    $token = Get-HRToken $DstServer $Domain $User $Password
    $FARMDETAILDST = Invoke-RestMethod -Method Get `
                     -Uri "https://$DstServer/rest/inventory/v1/farms?filter=%7B%0A%09%22type%22%3A%20%22Equals%22%2C%0A%09%22name%22%3A%20%22name%22%2C%0A%09%22value%22%3A%20%22$FarmDest%22%0A%7D" `
                     -Headers @{Authorization="Bearer $token"} `
                     -ContentType 'application/json' 
 
    Write-host $FARMDETAILDST.id
}

function SourceListFarmsID {
    param(
        [string]$SrcServer,  [string]$Domain,
        [string]$User,       [string]$Password,
        [string]$FarmSrc
    )


    $token = Get-HRToken $SrcServer $Domain $User $Password
  $FARMDETAILSRC = Invoke-RestMethod -Method Get -Uri "https://$SrcServer/rest/inventory/v3/farms?filter[name]=$FarmSrc" -Headers @{Authorization="Bearer $token"} -ContentType 'application/json'
    Write-host $FARMDETAILSRC.id
}
######MAIN PROGRAM###
do
{
    Show-Menu
    $choice = Read-Host "Enter your choice"
    switch ($choice)
    {
'1' {
    cls 
    Write-Host "You chose option 1"
# Insert Source HCS
$SrcServer = Read-Host -Prompt "Insert Source HCS Server Name (for ex. hsc2111.mydomain.lan)"
# Insert Dest HCS
$DstServer = Read-Host -Prompt "Insert Destination HCS Server Name (for ex. hsc2503.mydomain.lan)"
#Insert Domain
$Domain = Read-Host -Prompt "Insert Domain Name (ex. mydomain)"
# Insert Path to JSON file
$JsonFile = Read-Host -Prompt "Insert Path to JSON file (e.g. c:\temp\AppPoolsWithEntitlements.json)"
#Insert the export application
$appvalue = Read-Host -Prompt "Insert the application pool name or ALL for export all application pool"
# Insert Credentials 
$Credentials = Get-Credential -Message "Insert Domain Credentials for $SrcServer and $DstServer"
$Username = $Credentials.UserName
$Pass = $Credentials.GetNetworkCredential().Password
Read-Host -Prompt "Press Enter to continue"

break }

'2' { Write-Host "You chose option 2"
Import-Module ActiveDirectory
Import-Module Omnissa.Horizon.Helper
# --- EXPORT ---
Export-AppPoolsWithEntitlements `
    -SrcServer $SrcServer -Domain $Domain `
    -User $Username -Password $Pass -OutFile $JsonFile

#
$FarmSrc = Read-Host -Prompt "Insert Source Farm Name"
$SFARM=SourceListFarmsID `
     -SrcServer $SrcServer -Domain $Domain `
    -User $Username -Password $Pass -FarmSrc $FarmSrc 6>&1
$SFARM
$FarmDest = Read-Host -Prompt "Insert Destination Farm Name"
$DFARM=DestListFarmsID `
     -DstServer $DstServer -Domain $Domain `
    -User $Username -Password $Pass -FarmDest $FarmDest 6>&1
$DFARM
(Get-Content -Path $JsonFile) -replace "$($SFARM)", "$($DFARM)" | Set-Content -Path $JsonFile
Read-Host -Prompt "WARNING!! If you import the application in the same HCS change the Name and diplay name in the Json file.  Press Enter to continue"
Read-Host -Prompt "Press Enter to continue"
 break }
'3' { Write-Host "You chose option 3"
# --- IMPORT ---
Import-AppPoolsWithEntitlements `
    -DstServer $DstServer -Domain $Domain `
    -User $Username -Password $Pass -JsonFile $JsonFile
Read-Host -Prompt "Press Enter to continue"
break } 
'4' { Write-Host "You chose option 4"
# --- Show Application Pool Name on Source HCS ---
List-AppPools `
    -SrcServer $SrcServer -Domain $Domain `
    -User $Username -Password $Pass -OutFile $JsonFile
Read-Host -Prompt "Press Enter to continue"
break }
'5' { Write-Host "You chose option 5"
Write-host "Show variable"
write-host "Source Server $SrcServer"   
write-host "Destination Server $DstServer"
write-host "Domain $Domain"
write-host "User $Username"
write-host "Output File $JsonFile"
write-host "Application to export $Appvalue"
Read-Host -Prompt "Press Enter to continue"
break } 
######FINE SCRIPT
        'Q' { Write-Host "Exiting..."
              return }
        default { Write-Host "Invalid choice. Please try again." -ForegroundColor Red }
    }
}until ($choice -eq 'Q')



