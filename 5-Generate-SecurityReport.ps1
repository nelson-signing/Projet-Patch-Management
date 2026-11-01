# =====================================================================
# RAPPORT DE SECURITE ET SYNTHESE GLOBALE (Generate-SecurityReport.ps1)
# =====================================================================

$InventoryFile = ".\computers.txt"
$PatchFile     = ".\required-patches.txt"
$LogFile       = ".\PatchManager.log"
$HtmlReport    = ".\SecurityReport.html"

# Fonction d'ecriture horodatee dans le journal
function Write-AuditLog {
    param([string]$Message)
    $timestamp = (Get-Date).ToString("dd/MM/yyyy HH:mm:ss")
    $logLine = "$timestamp ; $Message"
    Add-Content -Path $LogFile -Value $logLine -Encoding UTF8
}

Write-AuditLog "Debut de l'audit"

# 1. Verification des pre-requis
if (-not (Test-Path -Path $InventoryFile)) {
    Write-Error "Fichier $InventoryFile introuvable."
    Write-AuditLog "Erreur : Fichier $InventoryFile introuvable"
    exit
}
if (-not (Test-Path -Path $PatchFile)) {
    Write-Error "Fichier $PatchFile introuvable."
    Write-AuditLog "Erreur : Fichier $PatchFile introuvable"
    exit
}

$requiredPatches = Get-Content -Path $PatchFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim().ToUpper() }
$totalRequired   = $requiredPatches.Count

if (-not $cred) {
    Write-Host "Authentification requise pour l'audit global :" -ForegroundColor Cyan
    $cred = Get-Credential
}

$targets      = Get-Content -Path $InventoryFile
$rapportParc  = @()
$dateControle = (Get-Date).ToString("dd/MM/yyyy HH:mm:ss")

# 2. Collecte et audit poste par poste
foreach ($entry in $targets) {
    if ([string]::IsNullOrWhiteSpace($entry)) { continue }

    $fields = $entry.Split(';')
    $nom    = $fields[0].Trim()
    $ip     = $fields[1].Trim()

    # Test de connectivite IP
    $estJoignable = Test-Connection -ComputerName $ip -Count 1 -Quiet

    if (-not $estJoignable) {
        Write-AuditLog "$nom ; Inaccessible reseau"
        $rapportParc += [PSCustomObject]@{
            Poste               = $nom
            AdresseIP           = $ip
            Accessibilite       = "Inaccessible"
            VersionWindows      = "N/A"
            DernierDemarrage    = "N/A"
            ServiceUpdate       = "N/A"
            KB_Requises         = $totalRequired
            KB_Manquantes       = "-"
            ListeManquants      = "N/A"
            Etat                = "INACCESSIBLE"
            InterventionRequise = "Oui"
            MotifIntervention   = "Machine injoignable sur le reseau"
            DateControle        = $dateControle
        }
        continue
    }

    Write-AuditLog "$nom ; Accessible"

    # Collecte WMI / WinRM
    $infosDistantes = $null
    try {
        $infosDistantes = Invoke-Command -ComputerName $ip -Credential $cred -ScriptBlock {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem
            $srv = Get-Service -Name "wuauserv" -ErrorAction SilentlyContinue
            $kb = (Get-HotFix -ErrorAction SilentlyContinue).HotFixID

            [PSCustomObject]@{
                OSCaption     = $os.Caption
                OSVersion     = $os.Version
                LastBoot      = $os.LastBootUpTime
                ServiceStatus = if ($srv) { $srv.Status.ToString() } else { "Introuvable" }
                InstalledKBs  = $kb
            }
        } -ErrorAction Stop
    }
    catch {
        Write-AuditLog "$nom ; WinRM inaccessible"
        $rapportParc += [PSCustomObject]@{
            Poste               = $nom
            AdresseIP           = $ip
            Accessibilite       = "Erreur WinRM"
            VersionWindows      = "N/A"
            DernierDemarrage    = "N/A"
            ServiceUpdate       = "N/A"
            KB_Requises         = $totalRequired
            KB_Manquantes       = "Erreur"
            ListeManquants      = "Erreur WinRM"
            Etat                = "INACCESSIBLE"
            InterventionRequise = "Oui"
            MotifIntervention   = "Echec de connexion WinRM"
            DateControle        = $dateControle
        }
        continue
    }

    # Analyse des correctifs
    $installedList = @()
    if ($infosDistantes.InstalledKBs) {
        $installedList = $infosDistantes.InstalledKBs | ForEach-Object { $_.Trim().ToUpper() }
    }

    $manquants = @()
    foreach ($kbReq in $requiredPatches) {
        if ($installedList -notcontains $kbReq) {
            $manquants += $kbReq
        }
    }

    $nbManquants    = $manquants.Count
    $etatConforme   = if ($nbManquants -eq 0) { "CONFORME" } else { "NON CONFORME" }
    $texteManquants = if ($nbManquants -eq 0) { "Aucun" } else { ($manquants -join ", ") }
    $bootDate       = if ($infosDistantes.LastBoot) { (Get-Date $infosDistantes.LastBoot).ToString("dd/MM/yyyy HH:mm:ss") } else { "Inconnu" }

    # Journalisation de l'etat
    if ($etatConforme -eq "CONFORME") {
        Write-AuditLog "$nom ; Conforme"
    } else {
        Write-AuditLog "$nom ; Non conforme ; $texteManquants"
    }

    # Critere d'intervention epure
    $besoinIntervention = if ($etatConforme -ne "CONFORME") { "Oui" } else { "Non" }
    $texteMotif         = if ($etatConforme -ne "CONFORME") { "Correctifs manquants : $texteManquants" } else { "Aucun" }

    $rapportParc += [PSCustomObject]@{
        Poste               = $nom
        AdresseIP           = $ip
        Accessibilite       = "Accessible"
        VersionWindows      = "$($infosDistantes.OSCaption) ($($infosDistantes.OSVersion))"
        DernierDemarrage    = $bootDate
        ServiceUpdate       = $infosDistantes.ServiceStatus
        KB_Requises         = $totalRequired
        KB_Manquantes       = $nbManquants
        ListeManquants      = $texteManquants
        Etat                = $etatConforme
        InterventionRequise = $besoinIntervention
        MotifIntervention   = $texteMotif
        DateControle        = $dateControle
    }
}

