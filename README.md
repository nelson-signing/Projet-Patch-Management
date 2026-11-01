# Automatisation de la Gestion des Correctifs de Sécurité (Patch Management)

Projet d'administration système et de sécurité sous Windows visant à automatiser l'audit des correctifs, la vérification de conformité, la génération de tableaux de bord visuels et l'alerte par e-mail en environnement hors domaine (Workgroup).

---

## 1. Architecture du Lab de Test

| Machine | Rôle | Adresse IP | Statut attendu |
| :--- | :--- | :--- | :--- |
| **PC-ADMIN** | Poste d'administration (exécute les scripts) | 192.168.97.137 | En ligne |
| **PC01** | Client administré | 192.168.97.138 | En ligne (Non conforme) |
| **PC02** | Client administré | 192.168.97.139 | En ligne (Non conforme) |
| **PC03** | Machine de test injoignable | 192.168.97.250 | Inaccessible (Simulation de coupure) |

---

## 2. Prérequis et Configuration Initiale

Avant la première exécution, exécuter les commandes suivantes dans une console PowerShell en Administrateur :

1. Configuration du profil réseau en Privé :
```powershell
Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private
```

2. Activation et configuration du service WinRM :
```powershell
Enable-PSRemoting -Force -SkipNetworkProfileCheck
```

3. Configuration du paramètre TrustedHosts sur PC-ADMIN :
```powershell
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "192.168.97.*" -Force
```

---

## 3. Structure du Dépôt

* `computers.txt` : Fichier contenant les adresses IP du parc à analyser.
* `required-patches.txt` : Référentiel des correctifs de sécurité obligatoires (KB).
* `Menu-PatchManagement.ps1` : Script interactif proposant un menu d'exécution unitaire ou globale.
* `1-Test-Connection.ps1` : Contrôle de joignabilité réseau des hôtes du parc (Ping).
* `2-Get-SystemInventory.ps1` : Collecte d'informations système (OS, Build, dernier boot, service wuauserv)[cite: 2].
* `3-Get-PatchInventory.ps1` : Inventaire des correctifs installés et export vers `Patches_Inventory.csv`.
* `4-Test-PatchCompliance.ps1` : Analyse d'écarts de sécurité et export vers `ComplianceReport.csv`.
* `5-Generate-SecurityReport.ps1` : Consolidation des indicateurs et génération du rapport visuel `SecurityReport.html`[cite: 2].
* `6-Send-PatchNotification.ps1` : Conversion PDF via Edge headless, notification e-mail SMTP et traçabilité dans `PatchManager.log`.
* `examples/` : Dossier contenant des exemplaires des livrables générés lors des tests.

---

## 4. Mode d'Exécution

Ouvrir une console PowerShell avec les privilèges d'administration dans le dossier du projet :

```powershell
.\Menu-PatchManagement.ps1
```

* Saisir le chiffre correspondant au script souhaité (1 à 6) pour un test unitaire.
* Saisir **A** pour lancer séquentiellement l'ensemble de la chaîne d'automatisation.