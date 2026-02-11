# Connessione a vCenter
$vCenter = Read-Host "Inserisci il nome del vCenter"
Connect-VIServer -Server $vCenter

# --- Selezioni via Out-GridView ---

$template = Get-Template |
    Out-GridView -Title "Seleziona il Template" -PassThru

$custSpecBase = Get-OSCustomizationSpec |
    Out-GridView -Title "Seleziona Guest Customization Spec (BASE)" -PassThru

$vmHost = Get-VMHost |
    Out-GridView -Title "Seleziona ESXi Host" -PassThru

$datastore = Get-Datastore -VMHost $vmHost |
    Out-GridView -Title "Seleziona Datastore" -PassThru

$portGroup = Get-VirtualPortGroup -VMHost $vmHost |
    Out-GridView -Title "Seleziona PortGroup (Standard Switch)" -PassThru

# --- Dati VM ---
$vmName = Read-Host "Inserisci il nome della VM"

# --- Configurazione IP ---
$ipAddress = Read-Host "Indirizzo IP"
$subnet    = Read-Host "Subnet Mask (es. 255.255.255.0)"
$gateway   = Read-Host "Gateway"
$dns       = Read-Host "DNS Server (separati da virgola)"

$dnsList = $dns -split ","

# --- Clonazione Customization Spec ---
$tempSpecName = "TMP-$vmName-$(Get-Random)"

Write-Host "Creo Customization Spec temporanea: $tempSpecName"

$tempSpec = New-OSCustomizationSpec `
    -Spec $custSpecBase `
    -Name $tempSpecName `
    -Type NonPersistent

# Impostazione IP statico
$nic = Get-OSCustomizationNicMapping -OSCustomizationSpec $tempSpec

Set-OSCustomizationNicMapping `
    -OSCustomizationNicMapping $nic `
    -IpMode UseStaticIP `
    -IpAddress $ipAddress `
    -SubnetMask $subnet `
    -DefaultGateway $gateway `
    -Dns $dnsList

# --- Riepilogo finale ---
$summary = [PSCustomObject]@{
    VMName        = $vmName
    Template      = $template.Name
    CustomSpec    = $tempSpecName
    VMHost        = $vmHost.Name
    Datastore     = $datastore.Name
    PortGroup     = $portGroup.Name
    IPAddress     = $ipAddress
}

$confirm = $summary |
    Out-GridView -Title "Riepilogo configurazione - OK per procedere?" -PassThru

if (-not $confirm) {
    Write-Warning "Operazione annullata dall'utente"
    Remove-OSCustomizationSpec -OSCustomizationSpec $tempSpec -Confirm:$false
    Disconnect-VIServer -Confirm:$false
    return
}

# --- Deploy VM ---
Write-Host "Deploy VM in corso..."

$vm = New-VM `
    -Name $vmName `
    -Template $template `
    -VMHost $vmHost `
    -Datastore $datastore `
    -OSCustomizationSpec $tempSpec

# Configurazione rete
Get-NetworkAdapter -VM $vm |
    Set-NetworkAdapter -PortGroup $portGroup -Confirm:$false

Write-Host "VM '$vmName' deployata correttamente" -ForegroundColor Green

# --- Cleanup ---
Remove-OSCustomizationSpec -OSCustomizationSpec $tempSpec -Confirm:$false
Disconnect-VIServer -Confirm:$false
