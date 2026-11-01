# =====================================================================
# INVENTAIRE DES CORRECTIFS (Get-PatchInventory.ps1)
# =====================================================================

$InventoryFile = ".\computers.txt"
$CsvOutputFile = ".\Patches Inventory.csv"

# 1. Verification du fichier computers.txt
if (-not (Test-Path -Path $InventoryFile)) {
    Write-Error "Fichier d'inventaire $InventoryFile introuvable."
    exit
}

# 2. Saisie des identifiants d'administration a distance
if (-not $cred) {
    Write-Host "Authentification requise pour l'inventaire des correctifs :" -ForegroundColor Cyan
    $cred = Get-Credential
}

$targets = Get-Content -Path $InventoryFile
$tousLesCorrectifs = @()
$resumeMachines    = @()

# 3. Parcours de chaque machine de l'inventaire
foreach ($entry in $targets) {
    if ([string]::IsNullOrWhiteSpace($entry)) { continue }

    $fields =$entry.Split(';')
    $nom    =$fields[0].Trim()
    $ip     =$fields[1].Trim()

    # Verification de la connectivite reseau
    $estJoignable = Test-Connection -ComputerName $ip -Count 1 -Quiet

    if (-not $estJoignable) {
		$resumeMachines += [PSCustomObject]@{
            Poste                = $nom
            AdresseIP            = $ip
            TotalCorrectifs      = "N/A"
            DernierKB            = "N/A"
            DateDernierCorrectif = "N/A"
            Etat                 = "Inaccessible"
        }
        continue
    }

    try {
        # 4. Collecte a distance des correctifs
        $correctifsDistants = Invoke-Command -ComputerName $ip -Credential $cred -ScriptBlock {
            Get-HotFix -ErrorAction SilentlyContinue | Select-Object -Property HotFixID, Description, InstalledOn, InstalledBy
        } -ErrorAction Stop

        if ($correctifsDistants) {
            $correctifsTries =$correctifsDistants | Sort-Object -Property InstalledOn -Descending

            foreach ($kb in $correctifsTries) {
				$dateInst = if ($kb.InstalledOn) { (Get-Date $kb.InstalledOn).ToString("dd/MM/yyyy") } else { "Date inconnue" }
                $tousLesCorrectifs += [PSCustomObject]@{
                    Poste            = $nom
                    AdresseIP        = $ip
                    KB               = $kb.HotFixID
                    Description      = $kb.Description
                    DateInstallation = $dateInst
                }
            }

            # Extraction du dernier correctif installe
            $dernierPatch = $correctifsTries | Where-Object { $_.InstalledOn } | Select-Object -First 1
            $dateDernier  = if ($dernierPatch -and $dernierPatch.InstalledOn) { (Get-Date $dernierPatch.InstalledOn).ToString("dd/MM/yyyy") } else { "N/A" }
            $idDernier    = if ($dernierPatch) {$dernierPatch.HotFixID } else { "N/A" }

            $resumeMachines += [PSCustomObject]@{
                Poste                = $nom
                AdresseIP            = $ip
                TotalCorrectifs      = ($correctifsDistants | Measure-Object).Count
                DernierKB            = $idDernier
                DateDernierCorrectif = $dateDernier
                Etat                 = "Accessible"
            }
        } else {
            $resumeMachines += [PSCustomObject]@{
                Poste                = $nom
                AdresseIP            = $ip
                TotalCorrectifs      = 0
                DernierKB            = "Aucun"
                DateDernierCorrectif = "Aucun"
                Etat                 = "Accessible"
            }
        }
    }
    catch {
        $resumeMachines += [PSCustomObject]@{
            Poste                = $nom
            AdresseIP            = $ip
            TotalCorrectifs      = "Erreur"
            DernierKB            = "Erreur"
            DateDernierCorrectif = "Erreur"
            Etat                 = "Erreur WinRM"
        }
    }
}

# 5. Export des correctifs dans le fichier CSV
$tousLesCorrectifs | Sort-Object -Property @{Expression="Poste"; Descending=$false}, @{Expression="DateInstallation"; Descending=$true} | Export-Csv -Path $CsvOutputFile -NoTypeInformation -Delimiter ";" -Encoding UTF8
Write-Host "`nInventaire exporte avec succes dans : $CsvOutputFile" -ForegroundColor Green

# 6. Affichage du bilan par machine
Write-Host "`n--- BILAN DES CORRECTIFS PAR MACHINE ---" -ForegroundColor Cyan
$resumeMachines | Format-Table -AutoSize