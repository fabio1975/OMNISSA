param(
    [int]$Port,
    [switch]$ListenOnly,
    [string]$ExportCsv
)

# Recupera connessioni TCP
if ($ListenOnly) {
    $tcpConnections = Get-NetTCPConnection -State Listen
}
else {
    $tcpConnections = Get-NetTCPConnection
}

# Filtro porta se specificata
if ($Port) {
    $tcpConnections = $tcpConnections | Where-Object {
        $_.LocalPort -eq $Port -or $_.RemotePort -eq $Port
    }
}

$result = foreach ($conn in $tcpConnections) {

    try {
        $process = Get-Process -Id $conn.OwningProcess -ErrorAction Stop
        $processName = $process.ProcessName
        $processPath = $process.Path
    }
    catch {
        $processName = "AccessDenied/Terminated"
        $processPath = "N/A"
    }

    [PSCustomObject]@{
        LocalAddress  = $conn.LocalAddress
        LocalPort     = $conn.LocalPort
        RemoteAddress = $conn.RemoteAddress
        RemotePort    = $conn.RemotePort
        State         = $conn.State
        ProcessName   = $processName
        ProcessPath   = $processPath
        PID           = $conn.OwningProcess
    }
}

$result = $result | Sort-Object LocalPort

if ($ExportCsv) {
    $result | Export-Csv -Path $ExportCsv -NoTypeInformation -Encoding UTF8
    Write-Host "Esportazione completata in $ExportCsv"
}
else {
    $result
}
