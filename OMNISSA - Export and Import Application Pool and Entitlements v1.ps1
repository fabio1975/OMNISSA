# === LOGIN & TOKEN ===

function Get-HRToken {

    param([string]$Server, [string]$Domain, [string]$User, [string]$Password)

    $body = @{ domain=$Domain; username=$User; password=$Password } | ConvertTo-Json

    $uri  = "https://$Server/rest/login"   # POST /rest/login :contentReference[oaicite:0]{index=0}

    (Invoke-RestMethod -Method Post -Uri $uri -Body $body -ContentType 'application/json' `

                       -SkipCertificateCheck).access_token

}

 

# === UTILITY: rimuove campi read-only non clonabili ===

function Sanitize-Pool {

    param($Pool)

    $Pool | Select-Object * -ExcludeProperty id, avm_shortcut_id, global_application_entitlement_id

}

 

function Export-AppPoolsWithEntitlements {

    param(

        [string]$SrcServer,  [string]$Domain,

        [string]$User,       [string]$Password,

        [string]$OutFile

    )

 

    $token = Get-HRToken $SrcServer $Domain $User $Password

 

    # Lista completa dei pool (max 1000) – GET /inventory/v4/application-pools :contentReference[oaicite:1]{index=1}

    $pools = Invoke-RestMethod -Method Get `

              -Uri "https://$SrcServer/rest/inventory/v3/application-pools?size=1000" `

              -Headers @{Authorization="Bearer $token"} -SkipCertificateCheck

 

    $export = foreach ($p in $pools) {

        # Entitlement del singolo pool – GET /entitlements/v1/application-pools/{id} :contentReference[oaicite:2]{index=2}

        $ents = Invoke-RestMethod -Method Get `

                -Uri "https://$SrcServer/rest/entitlements/v1/application-pools/$($p.id)" `

                -Headers @{Authorization="Bearer $token"} -SkipCertificateCheck

 

        [PSCustomObject]@{

            pool         = Sanitize-Pool $p

            entitlements = $ents.ad_user_or_group_ids

        }

    }

 

    $export | ConvertTo-Json -Depth 15 | Out-File $OutFile -Encoding UTF8

    Write-Host "✓ Esportati $($export.Count) pool in $OutFile"

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

    Write-Host "Singolo item $item"

    $item.pool

    Read-Host -Prompt "Press Enter to continue"

        # 4.1  Crea il nuovo Application Pool – POST /inventory/v1/application-pools :contentReference[oaicite:3]{index=3}

        $bodyPool = $item.pool | ConvertTo-Json -Depth 15

        $newPool  = Invoke-RestMethod -Method Post `

                     -Uri "https://$DstServer/rest/inventory/v1/application-pools" `

                     -Headers @{Authorization="Bearer $token"} `

                     -ContentType 'application/json' -Body $bodyPool -SkipCertificateCheck

        Write-Host "Pool creato $newPool"

        $nomepool = $($item.pool.name)

        Write-Host "Nome del application $nomepool"

        $poolid = Invoke-RestMethod -Method Get `

                     -Uri "https://hcs01.pollaio.lan/rest/inventory/v1/application-pools?filter=%7B%0A%09%22type%22%3A%20%22Equals%22%2C%0A%09%22name%22%3A%20%22name%22%2C%0A%09%22value%22%3A%20%22$nomepool%22%0A%7D" `

                     -Headers @{Authorization="Bearer $token"} `

                     -ContentType 'application/json' -SkipCertificateCheck

        $poolid

        $poolid.id

 

    Read-Host -Prompt "Press Enter to continue"

        Write-Host "✓ Creato pool '$($item.pool.name)' (nuovo id $($poolid.id))"

 

        # 4.2  Ripristina entitlement (se presenti) – POST /entitlements/v1/application-pools (bulk) :contentReference[oaicite:4]{index=4}

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

 

            Write-Host "  └─► Entitlement ripristinati: $($item.entitlements.Count) SID - APP ID $($newPool.id)"

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

                -Uri "https://$DstServer/rest/inventory/v7/farms?filter=%7B%0A%09%22type%22%3A%20%22Equals%22%2C%0A%09%22name%22%3A%20%22name%22%2C%0A%09%22value%22%3A%20%22$FarmDest%22%0A%7D" `

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

$filterhashtable = [ordered]@{}

$filterhashtable.filters = @()

$userfilter= [ordered]@{}

$userfilter.add('type','Equals')

$userfilter.add('name','name')

$userfilter.add('value',$FarmSrc)

$filterhashtable.filters+=$userfilter

$filterflat = $filterhashtable | ConvertTo-Json -Compress

    $token = Get-HRToken $SrcServer $Domain $User $Password

    $FARMDETAILSRC = Invoke-RestMethod -Method Get `

               -Uri "https://$SrcServer/rest/inventory/v3/farms?$filterflat" `

                -Headers @{Authorization="Bearer $token"} `

                -ContentType 'application/json' -skipCertificateCheck

    Write-host $FARMDETAILSRC.id

}

######MAIN PROGRAM###

# Insert Source HCS

$SrcServer = Read-Host -Prompt "Insert Source HCS Server Name"

#$SrcServer = "hcs2111.pollaio.lan"

# Insert Dest HCS

$DstServer = Read-Host -Prompt "Insert Destination HCS Server Name"

#$DstServer = "hcs01.pollaio.lan"

#Insert Domain

$Domain = Read-Host -Prompt "Insert Domain Name (e.g. POLLAIO)"

#$Domain = "pollaio"

# Insert Path to JSON file

$JsonFile = Read-Host -Prompt "Insert Path to JSON file (e.g. c:\attimo\AppPoolsWithEntitlements.json)"

# Insert Credentials

$Credentials = Get-Credential -Message "Insert Domain Credentials for $SrcServer and $DstServer"

$Username = $Credentials.UserName

$Pass = $Credentials.GetNetworkCredential().Password

 

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

 

# --- IMPORT ---

Import-AppPoolsWithEntitlements `

    -DstServer $DstServer -Domain $Domain `

    -User $Username -Password $Pass -JsonFile $JsonFile