# 3. Calcul des statistiques globales
$totalPostes       = ($rapportParc | Measure-Object).Count
$postesAccessibles = ($rapportParc | Where-Object { $_.Accessibilite -eq "Accessible" } | Measure-Object).Count
$postesInaccess    = $totalPostes - $postesAccessibles
$postesConformes   = ($rapportParc | Where-Object { $_.Etat -eq "CONFORME" } | Measure-Object).Count
$postesNonConf     = ($rapportParc | Where-Object { $_.Etat -eq "NON CONFORME" } | Measure-Object).Count

$totalKbManquants = 0
foreach ($p in ($rapportParc | Where-Object { $_.Accessibilite -eq "Accessible" })) {
    $totalKbManquants += [int]$p.KB_Manquantes
}

$tauxConformite = if ($postesAccessibles -gt 0) {
    [math]::Round(($postesConformes / $postesAccessibles) * 100, 2)
} else { 0 }

# Postes necessitant une intervention
$postesIntervention = $rapportParc | Where-Object { $_.InterventionRequise -eq "Oui" }

# 4. Affichage console
Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host "                SYNTHESE GLOBALE DU PARC                " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "Nombre total de postes            : $totalPostes"
Write-Host "Nombre de postes accessibles      : $postesAccessibles"
Write-Host "Nombre de postes inaccessibles    : $postesInaccess"
Write-Host "Nombre de postes conformes        : $postesConformes"
Write-Host "Nombre de postes non conformes    : $postesNonConf"
Write-Host "Nombre total de correctifs manq.  : $totalKbManquants"
Write-Host "Taux de conformite                : $tauxConformite %" -ForegroundColor $(if ($tauxConformite -eq 100) { "Green" } else { "Red" })

Write-Host "`n--- POSTES NECESSITANT UNE INTERVENTION ---" -ForegroundColor Yellow
if ($postesIntervention.Count -gt 0) {
    $postesIntervention | Format-Table -Property Poste, AdresseIP, Etat, ServiceUpdate, MotifIntervention -AutoSize
} else {
    Write-Host "Aucune intervention requise sur le parc." -ForegroundColor Green
}

