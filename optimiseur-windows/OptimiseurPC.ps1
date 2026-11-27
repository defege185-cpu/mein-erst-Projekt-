<#
    Optimiseur PC - Windows 10 et Windows 11
    -----------------------------------------
    Application gratuite, sans installation, pour rendre Windows plus fluide en jeu et en
    télétravail, sans surchauffe.

    Principes :
      * Rien n'est modifié sans que l'utilisateur ou l'utilisatrice coche une case ET confirme.
      * Uniquement des réglages officiels de Windows (Paramètres, stratégies de groupe documentées,
        powercfg, services, applications du Microsoft Store).
      * Aucun pilote, BIOS, firmware, overclocking, undervolting ou contournement de licence.
      * Chaque réglage d'origine est sauvegardé et peut être restauré.

    Lancement : double-cliquer sur « Lancer-Optimiseur.bat ».
    Licence : MIT.
#>
[CmdletBinding()]
param(
    [switch]$TestMode,
    [string]$DataPath
)

Set-StrictMode -Off
$AppName    = 'Optimiseur PC'
$AppVersion = '1.0.0'

if ($env:OS -ne 'Windows_NT') {
    Write-Error 'Cette application fonctionne uniquement sous Windows 10 et Windows 11.'
    return
}

# ---------------------------------------------------------------------------------------------
#  Droits administrateur (nécessaires pour les réglages système)
# ---------------------------------------------------------------------------------------------
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not $TestMode -and -not (Test-Admin)) {
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        $psExe = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    }
    try {
        Start-Process -FilePath $psExe -Verb RunAs -WindowStyle Hidden `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`"" -ErrorAction Stop
    } catch {
        Add-Type -AssemblyName PresentationFramework
        [void][System.Windows.MessageBox]::Show(
            "L'application a besoin des droits administrateur pour modifier les paramètres de Windows.`n`nRelancez-la et répondez « Oui » à la question de Windows.",
            $AppName, 'OK', 'Warning')
    }
    exit
}

# ---------------------------------------------------------------------------------------------
#  Dossiers, journal, version de Windows
# ---------------------------------------------------------------------------------------------
if (-not $DataPath) { $DataPath = Join-Path $env:LOCALAPPDATA 'OptimiseurPC' }
if (-not (Test-Path -LiteralPath $DataPath)) { New-Item -ItemType Directory -Path $DataPath -Force | Out-Null }
$DataFile = Join-Path $DataPath 'sauvegarde.json'
$LogFile  = Join-Path $DataPath 'journal.log'

$CurrentVersionKey = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
$Build   = [int]$CurrentVersionKey.CurrentBuildNumber
$IsWin11 = $Build -ge 22000

function Write-Log([string]$Message) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 } catch { }
    if ($script:TxtLog) {
        $script:TxtLog.AppendText($line + "`r`n")
        $script:TxtLog.ScrollToEnd()
    }
}

# ---------------------------------------------------------------------------------------------
#  Registre : lecture / écriture / sauvegarde
# ---------------------------------------------------------------------------------------------
function Read-Reg([string]$Path, [string]$Name) {
    $r = @{ Exists = $false; Value = $null; Kind = $null }
    try {
        $key = Get-Item -LiteralPath $Path -ErrorAction Stop
        if (@($key.GetValueNames()) -contains $Name) {
            $r.Exists = $true
            $r.Value  = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $r.Kind   = $key.GetValueKind($Name).ToString()
        }
    } catch { }
    return $r
}

