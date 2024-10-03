###
### PowerShell CRL Monitor v1.0.0
###

Import-Module PSPKI # PowerShell PKI Module is required (https://www.pkisolutions.com/tools/pspki/).

# Destination folder path.
$DestinationFolder = "C:\PS-CRL-Monitor"

##
## Set CDPs (CRL Distribution Points) URLs and threshold values of expiration days.
##

$CDPs = @(
    [pscustomobject]@{URL='http://pki.domain.org/RootCA.crl'; ThresholdDays='45'}
    [pscustomobject]@{URL='http://pki.domain.org/IssuingCA01.crl'; ThresholdDays='5'}
    [pscustomobject]@{URL='http://pki.domain.org/IssuingCA02.crl'; ThresholdDays='5'}
)

##
## Set Send-MailMessage parameters.
##

$sendMailMessageSplat = @{
    From = 'CRL Monitor <crlmonitor@domain.org>'
    #ReplyTo = 'pkiteam@domain.org'
    To = 'pkiteam@domain.org'
    Cc = 'servicedesk@domain.org'
    #Bcc = 'itmanager@domain.org'

    Priority = 'High'
    
    # SMTP Server settings
    SmtpServer = 'smtp.domain.org'
    Port = '587'
    UseSsl = $true
    # SMTP credentials is stored in a separate file, see below.
}

# SMTP Server credentials file path.
$SMTPCredentialsFile = "$DestinationFolder\SMTP.cred"

# Log file path.
$LogFilesPath = "$DestinationFolder\Logs"
$Logfile = "$LogFilesPath\CRLMon.log"

# Log function.
Function WriteLog
{
    Param ([string]$LogString)
    $Stamp = (Get-Date).toString("yyyy-MM-dd HH:mm:ss")
    $LogMessage = "$Stamp - $LogString"
    Add-content $LogFile -value $LogMessage
}

# Log rotation
Function Rotate-Logs {
    $maxLogSizeMB = 1
    if ((Get-Item $Logfile).Length -gt ($maxLogSizeMB * 1MB)) {
        $ArchiveName = "$LogFilesPath\CRLMon_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        Move-Item -Path $Logfile -Destination $ArchiveName
        New-Item -Path $Logfile -ItemType File
        WriteLog "Log rotated. Archived to $ArchiveName"
        WriteLog
    }
}

# Ensure the destination folder exists.
If (-not (Test-Path $DestinationFolder)) {
    New-Item -Path $DestinationFolder -ItemType Directory
}

# Ensure the log files folder exists.
If (-not (Test-Path $LogFilesPath)) {
    New-Item -Path $LogFilesPath -ItemType Directory
    WriteLog "Log files folder is missing. - Created: $LogFilesPath"
    WriteLog
}

# Test-CommandExists function.
Function Test-CommandExists
{
    Param ($command)
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = ‘stop’
    try {if(Get-Command $command){RETURN $true}}
    Catch {RETURN $false}
    Finally {$ErrorActionPreference=$oldPreference}
}

