# ---------------------------------------------------------
# INVENTAIRE DU PARC (Get-SystemInventory.ps1)
# ---------------------------------------------------------

$InventoryFile = ".\computers.txt"
$CsvExportPath = ".\SystemInventory.csv"

# 1. Verification de l'existence du fichier d'inventaire
if (-not (Test-Path -Path $InventoryFile)) {
    Write-Error "Fichier d'inventaire $InventoryFile introuvable."
    exit
}

# 2. Saisie des identifiants d'administration a distance
$cred = Get-Credential

$lines = Get-Content -Path $InventoryFile
$inventaireComplet = @()

foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }

    $elements = $line.Split(';')
    $nom       = $elements[0].Trim()
    $ip        = $elements[1].Trim()

    # Test prealable de connectivite (ping)
    $estJoignable = Test-Connection -ComputerName $ip -Count 1 -Quiet

    if (-not $estJoignable) {
        # Machine inaccessible : on consigne l'etat sans arreter le script
        $inventaireComplet += [PSCustomObject]@{
            Poste               = $nom
            AdresseIP           = $ip
            Modele              = "N/A"
            BiosVersion         = "N/A"
            Windows             = "N/A"
            Architecture        = "N/A"
            DernierDemarrage    = "N/A"
            RAM_Go              = "N/A"
            DisqueLibre_Go      = "N/A"
            NbMajInstallees     = "N/A"
            DerniereMajDate     = "N/A"
            WindowsUpdate       = "N/A"
            Etat                = "Inaccessible"
        }
        continue
    }

    try {
        # Collecte distante via WinRM
        $infosDistantes = Invoke-Command -ComputerName $ip -Credential $cred -ScriptBlock {
            # Informations OS et demarrage
            $os = Get-CimInstance -ClassName Win32_OperatingSystem
            $dernierBoot = if ($os.LastBootUpTime) { $os.LastBootUpTime.ToString("dd/MM/yyyy HH:mm") } else { "N/A" }
            $ramGo = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)

            # Informations materiel et BIOS
            $cs   = Get-CimInstance -ClassName Win32_ComputerSystem
            $bios = Get-CimInstance -ClassName Win32_BIOS

            # Espace disque systeme (C:)
            $disque = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'"
            $espaceLibreGo = [math]::Round($disque.FreeSpace / 1GB, 2)

            # Informations sur les mises a jour (HotFixes)
            $hotfixes = Get-HotFix -ErrorAction SilentlyContinue
            $nbHotfixes = if ($hotfixes) { ($hotfixes | Measure-Object).Count } else { 0 }
            
            $derniereMaj = if ($hotfixes) {
                ($hotfixes | Where-Object { $_.InstalledOn } | Sort-Object -Property InstalledOn -Descending | Select-Object -First 1).InstalledOn
            } else { 
                "Aucune" 
            }
            $dateDerniereMaj = if ($derniereMaj -is [datetime]) { (Get-Date $derniereMaj).ToString("dd/MM/yyyy") } else { "$derniereMaj" }

            # Etat du service Windows Update (wuauserv)
            $svc = Get-Service -Name "wuauserv" -ErrorAction SilentlyContinue
            $statutSvc = if ($svc) { $svc.Status.ToString() } else { "Introuvable" }

            [PSCustomObject]@{
                Poste               = $env:COMPUTERNAME
                Modele              = $cs.Model
                BiosVersion         = $bios.SMBIOSBIOSVersion
                Windows             = $os.Caption
                Architecture        = $os.OSArchitecture
                DernierDemarrage    = $dernierBoot
                RAM_Go              = $ramGo
                DisqueLibre_Go      = $espaceLibreGo
                NbMajInstallees     = $nbHotfixes
                DerniereMajDate     = $dateDerniereMaj
                WindowsUpdate       = $statutSvc
            }
        } -ErrorAction Stop

        $inventaireComplet += [PSCustomObject]@{
            Poste               = $nom
            AdresseIP           = $ip
            Modele              = $infosDistantes.Modele
            BiosVersion         = $infosDistantes.BiosVersion
            Windows             = $infosDistantes.Windows
            Architecture        = $infosDistantes.Architecture
            DernierDemarrage    = $infosDistantes.DernierDemarrage
            RAM_Go              = $infosDistantes.RAM_Go
            DisqueLibre_Go      = $infosDistantes.DisqueLibre_Go
            NbMajInstallees     = $infosDistantes.NbMajInstallees
            DerniereMajDate     = $infosDistantes.DerniereMajDate
            WindowsUpdate       = $infosDistantes.WindowsUpdate
            Etat                = "Accessible"
        }
    }
    catch {
        # Erreur lors de la communication WinRM ou execution
        $inventaireComplet += [PSCustomObject]@{
            Poste               = $nom
            AdresseIP           = $ip
            Modele              = "Erreur"
            BiosVersion         = "Erreur"
            Windows             = "Erreur"
            Architecture        = "Erreur"
            DernierDemarrage    = "Erreur"
            RAM_Go              = "Erreur"
            DisqueLibre_Go      = "Erreur"
            NbMajInstallees     = "Erreur"
            DerniereMajDate     = "Erreur"
            WindowsUpdate       = "Erreur"
            Etat                = "Erreur WinRM"
        }
    }
}

# 3. Affichage du tableau complet
Write-Host "`n--- INVENTAIRE COMPLET DU PARC ---" -ForegroundColor Cyan
$inventaireComplet | Format-Table -Property Poste, AdresseIP, Modele, BiosVersion, Windows, Architecture, DernierDemarrage, RAM_Go, DisqueLibre_Go, NbMajInstallees, DerniereMajDate, WindowsUpdate, Etat

# 4. Export automatique de l'ensemble des donnees en fichier CSV
$inventaireComplet | Export-Csv -Path $CsvExportPath -NoTypeInformation -Delimiter ";" -Encoding UTF8
Write-Host "Inventaire exporte avec succes dans : $CsvExportPath" -ForegroundColor Green