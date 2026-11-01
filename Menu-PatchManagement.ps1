<#
=====================================================================
Nom du script : Menu-PatchManagement.ps1
Description   : Menu interactif permettant d'exécuter les scripts
                d'automatisation du projet de Patch Management.
=====================================================================
#>

function Afficher-Titre {
    Clear-Host
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "       AUTOMATISATION DE LA GESTION DES CORRECTIFS WINDOWS       " -ForegroundColor Yellow
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Executer-Script {
    param (
        [string]$NomScript,
        [string]$Description
    )

    $CheminScript = Join-Path -Path $PSScriptRoot -ChildPath $NomScript

    Write-Host "`n>>> [LANCEMENT] $Description ($NomScript)..." -ForegroundColor Magenta
    
    if (Test-Path -Path $CheminScript) {
        try {
            & $CheminScript
            Write-Host "`n[SUCCES] Execution de $NomScript terminee." -ForegroundColor Green
        }
        catch {
            Write-Host "`n[ERREUR] Une erreur est survenue lors de l'execution : $_" -ForegroundColor Red
        }
    }
    else {
        Write-Host "`n[ERREUR] Le fichier introuvable : $CheminScript" -ForegroundColor Red
    }

    Write-Host "`nAppuyez sur Entree pour revenir au menu..." -ForegroundColor DarkGray
    [void][System.Console]::ReadLine()
}

function Executer-ChaineComplete {
    Clear-Host
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "       EXECUTION COMPLETE DE LA CHAINE DE TRAITEMENT (1 a 6)     " -ForegroundColor Yellow
    Write-Host "================================================================" -ForegroundColor Cyan

    $scripts = @(
        @{ Nom = "1-Test-Connection.ps1";        Desc = "Test d'accessibilite reseau" },
        @{ Nom = "2-Get-SystemInventory.ps1";    Desc = "Inventaire systeme distant" },
        @{ Nom = "3-Get-PatchInventory.ps1";     Desc = "Inventaire des correctifs installes" },
        @{ Nom = "4-Test-PatchCompliance.ps1";   Desc = "Controle de conformite (required-patches)" },
        @{ Nom = "5-Generate-SecurityReport.ps1"; Desc = "Generation du tableau de bord HTML" },
        @{ Nom = "6-Send-PatchNotification.ps1"; Desc = "Conversion PDF et envoi de l'alerte e-mail" }
    )

    foreach ($item in $scripts) {
        $chemin = Join-Path -Path $PSScriptRoot -ChildPath $item.Nom
        Write-Host "`n----------------------------------------------------------------" -ForegroundColor DarkCyan
        Write-Host ">>> Etape : $($item.Desc) [$($item.Nom)]" -ForegroundColor Magenta
        Write-Host "----------------------------------------------------------------" -ForegroundColor DarkCyan

        if (Test-Path -Path $chemin) {
            try {
                & $chemin
                Write-Host "[OK] $($item.Nom) execute avec succes." -ForegroundColor Green
            }
            catch {
                Write-Host "[ERREUR] sur $($item.Nom) : $_" -ForegroundColor Red
            }
        }
        else {
            Write-Host "[ATTENTION] Script non trouve : $chemin" -ForegroundColor Yellow
        }
    }

    Write-Host "`n>>> Chaine complete terminee." -ForegroundColor Cyan
    Write-Host "Appuyez sur Entree pour revenir au menu principal..." -ForegroundColor DarkGray
    [void][System.Console]::ReadLine()
}

# --- Boucle principale du Menu ---
do {
    Afficher-Titre
    Write-Host "  [1] Verifier l'accessibilite du parc (Ping)         - 1-Test-Connection.ps1"
    Write-Host "  [2] Collecter l'inventaire systeme (OS, Boot, ...)  - 2-Get-SystemInventory.ps1"
    Write-Host "  [3] Extraire les KB installes (CSV)                 - 3-Get-PatchInventory.ps1"
    Write-Host "  [4] Evaluer la conformite des correctifs (CSV)      - 4-Test-PatchCompliance.ps1"
    Write-Host "  [5] Generer le rapport de securite HTML             - 5-Generate-SecurityReport.ps1"
    Write-Host "  [6] Convertir en PDF et envoyer l'alerte e-mail     - 6-Send-PatchNotification.ps1"
    Write-Host "  ----------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  [A] TOUT EXECUTER A LA SUITE (Etapes 1 a 6)" -ForegroundColor Green
    Write-Host "  [Q] Quitter" -ForegroundColor Red
    Write-Host ""

    $choix = (Read-Host "Choisissez une option").Trim().ToUpper()

    switch ($choix) {
        "1" { Executer-Script -NomScript "1-Test-Connection.ps1"        -Description "Test d'accessibilite reseau" }
        "2" { Executer-Script -NomScript "2-Get-SystemInventory.ps1"    -Description "Inventaire systeme distant" }
        "3" { Executer-Script -NomScript "3-Get-PatchInventory.ps1"     -Description "Extraction des correctifs installes" }
        "4" { Executer-Script -NomScript "4-Test-PatchCompliance.ps1"   -Description "Audit de conformite des correctifs" }
        "5" { Executer-Script -NomScript "5-Generate-SecurityReport.ps1" -Description "Generation du rapport HTML" }
        "6" { Executer-Script -NomScript "6-Send-PatchNotification.ps1" -Description "Alerte de notification et PDF" }
        "A" { Executer-ChaineComplete }
        "Q" { Write-Host "`nFermeture du menu." -ForegroundColor Yellow; break }
        default {
            Write-Host "`nOption invalide. Appuyez sur Entree pour reessayer..." -ForegroundColor Red
            [void][System.Console]::ReadLine()
        }
    }

} while ($choix -ne "Q")