param (
    [Parameter(Mandatory=$true)]
    [string]$RemoteServer,          # Nome o IP del server remoto
    [Parameter(Mandatory=$true)]
    [string]$SourceInstallerPath,   # Percorso locale dell'EXE di Horizon Connection Server
    [Parameter(Mandatory=$true)]
    [ValidateSet("Normal", "Replica")]
    [string]$ServerType,            # Tipo di server da installare
    [Parameter(Mandatory=$false)]
    [string]$MasterServer    # Nome del master server se Replica
)

# Percorsi remoti
$RemotePath = "C:\Temp"
$RemoteInstaller = Join-Path $RemotePath (Split-Path $SourceInstallerPath -Leaf)
$RemoteBat = Join-Path $RemotePath "InstallHorizon.bat"
$LogFile = Join-Path $RemotePath "HorizonInstall.log"

try {
    # Creazione sessione remota
    $Session = New-PSSession -ComputerName $RemoteServer
    Write-Host "[INFO] Sessione PowerShell Remoting creata con $RemoteServer"
} catch {
    Write-Error "[ERRORE] Impossibile creare sessione remota: $_"
    exit 1
}

try {
    # Creazione cartella remota
    Invoke-Command -Session $Session -ScriptBlock {
        param($RemotePath)
        if (-not (Test-Path $RemotePath)) {
            New-Item -Path $RemotePath -ItemType Directory | Out-Null
        }
    } -ArgumentList $RemotePath
    Write-Host "[INFO] Cartella remota creata: $RemotePath"
} catch {
    Write-Error "[ERRORE] Impossibile creare cartella remota: $_"
    Remove-PSSession $Session
    exit 1
}

try {
    # Verifica se il file esiste già sul server remoto
    $FileExists = Invoke-Command -Session $Session -ScriptBlock {
        param ($DestPath)
        Test-Path -Path $DestPath
    } -ArgumentList $RemoteInstaller

    if ($FileExists) {
        Write-Host "[INFO] Installer già presente in $RemoteInstaller. Copia non necessaria."
    } else {
        # Copia installer EXE sul server remoto
        Copy-Item -Path $SourceInstallerPath -Destination $RemoteInstaller -ToSession $Session
        Write-Host "[INFO] Installer copiato su $RemoteInstaller"
    }

} catch {
    Write-Error "[ERRORE] Copia installer fallita: $_"
    Remove-PSSession $Session
    exit 1
}

# Creazione BAT unattended con comandi reali VMware
if ($ServerType -eq "Normal") {
    $InstallCommand = "`"$RemoteInstaller`" /s /v`"/qn VDM_SERVER_INSTANCE_TYPE=1 REBOOT=ReallySuppress VDM_INITIAL_ADMIN_SID=S-1-5-32-544 VDM_SERVER_RECOVERY_PWD=mini VDM_SERVER_RECOVERY_PWD_REMINDER=`"First car`"`""
} elseif ($ServerType -eq "Replica") {
    if ([string]::IsNullOrEmpty($MasterServer)) {
        Write-Error "[ERRORE] Master server non specificato per replica."
        Remove-PSSession $Session
        exit 1
    }
    $InstallCommand = "`"$RemoteInstaller`"/s /v`"/qn VDM_SERVER_INSTANCE_TYPE=2 VDM_INITIAL_ADMIN_SID=S-1-5-32-544 VDM_FIPS_ENABLED=0 ADAM_PRIMARY_NAME=$MasterServer`""
}

$BatContent = @"
@echo off
REM Horizon Connection Server Unattended Install
REM Tipo: $ServerType
REM Log file: $LogFile

echo Avvio installazione >> $LogFile
$InstallCommand >> $LogFile 2>&1
IF %ERRORLEVEL% NEQ 0 (
    echo [ERRORE] Installazione fallita con codice %ERRORLEVEL% >> $LogFile
    exit /B %ERRORLEVEL%
) ELSE (
    echo [INFO] Installazione completata correttamente >> $LogFile
)
exit /B 0
"@

# Salvataggio BAT localmente
$LocalBat = ".\InstallHorizon.bat"
$BatContent | Set-Content -Path $LocalBat -Encoding ASCII

try {
    # Copia BAT sul server remoto
    Copy-Item -Path $LocalBat -Destination $RemoteBat -ToSession $Session -Force
    Write-Host "[INFO] File BAT copiato su $RemoteBat"
} catch {
    Write-Error "[ERRORE] Copia BAT fallita: $_"
    Remove-PSSession $Session
    exit 1
}
if ($ServerType -eq "Normal") {
try {
    # Esecuzione BAT con diritti amministrativi sul server remoto
    Invoke-Command -Session $Session -ScriptBlock {
        param($BatPath)
        Start-Process -FilePath $BatPath -Verb RunAs -Wait
    } -ArgumentList $RemoteBat
    Write-Host "[INFO] Installazione avviata su $RemoteServer. Controllare log: $LogFile"
} catch {
    Write-Error "[ERRORE] Avvio installazione fallito: $_"
    Remove-PSSession $Session
    exit 1
}
} elseif ($ServerType -eq "Replica") {
try {
    Invoke-Command -Session $Session -ScriptBlock {
    schtasks /create `
  /tn "HorizonInstall" `
  /tr "C:\Windows\System32\cmd.exe /c ""C:\Temp\InstallHorizon.bat""" `
  /sc once `
  /st 23:59 `
  /ru pollaio\Administrator `
  /rp "Luca2008!Luca2008!" `
  /rl HIGHEST `
  /f
        }
    Write-Host "[INFO] Installato task su $RemoteServer. Controllare log: $LogFile"
    Read-Host "Premi INVIO per continuare"
    Write-Host "[INFO] Avvio task su $RemoteServer. Controllare log: $LogFile"
    Invoke-Command -Session $Session -ScriptBlock {
         schtasks /run /tn "HorizonInstall"
         }
    Write-Host "[INFO] Task terminato su $RemoteServer. Controllare log: $LogFile"
    Read-Host "Premi INVIO per continuare"
    Write-Host "[INFO] Rimuovo task su $RemoteServer. Controllare log: $LogFile"
    Invoke-Command -Session $Session -ScriptBlock {
         Unregister-ScheduledTask -TaskName "HorizonInstall" -Confirm:$false
         }
}catch {
    Write-Error "[ERRORE] Avvio installazione fallito: $_"
    Remove-PSSession $Session
    exit 1
    }
}