# 5. Generation du rapport HTML
$htmlBuilder = @"
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <title>Rapport de Securite du Parc</title>
    <style>
        body { font-family: Segoe UI, Tahoma, sans-serif; margin: 25px; background-color: #f7f9fa; color: #333; }
        h1, h2 { color: #1a365d; }
        table { border-collapse: collapse; width: 100%; margin-bottom: 30px; background-color: #fff; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        th, td { border: 1px solid #cbd5e1; padding: 10px 12px; text-align: left; font-size: 14px; }
        th { background-color: #0f172a; color: white; }
        tr:nth-child(even) { background-color: #f8fafc; }
        .conforme { color: #15803d; font-weight: bold; }
        .non-conforme { color: #b91c1c; font-weight: bold; }
        .inaccessible { color: #d97706; font-weight: bold; }
        .stat-box { display: flex; gap: 15px; margin-bottom: 25px; }
        .card { background: white; padding: 15px 20px; border-radius: 6px; box-shadow: 0 2px 4px rgba(0,0,0,0.08); border-left: 5px solid #0284c7; flex: 1; }
        .card h3 { margin: 0 0 8px 0; font-size: 13px; color: #64748b; text-transform: uppercase; }
        .card p { margin: 0; font-size: 22px; font-weight: bold; color: #0f172a; }
    </style>
</head>
<body>
    <h1>Rapport de Securite et de Conformite</h1>
    <p>Rapport genere le : <strong>$dateControle</strong></p>

    <h2>Synthese globale du parc</h2>
    <div class="stat-box">
        <div class="card"><h3>Total Postes</h3><p>$totalPostes</p></div>
        <div class="card"><h3>Accessibles</h3><p>$postesAccessibles</p></div>
        <div class="card"><h3>Inaccessibles</h3><p>$postesInaccess</p></div>
        <div class="card"><h3>Conformes</h3><p class="conforme">$postesConformes</p></div>
        <div class="card"><h3>Non conformes</h3><p class="non-conforme">$postesNonConf</p></div>
        <div class="card"><h3>Correctifs manquants</h3><p>$totalKbManquants</p></div>
        <div class="card"><h3>Taux conformite</h3><p>$tauxConformite %</p></div>
    </div>

    <h2>Postes necessitant une intervention prioritaire</h2>
    <table>
        <tr>
            <th>Poste</th>
            <th>Adresse IP</th>
            <th>Etat</th>
            <th>Service Windows Update</th>
            <th>Motif d'intervention</th>
        </tr>
"@

foreach ($item in $postesIntervention) {
    $classEtat = switch ($item.Etat) {
        "CONFORME" { "conforme" }
        "NON CONFORME" { "non-conforme" }
        default { "inaccessible" }
    }
    $htmlBuilder += @"
        <tr>
            <td>$($item.Poste)</td>
            <td>$($item.AdresseIP)</td>
            <td class="$classEtat">$($item.Etat)</td>
            <td>$($item.ServiceUpdate)</td>
            <td><strong>$($item.MotifIntervention)</strong></td>
        </tr>
"@
}

$htmlBuilder += @"
    </table>

    <h2>Etat detaille de tous les postes</h2>
    <table>
        <tr>
            <th>Poste</th>
            <th>IP</th>
            <th>Accessibilite</th>
            <th>Systeme d'exploitation</th>
            <th>Dernier demarrage</th>
            <th>Service Update</th>
            <th>KB Requis</th>
            <th>KB Manquants</th>
            <th>Liste manquants</th>
            <th>Etat</th>
        </tr>
"@

foreach ($item in $rapportParc) {
    $classEtat = switch ($item.Etat) {
        "CONFORME" { "conforme" }
        "NON CONFORME" { "non-conforme" }
        default { "inaccessible" }
    }
    $htmlBuilder += @"
        <tr>
            <td>$($item.Poste)</td>
            <td>$($item.AdresseIP)</td>
            <td>$($item.Accessibilite)</td>
            <td>$($item.VersionWindows)</td>
            <td>$($item.DernierDemarrage)</td>
            <td>$($item.ServiceUpdate)</td>
            <td>$($item.KB_Requises)</td>
            <td>$($item.KB_Manquantes)</td>
            <td>$($item.ListeManquants)</td>
            <td class="$classEtat">$($item.Etat)</td>
        </tr>
"@
}

$htmlBuilder += @"
    </table>
</body>
</html>
"@

$htmlBuilder | Set-Content -Path $HtmlReport -Encoding UTF8
Write-AuditLog "Rapport genere"
Write-AuditLog "Fin de l'audit"

Write-Host "`nRapport HTML genere dans : $HtmlReport" -ForegroundColor Green
Write-Host "Journal d'audit mis a jour dans : $LogFile" -ForegroundColor Green