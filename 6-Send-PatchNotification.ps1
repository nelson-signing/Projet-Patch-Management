# =====================================================================
# NOTIFICATION DES ANOMALIES (6-Send-PatchNotification.ps1)
# =====================================================================

param (
    [string]$AdresseMail = "admin-patch@lab.local"
)

$ReportCsvFile  = ".\ComplianceReport.csv"
$HtmlReport     = ".\SecurityReport.html"
$PdfReport      = ".\SecurityReport.pdf"
$LogFile        = ".\PatchManager.log"

$SmtpServer     = "smtp.gmail.com"
$SmtpPort       = 587

# 1. Fonction de journalisation
function Write-NotificationLog {
    param([string]$Message)

    $timestamp = (Get-Date).ToString("dd/MM/yyyy HH:mm:ss")
    $logLine   = "$timestamp ; $Message"
    Add-Content -Path $LogFile -Value $logLine -Encoding UTF8
}

# 2. Fonction de conversion HTML -> PDF (Edge ou Chrome en mode headless)
function ConvertTo-PdfFile {
    param(
        [string]$HtmlPath,
        [string]$PdfPath
    )

    $candidats = @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
    )
    $navigateur = $candidats | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $navigateur) {
        throw "Ni Microsoft Edge ni Google Chrome n'a ete trouve."
    }

    $htmlFull   = (Resolve-Path -Path $HtmlPath).Path
    $pdfFull    = Join-Path -Path (Get-Location).Path -ChildPath (Split-Path -Path $PdfPath -Leaf)
    $htmlUri    = ([System.Uri]$htmlFull).AbsoluteUri
    $profilTemp = Join-Path $env:TEMP "pdf_profile_patchmanager"
    $tempOut    = Join-Path $env:TEMP "pdf_browser_out.log"
    $tempErr    = Join-Path $env:TEMP "pdf_browser_err.log"

    if (Test-Path $pdfFull) { Remove-Item $pdfFull -Force }

    $arguments = @(
        "--headless",
        "--disable-gpu",
        "--no-pdf-header-footer",
        "--log-level=3",
        "--disable-logging",
        "--user-data-dir=`"$profilTemp`"",
        "--print-to-pdf=`"$pdfFull`"",
        "`"$htmlUri`""
    )
    Start-Process -FilePath $navigateur -ArgumentList $arguments -Wait -WindowStyle Hidden `
        -RedirectStandardOutput $tempOut -RedirectStandardError $tempErr

    Remove-Item $tempOut, $tempErr -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path $pdfFull) -or (Get-Item $pdfFull).Length -eq 0) {
        throw "La generation du PDF a echoue."
    }
    return $pdfFull
}

# 3. Verification de l'existence du rapport
if (-not (Test-Path -Path $ReportCsvFile)) {
    Write-Error "Fichier $ReportCsvFile introuvable."
    exit
}

# 4. Lecture des anomalies
$reportData = Import-Csv -Path $ReportCsvFile -Delimiter ";" -Encoding UTF8

$allPostes     = $reportData | Select-Object -ExpandProperty Poste -Unique
$inaccessibles = $reportData | Where-Object { $_.Statut -like "*Inaccessible*" -or $_.Statut -like "*Erreur WinRM*" } | Select-Object -ExpandProperty Poste -Unique
$nonConformes  = $reportData | Where-Object { $_.Statut -eq "Absent" } | Select-Object -ExpandProperty Poste -Unique

$totalControles    = @($allPostes).Count
$totalNonConformes = @($nonConformes).Count
$totalInaccess     = @($inaccessibles).Count

# 5. Arret si aucune anomalie
if ($totalNonConformes -eq 0 -and $totalInaccess -eq 0) {
    Write-Host "Aucune anomalie detectee. Fin de l'audit sans notification." -ForegroundColor Green
    exit
}

# 6. Construction du message
$dateJour = (Get-Date).ToString("dd/MM/yyyy")
$body = @"
Objet : [PATCH MANAGEMENT] Anomalies detectees

Date du controle : $dateJour

Postes controles     : $totalControles
Postes non conformes : $totalNonConformes
Postes inaccessibles : $totalInaccess

"@

foreach ($poste in $nonConformes) {
    $kbManquants = ($reportData | Where-Object { $_.Poste -eq $poste -and $_.Statut -eq "Absent" }).KB
    $body += "`n$poste : NON CONFORME`n"
    foreach ($kb in $kbManquants) {
        $body += "  $kb manquante`n"
    }
}

foreach ($poste in $inaccessibles) {
    $body += "`n$poste : INACCESSIBLE`n"
}

Write-Host "`n--- APERCU DU MESSAGE ---" -ForegroundColor Cyan
Write-Host $body

# 7. Envoi par Gmail et journalisation
try {
    Write-Host "Authentification SMTP requise pour l'envoi :" -ForegroundColor Cyan
    Write-Host "(Entrez votre adresse mail d'envoi et votre mot de passe d'application)" -ForegroundColor Gray
    
    $smtpCred = Get-Credential -Message "Authentification SMTP (Patch Management)"
    
    # Si l'utilisateur saisit son adresse dans l'invite, elle est reprise pour l'envoi
    $destinataire = if ($AdresseMail -ne "admin-patch@lab.local") { $AdresseMail } else { $smtpCred.UserName }

    $mailParams = @{
        To         = $destinataire
        From       = $smtpCred.UserName
        Subject    = "[PATCH MANAGEMENT] Anomalies detectees"
        Body       = $body
        SmtpServer = $SmtpServer
        Port       = $SmtpPort
        UseSsl     = $true
        Credential = $smtpCred
        Encoding   = [System.Text.Encoding]::UTF8
    }

    if (Test-Path -Path $HtmlReport) {
        $pdfPath = ConvertTo-PdfFile -HtmlPath $HtmlReport -PdfPath $PdfReport
        $mailParams.Attachments = $pdfPath
    }

    Send-MailMessage @mailParams -ErrorAction Stop

    Write-NotificationLog "Notification envoyee a $destinataire"
    Write-Host "`nNotification envoyee avec succes a $destinataire" -ForegroundColor Green
}
catch {
    Write-NotificationLog "ERREUR ; Notification non envoyee"
    Write-Host "`nErreur lors de l'envoi : $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Echec consigne dans $LogFile." -ForegroundColor Yellow
}