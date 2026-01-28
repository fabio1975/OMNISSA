########INIZIO SCRIPT

#Script for export and import desktop pools with entitlements

#Requires -Version 5.1

#Requires -Modules ActiveDirectory

#The script permit to export and import desktop pools with entitlements from one Horizon server to another Horizon server

#The script use the REST API of Horizon server

#The script permit to modify some parameters of the desktop pools in a CSV file

#Function to get the token
#version 3.0  - 16092025 - Fabio Storni 
#Check certificati SSL generalizzato anche per Powershell pre 7.x
#Aggiunta gestione di desktop pool con nic differenti dalla gold image
#Aggiunto possibilit√† di clonare il dekstop pool e impostarlo come disable 


[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
function Show-Menu
 {
            param (
            [string]$Title = 'Export/Import Instant Clone Desktop Pool'
            )
            cls
            Write-Host "================ $Title ================"
    
            Write-Host "1: Press '1' for set variabale"
            Write-Host "2: Press '2' for export instant clone desktop pool settings"
            Write-Host "3: Press '3' for import instant clone desktop pool"
            Write-Host "4: Press '4' for show desktop pool name on source Horizon POD"
            Write-Host "5: Press '5' for create single desktop pool from json file"
            Write-Host "6: Press '6' to change desktop pool"
            Write-Host "Q: Press 'Q' to quit."
 }
function Get-HRToken {
    param([string]$Server, [string]$Domain, [string]$User, [string]$Password)
    $body = @{ domain=$Domain; username=$User; password=$Password } | ConvertTo-Json
    $uri  = "https://$Server/rest/login"   # POST /rest/login :contentReference[oaicite:0]{index=0}
    (Invoke-RestMethod -Method Post -Uri $uri -Body $body -ContentType 'application/json').access_token
}

#Function to export desktop pools with entitlements
function new-DesktopPools {
    param(
        [string]$DstServer,  [string]$Domain,
        [string]$User,       [string]$Password,
        [string]$JsonFile
    )
    $token = Get-HRToken $DstServer $Domain $User $Password
    $data  = Get-Content $JsonFile | ConvertFrom-Json
    foreach ($item in $data) {
        #Write-Host "Singolo item $item"
        $actualpool = Invoke-RestMethod -Method Get -Uri "https://$Server/rest/inventory/v8/desktop-pools?filter=%7B%0A%09%22type%22%3A%20%22Equals%22%2C%0A%09%22name%22%3A%20%22name%22%2C%0A%09%22value%22%3A%20%22$($item.pool.name)%22%0A%7D" -Headers @{Authorization="Bearer $token"}  -ContentType 'application/json' 
        if ($actualpool) {
            Write-Host "Il pool '$($item.pool.name)' esiste gi‡† sul server di destinazione. Viene saltato." -ForegroundColor Yellow
            continue
        } else {
            Write-Host "Il pool '$($item.pool.name)' non esiste sul server di destinazione. Viene creato." -ForegroundColor Green
            #$item.pool
            Read-Host -Prompt "Press Enter to continue"
            # 4.1  Crea il nuovo Application Pool  POST /inventory/v1/application-pools :contentReference[oaicite:3]{index=3}
            $bodyPool = $item.pool | ConvertTo-Json -Depth 15
            $newPool  = Invoke-RestMethod -Method Post -Uri "https://$Server/rest/inventory/v8/desktop-pools" -Headers @{Authorization="Bearer $token"}  -ContentType 'application/json' -Body $bodyPool 
            Write-Host "Pool creato $newPool"
        }
    }
}   
function Export-DesktopPoolsList {
    param(
        [string]$SrcServer,  [string]$Domain,
        [string]$User,       [string]$Password
    )
    $token = Get-HRToken $SrcServer $Domain $User $Password
    $pools = Invoke-RestMethod -Method Get -Uri "https://$SrcServer/rest/inventory/v8/desktop-pools" -Headers @{Authorization="Bearer $token"} 
    return $pools
}
function Export-DesktopPoolsWithEntitlements {

    param(

        [string]$SrcServer,  [string]$Domain,

        [string]$User,       [string]$Password,

        [string]$OutFile,    [string]$poolname

    )

    $token = Get-HRToken $SrcServer $Domain $User $Password

    $pools = Invoke-RestMethod -Method Get -Uri "https://$SrcServer/rest/inventory/v8/desktop-pools" -Headers @{Authorization="Bearer $token"} 
    write-host "Sono $($pools.Count) pool"
    write-host "$($pools)"
    Read-Host -Prompt "Press Enter to continue"
    if ($poolname -eq "ALL") {

       $export = foreach ($p in $pools) {
        if ($p.source -ne "INSTANT_CLONE") {
            Write-Host "‚ùå Il pool $($p.name) non Ë di tipo Instant Clone. Viene saltato." -ForegroundColor Yellow
            continue
        } else {
        # Entitlement del singolo pool ‚Äì GET /entitlements/v1/application-pools/{id} :contentReference[oaicite:2]{index=2}
        Write-Host "Il pool $($p.name) √® di tipo Instant Clone. Viene esportato." -ForegroundColor Green
        $ents = Invoke-RestMethod -Method Get -Uri "https://$SrcServer/rest/entitlements/v1/desktop-pools/$($p.id)"-Headers @{Authorization="Bearer $token"} 

 

        [PSCustomObject]@{

            pool         = $p

            entitlements = $ents.ad_user_or_group_ids

        }
      }
     }

     $export | ConvertTo-Json -Depth 15 | Out-File $OutFile -Encoding UTF8

     Write-Host "Esportati $($export.Count) pool in $OutFile"

    return $true

    } else {  

    $singlepool = $pools | Where-Object { $_.name -eq $poolname }
    write-host "Sono solo $($singlepool.name)"
    Read-Host -Prompt "Press Enter to continue"

    if ($singlepool -ne "" ) {

       if ($singlepool.source -ne "INSTANT_CLONE") {
            Write-Host "Il pool $($singlepool.name) non Ë di tipo Instant Clone. Viene saltato." -ForegroundColor Yellow
        } else {
        # Entitlement del singolo pool  GET /entitlements/v1/application-pools/{id} :contentReference[oaicite:2]{index=2}
        Write-Host "Il pool $($singlepool.name) Ë di tipo Instant Clone. Viene esportato." -ForegroundColor Green
        write-host "Pool ID $($singlepool.id)"
        Read-Host -Prompt "Press Enter to continue"
        $ents = Invoke-RestMethod -Method Get -Uri "https://$SrcServer/rest/entitlements/v1/desktop-pools/$($singlepool.id)" -Headers @{Authorization="Bearer $token"} 
        $singlepool.poolname
        $exportdata = @{
            pool         = $singlepool
            entitlements = $ents.ad_user_or_group_ids
        }
     } 
     $export = [pscustomobject]$exportdata
    write-host "Sono $($export) pool esportati"
    Read-Host -Prompt "Press Enter to continue"
    $export | ConvertTo-Json -Depth 15 | Out-File $OutFile -Encoding UTF8

    Write-Host "Esportati un pool in $OutFile"

    return $true
      
    }
    } else {

        Write-Host "Desktop pool non trovato" -ForegroundColor Red

        return $false
    }
   }

#function to get base vm id

function Get-BaseVMID {

    param(

        [string]$DstServer,  [string]$Domain,

        [string]$User,       [string]$Password,

        [string]$vcenterId

    )

 

    $token = Get-HRToken $DstServer $Domain $User $Password

    $basevm = Invoke-RestMethod -Method Get -Uri "https://$DstServer/rest/external/v2/base-vms?vcenter_id=$vcenterId" -Headers @{Authorization="Bearer $token"} 

      return $basevm

   

}

function Get-NetworkID {

    param(

        [string]$DstServer,  [string]$Domain,

        [string]$User,       [string]$Password,

        [string]$vcenterId,  [string]$basevmId,

        [string]$snapshotId

    )

 

    $token = Get-HRToken $DstServer $Domain $User $Password

    $networkID = Invoke-RestMethod -Method Get -Uri "https://$DstServer/rest/external/v1/network-interface-cards?vcenter_id=$vcenterId&base_vm_id=$basevmId&base_snapshot_id=$snapshotId" -Headers @{Authorization="Bearer $token"} 

      return $networkID

   

}

#function to get ic domain account

function Get-ICdomainAccount {

    param(

        [string]$DstServer,  [string]$Domain,

        [string]$User,       [string]$Password

    )

 

    $token = Get-HRToken $DstServer $Domain $User $Password

    $icaccount = Invoke-RestMethod -Method Get -Uri "https://$DstServer/rest/config/v1/ic-domain-accounts"  -Headers @{Authorization="Bearer $token"} 

 

        return $icaccount

}


#function to get vcenter id

function Get-vCenterID {

    param(

        [string]$DstServer,  [string]$Domain,

        [string]$User,       [string]$Password

    )

 

    $token = Get-HRToken $DstServer $Domain $User $Password

    $group = Invoke-RestMethod -Method Get -Uri "https://$DstServer/rest/config/v2/virtual-centers"  -Headers @{Authorization="Bearer $token"} 

    if ($group.Count -eq 1) {

        return $group.id

    } else {

        Write-Host "Gruppo di accesso non trovato o non univoco!" -ForegroundColor Red

        return $null

    }

}

#function to get access group id

function Get-AccessGroupID {

    param(

        [string]$DstServer,  [string]$Domain,

        [string]$User,       [string]$Password

    )

 

    $token = Get-HRToken $DstServer $Domain $User $Password

    $group = Invoke-RestMethod -Method Get -Uri "https://$DstServer/rest/config/v2/local-access-groups" -Headers @{Authorization="Bearer $token"} 

    if ($group.Count -eq 1) {

        return $group.id

    } else {

        Write-Host "Gruppo di accesso non trovato o non univoco!" -ForegroundColor Red

        return $null

    }

}

##Funzione di creazione desktop pool

function Import-DesktopPoolsWithEntitlements {

    param(

        [string]$DstServer,  [string]$Domain,

        [string]$User,       [string]$Password,

        [string]$JsonFile

    )

 

    $token = Get-HRToken $DstServer $Domain $User $Password

    $data  = Get-Content $JsonFile | ConvertFrom-Json

    

    foreach ($item in $data) {

    #Write-Host "Singolo item $item"

    $actualpool = Invoke-RestMethod -Method Get -Uri "https://$DstServer/rest/inventory/v8/desktop-pools?filter=%7B%0A%09%22type%22%3A%20%22Equals%22%2C%0A%09%22name%22%3A%20%22name%22%2C%0A%09%22value%22%3A%20%22$($item.pool.name)%22%0A%7D" -Headers @{Authorization="Bearer $token"}  -ContentType 'application/json' 

    if ($actualpool) {

        Write-Host "Il pool '$($item.pool.name)' esiste gi‡† sul server di destinazione. Viene saltato." -ForegroundColor Yellow

        continue

    } else {

        Write-Host "Il pool '$($item.pool.name)' non esiste sul server di destinazione. Viene creato." -ForegroundColor Green

    
    #$item.pool

    Read-Host -Prompt "Press Enter to continue"

        # 4.1  Crea il nuovo Application Pool ‚Äì POST /inventory/v1/application-pools :contentReference[oaicite:3]{index=3}

        $bodyPool = $item.pool | ConvertTo-Json -Depth 15

      
        $newPool  = Invoke-RestMethod -Method Post -Uri "https://$DstServer/rest/inventory/v8/desktop-pools" -Headers @{Authorization="Bearer $token"}  -ContentType 'application/json' -Body $bodyPool 

        Write-Host "Pool creato $newPool"

        $nomepool = $($item.pool.name)

        Write-Host "Nome del desktop $nomepool"

        $poolid = Invoke-RestMethod -Method Get -Uri "https://$DstServer/rest/inventory/v8/desktop-pools?filter=%7B%0A%09%22type%22%3A%20%22Equals%22%2C%0A%09%22name%22%3A%20%22name%22%2C%0A%09%22value%22%3A%20%22$nomepool%22%0A%7D" -Headers @{Authorization="Bearer $token"}  -ContentType 'application/json' 

     #   $poolid

      #  $poolid.id

 

    Read-Host -Prompt "Press Enter to continue"

        Write-Host "Creato pool '$($item.pool.name)' (nuovo id $($poolid.id))"

 

        # 4.2  Ripristina entitlement (se presenti)  POST /entitlements/v1/application-pools (bulk) :contentReference[oaicite:4]{index=4}

        if ($item.entitlements.Count) {

            $Psobj=New-Object -Type psobject

            $Psobj | Add-Member -MemberType NoteProperty -Name "id" -Value $poolid.id -Force

            $Psobj | Add-Member -MemberType NoteProperty -Name "ad_user_or_group_ids" -Value $item.entitlements -Force

            $entSpec ="["

            $entSpec += $Psobj | ConvertTo-Json

            $entSpec += "]"

       

            Invoke-RestMethod -Method Post -Uri "https://$DstServer/rest/entitlements/v1/desktop-pools" -Headers @{Authorization="Bearer $token"} -ContentType 'application/json' -Body $entSpec 


            Write-Host "Entitlement ripristinati: $($item.entitlements.Count) SID - APP ID $($newPool.id)"

        }

    }
  }
}

do
{
    Show-Menu
    $choice = Read-Host "Enter your choice"
    switch ($choice)
    {
        '1' {
            cls 
            Write-Host "You chose option 1"
            $settings = Read-Host "Change default value? (Y/N)"  
            If ($settings -ne "Y") { 
            #Input parameters
            $SrcServer = "horizon1.internet.lan"
            $DstServer = "horizon5.internet.lan"
            $Domain = "internet.lan"
            $User = "fstorni"
            $PasswordSec = Read-Host -AsSecureString "Password"
            #$Password =
            $OutFile = "C:\temp\horizon_desktop_pools.json"
            $poolvalue = Read-Host -Prompt "Insert the pool name to export or ALL for all pool"
            } else {
            $SrcServer = Read-Host "Insert Source Connection Server"
            $DstServer = Read-Host "Insert Target Connection Server"
            $Domain = Read-Host "Insert FQDN domain"
            $User = Read-Host "Insert Connection Server admin username"
            $PasswordSec = Read-Host -AsSecureString "Password"
            $OutFile = "C:\temp\horizon_desktop_pools.json"
            $poolvalue = Read-Host -Prompt "Insert the pool name to export or ALL for all pool"
            }
write-host "Questi sono i valori inseriti"
write-host "Source Server $SrcServer"   
write-host "Destination Server $DstServer"
write-host "Domain $Domain"
write-host "User $User"
write-host "Output File $OutFile"
write-host "Pool to export $poolvalue"
$Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($PasswordSec))

Read-Host -Prompt "Press Enter to continue"

break }
 
'2' { Write-Host "You chose option 2"
             
Import-Module ActiveDirectory

Import-Module Omnissa.Horizon.Helper

#Export desktop pools with entitlements

$checkd = Export-DesktopPoolsWithEntitlements -SrcServer $SrcServer -Domain $Domain -User $User -Password $Password -OutFile $OutFile -poolname $poolvalue

if ($checkd -eq $false) {

    Write-Host "Errore nell'esportazione dei pool desktop. Uscita dallo script." -ForegroundColor Red

    exit

}

#Export the json file to csv file for check and modify some value
$destAccessGroupID = Get-AccessGroupID -DstServer $DstServer -Domain $Domain -User $User -Password $Password

$destvCenterID = Get-vCenterID -DstServer $DstServer -Domain $Domain -User $User -Password $Password

$basevm = Get-BaseVMID -DstServer $DstServer -Domain $Domain -User $User -Password $Password -vcenterId $destvCenterID

$idaccout = Get-ICdomainAccount -DstServer $DstServer -Domain $Domain -User $User -Password $Password


Write-Host "Accessgroup $destAccessGroupID"

Write-host "Vcenter ID $destvCenterID"

Write-host "BaseVM $basevm"

Write-Host "Domain Account $idaccout"

$data  = Get-Content $OutFile | ConvertFrom-Json

$checkvalue = foreach ($dpoll in $data.pool) {
       
       #$netID = Get-NetworkID -DstServer $DstServer -Domain $Domain -User $User -Password $Password -vcenterId $destvCenterID -basevmId $dpoll.provisioning_settings.parent_vm_id -snapshotId $dpoll.provisioning_settings.base_snapshot_id
       $netID = Get-NetworkID -DstServer $DstServer -Domain $Domain -User $User -Password $Password -vcenterId $destvCenterID -basevmId $dpoll.provisioning_settings.parent_vm_id 

      [PSCustomObject]@{

            poolname = $dpoll.name

            pooldisplayname = $dpoll.display_name

            poolvmname = $dpoll.pattern_naming_settings.naming_pattern

            statuspool = $dpoll.enabled

            provisioning = $dpoll.enable_provisioning

            parentvm = $dpoll.provisioning_settings.parent_vm_id

            snapshot = $dpoll.provisioning_settings.base_snapshot_id

            accessgroupid = $destAccessGroupID

            vcenterid = $destvCenterID

            userid = $idaccout.id

            networkid = $netID.id
            

        }

}  

$checkvalue | export-csv -Path "C:\temp\horizon_checkvalue.csv" -NoTypeInformation -Encoding UTF8
Read-Host -Prompt "Press Enter to continue"
 break }
'3' { Write-Host "You chose option 3"
            

###pause for check and modify csv file

Read-Host -Prompt "Press Enter to continue"

### Change the value on json file with csv file

$csv =  Import-Csv -Path "C:\temp\horizon_checkvalue.csv"

$csv

$json = Get-Content $OutFile -Raw | ConvertFrom-Json

$json

 

$outputPath = "C:\temp\dati_modificati.json"

 

# Per ogni riga del CSV

foreach ($row in $csv) {

    # Trova l'oggetto JSON con la stessa chiave

    $obj = $json | Where-Object { $_.pool.name -eq $row.poolname }

    if ($obj.pool.nics) {

        # Aggiorna i campi (prendendo i nomi delle colonne dal CSV)

        foreach ($col in $row.PSObject.Properties.Name) {

            if ($col -ne "Key") {

                $obj.pool.name = $row.poolname

                $obj.pool.display_name = $row.pooldisplayname

                $obj.pool.pattern_naming_settings.naming_pattern = $row.poolvmname

                $obj.pool.enable_provisioning = [bool]::Parse($row.provisioning)

                $obj.pool.access_group_id = $row.accessgroupid

                $obj.pool.vcenter_id = $row.vcenterid

                $obj.pool.customization_settings.instant_clone_domain_account_id = $row.userid

                $obj.pool.nics | % { $_.network_interface_card_id = $row.networkid }
                $obj.pool.enabled = [bool]::Parse($row.statuspool)


            }

        }

    } else {


        # Aggiorna i campi (prendendo i nomi delle colonne dal CSV)

        foreach ($col in $row.PSObject.Properties.Name) {

            if ($col -ne "Key") {

                $obj.pool.name = $row.poolname

                $obj.pool.display_name = $row.pooldisplayname

                $obj.pool.pattern_naming_settings.naming_pattern = $row.poolvmname

                $obj.pool.enable_provisioning = [bool]::Parse($row.provisioning)

                $obj.pool.access_group_id = $row.accessgroupid

                $obj.pool.vcenter_id = $row.vcenterid

                $obj.pool.customization_settings.instant_clone_domain_account_id = $row.userid

              #  $obj.pool.nics | % { $_.network_interface_card_id = $row.networkid }
                $obj.pool.enabled = [bool]::Parse($row.statuspool)


            }

        }


    }

}

 

# Salva il JSON aggiornato

$json | ConvertTo-Json -Depth 10 | Out-File $outputPath -Encoding UTF8

 

#import desktop pools with entitlements

Import-DesktopPoolsWithEntitlements -DstServer $DstServer -Domain $Domain -User $User -Password $Password -JsonFile $outputPath
Read-Host -Prompt "Press Enter to continue"
break }
'4' { Write-Host "You chose option 4"
            #Show desktop pool name on source horizon pod
            Import-Module Omnissa.Horizon.Helper

            $pools = Export-DesktopPoolsList -SrcServer $SrcServer -Domain $Domain -User $User -Password $Password
            write-host "Sono $($pools.Count) pool"
            foreach ($p in $pools) {
                if ($p.source -ne "INSTANT_CLONE") {
                    Write-Host "Il pool $($p.name) non √® di tipo Instant Clone." -ForegroundColor Yellow
                    continue
                } else {
                # Entitlement del singolo pool ‚Äì GET /entitlements/v1/application-pools/{id} :contentReference[oaicite:2]{index=2}
                Write-Host "Il pool $($p.name) √® di tipo Instant Clone." -ForegroundColor Green
                }
            }
            Read-Host -Prompt "Press Enter to continue"
            break }
'5' { Write-Host "You chose option 5"
            #Create single desktop pool from json file  
            $Server = Read-Host -Prompt "Insert the horizon server name"
            $Filejson = Read-Host -Prompt "Insert the json file path"
            $Newpool = new-DesktopPools -DstServer $Server -Domain $Domain -User $User -Password $Password -JsonFile $Filejson
            write-host "Creazione del desktop pool $($Newpool.name) da file json $filejson sul server $server"
            Read-Host -Prompt "Press Enter to continue"
           break } 
'6' { Write-Host "You chose option 6"
            #change Desktop pool  
            $poolvalue  = Read-Host -Prompt "Insert the desktop pool name"
            write-host "Lavoro  sul  desktop pool $poolvalue"
            Read-Host -Prompt "Press Enter to continue"
           break } 
######FINE SCRIPT
        'Q' { Write-Host "Exiting..."
              return }
        default { Write-Host "Invalid choice. Please try again." -ForegroundColor Red }
    }
} until ($choice -eq 'Q')