function Write-Reg([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord') {
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
}

function New-RegBackup([string]$Path, [string]$Name) {
    $c = Read-Reg $Path $Name
    return [pscustomobject]@{ Type = 'Reg'; Path = $Path; Name = $Name; Exists = $c.Exists; Value = $c.Value; Kind = $c.Kind }
}

# Raccourci pour décrire une valeur de registre
function RegV([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord') {
    return [pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value; Type = $Type }
}

# Modifie « clé=valeur; » dans une chaîne du type « A=1;B=0; »
function Set-KVString([string]$Text, [string]$Key, [string]$Value) {
    $parts = New-Object System.Collections.Generic.List[string]
    $found = $false
    foreach ($p in ($Text -split ';')) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if ($p -like "$Key=*") { $parts.Add("$Key=$Value"); $found = $true }
        else { $parts.Add($p) }
    }
    if (-not $found) { $parts.Add("$Key=$Value") }
    return (($parts -join ';') + ';')
}

# ---------------------------------------------------------------------------------------------
#  Alimentation (powercfg, outil officiel de Windows)
# ---------------------------------------------------------------------------------------------
$GuidRx       = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
$BalancedGuid = '381b4222-f694-41f0-9685-ff5bb260df2e'

function Get-ActiveScheme {
    $o = (& powercfg.exe /getactivescheme) -join ' '
    if ($o -match $GuidRx) { return $Matches[0].ToLower() }
    return $null
}

function Get-PowerSetting([string]$Scheme, [string]$Sub, [string]$Setting) {
    $o = (& powercfg.exe /query $Scheme $Sub $Setting) -join "`n"
    $m = [regex]::Matches($o, '0x([0-9a-fA-F]{8})')
    if ($m.Count -ge 2) {
        return [pscustomobject]@{
            AC = [Convert]::ToInt32($m[$m.Count - 2].Groups[1].Value, 16)
            DC = [Convert]::ToInt32($m[$m.Count - 1].Groups[1].Value, 16)
        }
    }
    return $null
}

# ---------------------------------------------------------------------------------------------
#  Catalogue des optimisations
#  Chaque réglage : Id, Cat, Name, Desc, Profiles, Reg (valeurs de registre) et/ou Apply/Test
#  (réglages spéciaux). Apply reçoit une liste où il enregistre l'état d'origine AVANT de modifier.
# ---------------------------------------------------------------------------------------------
$Categories = @(
    [pscustomobject]@{ Id = 'jeux';      Title = 'Jeux et carte graphique';  Sub = 'Réglages officiels de Windows pour des jeux plus fluides. Compatibles NVIDIA GeForce RTX / GTX, AMD Radeon et Intel Arc / Iris : aucun pilote n''est modifié.' }
    [pscustomobject]@{ Id = 'chaleur';   Title = 'Température et énergie';   Sub = 'Moins de chaleur et de bruit, sans overclocking ni modification du matériel ou du BIOS.' }
    [pscustomobject]@{ Id = 'fluide';    Title = 'Fluidité de Windows';      Sub = 'Effets visuels allégés pour les PC modestes.' }
    [pscustomobject]@{ Id = 'pub';       Title = 'Publicités et suggestions'; Sub = 'Retire les publicités, suggestions et installations automatiques d''applications sponsorisées.' }
    [pscustomobject]@{ Id = 'vie';       Title = 'Confidentialité';          Sub = 'Moins de données envoyées et moins de tâches en arrière-plan, avec les options prévues par Microsoft.' }
    [pscustomobject]@{ Id = 'bureau';    Title = 'Bureau et télétravail';    Sub = 'Confort et sécurité au quotidien.' }
    [pscustomobject]@{ Id = 'entretien'; Title = 'Entretien';                Sub = 'Petites actions ponctuelles.' }
)

$ProfileLabels = @{ Jeux = 'Jeux'; Bureau = 'Bureau'; Chaleur = 'Anti-surchauffe' }

$CDM = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'

$TweakDefs = @(
    # ------------------------------ JEUX ------------------------------
    @{
        Id = 'GameMode'; Cat = 'jeux'; Profiles = @('Jeux')
        Name = 'Activer le Mode Jeu de Windows'
        Desc = "Windows donne la priorité au jeu en cours (processeur et carte graphique) et évite d'installer les mises à jour pendant que vous jouez."
        Reg = @(
            (RegV 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1),
            (RegV 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' 1)
        )
    }
    @{
        Id = 'HAGS'; Cat = 'jeux'; Profiles = @('Jeux'); MinBuild = 19041; Reboot = $true
        Name = 'Planification GPU à accélération matérielle'
        Desc = "La carte graphique gère elle-même sa mémoire vidéo : moins de latence. Indispensable pour la génération d'images DLSS (Frame Generation) des RTX 40 et 50. Fonctionne avec NVIDIA GTX 10 et plus récentes, AMD Radeon RX 5000 et plus récentes, Intel Arc, avec un pilote à jour. Sur une carte non compatible, Windows l'ignore."
        Warn = "En cas d'écran noir ou de saccades, restaurez ce réglage"
        Reg = @( (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2) )
    }
    @{
        Id = 'GameDVR'; Cat = 'jeux'; Profiles = @('Jeux', 'Chaleur')
        Name = "Arrêter l'enregistrement vidéo en arrière-plan (Xbox Game Bar)"
        Desc = "L'enregistrement permanent des dernières minutes de jeu consomme de la puissance graphique et fait chauffer. La Game Bar reste disponible ; NVIDIA ShadowPlay et AMD ReLive ne sont pas concernés."
        Reg = @(
            (RegV 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0),
            (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0)
        )
    }
    @{
        Id = 'DXWindowed'; Cat = 'jeux'; Profiles = @('Jeux'); MinBuild = 22000
        Name = 'Optimisations pour les jeux en mode fenêtré (Windows 11)'
        Desc = "Réglage officiel de Windows 11 : moins de latence et prise en charge de l'Auto HDR et du VRR (G-SYNC / FreeSync) dans les jeux DirectX 10 et 11 en fenêtré ou plein écran sans bordure."
        Apply = {
            param($items)
            $p = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'; $n = 'DirectXUserGlobalSettings'
            $items.Add((New-RegBackup $p $n))
            $c = Read-Reg $p $n
            $s = ''
            if ($c.Exists) { $s = [string]$c.Value }
            Write-Reg $p $n (Set-KVString $s 'SwapEffectUpgradeEnable' '1') 'String'
        }
        Test = {
            $c = Read-Reg 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' 'DirectXUserGlobalSettings'
            $c.Exists -and ([string]$c.Value -match '(^|;)SwapEffectUpgradeEnable=1(;|$)')
        }
    }
    @{
        Id = 'MouseAccel'; Cat = 'jeux'; Profiles = @('Jeux'); Reboot = $true
        Name = 'Désactiver l''accélération de la souris'
        Desc = "Désactive « Améliorer la précision du pointeur » : la souris réagit toujours de la même façon, la visée devient plus précise."
        Reg = @(
            (RegV 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0' 'String'),
            (RegV 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0' 'String'),
            (RegV 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0' 'String')
        )
    }
    @{
        Id = 'StickyKeys'; Cat = 'jeux'; Profiles = @('Jeux'); Reboot = $true
        Name = 'Ne plus ouvrir les touches rémanentes avec 5 appuis sur Maj'
        Desc = "Évite que la fenêtre des touches rémanentes interrompe le jeu. La fonction d'accessibilité reste utilisable dans les Paramètres."
        Reg = @( (RegV 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' '506' 'String') )
    }

    # ------------------------------ TEMPÉRATURE ------------------------------
    @{
        Id = 'PowerBalanced'; Cat = 'chaleur'; Profiles = @('Jeux', 'Bureau', 'Chaleur')
        Name = 'Mode d''alimentation « Utilisation normale » (Équilibré)'
        Desc = "Le mode recommandé par Microsoft : le processeur accélère instantanément quand un jeu le demande et ralentit au repos. Le mode « Performances élevées » garde le processeur chaud en permanence pour un gain quasi nul sur les processeurs Intel et AMD récents."
        Apply = {
            param($items)
            $items.Add([pscustomobject]@{ Type = 'Power'; Guid = (Get-ActiveScheme) })
            & powercfg.exe /setactive $BalancedGuid | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Le mode Équilibré est introuvable sur ce PC.' }
        }
        Test = { (Get-ActiveScheme) -eq $BalancedGuid }
    }
    @{
        Id = 'CpuNoBoost'; Cat = 'chaleur'; Profiles = @('Chaleur')
        Name = 'Anti-surchauffe : limiter le processeur à 99 % (désactive le Turbo)'
        Desc = "Désactive en général le Turbo Boost (Intel) et le Precision Boost (AMD) dans le mode d'alimentation actuel : température et bruit des ventilateurs nettement plus bas. Idéal pour les portables qui chauffent. Ne touche ni au BIOS ni au matériel."
        Warn = 'Performances un peu plus basses en jeu'
        Apply = {
            param($items)
            $s = Get-ActiveScheme
            $v = Get-PowerSetting $s 'SUB_PROCESSOR' 'PROCTHROTTLEMAX'
            if (-not $v) { throw 'Réglage du processeur illisible.' }
            $items.Add([pscustomobject]@{ Type = 'PowerValue'; Scheme = $s; Sub = 'SUB_PROCESSOR'; Setting = 'PROCTHROTTLEMAX'; AC = $v.AC; DC = $v.DC })
            & powercfg.exe /setacvalueindex $s SUB_PROCESSOR PROCTHROTTLEMAX 99 | Out-Null
            & powercfg.exe /setdcvalueindex $s SUB_PROCESSOR PROCTHROTTLEMAX 99 | Out-Null
            & powercfg.exe /setactive $s | Out-Null
        }
        Test = {
            $v = Get-PowerSetting (Get-ActiveScheme) 'SUB_PROCESSOR' 'PROCTHROTTLEMAX'
            [bool]($v -and $v.AC -le 99 -and $v.DC -le 99)
        }
    }
    @{
        Id = 'BackgroundApps'; Cat = 'chaleur'; Profiles = @('Chaleur')
        Name = 'Empêcher les applications du Store de tourner en arrière-plan'
        Desc = "Météo, Actualités et autres applications du Microsoft Store ne restent plus actives cachées : moins de charge et de chaleur. Selon la version de Windows, certaines applications gèrent ce réglage elles-mêmes."
        Warn = 'Certaines notifications (Courrier, Lien avec votre téléphone) peuvent ne plus arriver application fermée'
        Reg = @(
            (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1),
            (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BackgroundAppGlobalToggle' 0)
        )
    }

    # ------------------------------ FLUIDITÉ ------------------------------
    @{
        Id = 'Transparency'; Cat = 'fluide'; Profiles = @('Chaleur')
        Name = 'Désactiver les effets de transparence'
        Desc = 'Barre des tâches et menus opaques : un peu moins de travail pour la carte graphique, utile sur les PC portables et modestes.'
        Reg = @( (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0) )
    }
    @{
        Id = 'Animations'; Cat = 'fluide'; Reboot = $true
        Name = 'Réduire les animations des fenêtres'
        Desc = 'Les fenêtres s''ouvrent et se réduisent sans animation : Windows paraît plus réactif sur les PC modestes.'
        Reg = @(
            (RegV 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String'),
            (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 0)
        )
    }

    # ------------------------------ PUBLICITÉS ------------------------------
    @{
        Id = 'Suggestions'; Cat = 'pub'; Profiles = @('Jeux', 'Bureau')
        Name = 'Retirer les suggestions et publicités de Windows'
        Desc = "Plus de suggestions d'applications dans le menu Démarrer, de « conseils » publicitaires dans les Paramètres ni d'anecdotes sur l'écran de verrouillage."
        Reg = @(
            (RegV $CDM 'SubscribedContent-338388Enabled' 0),
            (RegV $CDM 'SubscribedContent-338389Enabled' 0),
            (RegV $CDM 'SubscribedContent-338387Enabled' 0),
            (RegV $CDM 'SubscribedContent-353694Enabled' 0),
            (RegV $CDM 'SubscribedContent-353696Enabled' 0),
            (RegV $CDM 'SubscribedContent-310093Enabled' 0),
            (RegV $CDM 'SystemPaneSuggestionsEnabled' 0),
            (RegV $CDM 'SoftLandingEnabled' 0),
            (RegV $CDM 'RotatingLockScreenOverlayEnabled' 0)
        )
    }
    @{
        Id = 'SilentApps'; Cat = 'pub'; Profiles = @('Jeux', 'Bureau')
        Name = 'Bloquer l''installation automatique d''applications sponsorisées'
        Desc = 'Empêche Windows d''installer tout seul des jeux et applications promotionnelles (Candy Crush, etc.).'
        Reg = @(
            (RegV $CDM 'SilentInstalledAppsEnabled' 0),
            (RegV $CDM 'PreInstalledAppsEnabled' 0),
            (RegV $CDM 'OemPreInstalledAppsEnabled' 0)
        )
    }
    @{
        Id = 'Scoobe'; Cat = 'pub'; Profiles = @('Jeux', 'Bureau')
        Name = 'Supprimer l''écran « Tirons encore plus parti de Windows »'
        Desc = 'Cet écran apparaît après certaines mises à jour pour proposer des abonnements et services. Il ne s''affichera plus.'
        Reg = @( (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0) )
    }
    @{
        Id = 'Widgets11'; Cat = 'pub'; Profiles = @('Jeux', 'Bureau'); MinBuild = 22000; Reboot = $true
        Name = 'Désactiver les Widgets (actualités MSN)'
        Desc = 'Retire le panneau d''actualités de la barre des tâches, qui charge des pages web et des publicités en arrière-plan.'
        Reg = @( (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0) )
    }
    @{
        Id = 'Widgets10'; Cat = 'pub'; Profiles = @('Jeux', 'Bureau'); MaxBuild = 21999; Reboot = $true
        Name = 'Désactiver « Actualités et centres d''intérêt » (barre des tâches)'
        Desc = 'Retire la météo et les actualités MSN de la barre des tâches de Windows 10, qui se mettent à jour en permanence en arrière-plan.'
        Reg = @( (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' 'EnableFeeds' 0) )
    }
    @{
        Id = 'BingSearch'; Cat = 'pub'; Profiles = @('Bureau'); Reboot = $true
        Name = 'Recherche du menu Démarrer sans Bing ni web'
        Desc = 'La recherche du menu Démarrer cherche uniquement sur votre PC : plus rapide, sans résultats web ni publicités. Pour Internet, utilisez votre navigateur.'
        Reg = @(
            (RegV 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1),
            (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0)
        )
    }

    # ------------------------------ CONFIDENTIALITÉ ------------------------------
    @{
        Id = 'AdId'; Cat = 'vie'; Profiles = @('Jeux', 'Bureau')
        Name = 'Désactiver l''identifiant de publicité'
        Desc = 'Les applications ne peuvent plus utiliser cet identifiant pour vous montrer des publicités ciblées (réglage de Paramètres > Confidentialité).'
        Reg = @( (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0) )
    }
    @{
        Id = 'Telemetry'; Cat = 'vie'; Reboot = $true
        Name = 'Données de diagnostic au minimum (« Obligatoires »)'
        Desc = "Limite les données envoyées à Microsoft au niveau minimum prévu par Microsoft pour Windows Famille et Professionnel, et désactive les « expériences personnalisées ». Windows Update fonctionne normalement. Les Paramètres afficheront « Certains paramètres sont gérés par votre organisation » : c'est normal."
        Reg = @(
            (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 1),
            (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0)
        )
    }
    @{
        Id = 'DiagTrack'; Cat = 'vie'
        Name = 'Arrêter le service « Expériences des utilisateurs connectés et télémétrie »'
        Desc = 'Ce service (DiagTrack) envoie les données de diagnostic en arrière-plan. L''arrêter libère un peu de ressources ; il peut être réactivé à tout moment depuis l''onglet Restaurer.'
        Apply = {
            param($items)
            $svc = Get-Service -Name 'DiagTrack' -ErrorAction Stop
            $items.Add([pscustomobject]@{ Type = 'Service'; Name = 'DiagTrack'; StartType = $svc.StartType.ToString() })
            Stop-Service -Name 'DiagTrack' -Force -ErrorAction SilentlyContinue
            Set-Service -Name 'DiagTrack' -StartupType Disabled -ErrorAction Stop
        }
        Test = {
            $s = Get-Service -Name 'DiagTrack' -ErrorAction SilentlyContinue
            (-not $s) -or ($s.StartType.ToString() -eq 'Disabled')
        }
    }
    @{
        Id = 'Activity'; Cat = 'vie'; Profiles = @('Bureau')
        Name = 'Désactiver l''historique des activités'
        Desc = 'Windows n''enregistre plus la liste des documents et sites que vous avez ouverts, et ne l''envoie pas à Microsoft.'
        Reg = @(
            (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 0),
            (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' 0)
        )
    }
    @{
        Id = 'Recall'; Cat = 'vie'; MinBuild = 26100; Reboot = $true
        Name = 'Désactiver Recall (captures d''écran automatiques)'
        Desc = 'Concerne seulement les PC « Copilot+ » : Windows n''enregistre plus de captures régulières de votre écran. Sans effet sur les autres PC.'
        Reg = @( (RegV 'HKCU:\Software\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1) )
    }
    @{
        Id = 'DeliveryOpt'; Cat = 'vie'; Profiles = @('Jeux', 'Bureau')
        Name = 'Ne pas partager vos mises à jour avec d''autres PC sur Internet'
        Desc = 'Windows Update télécharge directement chez Microsoft sans envoyer de morceaux de mises à jour à des PC inconnus : votre connexion reste libre pour les jeux et la visioconférence.'
        Reg = @( (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0) )
    }

    # ------------------------------ BUREAU ------------------------------
    @{
        Id = 'FileExt'; Cat = 'bureau'; Profiles = @('Bureau')
        Name = 'Afficher les extensions des fichiers (.pdf, .docx, .exe...)'
        Desc = 'Plus pratique et plus sûr : un faux « facture.pdf.exe » envoyé par e-mail devient facile à repérer.'
        Reg = @( (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideFileExt' 0) )
    }
    @{
        Id = 'ThisPC'; Cat = 'bureau'; Profiles = @('Bureau')
        Name = 'L''Explorateur de fichiers s''ouvre sur « Ce PC »'
        Desc = 'Accès direct à vos disques et dossiers au lieu de la page « Accueil / Accès rapide ».'
        Reg = @( (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'LaunchTo' 1) )
    }
    @{
        Id = 'Clipboard'; Cat = 'bureau'; Profiles = @('Bureau')
        Name = 'Activer l''historique du presse-papiers (touches Windows + V)'
        Desc = 'Retrouvez les derniers textes et images copiés. Rien n''est synchronisé sur Internet.'
        Reg = @( (RegV 'HKCU:\Software\Microsoft\Clipboard' 'EnableClipboardHistory' 1) )
    }
    @{
        Id = 'StorageSense'; Cat = 'bureau'; Profiles = @('Bureau')
        Name = 'Activer l''Assistant Stockage'
        Desc = 'Windows supprime automatiquement les fichiers temporaires et les anciens éléments de la corbeille quand le disque se remplit. Réglable dans Paramètres > Système > Stockage.'
        Reg = @( (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '01' 1) )
    }

    # ------------------------------ ENTRETIEN ------------------------------
    @{
        Id = 'TempClean'; Cat = 'entretien'; NoUndo = $true
        Name = 'Nettoyer les fichiers temporaires (plus de 2 jours)'
        Desc = 'Supprime les fichiers temporaires de votre compte et de Windows qui ont plus de 2 jours. Les fichiers en cours d''utilisation sont ignorés. Vos documents ne sont jamais touchés.'
        Warn = 'Action définitive (fichiers temporaires uniquement)'
        Apply = {
            param($items)
            $limit = (Get-Date).AddDays(-2)
            $freed = [long]0; $count = 0
            foreach ($dir in @($env:TEMP, (Join-Path $env:SystemRoot 'Temp'))) {
                if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { continue }
                $files = @(Get-ChildItem -LiteralPath $dir -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $limit })
                foreach ($f in $files) {
                    $len = $f.Length
                    try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $freed += $len; $count++ } catch { }
                }
            }
            Write-Log ('Nettoyage : {0} fichier(s) supprimé(s), {1:N1} Mo libérés.' -f $count, ($freed / 1MB))
        }
    }
)

function ConvertTo-Tweak([hashtable]$h) {
    $d = @{ Profiles = @(); Reg = @(); Apply = $null; Test = $null; MinBuild = 0; MaxBuild = 999999; Reboot = $false; NoUndo = $false; Warn = '' }
    foreach ($k in $h.Keys) { $d[$k] = $h[$k] }
    $d.Undoable = -not $d.NoUndo
    return [pscustomobject]$d
}
$Tweaks = @(foreach ($h in $TweakDefs) { ConvertTo-Tweak $h })

function Test-TweakAvailable($t) { return ($Build -ge $t.MinBuild -and $Build -le $t.MaxBuild) }

function Test-TweakApplied($t) {
    if ($t.Test) { try { return [bool](& $t.Test) } catch { return $false } }
    if (-not $t.Undoable -or @($t.Reg).Count -eq 0) { return $false }
    foreach ($r in $t.Reg) {
        $c = Read-Reg $r.Path $r.Name
        if (-not $c.Exists -or ([string]$c.Value -ne [string]$r.Value)) { return $false }
    }
    return $true
}

# ---------------------------------------------------------------------------------------------
#  Sauvegarde des réglages d'origine (fichier JSON dans %LOCALAPPDATA%\OptimiseurPC)
# ---------------------------------------------------------------------------------------------
$Backup      = @{}
$RemovedApps = New-Object System.Collections.ArrayList

function Save-Data {
    $obj = [pscustomobject]@{ Version = 1; Tweaks = @($Backup.Values); Apps = @($RemovedApps) }
    $obj | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $DataFile -Encoding UTF8
}

function Import-Data {
    $Backup.Clear(); $RemovedApps.Clear()
    if (-not (Test-Path -LiteralPath $DataFile)) { return }
    try {
        $d = Get-Content -LiteralPath $DataFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($e in @($d.Tweaks)) { if ($e -and $e.Id) { $Backup[$e.Id] = $e } }
        foreach ($a in @($d.Apps))   { if ($a -and $a.Family) { [void]$RemovedApps.Add($a) } }
    } catch {
        Write-Log ('Fichier de sauvegarde illisible : ' + $_.Exception.Message)
    }
}

function Invoke-Tweak($t) {
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($r in $t.Reg) { $items.Add((New-RegBackup $r.Path $r.Name)) }
    try {
        if ($t.Apply) { & $t.Apply $items }
        foreach ($r in $t.Reg) { Write-Reg $r.Path $r.Name $r.Value $r.Type }
    } finally {
        # L'état d'origine est enregistré même si une erreur survient en cours de route.
        # S'il existe déjà une sauvegarde, on la garde : c'est elle qui contient le vrai réglage d'origine.
        if ($t.Undoable -and $items.Count -gt 0 -and -not $Backup.ContainsKey($t.Id)) {
            $Backup[$t.Id] = [pscustomobject]@{
                Id = $t.Id; Name = $t.Name; Reboot = $t.Reboot
                Date = (Get-Date).ToString('yyyy-MM-dd HH:mm'); Items = $items.ToArray()
            }
            Save-Data
        }
    }
}

function Undo-Tweak($entry) {
    $items = @($entry.Items)
    [array]::Reverse($items)
    $errors = @()
    foreach ($i in $items) {
        try {
            switch ($i.Type) {
                'Reg' {
                    if ($i.Exists) {
                        $v = $i.Value
                        if ($i.Kind -eq 'Binary')      { $v = [byte[]]@($v) }
                        if ($i.Kind -eq 'MultiString') { $v = [string[]]@($v) }
                        Write-Reg $i.Path $i.Name $v $i.Kind
                    } else {
                        Remove-ItemProperty -LiteralPath $i.Path -Name $i.Name -ErrorAction SilentlyContinue
                    }
                }
                'Power' {
                    if ($i.Guid) { & powercfg.exe /setactive $i.Guid | Out-Null }
                }
                'PowerValue' {
                    & powercfg.exe /setacvalueindex $i.Scheme $i.Sub $i.Setting $i.AC | Out-Null
                    & powercfg.exe /setdcvalueindex $i.Scheme $i.Sub $i.Setting $i.DC | Out-Null
                    & powercfg.exe /setactive (Get-ActiveScheme) | Out-Null
                }
                'Service' {
                    Set-Service -Name $i.Name -StartupType $i.StartType -ErrorAction Stop
                    if ($i.StartType -eq 'Automatic') { Start-Service -Name $i.Name -ErrorAction SilentlyContinue }
                }
            }
        } catch {
            $errors += $_.Exception.Message
        }
    }
    if ($errors.Count -gt 0) { throw ($errors -join ' | ') }
    $Backup.Remove($entry.Id)
    Save-Data
}

# ---------------------------------------------------------------------------------------------
#  Applications préinstallées inutiles (désinstallées pour votre compte uniquement,
#  réinstallables gratuitement depuis le Microsoft Store). Les applications Xbox sont
#  volontairement absentes : elles servent aux jeux (Game Pass, Game Bar, manettes).
# ---------------------------------------------------------------------------------------------
$AppCatalog = @(
    @{ P = 'Microsoft.BingNews';                     N = 'Actualités (Microsoft Start / MSN)'; S = $true }
    @{ P = 'Microsoft.BingWeather';                  N = 'Météo MSN'; S = $true }
    @{ P = 'Microsoft.BingSearch';                   N = 'Recherche Bing'; S = $true }
    @{ P = 'Microsoft.GetHelp';                      N = 'Obtenir de l''aide'; S = $true }
    @{ P = 'Microsoft.Getstarted';                   N = 'Astuces / Prise en main'; S = $true }
    @{ P = 'Microsoft.MicrosoftSolitaireCollection'; N = 'Microsoft Solitaire Collection (avec publicités)'; S = $true }
    @{ P = 'Microsoft.People';                       N = 'Contacts'; S = $true }
    @{ P = 'Microsoft.WindowsFeedbackHub';           N = 'Hub de commentaires'; S = $true }
    @{ P = 'Microsoft.ZuneVideo';                    N = 'Films et TV'; S = $true }
    @{ P = 'Microsoft.SkypeApp';                     N = 'Skype'; S = $true; Note = 'Service arrêté par Microsoft en 2025.' }
    @{ P = 'Microsoft.Microsoft3DViewer';            N = 'Visionneuse 3D'; S = $true }
    @{ P = 'Microsoft.Print3D';                      N = 'Print 3D'; S = $true }
    @{ P = 'Microsoft.MSPaint';                      N = 'Paint 3D'; S = $true; Note = 'Le Paint classique n''est pas concerné.' }
    @{ P = 'Microsoft.MixedReality.Portal';          N = 'Portail de réalité mixte'; S = $true; Note = 'Utile seulement avec un casque Windows Mixed Reality.' }
    @{ P = 'Microsoft.Wallet';                       N = 'Microsoft Pay / Wallet'; S = $true }
    @{ P = 'Microsoft.WindowsMaps';                  N = 'Cartes'; S = $true }
    @{ P = 'Microsoft.Messaging';                    N = 'Messages'; S = $true }
    @{ P = 'Microsoft.OneConnect';                   N = 'Forfaits mobiles'; S = $true }
    @{ P = 'Microsoft.549981C3F5F10';                N = 'Cortana'; S = $true; Note = 'Abandonnée par Microsoft.' }
    @{ P = 'Microsoft.PowerAutomateDesktop';         N = 'Power Automate'; S = $true; Note = 'Gardez-la si vous automatisez des tâches.' }
    @{ P = 'MicrosoftTeams';                         N = 'Microsoft Teams (personnel / « Conversation »)'; S = $true; Note = 'La version Travail ou scolaire n''est pas concernée.' }
    @{ P = 'Microsoft.MicrosoftOfficeHub';           N = 'Microsoft 365 (Office) - application de lancement'; S = $false; Note = 'Ne désinstalle PAS Word, Excel ou PowerPoint.' }
    @{ P = 'Microsoft.Todos';                        N = 'Microsoft To Do'; S = $false; Note = 'Utile pour les listes de tâches.' }
    @{ P = 'Clipchamp.Clipchamp';                    N = 'Clipchamp (montage vidéo)'; S = $false; Note = 'Gardez-la si vous montez des vidéos.' }
    @{ P = 'Microsoft.Copilot';                      N = 'Copilot'; S = $false; Note = 'Assistant IA de Microsoft.' }
    @{ P = 'Microsoft.YourPhone';                    N = 'Lien avec votre téléphone'; S = $false; Note = 'Gardez-la si vous lisez vos SMS sur le PC.' }
    @{ P = 'microsoft.windowscommunicationsapps';    N = 'Courrier et Calendrier'; S = $false; Note = 'Abandonnés par Microsoft (remplacés par Outlook). Gardez-les si vous les utilisez encore.' }
    @{ P = 'MicrosoftCorporationII.QuickAssist';     N = 'Assistance rapide'; S = $false; Note = 'Souvent utilisée par les escrocs au faux support technique. Gardez-la si un proche vous dépanne à distance.' }
    @{ P = 'king.com.*';                             N = 'Jeux King (Candy Crush...) - sponsorisé'; S = $true }
    @{ P = '*Disney*';                               N = 'Disney+ - sponsorisé'; S = $false }
    @{ P = '*TikTok*';                               N = 'TikTok - sponsorisé'; S = $true }
    @{ P = '*Facebook*';                             N = 'Facebook - sponsorisé'; S = $true }
    @{ P = '*Instagram*';                            N = 'Instagram - sponsorisé'; S = $true }
    @{ P = '*LinkedIn*';                             N = 'LinkedIn - sponsorisé'; S = $false }
    @{ P = '*Twitter*';                              N = 'X (Twitter) - sponsorisé'; S = $true }
    @{ P = '*Spotify*';                              N = 'Spotify'; S = $false; Note = 'Gardez-la si vous l''utilisez.' }
    @{ P = '*PrimeVideo*';                           N = 'Prime Video'; S = $false }
    @{ P = '*Netflix*';                              N = 'Netflix'; S = $false }
)

function Get-BloatApps {
    $all = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { -not $_.IsFramework -and -not $_.NonRemovable })
    $seen = @{}
    $res = New-Object System.Collections.Generic.List[object]
    foreach ($e in $AppCatalog) {
        foreach ($p in @($all | Where-Object { $_.Name -like $e.P })) {
            if ($seen.ContainsKey($p.PackageFullName)) { continue }
            $seen[$p.PackageFullName] = $true
            $res.Add([pscustomobject]@{
                Name = $e.N; Note = $e.Note; Suggest = [bool]$e.S
                FullName = $p.PackageFullName; Family = $p.PackageFamilyName; PkgName = $p.Name
            })
        }
    }
    return $res.ToArray()
}

Import-Data

# ---------------------------------------------------------------------------------------------
#  Interface (WPF, intégrée à Windows)
# ---------------------------------------------------------------------------------------------
$XamlText = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Optimiseur PC" Width="1120" Height="780" MinWidth="900" MinHeight="620"
        WindowStartupLocation="CenterScreen" Background="#0E1116" Foreground="#E6E9EF"
        FontFamily="Segoe UI" FontSize="13" UseLayoutRounding="True" TextOptions.TextFormattingMode="Display">
  <Window.Resources>
    <SolidColorBrush x:Key="Muted" Color="#97A1B3"/>
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="#161A22"/>
      <Setter Property="BorderBrush" Value="#242B39"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="12"/>
      <Setter Property="Padding" Value="18"/>
      <Setter Property="Margin" Value="8"/>
    </Style>
    <Style x:Key="ItemCard" TargetType="Border">
      <Setter Property="Background" Value="#161A22"/>
      <Setter Property="BorderBrush" Value="#242B39"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="10"/>
      <Setter Property="Padding" Value="14,12"/>
      <Setter Property="Margin" Value="0,0,0,8"/>
    </Style>
    <Style x:Key="H2" TargetType="TextBlock">
      <Setter Property="FontSize" Value="16"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Margin" Value="0,0,0,10"/>
    </Style>
    <Style x:Key="Label" TargetType="TextBlock">
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Foreground" Value="#97A1B3"/>
    </Style>
    <Style x:Key="Para" TargetType="TextBlock">
      <Setter Property="TextWrapping" Value="Wrap"/>
      <Setter Property="Foreground" Value="#C3CAD6"/>
      <Setter Property="Margin" Value="0,0,0,8"/>
      <Setter Property="LineHeight" Value="20"/>
    </Style>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="Background" Value="#252C3B"/>
      <Setter Property="Padding" Value="14,8"/>
      <Setter Property="Margin" Value="0,0,8,8"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.85"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.7"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Accent" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="#2F6FED"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="22,11"/>
      <Setter Property="Margin" Value="0"/>
    </Style>
    <Style x:Key="Danger" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="#B83A3A"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="22,11"/>
      <Setter Property="Margin" Value="0"/>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="#E6E9EF"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
    </Style>
    <Style TargetType="ProgressBar">
      <Setter Property="Height" Value="8"/>
      <Setter Property="Background" Value="#262D3B"/>
      <Setter Property="Foreground" Value="#2F6FED"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Maximum" Value="100"/>
    </Style>
    <Style TargetType="TabItem">
      <Setter Property="Foreground" Value="#AEB6C6"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TabItem">
            <Border x:Name="Bd" Padding="16,9" Margin="0,0,6,0" CornerRadius="8" Background="Transparent">
              <ContentPresenter ContentSource="Header" HorizontalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="#1B2130"/></Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#22345A"/>
                <Setter Property="Foreground" Value="White"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- En-tête -->
    <Border Grid.Row="0" Padding="24,18,24,6">
      <DockPanel>
        <Border DockPanel.Dock="Right" VerticalAlignment="Center" Background="#14301F" CornerRadius="10" Padding="12,5">
          <TextBlock x:Name="TxtVersion" Foreground="#5BD48A" FontSize="12"/>
        </Border>
        <StackPanel>
          <TextBlock Text="Optimiseur PC" FontSize="26" FontWeight="Bold"/>
          <TextBlock x:Name="TxtSubtitle" Foreground="{StaticResource Muted}" Margin="0,2,0,0" TextWrapping="Wrap"/>
        </StackPanel>
      </DockPanel>
    </Border>

    <TabControl x:Name="Tabs" Grid.Row="1" Margin="16,6,16,0" Background="Transparent" BorderThickness="0" Padding="0,10,0,0">

      <!-- ============ TABLEAU DE BORD ============ -->
      <TabItem Header="Tableau de bord" x:Name="TabDash">
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions>
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>

            <Border Style="{StaticResource Card}" Grid.Column="0">
              <StackPanel>
                <TextBlock Text="Votre matériel" Style="{StaticResource H2}"/>
                <TextBlock Text="Processeur" Style="{StaticResource Label}"/>
                <TextBlock x:Name="TxtCpu" TextWrapping="Wrap" Margin="0,1,0,10"/>
                <TextBlock Text="Carte(s) graphique(s)" Style="{StaticResource Label}"/>
                <TextBlock x:Name="TxtGpu" TextWrapping="Wrap" Margin="0,1,0,10"/>
                <TextBlock Text="Mémoire vive" Style="{StaticResource Label}"/>
                <TextBlock x:Name="TxtRam" TextWrapping="Wrap" Margin="0,1,0,10"/>
                <TextBlock Text="Windows" Style="{StaticResource Label}"/>
                <TextBlock x:Name="TxtOs" TextWrapping="Wrap" Margin="0,1,0,0"/>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}" Grid.Column="1">
              <StackPanel>
                <TextBlock Text="Surveillance en direct" Style="{StaticResource H2}"/>
                <Grid Margin="0,4">
                  <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition/><ColumnDefinition Width="70"/></Grid.ColumnDefinitions>
                  <TextBlock Text="Processeur" VerticalAlignment="Center"/>
                  <ProgressBar x:Name="PbCpu" Grid.Column="1" VerticalAlignment="Center"/>
                  <TextBlock x:Name="TxtCpuVal" Grid.Column="2" Text="..." TextAlignment="Right" VerticalAlignment="Center"/>
                </Grid>
                <Grid Margin="0,8">
                  <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition/><ColumnDefinition Width="70"/></Grid.ColumnDefinitions>
                  <TextBlock Text="Carte graphique" VerticalAlignment="Center"/>
                  <ProgressBar x:Name="PbGpu" Grid.Column="1" VerticalAlignment="Center"/>
                  <TextBlock x:Name="TxtGpuVal" Grid.Column="2" Text="..." TextAlignment="Right" VerticalAlignment="Center"/>
                </Grid>
                <Grid Margin="0,4">
                  <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition/><ColumnDefinition Width="70"/></Grid.ColumnDefinitions>
                  <TextBlock Text="Mémoire" VerticalAlignment="Center"/>
                  <ProgressBar x:Name="PbRam" Grid.Column="1" VerticalAlignment="Center"/>
                  <TextBlock x:Name="TxtRamVal" Grid.Column="2" Text="..." TextAlignment="Right" VerticalAlignment="Center"/>
                </Grid>
                <Border Height="1" Background="#242B39" Margin="0,12"/>
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="190"/><ColumnDefinition/></Grid.ColumnDefinitions>
                  <Grid.RowDefinitions><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
                  <TextBlock Text="Température carte graphique"/>
                  <TextBlock x:Name="TxtGpuTemp" Grid.Column="1" TextWrapping="Wrap" FontWeight="SemiBold" Text="..."/>
                  <TextBlock Grid.Row="1" Text="Température processeur" Margin="0,8,0,0"/>
                  <TextBlock x:Name="TxtCpuTemp" Grid.Row="1" Grid.Column="1" TextWrapping="Wrap" FontWeight="SemiBold" Margin="0,8,0,0" Text="..."/>
                </Grid>
                <Border x:Name="HeatBox" CornerRadius="8" Padding="12,9" Margin="0,14,0,0" Background="#1B2130">
                  <TextBlock x:Name="TxtHeat" TextWrapping="Wrap" Text="Mesure en cours..."/>
                </Border>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}" Grid.Row="1" Grid.ColumnSpan="2">
              <StackPanel>
                <TextBlock Text="Conseils pour votre matériel" Style="{StaticResource H2}"/>
                <StackPanel x:Name="PanelTips"/>
                <WrapPanel x:Name="PanelLinks" Margin="0,8,0,0"/>
              </StackPanel>
            </Border>
          </Grid>
        </ScrollViewer>
      </TabItem>

      <!-- ============ OPTIMISATIONS ============ -->
      <TabItem Header="Optimisations" x:Name="TabOpt">
        <DockPanel>
          <Border DockPanel.Dock="Top" Style="{StaticResource Card}" Margin="8,0,8,8" Padding="16,12">
            <StackPanel>
              <TextBlock Style="{StaticResource Para}" Text="Rien n'est modifié tant que vous n'avez pas coché une case ET confirmé. Les boutons « Suggestion » ne font que cocher des cases : vérifiez, décochez ce que vous ne voulez pas, puis cliquez sur « Appliquer la sélection »."/>
              <WrapPanel>
                <Button x:Name="BtnProfGame"   Content="Suggestion Jeux"/>
                <Button x:Name="BtnProfOffice" Content="Suggestion Bureau / télétravail"/>
                <Button x:Name="BtnProfHeat"   Content="Suggestion Anti-surchauffe"/>
                <Button x:Name="BtnProfNone"   Content="Tout décocher"/>
              </WrapPanel>
            </StackPanel>
          </Border>
          <Border DockPanel.Dock="Bottom" Style="{StaticResource Card}" Margin="8" Padding="16,12">
            <DockPanel>
              <Button x:Name="BtnApply" DockPanel.Dock="Right" Style="{StaticResource Accent}" Content="Appliquer la sélection (0)" VerticalAlignment="Center"/>
              <StackPanel VerticalAlignment="Center" Margin="0,0,16,0">
                <CheckBox x:Name="ChkRestore" IsChecked="True" Content="Créer un point de restauration Windows avant (recommandé)"/>
                <TextBlock Foreground="{StaticResource Muted}" FontSize="12" Margin="21,3,0,0" TextWrapping="Wrap" Text="Vos réglages d'origine sont aussi sauvegardés par l'application : vous pourrez tout annuler dans l'onglet « Restaurer »."/>
              </StackPanel>
            </DockPanel>
          </Border>
          <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="8,0,8,0">
            <StackPanel x:Name="PanelTweaks" Margin="0,0,6,0"/>
          </ScrollViewer>
        </DockPanel>
      </TabItem>

      <!-- ============ APPLICATIONS ============ -->
      <TabItem Header="Applications inutiles" x:Name="TabApps">
        <DockPanel>
          <Border DockPanel.Dock="Top" Style="{StaticResource Card}" Margin="8,0,8,8" Padding="16,12">
            <StackPanel>
              <TextBlock Style="{StaticResource Para}" Text="Applications préinstallées détectées sur ce PC. Elles sont désinstallées uniquement pour votre compte, avec l'outil officiel de Windows, et restent réinstallables gratuitement depuis le Microsoft Store (onglet « Restaurer »). Les applications Xbox, le Microsoft Store, la Calculatrice, Photos, Paint et les pilotes ne sont jamais proposés."/>
              <WrapPanel>
                <Button x:Name="BtnAppsSuggest" Content="Cocher les suggestions"/>
                <Button x:Name="BtnAppsNone"    Content="Tout décocher"/>
                <Button x:Name="BtnAppsRefresh" Content="Actualiser la liste"/>
              </WrapPanel>
            </StackPanel>
          </Border>
          <Border DockPanel.Dock="Bottom" Style="{StaticResource Card}" Margin="8" Padding="16,12">
            <DockPanel>
              <Button x:Name="BtnRemoveApps" DockPanel.Dock="Right" Style="{StaticResource Danger}" Content="Désinstaller la sélection (0)" VerticalAlignment="Center"/>
              <TextBlock VerticalAlignment="Center" TextWrapping="Wrap" Foreground="{StaticResource Muted}" Margin="0,0,16,0" Text="Une confirmation vous sera demandée avec la liste exacte des applications."/>
            </DockPanel>
          </Border>
          <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="8,0,8,0">
            <StackPanel x:Name="PanelApps" Margin="0,0,6,0"/>
          </ScrollViewer>
        </DockPanel>
      </TabItem>

      <!-- ============ RESTAURER ============ -->
      <TabItem Header="Restaurer" x:Name="TabUndo">
        <DockPanel>
          <Border DockPanel.Dock="Top" Style="{StaticResource Card}" Margin="8,0,8,8" Padding="16,12">
            <StackPanel>
              <TextBlock Style="{StaticResource Para}" Text="Remettez n'importe quel réglage comme il était avant. Vous pouvez aussi utiliser la Restauration du système de Windows pour revenir au point de restauration créé avant les modifications."/>
              <WrapPanel>
                <Button x:Name="BtnUndoAll"  Content="Tout cocher"/>
                <Button x:Name="BtnUndoNone" Content="Tout décocher"/>
                <Button x:Name="BtnRstrui"   Content="Ouvrir la Restauration du système"/>
                <Button x:Name="BtnLogs"     Content="Ouvrir le dossier du journal"/>
              </WrapPanel>
            </StackPanel>
          </Border>
          <Border DockPanel.Dock="Bottom" Style="{StaticResource Card}" Margin="8" Padding="16,12">
            <DockPanel>
              <Button x:Name="BtnUndo" DockPanel.Dock="Right" Style="{StaticResource Accent}" Content="Restaurer la sélection (0)" VerticalAlignment="Center"/>
              <TextBlock VerticalAlignment="Center" TextWrapping="Wrap" Foreground="{StaticResource Muted}" Margin="0,0,16,0" Text="Une confirmation vous sera demandée."/>
            </DockPanel>
          </Border>
          <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="8,0,8,0">
            <StackPanel Margin="0,0,6,0">
              <TextBlock Text="Réglages modifiés" Style="{StaticResource H2}" Margin="4,4,0,8"/>
              <StackPanel x:Name="PanelUndo"/>
              <TextBlock Text="Applications désinstallées" Style="{StaticResource H2}" Margin="4,16,0,8"/>
              <StackPanel x:Name="PanelRemoved"/>
            </StackPanel>
          </ScrollViewer>
        </DockPanel>
      </TabItem>

      <!-- ============ À PROPOS ============ -->
      <TabItem Header="À propos" x:Name="TabAbout">
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Text="Ce que fait l'application" Style="{StaticResource H2}"/>
                <TextBlock Style="{StaticResource Para}" Text="Elle modifie uniquement des réglages officiels et documentés de Windows 10 et 11 : options des Paramètres, stratégies de groupe publiées par Microsoft, modes d'alimentation (outil powercfg), démarrage d'un service, et désinstallation d'applications du Microsoft Store pour votre compte."/>
                <TextBlock Style="{StaticResource Para}" Text="Chaque modification doit être cochée puis confirmée. Les réglages d'origine sont sauvegardés et peuvent être restaurés à tout moment. Un point de restauration Windows est proposé avant chaque série de modifications."/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Text="Ce qu'elle ne fera jamais" Style="{StaticResource H2}"/>
                <TextBlock Style="{StaticResource Para}" Text="- Aucun overclocking, undervolting, modification de tension, de ventilateurs, du BIOS ou du firmware : aucun risque de surchauffe ni de perte de garantie."/>
                <TextBlock Style="{StaticResource Para}" Text="- Aucune modification ou redistribution des pilotes NVIDIA, AMD ou Intel : l'application renvoie seulement vers les sites officiels des fabricants."/>
                <TextBlock Style="{StaticResource Para}" Text="- Aucun contournement d'activation ou de licence, aucune désactivation de Windows Update, de Microsoft Defender ou du pare-feu."/>
                <TextBlock Style="{StaticResource Para}" Text="- Aucune donnée envoyée sur Internet, aucune publicité, aucun compte requis."/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Text="Mentions légales" Style="{StaticResource H2}"/>
                <TextBlock Style="{StaticResource Para}" Text="Application indépendante, gratuite et open source (licence MIT), fournie sans garantie. Elle n'est ni affiliée, ni approuvée, ni sponsorisée par Microsoft, NVIDIA, Intel ou AMD."/>
                <TextBlock Style="{StaticResource Para}" Text="Windows, Xbox et Microsoft Store sont des marques de Microsoft Corporation. NVIDIA, GeForce, RTX, DLSS, G-SYNC et ShadowPlay sont des marques de NVIDIA Corporation. Intel, Arc et Turbo Boost sont des marques d'Intel Corporation. AMD, Radeon, Ryzen, FreeSync et Precision Boost sont des marques d'Advanced Micro Devices, Inc. Ces noms sont cités uniquement pour indiquer la compatibilité."/>
                <TextBlock x:Name="TxtDataPath" Style="{StaticResource Para}"/>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>
      </TabItem>
    </TabControl>

    <!-- Journal -->
    <Border Grid.Row="2" Padding="24,6,24,14">
      <StackPanel>
        <TextBlock Text="Journal" Style="{StaticResource Label}" Margin="0,0,0,4"/>
        <TextBox x:Name="TxtLog" Height="72" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"
                 Background="#0A0C10" Foreground="#8FA0B8" BorderBrush="#242B39" FontFamily="Consolas" FontSize="11" Padding="6"/>
      </StackPanel>
    </Border>

    <!-- Écran d'attente -->
    <Grid x:Name="Overlay" Grid.RowSpan="3" Background="#E00E1116" Visibility="Collapsed">
      <Border Style="{StaticResource Card}" HorizontalAlignment="Center" VerticalAlignment="Center" Padding="32,26">
        <StackPanel>
          <ProgressBar IsIndeterminate="True" Width="300"/>
          <TextBlock x:Name="TxtBusy" Margin="0,16,0,0" TextAlignment="Center" TextWrapping="Wrap" MaxWidth="380"/>
        </StackPanel>
      </Border>
    </Grid>
  </Grid>
</Window>
'@

# En mode test, on s'arrête ici : toutes les fonctions et définitions sont chargées.
if ($TestMode) { return }

if ($Build -lt 10240) {
    Add-Type -AssemblyName PresentationFramework
    [void][System.Windows.MessageBox]::Show('Cette application nécessite Windows 10 ou Windows 11.', $AppName, 'OK', 'Error')
    exit
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

try {
    [xml]$XamlXml = $XamlText
    $Window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $XamlXml))
    foreach ($node in $XamlXml.SelectNodes('//*')) {
        $n = $node.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
        if ($n) { Set-Variable -Name $n -Value $Window.FindName($n) -Scope Script }
    }

    $BrushConv = New-Object System.Windows.Media.BrushConverter
    function Br([string]$Hex) { return $BrushConv.ConvertFromString($Hex) }
    function Th([double]$l, [double]$t, [double]$r, [double]$b) { return [System.Windows.Thickness]::new($l, $t, $r, $b) }

    function New-Text([string]$Text, [string]$Color = '#E6E9EF', [double]$Size = 13, [switch]$Bold, $Margin = $null) {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = $Text; $tb.Foreground = (Br $Color); $tb.FontSize = $Size
        $tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
        if ($Bold) { $tb.FontWeight = [System.Windows.FontWeights]::SemiBold }
        if ($Margin) { $tb.Margin = $Margin }
        return $tb
    }

    function New-Badge([string]$Text, [string]$Fg, [string]$Bg) {
        $b = New-Object System.Windows.Controls.Border
        $b.Background = (Br $Bg); $b.CornerRadius = [System.Windows.CornerRadius]::new(6)
        $b.Padding = (Th 8 2 8 2); $b.Margin = (Th 0 6 6 0)
        $b.Child = (New-Text $Text $Fg 11.5)
        return $b
    }

    function New-ActionButton([string]$Text, [string]$Target) {
        $btn = New-Object System.Windows.Controls.Button
        $btn.Content = $Text; $btn.Tag = $Target
        $btn.Add_Click({
            try { Start-Process $this.Tag } catch { Write-Log ('Impossible d''ouvrir : ' + $this.Tag) }
        })
        return $btn
    }

    function Show-Info([string]$Text, [string]$Icon = 'Information') {
        [void][System.Windows.MessageBox]::Show($Window, $Text, $AppName, [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]$Icon)
    }

    function Confirm-Action([string]$Text, [string]$Icon = 'Question') {
        $r = [System.Windows.MessageBox]::Show($Window, $Text, $AppName, [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]$Icon, [System.Windows.MessageBoxResult]::No)
        return ($r -eq [System.Windows.MessageBoxResult]::Yes)
    }

    function Invoke-UIPump { $Window.Dispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::Background) }
    function Show-Busy([string]$Text) {
        $TxtBusy.Text = $Text; $Overlay.Visibility = 'Visible'
        $Window.Cursor = [System.Windows.Input.Cursors]::Wait
        Invoke-UIPump
    }
    function Hide-Busy { $Overlay.Visibility = 'Collapsed'; $Window.Cursor = $null }

    function Format-Bullets([object[]]$Names) {
        $lines = @($Names | ForEach-Object { '   - ' + $_ })
        if ($lines.Count -gt 25) { $lines = @($lines[0..23]) + ('   ... et {0} autre(s)' -f ($lines.Count - 24)) }
        return ($lines -join "`n")
    }

    function Get-CheckedCount($boxes) { return @($boxes | Where-Object { $_.IsChecked -eq $true -and $_.IsEnabled }).Count }

    # ------------------------- Matériel -------------------------
    $Cpu       = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $CpuName   = if ($Cpu) { ($Cpu.Name -replace '\s+', ' ').Trim() } else { 'Inconnu' }
    $CpuVendor = if ($CpuName -match 'AMD|Ryzen') { 'AMD' } elseif ($CpuName -match 'Intel') { 'Intel' } else { 'Autre' }
    $Gpus      = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -and $_.Name -notmatch 'Basic Display|Basic Render|Remote|Virtual|Hyper-V|Parsec|Mirage|DisplayLink|Meta' })
    $GpuNames  = @($Gpus | ForEach-Object { $_.Name.Trim() })
    $HasNvidia = [bool]($GpuNames -match 'NVIDIA')
    $HasAmdGpu = [bool]($GpuNames -match 'AMD|Radeon')
    $HasIntelGpu = [bool]($GpuNames -match 'Intel')
    $IsLaptop  = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
    $Cs        = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $RamGB     = if ($Cs) { [math]::Round($Cs.TotalPhysicalMemory / 1GB) } else { 0 }
    $Os        = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $OsCaption = if ($Os) { $Os.Caption -replace '^Microsoft ', '' } else { 'Windows' }
    $DispVer   = $CurrentVersionKey.DisplayVersion

    $TxtVersion.Text  = "Version $AppVersion  -  Administrateur"
    $TxtCpu.Text      = '{0}{1}' -f $CpuName, $(if ($Cpu) { "  ($($Cpu.NumberOfCores) cœurs / $($Cpu.NumberOfLogicalProcessors) threads)" } else { '' })
    $TxtGpu.Text      = if ($Gpus.Count) { ($Gpus | ForEach-Object { '{0}  (pilote {1})' -f $_.Name.Trim(), $_.DriverVersion }) -join "`n" } else { 'Non détectée' }
    $TxtRam.Text      = "$RamGB Go"
    $TxtOs.Text       = '{0} {1} (build {2}){3}' -f $OsCaption, $DispVer, $Build, $(if ($IsLaptop) { '  -  PC portable' } else { '' })
    $TxtSubtitle.Text = 'Jeux et télétravail, sans surchauffe  -  {0}  -  {1}' -f $OsCaption, $(if ($GpuNames.Count) { $GpuNames[0] } else { $CpuName })
    $TxtDataPath.Text = "Sauvegardes et journal : $DataPath"

    # ------------------------- Conseils -------------------------
    $tips = New-Object System.Collections.Generic.List[string]
    if ($HasNvidia) {
        $tips.Add('Carte NVIDIA : mettez à jour le pilote avec l''application officielle NVIDIA App. Dans les jeux compatibles, activez DLSS et NVIDIA Reflex : plus d''images par seconde et moins de chaleur.')
        $GpuTempHint = 'Non disponible (pilote NVIDIA introuvable)'
    }
    if ($HasAmdGpu) {
        $tips.Add('Carte AMD Radeon : mettez à jour le pilote avec AMD Software: Adrenalin Edition. Activez FSR et Radeon Anti-Lag dans les jeux ; Radeon Chill réduit fortement la chauffe.')
    }
    if ($HasIntelGpu) {
        $tips.Add('Graphique Intel : mettez à jour le pilote avec Intel Driver & Support Assistant (ou le site du fabricant de votre PC portable). Activez XeSS dans les jeux compatibles.')
    }
    if ($CpuVendor -eq 'AMD') { $tips.Add('Processeur AMD Ryzen : installez le pilote « chipset » AMD depuis le site officiel ; il améliore la gestion de l''énergie avec le mode Équilibré.') }
    if ($CpuVendor -eq 'Intel') { $tips.Add('Processeur Intel : les mises à jour de pilotes et du BIOS se font via Intel Driver & Support Assistant ou le site du fabricant de votre PC.') }
    if ($IsLaptop) { $tips.Add('PC portable : jouez branché sur secteur, laissez de l''espace sous et derrière le PC (support ventilé) et dépoussiérez les grilles. L''option « Anti-surchauffe : limiter le processeur à 99 % » réduit beaucoup la chaleur.') }
    $tips.Add('Limitez les images par seconde à la fréquence de votre écran (60, 144, 165 Hz...) avec la V-Sync ou le limiteur du pilote : la carte graphique travaille moins et chauffe moins, sans perte visible.')
    $tips.Add('Un PC propre chauffe moins : un dépoussiérage des ventilateurs tous les 6 à 12 mois fait souvent baisser la température de plusieurs degrés.')
    foreach ($tip in $tips) { [void]$PanelTips.Children.Add((New-Text ('•  ' + $tip) '#C3CAD6' 13 -Margin (Th 0 0 0 6))) }

    if ($HasNvidia)   { [void]$PanelLinks.Children.Add((New-ActionButton 'Pilote NVIDIA (site officiel)' 'https://www.nvidia.com/fr-fr/software/nvidia-app/')) }
    if ($HasAmdGpu -or $CpuVendor -eq 'AMD') { [void]$PanelLinks.Children.Add((New-ActionButton 'Pilotes AMD (site officiel)' 'https://www.amd.com/fr/support/download/drivers.html')) }
    if ($HasIntelGpu -or $CpuVendor -eq 'Intel') { [void]$PanelLinks.Children.Add((New-ActionButton 'Pilotes Intel (site officiel)' 'https://www.intel.fr/content/www/fr/fr/support/detect.html')) }
    [void]$PanelLinks.Children.Add((New-ActionButton 'Windows Update' 'ms-settings:windowsupdate'))
    [void]$PanelLinks.Children.Add((New-ActionButton 'Applications au démarrage' 'ms-settings:startupapps'))
    [void]$PanelLinks.Children.Add((New-ActionButton 'Stockage' 'ms-settings:storagesense'))
    [void]$PanelLinks.Children.Add((New-ActionButton 'Gestionnaire des tâches' 'taskmgr.exe'))

    if (-not $GpuTempHint) {
        if ($HasAmdGpu) { $GpuTempHint = 'Visible dans AMD Software (Alt+R) ou le Gestionnaire des tâches' }
        elseif ($HasIntelGpu) { $GpuTempHint = 'Visible dans le logiciel graphique Intel ou le Gestionnaire des tâches' }
        else { $GpuTempHint = 'Non disponible' }
    }

    # ------------------------- Liste des optimisations -------------------------
    $script:TweakBoxes = New-Object System.Collections.Generic.List[object]

    function Update-SelCount {
        $BtnApply.Content = 'Appliquer la sélection ({0})' -f (Get-CheckedCount $script:TweakBoxes)
    }

    function Build-TweakList {
        $PanelTweaks.Children.Clear(); $script:TweakBoxes.Clear()
        foreach ($cat in $Categories) {
            $list = @($Tweaks | Where-Object { $_.Cat -eq $cat.Id -and (Test-TweakAvailable $_) })
            if ($list.Count -eq 0) { continue }
            [void]$PanelTweaks.Children.Add((New-Text $cat.Title '#FFFFFF' 17 -Bold -Margin (Th 2 12 0 2)))
            [void]$PanelTweaks.Children.Add((New-Text $cat.Sub '#97A1B3' 12.5 -Margin (Th 2 0 0 10)))
            foreach ($t in $list) {
                $applied = $t.Undoable -and (Test-TweakApplied $t)
                $card = New-Object System.Windows.Controls.Border
                $card.Style = $Window.FindResource('ItemCard')
                $sp = New-Object System.Windows.Controls.StackPanel
                $cb = New-Object System.Windows.Controls.CheckBox
                $cb.Content = (New-Text $t.Name '#E6E9EF' 14 -Bold)
                $cb.Tag = $t
                $cb.Add_Checked({ Update-SelCount })
                $cb.Add_Unchecked({ Update-SelCount })
                [void]$sp.Children.Add($cb)
                [void]$sp.Children.Add((New-Text $t.Desc '#97A1B3' 12.5 -Margin (Th 21 4 0 0)))
                $wp = New-Object System.Windows.Controls.WrapPanel
                $wp.Margin = (Th 21 2 0 0)
                if ($applied) {
                    $cb.IsEnabled = $false
                    [void]$wp.Children.Add((New-Badge 'Déjà actif' '#5BD48A' '#14301F'))
                }
                if ($t.Reboot)       { [void]$wp.Children.Add((New-Badge 'Redémarrage requis' '#F0B429' '#33290F')) }
                if (-not $t.Undoable) { [void]$wp.Children.Add((New-Badge 'Non annulable' '#F28B82' '#3A1A1A')) }
                if ($t.Warn)         { [void]$wp.Children.Add((New-Badge $t.Warn '#F0B429' '#33290F')) }
                foreach ($p in $t.Profiles) { [void]$wp.Children.Add((New-Badge $ProfileLabels[$p] '#9DB7F5' '#1B2740')) }
                [void]$sp.Children.Add($wp)
                $card.Child = $sp
                [void]$PanelTweaks.Children.Add($card)
                $script:TweakBoxes.Add($cb)
            }
        }
        Update-SelCount
    }

    function Select-Profile([string]$Name) {
        foreach ($cb in $script:TweakBoxes) {
            if ($cb.IsEnabled) { $cb.IsChecked = (@($cb.Tag.Profiles) -contains $Name) }
        }
        Update-SelCount
        $n = Get-CheckedCount $script:TweakBoxes
        if ($Name -and $n -eq 0) { Show-Info 'Toutes les optimisations de cette suggestion sont déjà actives sur ce PC.' }
        elseif ($Name) { Write-Log ("Suggestion « {0} » : {1} case(s) cochée(s). Rien n'est encore modifié." -f $ProfileLabels[$Name], $n) }
    }

    # ------------------------- Point de restauration -------------------------
    function Wait-JobUI($Job) {
        while ($Job.State -eq 'Running' -or $Job.State -eq 'NotStarted') { Invoke-UIPump; Start-Sleep -Milliseconds 120 }
        $out = @(Receive-Job -Job $Job -ErrorAction SilentlyContinue)
        Remove-Job -Job $Job -Force -ErrorAction SilentlyContinue
        if ($out.Count) { return [string]$out[-1] }
        return 'ERREUR : aucune réponse'
    }

    function Invoke-RestorePointJob([bool]$Enable) {
        $job = Start-Job -ArgumentList $Enable -ScriptBlock {
            param($enable)
            try {
                if ($enable) { Enable-ComputerRestore -Drive ($env:SystemDrive + '\') -ErrorAction Stop }
                Checkpoint-Computer -Description 'Optimiseur PC - avant modifications' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningAction Stop
                'OK'
            } catch { 'ERREUR : ' + $_.Exception.Message }
        }
        return (Wait-JobUI $job)
    }

    function New-RestorePointUI {
        Show-Busy "Création du point de restauration Windows...`nCela peut prendre jusqu'à une minute."
        $srKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
        $freq = Read-Reg $srKey 'SystemRestorePointCreationFrequency'
        $ok = $false
        try {
            # Windows limite à un point par 24 h par défaut : on lève cette limite le temps de la création.
            Write-Reg $srKey 'SystemRestorePointCreationFrequency' 0 'DWord'
            $r = Invoke-RestorePointJob $false
            if ($r -eq 'OK') { $ok = $true }
            else {
                Write-Log ('Point de restauration : ' + $r)
                Hide-Busy
                if (Confirm-Action ("Le point de restauration n'a pas pu être créé.`n$r`n`nLa protection du système est peut-être désactivée.`nVoulez-vous l'activer sur le disque $env:SystemDrive et réessayer ?`n(Windows utilisera un peu d'espace disque pour les points de restauration.)") 'Warning') {
                    Show-Busy 'Activation de la protection du système et nouvelle tentative...'
                    $r = Invoke-RestorePointJob $true
                    if ($r -eq 'OK') { $ok = $true; Write-Log 'Protection du système activée.' }
                    else { Write-Log ('Point de restauration : ' + $r) }
                }
            }
        } finally {
            if ($freq.Exists) { Write-Reg $srKey 'SystemRestorePointCreationFrequency' $freq.Value $freq.Kind }
            else { Remove-ItemProperty -LiteralPath $srKey -Name 'SystemRestorePointCreationFrequency' -ErrorAction SilentlyContinue }
            Hide-Busy
        }
        if ($ok) { Write-Log 'Point de restauration créé.' }
        return $ok
    }

    function Request-Restart([string]$Text) {
        if (Confirm-Action ($Text + "`n`nRedémarrer l'ordinateur maintenant ?`n(Enregistrez d'abord votre travail en cours.)")) {
            try { Restart-Computer -ErrorAction Stop } catch { Show-Info ('Redémarrage impossible : ' + $_.Exception.Message) 'Warning' }
        }
    }

    # ------------------------- Applications -------------------------
    $script:AppBoxes = New-Object System.Collections.Generic.List[object]

    function Update-AppCount {
        $BtnRemoveApps.Content = 'Désinstaller la sélection ({0})' -f (Get-CheckedCount $script:AppBoxes)
    }

    function Build-AppList {
        $PanelApps.Children.Clear(); $script:AppBoxes.Clear()
        $apps = @(Get-BloatApps)
        if ($apps.Count -eq 0) {
            [void]$PanelApps.Children.Add((New-Text 'Aucune application inutile connue n''est installée sur ce compte.' '#5BD48A' 14 -Margin (Th 4 8 0 0)))
        }
        foreach ($a in @($apps | Sort-Object @{ Expression = 'Suggest'; Descending = $true }, Name)) {
            $card = New-Object System.Windows.Controls.Border
            $card.Style = $Window.FindResource('ItemCard')
            $sp = New-Object System.Windows.Controls.StackPanel
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Content = (New-Text $a.Name '#E6E9EF' 14 -Bold)
            $cb.Tag = $a
            $cb.Add_Checked({ Update-AppCount }); $cb.Add_Unchecked({ Update-AppCount })
            [void]$sp.Children.Add($cb)
            $info = $a.PkgName
            if ($a.Note) { $info = $a.Note + '   (' + $a.PkgName + ')' }
            [void]$sp.Children.Add((New-Text $info '#97A1B3' 12.5 -Margin (Th 21 3 0 0)))
            if ($a.Suggest) {
                $wp = New-Object System.Windows.Controls.WrapPanel; $wp.Margin = (Th 21 0 0 0)
                [void]$wp.Children.Add((New-Badge 'Suggérée' '#9DB7F5' '#1B2740'))
                [void]$sp.Children.Add($wp)
            }
            $card.Child = $sp
            [void]$PanelApps.Children.Add($card)
            $script:AppBoxes.Add($cb)
        }
        Update-AppCount
    }

    # ------------------------- Restauration -------------------------
    $script:UndoBoxes = New-Object System.Collections.Generic.List[object]

    function Update-UndoCount {
        $BtnUndo.Content = 'Restaurer la sélection ({0})' -f (Get-CheckedCount $script:UndoBoxes)
    }

    function Build-UndoList {
        $PanelUndo.Children.Clear(); $script:UndoBoxes.Clear()
        $entries = @($Backup.Values | Sort-Object Date)
        if ($entries.Count -eq 0) {
            [void]$PanelUndo.Children.Add((New-Text 'Aucun réglage modifié par l''application pour le moment.' '#97A1B3' 13 -Margin (Th 4 0 0 0)))
        }
        foreach ($e in $entries) {
            $card = New-Object System.Windows.Controls.Border
            $card.Style = $Window.FindResource('ItemCard')
            $sp = New-Object System.Windows.Controls.StackPanel
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Content = (New-Text $e.Name '#E6E9EF' 14 -Bold)
            $cb.Tag = $e
            $cb.Add_Checked({ Update-UndoCount }); $cb.Add_Unchecked({ Update-UndoCount })
            [void]$sp.Children.Add($cb)
            [void]$sp.Children.Add((New-Text ('Modifié le ' + $e.Date) '#97A1B3' 12.5 -Margin (Th 21 3 0 0)))
            $card.Child = $sp
            [void]$PanelUndo.Children.Add($card)
            $script:UndoBoxes.Add($cb)
        }
        Update-UndoCount

        $PanelRemoved.Children.Clear()
        if ($RemovedApps.Count -eq 0) {
            [void]$PanelRemoved.Children.Add((New-Text 'Aucune application désinstallée par l''application.' '#97A1B3' 13 -Margin (Th 4 0 0 0)))
        }
        foreach ($a in $RemovedApps) {
            $card = New-Object System.Windows.Controls.Border
            $card.Style = $Window.FindResource('ItemCard')
            $dp = New-Object System.Windows.Controls.DockPanel
            $btn = New-ActionButton 'Réinstaller depuis le Microsoft Store' ('ms-windows-store://pdp/?PFN=' + $a.Family)
            $btn.Margin = (Th 12 0 0 0)
            [System.Windows.Controls.DockPanel]::SetDock($btn, [System.Windows.Controls.Dock]::Right)
            [void]$dp.Children.Add($btn)
            $sp = New-Object System.Windows.Controls.StackPanel
            $sp.VerticalAlignment = 'Center'
            [void]$sp.Children.Add((New-Text $a.Name '#E6E9EF' 14 -Bold))
            [void]$sp.Children.Add((New-Text ('Désinstallée le ' + $a.Date) '#97A1B3' 12.5))
            [void]$dp.Children.Add($sp)
            $card.Child = $dp
            [void]$PanelRemoved.Children.Add($card)
        }
    }

    # ------------------------- Actions des boutons -------------------------
    $BtnProfGame.Add_Click({ Select-Profile 'Jeux' })
    $BtnProfOffice.Add_Click({ Select-Profile 'Bureau' })
    $BtnProfHeat.Add_Click({ Select-Profile 'Chaleur' })
    $BtnProfNone.Add_Click({ foreach ($cb in $script:TweakBoxes) { $cb.IsChecked = $false }; Update-SelCount })

    $BtnApply.Add_Click({
        $sel = @($script:TweakBoxes | Where-Object { $_.IsChecked -eq $true -and $_.IsEnabled } | ForEach-Object { $_.Tag })
        if ($sel.Count -eq 0) {
            Show-Info "Aucune case n'est cochée.`n`nCochez d'abord les optimisations souhaitées, ou utilisez un bouton « Suggestion »."
            return
        }
        $names = @($sel | ForEach-Object { $_.Name + $(if ($_.Reboot) { '  [redémarrage]' } elseif (-not $_.Undoable) { '  [définitif]' } else { '' }) })
        $msg = "Vous allez modifier {0} réglage(s) de Windows :`n`n{1}`n`n" -f $sel.Count, (Format-Bullets $names)
        if ($ChkRestore.IsChecked) { $msg += "Un point de restauration Windows sera créé avant.`n" }
        $msg += "Vos réglages d'origine seront sauvegardés (onglet « Restaurer »).`n`nConfirmez-vous ces modifications ?"
        if (-not (Confirm-Action $msg)) { Write-Log 'Modifications annulées : non confirmées.'; return }

        if ($ChkRestore.IsChecked) {
            if (-not (New-RestorePointUI)) {
                if (-not (Confirm-Action "Le point de restauration n'a pas été créé.`n`nContinuer quand même ?`nVos réglages d'origine restent sauvegardés par l'application et peuvent être restaurés." 'Warning')) {
                    Write-Log 'Modifications annulées : pas de point de restauration.'
                    return
                }
            }
        }

        Show-Busy 'Application des réglages...'
        $okCount = 0; $errors = @(); $needReboot = $false
        try {
            foreach ($t in $sel) {
                $TxtBusy.Text = 'Application : ' + $t.Name
                Invoke-UIPump
                try {
                    Invoke-Tweak $t
                    $okCount++
                    if ($t.Reboot) { $needReboot = $true }
                    Write-Log ('Appliqué : ' + $t.Name)
                } catch {
                    $errors += ($t.Name + ' : ' + $_.Exception.Message)
                    Write-Log ('ERREUR : ' + $t.Name + ' : ' + $_.Exception.Message)
                }
            }
        } finally {
            Hide-Busy
            Build-TweakList; Build-UndoList
        }

        $summary = '{0} réglage(s) appliqué(s) sur {1}.' -f $okCount, $sel.Count
        if ($errors.Count) { Show-Info ($summary + "`n`nErreurs :`n" + (Format-Bullets $errors)) 'Warning' }
        if ($needReboot) { Request-Restart ($summary + "`nCertains réglages prendront effet après un redémarrage.") }
        elseif (-not $errors.Count) { Show-Info $summary }
    })

    $BtnAppsSuggest.Add_Click({ foreach ($cb in $script:AppBoxes) { $cb.IsChecked = [bool]$cb.Tag.Suggest }; Update-AppCount })
    $BtnAppsNone.Add_Click({ foreach ($cb in $script:AppBoxes) { $cb.IsChecked = $false }; Update-AppCount })
    $BtnAppsRefresh.Add_Click({ Show-Busy 'Recherche des applications...'; try { Build-AppList } finally { Hide-Busy } })

    $BtnRemoveApps.Add_Click({
        $sel = @($script:AppBoxes | Where-Object { $_.IsChecked -eq $true } | ForEach-Object { $_.Tag })
        if ($sel.Count -eq 0) { Show-Info 'Aucune application n''est cochée.'; return }
        $msg = "Vous allez désinstaller {0} application(s) pour votre compte :`n`n{1}`n`nElles pourront être réinstallées gratuitement depuis le Microsoft Store (onglet « Restaurer »).`n`nConfirmez-vous la désinstallation ?" -f $sel.Count, (Format-Bullets @($sel | ForEach-Object { $_.Name }))
        if (-not (Confirm-Action $msg 'Warning')) { Write-Log 'Désinstallation annulée : non confirmée.'; return }

        Show-Busy 'Désinstallation...'
        $okCount = 0; $errors = @()
        try {
            foreach ($a in $sel) {
                $TxtBusy.Text = 'Désinstallation : ' + $a.Name
                Invoke-UIPump
                try {
                    Remove-AppxPackage -Package $a.FullName -ErrorAction Stop
                    [void]$RemovedApps.Add([pscustomobject]@{ Name = $a.Name; Family = $a.Family; PkgName = $a.PkgName; Date = (Get-Date).ToString('yyyy-MM-dd HH:mm') })
                    Save-Data
                    $okCount++
                    Write-Log ('Désinstallée : ' + $a.Name)
                } catch {
                    $errors += ($a.Name + ' : ' + $_.Exception.Message)
                    Write-Log ('ERREUR : ' + $a.Name + ' : ' + $_.Exception.Message)
                }
            }
        } finally {
            Build-AppList; Build-UndoList
            Hide-Busy
        }
        $summary = '{0} application(s) désinstallée(s) sur {1}.' -f $okCount, $sel.Count
        if ($errors.Count) { Show-Info ($summary + "`n`nErreurs :`n" + (Format-Bullets $errors)) 'Warning' } else { Show-Info $summary }
    })

    $BtnUndoAll.Add_Click({ foreach ($cb in $script:UndoBoxes) { $cb.IsChecked = $true }; Update-UndoCount })
    $BtnUndoNone.Add_Click({ foreach ($cb in $script:UndoBoxes) { $cb.IsChecked = $false }; Update-UndoCount })
    $BtnRstrui.Add_Click({ try { Start-Process 'rstrui.exe' } catch { Show-Info 'La Restauration du système est indisponible sur ce PC.' 'Warning' } })
    $BtnLogs.Add_Click({ Start-Process 'explorer.exe' -ArgumentList "`"$DataPath`"" })

    $BtnUndo.Add_Click({
        $sel = @($script:UndoBoxes | Where-Object { $_.IsChecked -eq $true } | ForEach-Object { $_.Tag })
        if ($sel.Count -eq 0) { Show-Info 'Aucun réglage n''est coché.'; return }
        $msg = "Vous allez remettre {0} réglage(s) comme avant :`n`n{1}`n`nConfirmez-vous ?" -f $sel.Count, (Format-Bullets @($sel | ForEach-Object { $_.Name }))
        if (-not (Confirm-Action $msg)) { Write-Log 'Restauration annulée : non confirmée.'; return }

        Show-Busy 'Restauration des réglages...'
        $okCount = 0; $errors = @(); $needReboot = $false
        try {
            foreach ($e in $sel) {
                $TxtBusy.Text = 'Restauration : ' + $e.Name
                Invoke-UIPump
                try {
                    Undo-Tweak $e
                    $okCount++
                    if ($e.Reboot) { $needReboot = $true }
                    Write-Log ('Restauré : ' + $e.Name)
                } catch {
                    $errors += ($e.Name + ' : ' + $_.Exception.Message)
                    Write-Log ('ERREUR restauration : ' + $e.Name + ' : ' + $_.Exception.Message)
                }
            }
        } finally {
            Hide-Busy
            Build-TweakList; Build-UndoList
        }
        $summary = '{0} réglage(s) restauré(s) sur {1}.' -f $okCount, $sel.Count
        if ($errors.Count) { Show-Info ($summary + "`n`nErreurs :`n" + (Format-Bullets $errors)) 'Warning' }
        if ($needReboot) { Request-Restart ($summary + "`nCertains réglages reviendront après un redémarrage.") }
        elseif (-not $errors.Count) { Show-Info $summary }
    })

    # ------------------------- Surveillance en arrière-plan -------------------------
    $script:Sync = [hashtable]::Synchronized(@{ Run = $true })
    $MonRunspace = [runspacefactory]::CreateRunspace()
    $MonRunspace.Open()
    $MonRunspace.SessionStateProxy.SetVariable('Sync', $script:Sync)
    $MonPS = [powershell]::Create()
    $MonPS.Runspace = $MonRunspace
    [void]$MonPS.AddScript({
        $smi = @((Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'),
                 (Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe')) |
               Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        $thermalOk = $true
        while ($Sync.Run) {
            try { $Sync.Cpu = [int](Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction Stop).PercentProcessorTime } catch { $Sync.Cpu = $null }
            try {
                $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
                $Sync.Ram = [int](100 - 100 * $os.FreePhysicalMemory / $os.TotalVisibleMemorySize)
            } catch { $Sync.Ram = $null }
            try {
                $eng = @(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -ErrorAction Stop | Where-Object { $_.Name -like '*engtype_3D' })
                $sum = ($eng | Measure-Object -Property UtilizationPercentage -Sum).Sum
                $Sync.Gpu = [int][Math]::Min(100, [double]$sum)
            } catch { $Sync.Gpu = $null }
            if ($smi) {
                try {
                    $line = @(& $smi --query-gpu=temperature.gpu,utilization.gpu,power.draw --format=csv,noheader,nounits 2>$null)[0]
                    $p = $line -split ','
                    $Sync.GpuTemp = [int]$p[0].Trim()
                    $Sync.GpuNv   = [int]$p[1].Trim()
                    $w = 0.0
                    if ([double]::TryParse($p[2].Trim(), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$w)) { $Sync.GpuPower = [int]$w } else { $Sync.GpuPower = $null }
                } catch { $Sync.GpuTemp = $null; $Sync.GpuNv = $null }
            }
            if ($thermalOk) {
                try {
                    $z = Get-CimInstance -Namespace 'root/wmi' -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop | Select-Object -First 1
                    $c = [int][Math]::Round($z.CurrentTemperature / 10 - 273.15)
                    if ($c -gt 5 -and $c -lt 125) { $Sync.CpuTemp = $c } else { $Sync.CpuTemp = $null; $thermalOk = $false }
                } catch { $Sync.CpuTemp = $null; $thermalOk = $false }
            }
            $Sync.Ready = $true
            for ($i = 0; $i -lt 20 -and $Sync.Run; $i++) { Start-Sleep -Milliseconds 100 }
        }
    })
    $MonHandle = $MonPS.BeginInvoke()

    function Set-TempText($TextBlock, $Value, [int]$Warm, [int]$Hot, [string]$Suffix) {
        $TextBlock.Text = "$Value °C$Suffix"
        if ($Value -ge $Hot) { $TextBlock.Foreground = (Br '#F05252'); return 2 }
        if ($Value -ge $Warm) { $TextBlock.Foreground = (Br '#F0B429'); return 1 }
        $TextBlock.Foreground = (Br '#5BD48A'); return 0
    }

    function Update-Monitor {
        $s = $script:Sync
        if (-not $s.Ready) { return }
        if ($null -ne $s.Cpu) { $PbCpu.Value = $s.Cpu; $TxtCpuVal.Text = "$($s.Cpu) %" } else { $TxtCpuVal.Text = 'n/d' }
        $g = $s.Gpu
        if ($null -ne $s.GpuNv) { $g = $s.GpuNv }
        if ($null -ne $g) { $PbGpu.Value = $g; $TxtGpuVal.Text = "$g %" } else { $TxtGpuVal.Text = 'n/d' }
        if ($null -ne $s.Ram) { $PbRam.Value = $s.Ram; $TxtRamVal.Text = "$($s.Ram) %" }

        $level = 0; $hasTemp = $false
        if ($null -ne $s.GpuTemp) {
            $hasTemp = $true
            $suffix = ''
            if ($s.GpuPower) { $suffix = "   ($($s.GpuPower) W)" }
            $level = [Math]::Max($level, (Set-TempText $TxtGpuTemp $s.GpuTemp 80 87 $suffix))
        } else {
            $TxtGpuTemp.Text = $GpuTempHint; $TxtGpuTemp.Foreground = (Br '#97A1B3')
        }
        if ($null -ne $s.CpuTemp) {
            $hasTemp = $true
            $level = [Math]::Max($level, (Set-TempText $TxtCpuTemp $s.CpuTemp 80 90 '   (capteur ACPI, approximatif)'))
        } else {
            $TxtCpuTemp.Text = 'Non disponible sans l''outil du fabricant'; $TxtCpuTemp.Foreground = (Br '#97A1B3')
        }

        if ($level -ge 2) {
            $HeatBox.Background = (Br '#3A1618')
            $TxtHeat.Text = 'Température élevée ! Vérifiez que les aérations ne sont pas bouchées, dépoussiérez le PC, limitez les images par seconde dans vos jeux et essayez la « Suggestion Anti-surchauffe ».'
        } elseif ($level -eq 1) {
            $HeatBox.Background = (Br '#33290F')
            $TxtHeat.Text = 'Température soutenue : normal pendant un jeu exigeant. Si cela dure au repos, pensez au dépoussiérage et à la « Suggestion Anti-surchauffe ».'
        } elseif ($hasTemp) {
            $HeatBox.Background = (Br '#14301F')
            $TxtHeat.Text = 'Températures normales.'
        } else {
            $HeatBox.Background = (Br '#1B2130')
            $TxtHeat.Text = 'Ce PC ne donne pas accès à ses capteurs de température à Windows. Utilisez le logiciel du fabricant de votre carte graphique ou de votre PC pour les consulter.'
        }
    }

    $Timer = New-Object System.Windows.Threading.DispatcherTimer
    $Timer.Interval = [TimeSpan]::FromSeconds(2)
    $Timer.Add_Tick({ try { Update-Monitor } catch { } })

    $Window.Add_Loaded({ $Timer.Start() })
    $Window.Add_Closed({
        $Timer.Stop()
        $script:Sync.Run = $false
        try { [void]$MonPS.EndInvoke($MonHandle) } catch { }
        try { $MonPS.Dispose(); $MonRunspace.Dispose() } catch { }
    })

    # ------------------------- Démarrage -------------------------
    $script:TxtLog = $TxtLog
    Write-Log "$AppName $AppVersion démarré - $OsCaption $DispVer (build $Build)."
    Build-TweakList
    Build-AppList
    Build-UndoList
    if ($Backup.Count -gt 0) { Write-Log ('{0} réglage(s) modifié(s) précédemment peuvent être restaurés (onglet « Restaurer »).' -f $Backup.Count) }

    [void]$Window.ShowDialog()
} catch {
    Write-Log ('Erreur inattendue : ' + $_.Exception.Message)
    [void][System.Windows.MessageBox]::Show("Erreur inattendue :`n" + $_.Exception.Message + "`n`nJournal : $LogFile", $AppName, 'OK', 'Error')
}