# Check if Get-CertificateRevocationList command is installed.
If (-not (Test-CommandExists Get-CertificateRevocationList)) {
    Write-Host “Get-CertificateRevocationList command is missing - Please, install PowerShell PKI Module (https://www.pkisolutions.com/tools/pspki/).”
    WriteLog “Get-CertificateRevocationList command is missing - Please install PowerShell PKI Module (https://www.pkisolutions.com/tools/pspki/).”
    WriteLog
    Exit 1
}

# Ensure the CRLs folder exists.
If (-not (Test-Path $DestinationFolder\CRLs)) {
    New-Item -Path $DestinationFolder\CRLs -ItemType Directory
    WriteLog "CRLs folder is missing. - Created: $DestinationFolder\CRLs"
    WriteLog
}

# Check if SMTP Server credential file is created otherwise create one.
If (-not (Test-Path $SMTPCredentialsFile)) {
    Write-Host "Credential file is missing. Creating: $SMTPCredentialsFile"
    WriteLog "Credential file is missing. Creating: $SMTPCredentialsFile"
    WriteLog

    Get-Credential | Export-Clixml -Path $SMTPCredentialsFile -Force
    $SMTPCredentials = Import-Clixml -Path $SMTPCredentialsFile
}
Else {
    $SMTPCredentials = Import-Clixml -Path $SMTPCredentialsFile
}

# Download each CRL and check their expiration dates. 
ForEach($CRL in $CDPs)
{
    $CRLUrl = $CRL.URL
    $CRLExpirationThreshold = $CRL.ThresholdDays

    $FileName = [System.IO.Path]::GetFileName($CRLUrl)  # Extract file name from URL.
    $CRLDestinationPath = Join-Path -Path $DestinationFolder\CRLs -ChildPath $FileName
    
    Invoke-WebRequest -Uri $CRLUrl -OutFile $CRLDestinationPath -ErrorVariable DownloadError -ErrorAction Continue

    If ($DownloadError.Count -gt 0) {
        $ErrorMessage = "Download failed - $CRLUrl"
        Write-Host $ErrorMessage
        WriteLog $ErrorMessage
        Try { Send-MailMessage @sendMailMessageSplat -Subject "CRL Download failed: $FileName" -Body "$ErrorMessage" -Credential $SMTPCredentials -ErrorAction Continue; }
        Catch { Write-Host "Send-MailMessage failed - $CRLUrl"; WriteLog "Send-MailMessage failed - $CRLUrl"; }
        WriteLog
    }

    Else {
        $GetCRL = Get-CertificateRevocationList $CRLDestinationPath
        $CRLThumbprint = $GetCRL.Thumbprint
        $CRLExpiration = ($GetCRL.NextUpdate) - (Get-Date)
        $CRLExpirationDays = $CRLExpiration.Days
        $CRLExpirationDate = ($GetCRL.NextUpdate).toString("yyyy-MM-dd HH:mm")

        If($CRLThumbprint -le 0) {
            $ErrorMessage =  "Failed to parse CRL - $CRLUrl"
            Write-Host $ErrorMessage
            WriteLog $ErrorMessage
            Try { Send-MailMessage @sendMailMessageSplat -Subject "CRL Error: $FileName" -Body "$ErrorMessage" -Credential $SMTPCredentials -ErrorAction Continue; }
            Catch { Write-Host "Send-MailMessage failed - $CRLUrl"; WriteLog "Send-MailMessage failed - $CRLUrl"; }
            WriteLog
        }
        
        Elseif($CRLExpirationDays -le 0) {
            $ErrorMessage =  "CRL has expired $CRLExpirationDate - $CRLUrl"
            Write-Host $ErrorMessage
            WriteLog $ErrorMessage
            Try { Send-MailMessage @sendMailMessageSplat -Subject "CRL Expiration: $FileName" -Body "$ErrorMessage" -Credential $SMTPCredentials -ErrorAction Continue; }
            Catch { Write-Host "Send-MailMessage failed - $CRLUrl"; WriteLog "Send-MailMessage failed - $CRLUrl"; }
            WriteLog
        }

        Elseif($CRLExpirationDays -le $CRLExpirationThreshold) {
            $ErrorMessage =  "$CRLUrl - Expires in $CRLExpirationDays days ($CRLExpirationDate)."
            Write-Host $ErrorMessage
            WriteLog $ErrorMessage
            Try { Send-MailMessage @sendMailMessageSplat -Subject "CRL Expiration: $FileName" -Body "$ErrorMessage" -Credential $SMTPCredentials -ErrorAction Continue; }
            Catch { Write-Host "Send-MailMessage failed - $CRLUrl"; WriteLog "Send-MailMessage failed - $CRLUrl"; }
            WriteLog
        }

        Else {
            Write-Host "$CRLUrl - OK"
            WriteLog "$CRLUrl - OK"
            WriteLog
        }
    }
}

Rotate-Logs
WriteLog