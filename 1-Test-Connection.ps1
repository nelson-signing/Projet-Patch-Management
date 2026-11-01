# 1. Emplacement du fichier d'inventaire
$InventoryPath = ".\computers.txt"

# 2. Verification de l'existence du fichier
if (-not (Test-Path -Path $InventoryPath)) {
    Write-Error "Fichier $InventoryPath introuvable."
    exit
}

# 3. Lecture ligne par ligne
$lines = Get-Content -Path $InventoryPath

# 4. Liste de stockage
$report = @()

foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) { 
        continue 
    }

    # Decoupage au point-virgule
    $parts = $line.Split(';')
    $nom   = $parts[0].Trim()
    $ip    = $parts[1].Trim()

    # Test reseau ICMP
    $isUp = Test-Connection -ComputerName $ip -Count 1 -Quiet

    if ($isUp) {
        $etat = "Accessible"
    } else {
        $etat = "Inaccessible"
    }

    # Creation de l'objet resultat
    $machine = [PSCustomObject]@{
        Nom       = $nom
        AdresseIP = $ip
        Etat      = $etat
    }

    $report += $machine
}

# 5. Affichage du tableau
Write-Host "`n--- RESULTAT DU CONTROLE DU PARC ---" -ForegroundColor Cyan
$report | Format-Table -AutoSize