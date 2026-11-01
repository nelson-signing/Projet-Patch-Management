# =====================================================================
# CONTROLE DE CONFORMITE (Test-PatchCompliance.ps1)
# =====================================================================

$InventoryFile = ".\computers.txt"
$PatchFile     = ".\required-patches.txt"
$ReportCsvFile = ".\ComplianceReport.csv"

# 1. Verification de l'existence des fichiers
if (-not (Test-Path -Path $InventoryFile)) {
    Write-Error "Fichier d'inventaire $InventoryFile introuvable."
    exit
}
if (-not (Test-Path -Path $PatchFile)) {
    Write-Error "Fichier des correctifs requis $PatchFile introuvable."
    exit
}

# 2. Chargement de la liste des correctifs requis et identifiants
$requiredPatches = Get-Content -Path $PatchFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim().ToUpper() }
$totalRequired   = $requiredPatches.Count

if (-not $cred) {
    Write-Host "Authentification requise pour le controle de conformite :" -ForegroundColor Cyan
    $cred = Get-Credential
}

$targets         = Get-Content -Path $InventoryFile
$rapportSynthese = @()
$rapportDetail   = @()
$dateControle    = (Get-Date).ToString("dd/MM/yyyy HH:mm:ss")

# 3. Evaluation de conformite pour chaque machine
foreach ($entry in $targets) {
    if ([string]::IsNullOrWhiteSpace($entry)) { continue }

    $fields = $entry.Split(';')
    $nom    = $fields[0].Trim()
    $ip     = $fields[1].Trim()

    $estJoignable = Test-Connection -ComputerName $ip -Count 1 -Quiet

    if (-not $estJoignable) {
        # Ligne de synthese pour l'affichage console
        $rapportSynthese += [PSCustomObject]@{
            Poste          = $nom
            AdresseIP      = $ip
            KB_Requises    = $totalRequired
            KB_Manquantes  = "-"
            Etat           = "INACCESSIBLE"
            ListeManquants = "N/A"
            DateControle   = $dateControle
        }

        # Ligne de detail pour l'export CSV
        $rapportDetail += [PSCustomObject]@{
            Poste        = $nom
            AdresseIP    = $ip
            KB           = "N/A"
            Statut       = "Inaccessible"
            DateControle = $dateControle
        }
        continue
    }

    $correctifsDistants = $null
    try {
        $correctifsDistants = Invoke-Command -ComputerName $ip -Credential $cred -ScriptBlock {
            (Get-HotFix -ErrorAction SilentlyContinue).HotFixID
        } -ErrorAction Stop
    }
    catch {
        # Synthese console en cas d'erreur WinRM
        $rapportSynthese += [PSCustomObject]@{
            Poste          = $nom
            AdresseIP      = $ip
            KB_Requises    = $totalRequired
            KB_Manquantes  = "Erreur"
            Etat           = "ERREUR"
            ListeManquants = "Erreur WinRM"
            DateControle   = $dateControle
        }

        # Detail CSV en cas d'erreur WinRM
        $rapportDetail += [PSCustomObject]@{
            Poste        = $nom
            AdresseIP    = $ip
            KB           = "N/A"
            Statut       = "Erreur WinRM"
            DateControle = $dateControle
        }
        continue
    }

    $installedList = @()
    if ($correctifsDistants) {
        $installedList = $correctifsDistants | ForEach-Object { $_.Trim().ToUpper() }
    }

    $manquants = @()

    # Verification KB par KB pour le detail CSV et l'identification des manquants
    foreach ($kbReq in $requiredPatches) {
        if ($installedList -contains $kbReq) {
            $statutKB = "Present"
        } else {
            $statutKB = "Absent"
            $manquants += $kbReq
        }

        $rapportDetail += [PSCustomObject]@{
            Poste        = $nom
            AdresseIP    = $ip
            KB           = $kbReq
            Statut       = $statutKB
            DateControle = $dateControle
        }
    }

    $nbManquants    = $manquants.Count
    $etatConforme   = if ($nbManquants -eq 0) { "CONFORME" } else { "NON CONFORME" }
    $texteManquants = if ($nbManquants -eq 0) { "Aucun" } else { ($manquants -join ", ") }

    $rapportSynthese += [PSCustomObject]@{
        Poste          = $nom
        AdresseIP      = $ip
        KB_Requises    = $totalRequired
        KB_Manquantes  = $nbManquants
        Etat           = $etatConforme
        ListeManquants = $texteManquants
        DateControle   = $dateControle
    }
}

# 4. Export CSV detaille ligne par ligne
$rapportDetail | Export-Csv -Path $ReportCsvFile -NoTypeInformation -Delimiter ";" -Encoding UTF8
Write-Host "`nRapport de conformite detaille enregistre dans : $ReportCsvFile" -ForegroundColor Green

# 5. Affichage du tableau de synthese en console avec les manquants
Write-Host "`n--- RESULTAT DU CONTROLE DE CONFORMITE ---" -ForegroundColor Cyan
$rapportSynthese | Format-Table -Property Poste, AdresseIP, KB_Requises, KB_Manquantes, Etat, ListeManquants, DateControle -AutoSize

# 6. Calcul du taux global de conformite (hors machines inaccessibles)
$machinesEvaluees = $rapportSynthese | Where-Object { $_.Etat -in @("CONFORME", "NON CONFORME") }
$totalEvaluees    = ($machinesEvaluees | Measure-Object).Count
$totalConformes   = ($machinesEvaluees | Where-Object { $_.Etat -eq "CONFORME" } | Measure-Object).Count

if ($totalEvaluees -gt 0) {
    $taux = [math]::Round(($totalConformes / $totalEvaluees) * 100, 2)
    Write-Host "`n--- STATISTIQUES GLOBALES ---" -ForegroundColor Yellow
    Write-Host "Postes audites (accessibles) : $totalEvaluees"
    Write-Host "Postes conformes             : $totalConformes"
    Write-Host "Taux global de conformite    : $taux %" -ForegroundColor $(if ($taux -eq 100) { "Green" } else { "Red" })
}