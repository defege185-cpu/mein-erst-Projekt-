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
    [string]$DataPath,
    [string]$Lang,
    [string]$CaptureDir   # tests : enregistre une image de chaque onglet puis ferme
)

Set-StrictMode -Off
$AppName    = 'Optimiseur PC'
$AppVersion = '1.1.0'

if ($env:OS -ne 'Windows_NT') {
    Write-Error 'Cette application fonctionne uniquement sous Windows 10 et Windows 11.'
    return
}

# ---------------------------------------------------------------------------------------------
#  Langues : français intégré, autres langues dans le dossier « langues » (fichiers JSON
#  « texte français » -> « traduction »). Pour ajouter une langue : copier en.json et le traduire.
# ---------------------------------------------------------------------------------------------
if (-not $DataPath) { $DataPath = Join-Path $env:LOCALAPPDATA 'OptimiseurPC' }
if (-not (Test-Path -LiteralPath $DataPath)) { New-Item -ItemType Directory -Path $DataPath -Force | Out-Null }
$SettingsFile = Join-Path $DataPath 'parametres.json'

$Languages = [ordered]@{ fr = @{ '@langue' = 'Français' } }
$LangDir = Join-Path $PSScriptRoot 'langues'
if (Test-Path -LiteralPath $LangDir) {
    foreach ($f in @(Get-ChildItem -LiteralPath $LangDir -Filter '*.json' -File | Sort-Object Name)) {
        try {
            $obj = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $h = @{}
            foreach ($prop in $obj.PSObject.Properties) { $h[$prop.Name] = [string]$prop.Value }
            if ($h.ContainsKey('@langue')) { $Languages[$f.BaseName.ToLower()] = $h }
        } catch { }
    }
}
if (-not $Lang) {
    try {
        if (Test-Path -LiteralPath $SettingsFile) { $Lang = [string](Get-Content -LiteralPath $SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json).Lang }
    } catch { }
}
if (-not $Lang) { $Lang = [Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName }
$Lang = $Lang.ToLower()
if (-not $Languages.Contains($Lang)) { if ($Languages.Contains('en')) { $Lang = 'en' } else { $Lang = 'fr' } }
$Dict = $Languages[$Lang]

# Traduit un texte français (\n = retour à la ligne). Sans traduction, le français est gardé.
function Tr([string]$Text) {
    $k = $Text.Replace('\n', "`n")
    if ($Lang -ne 'fr' -and $Dict.ContainsKey($k)) { return $Dict[$k] }
    return $k
}
$AppName = Tr 'Optimiseur PC'

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
            (Tr 'L''application a besoin des droits administrateur pour modifier les paramètres de Windows.\n\nRelancez-la et répondez « Oui » à la question de Windows.'),
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
            if ($LASTEXITCODE -ne 0) { throw (Tr 'Le mode Équilibré est introuvable sur ce PC.') }
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
            if (-not $v) { throw (Tr 'Réglage du processeur illisible.') }
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
            Write-Log ((Tr 'Nettoyage : {0} fichier(s) supprimé(s), {1:N1} Mo libérés.') -f $count, ($freed / 1MB))
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
        Write-Log ((Tr 'Fichier de sauvegarde illisible : ') + $_.Exception.Message)
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
    # Instagram avant Facebook : ses paquets s'appellent « Facebook.Instagram... »
    @{ P = '*Instagram*';                            N = 'Instagram - sponsorisé'; S = $true }
    @{ P = '*Facebook*';                             N = 'Facebook - sponsorisé'; S = $true }
    @{ P = '*LinkedIn*';                             N = 'LinkedIn - sponsorisé'; S = $false }
    @{ P = '*Twitter*';                              N = 'X (Twitter) - sponsorisé'; S = $true }
    @{ P = '*Spotify*';                              N = 'Spotify'; S = $false; Note = 'Gardez-la si vous l''utilisez.' }
    @{ P = '*PrimeVideo*';                           N = 'Prime Video'; S = $false }
    @{ P = '*Netflix*';                              N = 'Netflix'; S = $false }
)

# Première entrée du catalogue qui correspond au nom du paquet (l'ordre du catalogue compte)
function Get-CatalogEntry([string]$PackageName) {
    foreach ($e in $AppCatalog) { if ($PackageName -like $e.P) { return $e } }
    return $null
}

function Get-BloatApps {
    $all = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { -not $_.IsFramework -and -not $_.NonRemovable })
    $seen = @{}
    $res = New-Object System.Collections.Generic.List[object]
    foreach ($p in $all) {
        $e = Get-CatalogEntry $p.Name
        if (-not $e -or $seen.ContainsKey($p.PackageFullName)) { continue }
        $seen[$p.PackageFullName] = $true
        $res.Add([pscustomobject]@{
            Name = $e.N; Note = $e.Note; Suggest = [bool]$e.S
            FullName = $p.PackageFullName; Family = $p.PackageFamilyName; PkgName = $p.Name
        })
    }
    return $res.ToArray()
}

# Processeurs Intel Core de bureau 13e et 14e génération (i5/i7/i9-13xxx ou 14xxx, sans H, HX, U, P ou T),
# concernés par les mises à jour de microcode publiées par Intel contre un problème d'instabilité.
function Test-IntelRaptorDesktop([string]$CpuName) {
    return [bool]($CpuName -match 'Intel.*Core.*\bi[579]-1[34]\d{3}(K|KF|KS|F)?\b')
}

# ---------------------------------------------------------------------------------------------
#  Astuces intelligentes : analyse du PC (lecture seule) puis conseils personnalisés
# ---------------------------------------------------------------------------------------------
function Get-DisplayModes {
    if (-not ('OptPC.Display' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
namespace OptPC {
    public static class Display {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct DEVMODE {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
            public short dmSpecVersion; public short dmDriverVersion; public short dmSize; public short dmDriverExtra;
            public int dmFields; public int dmPositionX; public int dmPositionY; public int dmDisplayOrientation; public int dmDisplayFixedOutput;
            public short dmColor; public short dmDuplex; public short dmYResolution; public short dmTTOption; public short dmCollate;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
            public short dmLogPixels; public int dmBitsPerPel; public int dmPelsWidth; public int dmPelsHeight;
            public int dmDisplayFlags; public int dmDisplayFrequency; public int dmICMMethod; public int dmICMIntent;
            public int dmMediaType; public int dmDitherType; public int dmReserved1; public int dmReserved2;
            public int dmPanningWidth; public int dmPanningHeight;
        }
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct DISPLAY_DEVICE {
            public int cb;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
            public int StateFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
        }
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern bool EnumDisplayDevices(string device, uint devNum, ref DISPLAY_DEVICE displayDevice, uint flags);
        // [numéro, largeur, hauteur, fréquence actuelle, fréquence maximale à cette résolution]
        public static List<int[]> Modes() {
            var res = new List<int[]>();
            for (uint i = 0; i < 16; i++) {
                var dd = new DISPLAY_DEVICE(); dd.cb = Marshal.SizeOf(dd);
                if (!EnumDisplayDevices(null, i, ref dd, 0)) break;
                if ((dd.StateFlags & 1) == 0) continue;
                var cur = new DEVMODE(); cur.dmSize = (short)Marshal.SizeOf(cur);
                if (!EnumDisplaySettings(dd.DeviceName, -1, ref cur)) continue;
                int max = cur.dmDisplayFrequency;
                var m = new DEVMODE(); m.dmSize = (short)Marshal.SizeOf(m);
                for (int k = 0; k < 4000 && EnumDisplaySettings(dd.DeviceName, k, ref m); k++) {
                    if (m.dmPelsWidth == cur.dmPelsWidth && m.dmPelsHeight == cur.dmPelsHeight
                        && m.dmDisplayFrequency > max && m.dmDisplayFrequency < 1000) max = m.dmDisplayFrequency;
                }
                res.Add(new int[] { (int)i + 1, cur.dmPelsWidth, cur.dmPelsHeight, cur.dmDisplayFrequency, max });
            }
            return res;
        }
    }
}
'@
    }
    foreach ($m in [OptPC.Display]::Modes()) {
        [pscustomobject]@{ Index = $m[0]; Width = $m[1]; Height = $m[2]; Current = $m[3]; Max = $m[4] }
    }
}

function Get-SystemFacts {
    $f = [ordered]@{ Displays = @(); RamModules = 0; RamType = 0; RamMHz = 0; RamGB = 0; IsLaptop = $false; OnBattery = $false
                     SysFreePct = 100; SysFreeGB = 0; SysMedia = ''; SysHealth = ''; Gpus = @(); UptimeDays = 0; RebootPending = $false }
    try { $f.Displays = @(Get-DisplayModes) } catch { }
    try {
        $mem = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop)
        $f.RamModules = $mem.Count
        $f.RamType = [int]($mem | Select-Object -First 1).SMBIOSMemoryType
        $f.RamMHz = [int](($mem | Measure-Object -Property ConfiguredClockSpeed -Minimum).Minimum)
        $f.RamGB = [int][math]::Round((($mem | Measure-Object -Property Capacity -Sum).Sum) / 1GB)
    } catch { }
    try {
        $bat = @(Get-CimInstance Win32_Battery -ErrorAction Stop)
        $f.IsLaptop = $bat.Count -gt 0
        $f.OnBattery = [bool]($bat | Where-Object { $_.BatteryStatus -eq 1 })
    } catch { }
    try {
        $vol = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'" -ErrorAction Stop
        if ($vol.Size) { $f.SysFreePct = [int](100 * $vol.FreeSpace / $vol.Size); $f.SysFreeGB = [int][math]::Round($vol.FreeSpace / 1GB) }
    } catch { }
    try {
        $part = Get-Partition -DriveLetter $env:SystemDrive[0] -ErrorAction Stop
        $pd = Get-PhysicalDisk -ErrorAction Stop | Where-Object { $_.DeviceId -eq [string]$part.DiskNumber } | Select-Object -First 1
        if ($pd) { $f.SysMedia = [string]$pd.MediaType; $f.SysHealth = [string]$pd.HealthStatus }
    } catch { }
    try {
        $f.Gpus = @(Get-CimInstance Win32_VideoController -ErrorAction Stop |
            Where-Object { $_.Name -and $_.Name -notmatch 'Basic Display|Basic Render|Remote|Virtual|Hyper-V|Parsec|Mirage|DisplayLink|Meta' } |
            ForEach-Object { [pscustomobject]@{ Name = $_.Name.Trim(); DriverDate = $_.DriverDate } })
    } catch { }
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $f.UptimeDays = [int][math]::Floor(((Get-Date) - $os.LastBootUpTime).TotalDays)
    } catch { }
    $f.RebootPending = (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
                       (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
    return [pscustomobject]$f
}

# Conseils à partir des informations du PC. Level : warn (à corriger) ou info (conseil).
function Get-SmartTips($Facts) {
    $tips = New-Object System.Collections.Generic.List[object]
    function Add-Tip([string]$Level, [string]$Text, [string]$Action = $null, [string]$Label = $null) {
        $tips.Add([pscustomobject]@{ Level = $Level; Text = $Text; Action = $Action; Label = $Label })
    }
    foreach ($d in @($Facts.Displays)) {
        if ($d.Max -ge $d.Current + 5) {
            Add-Tip 'warn' ((Tr 'Écran {0} : réglé à {1} Hz alors qu''il peut afficher {2} Hz. Choisissez {2} Hz dans Paramètres > Affichage > Affichage avancé : les jeux et la souris seront beaucoup plus fluides.') -f $d.Index, $d.Current, $d.Max) 'ms-settings:display' (Tr 'Paramètres d''affichage')
        }
    }
    if ($Facts.RebootPending) {
        Add-Tip 'warn' (Tr 'Un redémarrage est en attente pour terminer des mises à jour de Windows.')
    }
    if ($Facts.SysFreePct -lt 15) {
        Add-Tip 'warn' ((Tr 'Disque système presque plein : {0} Go libres ({1} %). Windows et les jeux ralentissent quand le disque est plein.') -f $Facts.SysFreeGB, $Facts.SysFreePct) 'ms-settings:storagesense' (Tr 'Stockage')
    }
    if ($Facts.SysHealth -and $Facts.SysHealth -notin @('Healthy', '0')) {
        Add-Tip 'warn' ((Tr 'Windows signale un problème sur le disque système (état : {0}). Sauvegardez vos fichiers importants dès maintenant.') -f $Facts.SysHealth)
    }
    if ($Facts.SysMedia -eq 'HDD') {
        Add-Tip 'info' (Tr 'Windows est installé sur un disque dur classique (HDD). Un SSD rend le démarrage et les chargements des jeux beaucoup plus rapides.')
    }
    if (-not $Facts.IsLaptop -and $Facts.RamMHz -gt 0) {
        if (($Facts.RamType -eq 26 -and $Facts.RamMHz -le 2400) -or ($Facts.RamType -eq 34 -and $Facts.RamMHz -le 4800)) {
            Add-Tip 'info' ((Tr 'La mémoire fonctionne à {0} MT/s. Si vos barrettes sont prévues pour plus (indiqué sur l''étiquette ou la facture), activez le profil XMP ou EXPO dans le BIOS : gain de fluidité en jeu. Suivez le manuel de votre carte mère.') -f $Facts.RamMHz)
        }
        if ($Facts.RamModules -eq 1) {
            Add-Tip 'info' (Tr 'Une seule barrette de mémoire : le processeur fonctionne en simple canal. Deux barrettes identiques (double canal) donnent souvent plus d''images par seconde en jeu.')
        }
    }
    if ($Facts.RamGB -gt 0 -and $Facts.RamGB -le 8) {
        Add-Tip 'info' ((Tr '{0} Go de mémoire : fermez le navigateur pendant les jeux. 16 Go sont conseillés pour les jeux récents.') -f $Facts.RamGB)
    }
    foreach ($g in @($Facts.Gpus)) {
        if ($g.DriverDate -is [datetime] -and ((Get-Date) - $g.DriverDate).TotalDays -gt 180) {
            Add-Tip 'info' ((Tr 'Pilote de {0} daté du {1} : une version plus récente est probablement disponible sur le site officiel du fabricant.') -f $g.Name, $g.DriverDate.ToString('yyyy-MM-dd'))
        }
    }
    if ($Facts.UptimeDays -ge 7) {
        Add-Tip 'info' ((Tr 'PC allumé depuis {0} jours sans redémarrage. Utilisez « Redémarrer » (pas seulement « Arrêter », à cause du démarrage rapide) : la mémoire est libérée et les mises à jour se terminent.') -f $Facts.UptimeDays)
    }
    if ($Facts.OnBattery) {
        Add-Tip 'info' (Tr 'PC portable sur batterie : branchez le chargeur pour jouer, Windows réduit les performances sur batterie.')
    }
    return $tips.ToArray()
}

# ---------------------------------------------------------------------------------------------
#  Démarrage de Windows : même mécanisme que le Gestionnaire des tâches (clés StartupApproved)
# ---------------------------------------------------------------------------------------------
$SA = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
$StartupSources = @(
    [pscustomobject]@{ Kind = 'Reg';    Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';             Approved = "HKCU:\$SA\Run";           Scope = 'user' }
    [pscustomobject]@{ Kind = 'Reg';    Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';             Approved = "HKLM:\$SA\Run";           Scope = 'all' }
    [pscustomobject]@{ Kind = 'Reg';    Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = "HKLM:\$SA\Run32";         Scope = 'all' }
    [pscustomobject]@{ Kind = 'Folder'; Path = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup');     Approved = "HKCU:\$SA\StartupFolder"; Scope = 'user' }
    [pscustomobject]@{ Kind = 'Folder'; Path = (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp'); Approved = "HKLM:\$SA\StartupFolder"; Scope = 'all' }
)

# Premier octet : bit 0 à 1 = désactivé (03), à 0 = activé (02). Valeur absente = activé.
function Test-StartupEnabled($Bytes) {
    $b = @($Bytes)
    if ($b.Count -lt 1 -or $null -eq $b[0]) { return $true }
    return (([int]$b[0] -band 1) -eq 0)
}

function Get-StartupNote([string]$Name, [string]$Command) {
    $s = "$Name $Command"
    if ($s -match 'SecurityHealth') { return (Tr 'Icône de Sécurité Windows : la protection antivirus reste active même si cette icône ne se lance plus.') }
    if ($s -match 'RtkAud|Realtek|Waves|MaxxAudio|Nahimic|SmartAudio|Dolby') { return (Tr 'Logiciel audio : gardez-le si le son ou la prise casque fonctionnent mal sans lui.') }
    if ($s -match 'OneDrive') { return (Tr 'OneDrive : vos fichiers ne se synchronisent plus tant que OneDrive n''est pas ouvert.') }
    if ($s -match 'Teams|Zoom|Slack|Discord|Skype|WhatsApp') { return (Tr 'Messagerie : vous ne recevrez plus d''appels ni de messages tant qu''elle n''est pas ouverte.') }
    if ($s -match 'NVIDIA|Radeon|AMD|igfx|Intel') { return (Tr 'Logiciel du fabricant de la carte graphique ou du processeur.') }
    return $null
}

# Nom lisible d'un programme : description du fichier .exe (ex. « Google Chrome »), sinon le nom de l'entrée.
function Get-StartupDisplayName([string]$Name, [string]$Command) {
    $exe = $null
    if ($Command -match '^\s*"([^"]+?\.exe)"') { $exe = $Matches[1] }
    elseif ($Command -match '^\s*(.+?\.exe)(\s|$)') { $exe = $Matches[1] }
    if ($exe) {
        $exe = [Environment]::ExpandEnvironmentVariables($exe)
        try {
            if (Test-Path -LiteralPath $exe) {
                $d = (Get-Item -LiteralPath $exe -ErrorAction Stop).VersionInfo.FileDescription
                if ($d -and $d.Trim().Length -gt 1) { return $d.Trim() }
            }
        } catch { }
    }
    return $Name
}

function Get-StartupEntries {
    $res = New-Object System.Collections.Generic.List[object]
    foreach ($src in $StartupSources) {
        $items = @()
        if ($src.Kind -eq 'Reg') {
            $key = Get-Item -LiteralPath $src.Path -ErrorAction SilentlyContinue
            if (-not $key) { continue }
            foreach ($n in $key.GetValueNames()) { if ($n) { $items += , @($n, [string]$key.GetValue($n), $n) } }
        } elseif (Test-Path -LiteralPath $src.Path) {
            foreach ($file in @(Get-ChildItem -LiteralPath $src.Path -File -Force -ErrorAction SilentlyContinue)) {
                if ($file.Name -ieq 'desktop.ini') { continue }
                $items += , @($file.Name, $file.FullName, [IO.Path]::GetFileNameWithoutExtension($file.Name))
            }
        }
        foreach ($it in $items) {
            $c = Read-Reg $src.Approved $it[0]
            $res.Add([pscustomobject]@{
                Name = (Get-StartupDisplayName $it[2] $it[1]); ValueName = $it[0]; Command = $it[1]; Approved = $src.Approved; Scope = $src.Scope
                Enabled = (-not $c.Exists) -or (Test-StartupEnabled $c.Value)
                Id = 'Startup|' + $src.Approved + '|' + $it[0]; Note = (Get-StartupNote $it[0] $it[1])
            })
        }
    }
    return $res.ToArray()
}

function Set-StartupEnabled($Entry, [bool]$Enable) {
    # Retour à l'état d'origine sauvegardé : on restaure exactement la valeur d'avant
    if ($Backup.ContainsKey($Entry.Id) -and $Backup[$Entry.Id].Enable -ne $Enable) { Undo-Tweak $Backup[$Entry.Id]; return }
    $items = @(New-RegBackup $Entry.Approved $Entry.ValueName)
    $bytes = New-Object byte[] 12
    if ($Enable) { $bytes[0] = 2 } else { $bytes[0] = 3; [BitConverter]::GetBytes([DateTime]::Now.ToFileTime()).CopyTo($bytes, 4) }
    try {
        Write-Reg $Entry.Approved $Entry.ValueName $bytes 'Binary'
    } finally {
        if (-not $Backup.ContainsKey($Entry.Id)) {
            $Backup[$Entry.Id] = [pscustomobject]@{ Id = $Entry.Id; Kind = 'Startup'; Name = $Entry.Name; Enable = $Enable; Reboot = $false
                                                    Date = (Get-Date).ToString('yyyy-MM-dd HH:mm'); Items = $items }
            Save-Data
        }
    }
}

# ---------------------------------------------------------------------------------------------
#  Mises à jour des logiciels avec winget (outil officiel de Microsoft)
# ---------------------------------------------------------------------------------------------
function Get-WingetPath {
    $c = Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return $c.Source }
    $p = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path -LiteralPath $p) { return $p }
    return $null
}

# Lit le tableau affiché par « winget upgrade » (colonnes Nom, Id, Version, Disponible, Source, quelle que soit la langue).
# Renvoie $null s'il n'y a pas de tableau (aucune mise à jour ou message d'erreur).
# Récupère la sortie d'un job terminé, une ligne par élément (jamais un tableau imbriqué).
function Receive-JobLines($Job) {
    $out = @(Receive-Job -Job $Job -Wait -ErrorAction SilentlyContinue)
    Remove-Job -Job $Job -Force -ErrorAction SilentlyContinue
    return @(Split-OutputLines $out)
}

# Découpe une sortie de commande en lignes : retours à la ligne, animation de progression (\r)
# et codes de couleur du terminal sont pris en compte.
function Split-OutputLines($Output) {
    foreach ($item in @($Output)) {
        foreach ($part in @($item)) {
            foreach ($l in ([string]$part -split "`n")) {
                # fin de ligne Windows (CR LF) retirée d'abord ; un CR restant au milieu = animation écrasée
                ($l.TrimEnd("`r") -replace "\x1b\[[0-9;?]*[ -/]*[@-~]", '' -split "`r")[-1].TrimEnd()
            }
        }
    }
}

function ConvertFrom-WingetTable($Lines) {
    $lines = @(Split-OutputLines $Lines)
    $sep = -1
    for ($i = 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*-{10,}\s*$') { $sep = $i; break } }
    if ($sep -lt 1) { return $null }
    $head = $lines[$sep - 1].TrimEnd()
    $starts = @(0) + @([regex]::Matches($head, '(?<=\s)\S') | ForEach-Object { $_.Index })
    if ($starts.Count -lt 4) { return $null }
    $res = New-Object System.Collections.Generic.List[object]
    for ($i = $sep + 1; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($l) -or $l.Length -le $starts[2]) { break }
        $col = @()
        for ($k = 0; $k -lt $starts.Count; $k++) {
            $a = $starts[$k]
            if ($a -ge $l.Length) { $col += ''; continue }
            $len = if ($k + 1 -lt $starts.Count) { [Math]::Min($starts[$k + 1], $l.Length) - $a } else { $l.Length - $a }
            $col += $l.Substring($a, $len).Trim()
        }
        if (-not $col[1] -or -not $col[3]) { continue }
        $res.Add([pscustomobject]@{
            Name = $col[0]; Id = $col[1]; Version = $col[2]; Available = $col[3]
            Source = $(if ($col.Count -gt 4) { $col[4] } else { '' })
            Truncated = ($col[1] -match '…' -or $col[1].EndsWith('...'))
        })
    }
    return , $res.ToArray()
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
    <Style TargetType="ComboBox">
      <Setter Property="Foreground" Value="#E6E9EF"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <ToggleButton Focusable="False" ClickMode="Press"
                            IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton">
                    <Border x:Name="Bd" Background="#1B2130" BorderBrush="#2E3647" BorderThickness="1" CornerRadius="8">
                      <Path HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,10,0"
                            Data="M0,0 L4,4 L8,0" Stroke="#97A1B3" StrokeThickness="1.5"/>
                    </Border>
                    <ControlTemplate.Triggers>
                      <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="#252C3B"/></Trigger>
                    </ControlTemplate.Triggers>
                  </ControlTemplate>
                </ToggleButton.Template>
              </ToggleButton>
              <ContentPresenter IsHitTestVisible="False" Margin="10,5,28,5" VerticalAlignment="Center"
                                Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"/>
              <Popup x:Name="PART_Popup" IsOpen="{TemplateBinding IsDropDownOpen}" Placement="Bottom"
                     AllowsTransparency="True" Focusable="False" PopupAnimation="Fade">
                <Border Background="#1B2130" BorderBrush="#2E3647" BorderThickness="1" CornerRadius="8" Margin="0,4,0,0"
                        MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}">
                  <ScrollViewer MaxHeight="260"><ItemsPresenter Margin="4"/></ScrollViewer>
                </Border>
              </Popup>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="#E6E9EF"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBoxItem">
            <Border x:Name="Bd" Padding="10,6" CornerRadius="6" Background="Transparent"><ContentPresenter/></Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsSelected" Value="True"><Setter TargetName="Bd" Property="Background" Value="#22345A"/></Trigger>
              <Trigger Property="IsHighlighted" Value="True"><Setter TargetName="Bd" Property="Background" Value="#2F4470"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <ControlTemplate x:Key="ThumbTpl" TargetType="Thumb">
      <Border x:Name="T" Background="#3A4356" CornerRadius="4" Margin="2"/>
      <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="T" Property="Background" Value="#566078"/></Trigger>
        <Trigger Property="IsDragging" Value="True"><Setter TargetName="T" Property="Background" Value="#6B7590"/></Trigger>
      </ControlTemplate.Triggers>
    </ControlTemplate>
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="10"/>
      <Setter Property="MinWidth" Value="10"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Track x:Name="PART_Track" IsDirectionReversed="True">
              <Track.Thumb><Thumb Template="{StaticResource ThumbTpl}"/></Track.Thumb>
            </Track>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="Orientation" Value="Horizontal">
          <Setter Property="Width" Value="Auto"/>
          <Setter Property="MinWidth" Value="0"/>
          <Setter Property="Height" Value="10"/>
          <Setter Property="MinHeight" Value="10"/>
          <Setter Property="Template">
            <Setter.Value>
              <ControlTemplate TargetType="ScrollBar">
                <Track x:Name="PART_Track">
                  <Track.Thumb><Thumb Template="{StaticResource ThumbTpl}"/></Track.Thumb>
                </Track>
              </ControlTemplate>
            </Setter.Value>
          </Setter>
        </Trigger>
      </Style.Triggers>
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
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Text="Langue" VerticalAlignment="Center" Foreground="{StaticResource Muted}" Margin="0,0,8,0"/>
          <ComboBox x:Name="CmbLang" Width="120" VerticalAlignment="Center" Margin="0,0,14,0" Cursor="Hand"/>
          <Border VerticalAlignment="Center" Background="#14301F" CornerRadius="10" Padding="12,5">
            <TextBlock x:Name="TxtVersion" Foreground="#5BD48A" FontSize="12"/>
          </Border>
        </StackPanel>
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
                  <TextBlock Grid.Row="1" Text="Capteur thermique (ACPI)" Margin="0,8,0,0"/>
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
      <!-- ============ DÉMARRAGE ============ -->
      <TabItem Header="Démarrage" x:Name="TabStartup">
        <DockPanel>
          <Border DockPanel.Dock="Top" Style="{StaticResource Card}" Margin="8,0,8,8" Padding="16,12">
            <StackPanel>
              <TextBlock Style="{StaticResource Para}" Text="Programmes lancés automatiquement avec Windows : moins il y en a, plus Windows démarre vite. Cochez ceux dont vous voulez changer l'état (un programme activé sera désactivé, un programme désactivé sera réactivé). Rien n'est désinstallé."/>
              <WrapPanel>
                <Button x:Name="BtnStRefresh" Content="Actualiser la liste"/>
                <Button x:Name="BtnStNone"    Content="Tout décocher"/>
                <Button x:Name="BtnStStore"   Content="Applications du Store au démarrage"/>
              </WrapPanel>
            </StackPanel>
          </Border>
          <Border DockPanel.Dock="Bottom" Style="{StaticResource Card}" Margin="8" Padding="16,12">
            <DockPanel>
              <Button x:Name="BtnStApply" DockPanel.Dock="Right" Style="{StaticResource Accent}" Content="Appliquer la sélection (0)" VerticalAlignment="Center"/>
              <TextBlock VerticalAlignment="Center" TextWrapping="Wrap" Foreground="{StaticResource Muted}" Margin="0,0,16,0" Text="Effet au prochain démarrage de Windows. Une confirmation vous sera demandée."/>
            </DockPanel>
          </Border>
          <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="8,0,8,0">
            <StackPanel x:Name="PanelStartup" Margin="0,0,6,0"/>
          </ScrollViewer>
        </DockPanel>
      </TabItem>

      <!-- ============ LOGICIELS ============ -->
      <TabItem Header="Logiciels" x:Name="TabSoftware">
        <DockPanel>
          <Border DockPanel.Dock="Top" Style="{StaticResource Card}" Margin="8,0,8,8" Padding="16,12">
            <StackPanel>
              <TextBlock Style="{StaticResource Para}" Text="Mettez à jour vos logiciels (navigateurs, lanceurs de jeux, outils...) avec winget, l'outil officiel de Microsoft intégré à Windows 10 et 11. Les fichiers viennent des sources officielles des éditeurs."/>
              <WrapPanel>
                <Button x:Name="BtnWgScan" Content="Rechercher les mises à jour"/>
                <Button x:Name="BtnWgAll"  Content="Tout cocher"/>
                <Button x:Name="BtnWgNone" Content="Tout décocher"/>
              </WrapPanel>
            </StackPanel>
          </Border>
          <Border DockPanel.Dock="Bottom" Style="{StaticResource Card}" Margin="8" Padding="16,12">
            <DockPanel>
              <Button x:Name="BtnWgUpdate" DockPanel.Dock="Right" Style="{StaticResource Accent}" Content="Mettre à jour la sélection (0)" VerticalAlignment="Center"/>
              <TextBlock VerticalAlignment="Center" TextWrapping="Wrap" Foreground="{StaticResource Muted}" Margin="0,0,16,0" Text="Fermez les logiciels concernés avant. Une mise à jour ne peut pas être annulée."/>
            </DockPanel>
          </Border>
          <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="8,0,8,0">
            <StackPanel x:Name="PanelWg" Margin="0,0,6,0"/>
          </ScrollViewer>
        </DockPanel>
      </TabItem>

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

function Convert-XamlLanguage([xml]$Doc) {
    foreach ($node in $Doc.SelectNodes('//*')) {
        foreach ($attr in @('Text', 'Content', 'Header', 'Title')) {
            $v = $node.GetAttribute($attr)
            if ($v -and $v -notmatch '^\{') { $node.SetAttribute($attr, (Tr $v)) }
        }
    }
}

# En mode test, on s'arrête ici : toutes les fonctions et définitions sont chargées.
if ($TestMode) { return }

if ($Build -lt 10240) {
    Add-Type -AssemblyName PresentationFramework
    [void][System.Windows.MessageBox]::Show((Tr 'Cette application nécessite Windows 10 ou Windows 11.'), $AppName, 'OK', 'Error')
    exit
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

try {
    [xml]$XamlXml = $XamlText
    Convert-XamlLanguage $XamlXml
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
            try { Start-Process $this.Tag } catch { Write-Log ((Tr 'Impossible d''ouvrir : ') + $this.Tag) }
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
        if ($lines.Count -gt 25) { $lines = @($lines[0..23]) + ((Tr '   ... et {0} autre(s)') -f ($lines.Count - 24)) }
        return ($lines -join "`n")
    }

    function Get-CheckedCount($boxes) { return @($boxes | Where-Object { $_.IsChecked -eq $true -and $_.IsEnabled }).Count }

    # ------------------------- Matériel -------------------------
    $Cpu       = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $CpuName   = if ($Cpu) { ($Cpu.Name -replace '\s+', ' ').Trim() } else { Tr 'Inconnu' }
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

    $TxtVersion.Text  = (Tr 'Version {0}  -  Administrateur') -f $AppVersion
    $TxtCpu.Text      = '{0}{1}' -f $CpuName, $(if ($Cpu) { (Tr '  ({0} cœurs / {1} threads)') -f $Cpu.NumberOfCores, $Cpu.NumberOfLogicalProcessors } else { '' })
    $TxtGpu.Text      = if ($Gpus.Count) { ($Gpus | ForEach-Object { (Tr '{0}  (pilote {1})') -f $_.Name.Trim(), $_.DriverVersion }) -join "`n" } else { Tr 'Non détectée' }
    $TxtRam.Text      = (Tr '{0} Go') -f $RamGB
    $TxtOs.Text       = '{0} {1} (build {2}){3}' -f $OsCaption, $DispVer, $Build, $(if ($IsLaptop) { Tr '  -  PC portable' } else { '' })
    $TxtSubtitle.Text = (Tr 'Jeux et télétravail, sans surchauffe  -  {0}  -  {1}') -f $OsCaption, $(if ($GpuNames.Count) { $GpuNames[0] } else { $CpuName })
    $TxtDataPath.Text = (Tr 'Sauvegardes et journal : {0}') -f $DataPath

    # ------------------------- Conseils -------------------------
    $tips = New-Object System.Collections.Generic.List[string]
    if ($HasNvidia) {
        $tips.Add((Tr 'Carte NVIDIA : mettez à jour le pilote avec l''application officielle NVIDIA App. Dans les jeux compatibles, activez DLSS et NVIDIA Reflex : plus d''images par seconde et moins de chaleur.'))
        $GpuTempHint = Tr 'Non disponible (pilote NVIDIA introuvable)'
    }
    if ($HasAmdGpu) {
        $tips.Add((Tr 'Carte AMD Radeon : mettez à jour le pilote avec AMD Software: Adrenalin Edition. Activez FSR et Radeon Anti-Lag dans les jeux ; Radeon Chill réduit fortement la chauffe.'))
    }
    if ($HasIntelGpu) {
        $tips.Add((Tr 'Graphique Intel : mettez à jour le pilote avec Intel Driver & Support Assistant (ou le site du fabricant de votre PC portable). Activez XeSS dans les jeux compatibles.'))
    }
    if ($CpuVendor -eq 'AMD') { $tips.Add((Tr 'Processeur AMD Ryzen : installez le pilote « chipset » AMD depuis le site officiel ; il améliore la gestion de l''énergie avec le mode Équilibré.')) }
    if ($CpuVendor -eq 'Intel') { $tips.Add((Tr 'Processeur Intel : les mises à jour de pilotes et du BIOS se font via Intel Driver & Support Assistant ou le site du fabricant de votre PC.')) }
    if ($IsLaptop) { $tips.Add((Tr 'PC portable : jouez branché sur secteur, laissez de l''espace sous et derrière le PC (support ventilé) et dépoussiérez les grilles. L''option « Anti-surchauffe : limiter le processeur à 99 % » réduit beaucoup la chaleur.')) }
    $tips.Add((Tr 'Limitez les images par seconde à la fréquence de votre écran (60, 144, 165 Hz...) avec la V-Sync ou le limiteur du pilote : la carte graphique travaille moins et chauffe moins, sans perte visible.'))
    $tips.Add((Tr 'Un PC propre chauffe moins : un dépoussiérage des ventilateurs tous les 6 à 12 mois fait souvent baisser la température de plusieurs degrés.'))
    if (Test-IntelRaptorDesktop $CpuName) {
        [void]$PanelTips.Children.Add((New-Text ('⚠  ' + (Tr 'Processeur Intel Core de 13e/14e génération (PC de bureau) détecté : Intel a publié des mises à jour du microcode qui corrigent un problème d''instabilité de ces processeurs. Installez le dernier BIOS du fabricant de votre carte mère (avec le microcode 0x12B ou plus récent) et gardez les réglages Intel par défaut (« Intel Default Settings »).')) '#F0B429' 13 -Margin (Th 0 0 0 8)))
    }
    $script:Facts = $null
    try { $script:Facts = Get-SystemFacts } catch { Write-Log ((Tr 'Analyse du PC incomplète : ') + $_.Exception.Message) }
    $smart = @()
    if ($script:Facts) { $smart = @(Get-SmartTips $script:Facts) }
    foreach ($st in $smart) {
        $col = '#8FB4FF'; $sym = '➜  '
        if ($st.Level -eq 'warn') { $col = '#F0B429'; $sym = '⚠  ' }
        [void]$PanelTips.Children.Add((New-Text ($sym + $st.Text) $col 13 -Margin (Th 0 0 0 4)))
        if ($st.Action) {
            $b = New-ActionButton $st.Label $st.Action
            $b.Margin = (Th 24 2 0 8); $b.Padding = (Th 10 4 10 4); $b.HorizontalAlignment = 'Left'
            [void]$PanelTips.Children.Add($b)
        }
    }
    if ($smart.Count) { Write-Log ((Tr 'Analyse du PC : {0} conseil(s) personnalisé(s).') -f $smart.Count) }
    foreach ($tip in $tips) { [void]$PanelTips.Children.Add((New-Text ('•  ' + $tip) '#C3CAD6' 13 -Margin (Th 0 0 0 6))) }

    if ($HasNvidia)   { [void]$PanelLinks.Children.Add((New-ActionButton (Tr 'Pilote NVIDIA (site officiel)') 'https://www.nvidia.com/fr-fr/software/nvidia-app/')) }
    if ($HasAmdGpu -or $CpuVendor -eq 'AMD') { [void]$PanelLinks.Children.Add((New-ActionButton (Tr 'Pilotes AMD (site officiel)') 'https://www.amd.com/fr/support/download/drivers.html')) }
    if ($HasIntelGpu -or $CpuVendor -eq 'Intel') { [void]$PanelLinks.Children.Add((New-ActionButton (Tr 'Pilotes Intel (site officiel)') 'https://www.intel.fr/content/www/fr/fr/support/detect.html')) }
    [void]$PanelLinks.Children.Add((New-ActionButton (Tr 'Windows Update') 'ms-settings:windowsupdate'))
    [void]$PanelLinks.Children.Add((New-ActionButton (Tr 'Applications au démarrage') 'ms-settings:startupapps'))
    [void]$PanelLinks.Children.Add((New-ActionButton (Tr 'Stockage') 'ms-settings:storagesense'))
    [void]$PanelLinks.Children.Add((New-ActionButton (Tr 'Gestionnaire des tâches') 'taskmgr.exe'))

    if (-not $GpuTempHint) {
        if ($HasAmdGpu) { $GpuTempHint = Tr 'Visible dans AMD Software (Alt+R) ou le Gestionnaire des tâches' }
        elseif ($HasIntelGpu) { $GpuTempHint = Tr 'Visible dans le logiciel graphique Intel ou le Gestionnaire des tâches' }
        else { $GpuTempHint = Tr 'Non disponible' }
    }

    # ------------------------- Liste des optimisations -------------------------
    $script:TweakBoxes = New-Object System.Collections.Generic.List[object]

    function Update-SelCount {
        $BtnApply.Content = (Tr 'Appliquer la sélection ({0})') -f (Get-CheckedCount $script:TweakBoxes)
    }

    function Build-TweakList {
        $PanelTweaks.Children.Clear(); $script:TweakBoxes.Clear()
        foreach ($cat in $Categories) {
            $list = @($Tweaks | Where-Object { $_.Cat -eq $cat.Id -and (Test-TweakAvailable $_) })
            if ($list.Count -eq 0) { continue }
            [void]$PanelTweaks.Children.Add((New-Text (Tr $cat.Title) '#FFFFFF' 17 -Bold -Margin (Th 2 12 0 2)))
            [void]$PanelTweaks.Children.Add((New-Text (Tr $cat.Sub) '#97A1B3' 12.5 -Margin (Th 2 0 0 10)))
            foreach ($t in $list) {
                $applied = $t.Undoable -and (Test-TweakApplied $t)
                $card = New-Object System.Windows.Controls.Border
                $card.Style = $Window.FindResource('ItemCard')
                $sp = New-Object System.Windows.Controls.StackPanel
                $cb = New-Object System.Windows.Controls.CheckBox
                $cb.Content = (New-Text (Tr $t.Name) '#E6E9EF' 14 -Bold)
                $cb.Tag = $t
                $cb.Add_Checked({ Update-SelCount })
                $cb.Add_Unchecked({ Update-SelCount })
                [void]$sp.Children.Add($cb)
                [void]$sp.Children.Add((New-Text (Tr $t.Desc) '#97A1B3' 12.5 -Margin (Th 21 4 0 0)))
                $wp = New-Object System.Windows.Controls.WrapPanel
                $wp.Margin = (Th 21 2 0 0)
                if ($applied) {
                    $cb.IsEnabled = $false
                    [void]$wp.Children.Add((New-Badge (Tr 'Déjà actif') '#5BD48A' '#14301F'))
                }
                if ($t.Reboot)       { [void]$wp.Children.Add((New-Badge (Tr 'Redémarrage requis') '#F0B429' '#33290F')) }
                if (-not $t.Undoable) { [void]$wp.Children.Add((New-Badge (Tr 'Non annulable') '#F28B82' '#3A1A1A')) }
                if ($t.Warn)         { [void]$wp.Children.Add((New-Badge (Tr $t.Warn) '#F0B429' '#33290F')) }
                foreach ($p in $t.Profiles) { [void]$wp.Children.Add((New-Badge (Tr $ProfileLabels[$p]) '#9DB7F5' '#1B2740')) }
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
        if ($Name -and $n -eq 0) { Show-Info (Tr 'Toutes les optimisations de cette suggestion sont déjà actives sur ce PC.') }
        elseif ($Name) { Write-Log ((Tr 'Suggestion « {0} » : {1} case(s) cochée(s). Rien n''est encore modifié.') -f (Tr $ProfileLabels[$Name]), $n) }
    }

    # ------------------------- Point de restauration -------------------------
    function Wait-JobUI($Job, [switch]$All) {
        while ($Job.State -eq 'Running' -or $Job.State -eq 'NotStarted') { Invoke-UIPump; Start-Sleep -Milliseconds 120 }
        $out = @(Receive-JobLines $Job)
        if ($All) { return $out }
        if ($out.Count) { return [string]$out[-1] }
        return (Tr 'ERREUR : aucune réponse')
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
        Show-Busy (Tr 'Création du point de restauration Windows...\nCela peut prendre jusqu''à une minute.')
        $srKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
        $freq = Read-Reg $srKey 'SystemRestorePointCreationFrequency'
        $ok = $false
        try {
            # Windows limite à un point par 24 h par défaut : on lève cette limite le temps de la création.
            Write-Reg $srKey 'SystemRestorePointCreationFrequency' 0 'DWord'
            $r = Invoke-RestorePointJob $false
            if ($r -eq 'OK') { $ok = $true }
            else {
                Write-Log ((Tr 'Point de restauration : ') + $r)
                Hide-Busy
                if (Confirm-Action ((Tr 'Le point de restauration n''a pas pu être créé.\n{0}\n\nLa protection du système est peut-être désactivée.\nVoulez-vous l''activer sur le disque {1} et réessayer ?\n(Windows utilisera un peu d''espace disque pour les points de restauration.)') -f $r, $env:SystemDrive) 'Warning') {
                    Show-Busy (Tr 'Activation de la protection du système et nouvelle tentative...')
                    $r = Invoke-RestorePointJob $true
                    if ($r -eq 'OK') { $ok = $true; Write-Log (Tr 'Protection du système activée.') }
                    else { Write-Log ((Tr 'Point de restauration : ') + $r) }
                }
            }
        } finally {
            if ($freq.Exists) { Write-Reg $srKey 'SystemRestorePointCreationFrequency' $freq.Value $freq.Kind }
            else { Remove-ItemProperty -LiteralPath $srKey -Name 'SystemRestorePointCreationFrequency' -ErrorAction SilentlyContinue }
            Hide-Busy
        }
        if ($ok) { Write-Log (Tr 'Point de restauration créé.') }
        return $ok
    }

    function Request-Restart([string]$Text) {
        if (Confirm-Action ($Text + "`n`n" + (Tr 'Redémarrer l''ordinateur maintenant ?\n(Enregistrez d''abord votre travail en cours.)'))) {
            try { Restart-Computer -ErrorAction Stop } catch { Show-Info ((Tr 'Redémarrage impossible : ') + $_.Exception.Message) 'Warning' }
        }
    }

    # ------------------------- Applications -------------------------
    $script:AppBoxes = New-Object System.Collections.Generic.List[object]

    function Update-AppCount {
        $BtnRemoveApps.Content = (Tr 'Désinstaller la sélection ({0})') -f (Get-CheckedCount $script:AppBoxes)
    }

    function Build-AppList {
        $PanelApps.Children.Clear(); $script:AppBoxes.Clear()
        $apps = @(Get-BloatApps)
        if ($apps.Count -eq 0) {
            [void]$PanelApps.Children.Add((New-Text (Tr 'Aucune application inutile connue n''est installée sur ce compte.') '#5BD48A' 14 -Margin (Th 4 8 0 0)))
        }
        foreach ($a in @($apps | Sort-Object @{ Expression = 'Suggest'; Descending = $true }, Name)) {
            $card = New-Object System.Windows.Controls.Border
            $card.Style = $Window.FindResource('ItemCard')
            $sp = New-Object System.Windows.Controls.StackPanel
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Content = (New-Text (Tr $a.Name) '#E6E9EF' 14 -Bold)
            $cb.Tag = $a
            $cb.Add_Checked({ Update-AppCount }); $cb.Add_Unchecked({ Update-AppCount })
            [void]$sp.Children.Add($cb)
            $info = $a.PkgName
            if ($a.Note) { $info = (Tr $a.Note) + '   (' + $a.PkgName + ')' }
            [void]$sp.Children.Add((New-Text $info '#97A1B3' 12.5 -Margin (Th 21 3 0 0)))
            if ($a.Suggest) {
                $wp = New-Object System.Windows.Controls.WrapPanel; $wp.Margin = (Th 21 0 0 0)
                [void]$wp.Children.Add((New-Badge (Tr 'Suggérée') '#9DB7F5' '#1B2740'))
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
        $BtnUndo.Content = (Tr 'Restaurer la sélection ({0})') -f (Get-CheckedCount $script:UndoBoxes)
    }

    function Build-UndoList {
        $PanelUndo.Children.Clear(); $script:UndoBoxes.Clear()
        $entries = @($Backup.Values | Sort-Object Date)
        if ($entries.Count -eq 0) {
            [void]$PanelUndo.Children.Add((New-Text (Tr 'Aucun réglage modifié par l''application pour le moment.') '#97A1B3' 13 -Margin (Th 4 0 0 0)))
        }
        foreach ($e in $entries) {
            $card = New-Object System.Windows.Controls.Border
            $card.Style = $Window.FindResource('ItemCard')
            $sp = New-Object System.Windows.Controls.StackPanel
            $cb = New-Object System.Windows.Controls.CheckBox
            $label = Tr $e.Name
            if ($e.Kind -eq 'Startup') {
                $label = (Tr 'Démarrage : ') + $e.Name + '  (' + $(if ($e.Enable) { Tr 'Activé' } else { Tr 'Désactivé' }) + ')'
            }
            $cb.Content = (New-Text $label '#E6E9EF' 14 -Bold)
            $cb.Tag = $e
            $cb.Add_Checked({ Update-UndoCount }); $cb.Add_Unchecked({ Update-UndoCount })
            [void]$sp.Children.Add($cb)
            [void]$sp.Children.Add((New-Text ((Tr 'Modifié le ') + $e.Date) '#97A1B3' 12.5 -Margin (Th 21 3 0 0)))
            $card.Child = $sp
            [void]$PanelUndo.Children.Add($card)
            $script:UndoBoxes.Add($cb)
        }
        Update-UndoCount

        $PanelRemoved.Children.Clear()
        if ($RemovedApps.Count -eq 0) {
            [void]$PanelRemoved.Children.Add((New-Text (Tr 'Aucune application désinstallée par l''application.') '#97A1B3' 13 -Margin (Th 4 0 0 0)))
        }
        foreach ($a in $RemovedApps) {
            $card = New-Object System.Windows.Controls.Border
            $card.Style = $Window.FindResource('ItemCard')
            $dp = New-Object System.Windows.Controls.DockPanel
            $btn = New-ActionButton (Tr 'Réinstaller depuis le Microsoft Store') ('ms-windows-store://pdp/?PFN=' + $a.Family)
            $btn.Margin = (Th 12 0 0 0)
            [System.Windows.Controls.DockPanel]::SetDock($btn, [System.Windows.Controls.Dock]::Right)
            [void]$dp.Children.Add($btn)
            $sp = New-Object System.Windows.Controls.StackPanel
            $sp.VerticalAlignment = 'Center'
            [void]$sp.Children.Add((New-Text (Tr $a.Name) '#E6E9EF' 14 -Bold))
            [void]$sp.Children.Add((New-Text ((Tr 'Désinstallée le ') + $a.Date) '#97A1B3' 12.5))
            [void]$dp.Children.Add($sp)
            $card.Child = $dp
            [void]$PanelRemoved.Children.Add($card)
        }
    }

    # ------------------------- Démarrage de Windows -------------------------
    $script:StartupBoxes = New-Object System.Collections.Generic.List[object]

    function Update-StartupCount {
        $BtnStApply.Content = (Tr 'Appliquer la sélection ({0})') -f (Get-CheckedCount $script:StartupBoxes)
    }

    function Build-StartupList {
        $PanelStartup.Children.Clear(); $script:StartupBoxes.Clear()
        $entries = @(Get-StartupEntries | Sort-Object @{ Expression = 'Enabled'; Descending = $true }, Name)
        if ($entries.Count -eq 0) {
            [void]$PanelStartup.Children.Add((New-Text (Tr 'Aucun programme ne se lance au démarrage de Windows.') '#5BD48A' 14 -Margin (Th 4 8 0 0)))
        }
        foreach ($e in $entries) {
            $card = New-Object System.Windows.Controls.Border
            $card.Style = $Window.FindResource('ItemCard')
            $sp = New-Object System.Windows.Controls.StackPanel
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Content = (New-Text $e.Name '#E6E9EF' 14 -Bold)
            $cb.Tag = $e
            $cb.Add_Checked({ Update-StartupCount }); $cb.Add_Unchecked({ Update-StartupCount })
            [void]$sp.Children.Add($cb)
            $cmd = $e.Command
            if ($e.ValueName -and $e.ValueName -ne $e.Name -and $e.Command -ne $e.ValueName) { $cmd = $e.ValueName + '   ·   ' + $cmd }
            if ($cmd.Length -gt 140) { $cmd = $cmd.Substring(0, 137) + '...' }
            [void]$sp.Children.Add((New-Text $cmd '#97A1B3' 12 -Margin (Th 21 3 0 0)))
            $wp = New-Object System.Windows.Controls.WrapPanel; $wp.Margin = (Th 21 0 0 0)
            if ($e.Enabled) { [void]$wp.Children.Add((New-Badge (Tr 'Activé') '#5BD48A' '#14301F')) }
            else { [void]$wp.Children.Add((New-Badge (Tr 'Désactivé') '#AEB6C6' '#262D3B')) }
            if ($e.Scope -eq 'all') { [void]$wp.Children.Add((New-Badge (Tr 'Tous les comptes') '#9DB7F5' '#1B2740')) }
            else { [void]$wp.Children.Add((New-Badge (Tr 'Votre compte') '#9DB7F5' '#1B2740')) }
            [void]$sp.Children.Add($wp)
            if ($e.Note) { [void]$sp.Children.Add((New-Text ('ℹ  ' + $e.Note) '#F0B429' 12.5 -Margin (Th 21 6 0 0))) }
            $card.Child = $sp
            [void]$PanelStartup.Children.Add($card)
            $script:StartupBoxes.Add($cb)
        }
        Update-StartupCount
    }

    $BtnStRefresh.Add_Click({ Build-StartupList })
    $BtnStNone.Add_Click({ foreach ($cb in $script:StartupBoxes) { $cb.IsChecked = $false }; Update-StartupCount })
    $BtnStStore.Add_Click({ try { Start-Process 'ms-settings:startupapps' } catch { } })

    $BtnStApply.Add_Click({
        $sel = @($script:StartupBoxes | Where-Object { $_.IsChecked -eq $true } | ForEach-Object { $_.Tag })
        if ($sel.Count -eq 0) { Show-Info (Tr 'Aucun programme n''est coché.'); return }
        $off = @($sel | Where-Object { $_.Enabled } | ForEach-Object { $_.Name })
        $on = @($sel | Where-Object { -not $_.Enabled } | ForEach-Object { $_.Name })
        $msg = ''
        if ($off.Count) { $msg += (Tr 'Ne plus lancer au démarrage de Windows :') + "`n" + (Format-Bullets $off) + "`n`n" }
        if ($on.Count) { $msg += (Tr 'Lancer de nouveau au démarrage de Windows :') + "`n" + (Format-Bullets $on) + "`n`n" }
        $msg += (Tr 'Les programmes ne sont pas désinstallés : seul leur lancement automatique change. Vous pourrez revenir en arrière dans l''onglet « Restaurer ».\n\nConfirmez-vous ?')
        if (-not (Confirm-Action $msg)) { Write-Log (Tr 'Démarrage : modifications annulées, non confirmées.'); return }
        $okCount = 0; $errors = @()
        foreach ($e in $sel) {
            try {
                Set-StartupEnabled $e (-not $e.Enabled)
                $okCount++
                Write-Log ((Tr 'Démarrage : ') + $e.Name + ' -> ' + $(if ($e.Enabled) { Tr 'Désactivé' } else { Tr 'Activé' }))
            } catch {
                $errors += ($e.Name + ' : ' + $_.Exception.Message)
                Write-Log ((Tr 'ERREUR : ') + $e.Name + ' : ' + $_.Exception.Message)
            }
        }
        Build-StartupList; Build-UndoList
        $summary = (Tr '{0} programme(s) modifié(s) sur {1}. Effet au prochain démarrage de Windows.') -f $okCount, $sel.Count
        if ($errors.Count) { Show-Info ($summary + "`n`n" + (Tr 'Erreurs :') + "`n" + (Format-Bullets $errors)) 'Warning' } else { Show-Info $summary }
    })

    # ------------------------- Mises à jour des logiciels (winget) -------------------------
    $script:WgBoxes = New-Object System.Collections.Generic.List[object]
    $script:WgList = @()

    function Update-WgCount {
        $BtnWgUpdate.Content = (Tr 'Mettre à jour la sélection ({0})') -f (Get-CheckedCount $script:WgBoxes)
    }

    function Show-WgMessage([string]$Text, [string]$Color = '#97A1B3') {
        $PanelWg.Children.Clear(); $script:WgBoxes.Clear()
        [void]$PanelWg.Children.Add((New-Text $Text $Color 14 -Margin (Th 4 8 0 0)))
        Update-WgCount
    }

    function Build-WgList($List) {
        $PanelWg.Children.Clear(); $script:WgBoxes.Clear()
        foreach ($p in @($List)) {
            $card = New-Object System.Windows.Controls.Border
            $card.Style = $Window.FindResource('ItemCard')
            $sp = New-Object System.Windows.Controls.StackPanel
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Content = (New-Text $p.Name '#E6E9EF' 14 -Bold)
            $cb.Tag = $p
            $cb.Add_Checked({ Update-WgCount }); $cb.Add_Unchecked({ Update-WgCount })
            [void]$sp.Children.Add($cb)
            [void]$sp.Children.Add((New-Text ((Tr 'Version {0}  →  {1}') -f $p.Version, $p.Available) '#C3CAD6' 13 -Margin (Th 21 3 0 0)))
            [void]$sp.Children.Add((New-Text ($p.Id + '   ·   ' + $p.Source) '#97A1B3' 12 -Margin (Th 21 2 0 0)))
            if ($p.Truncated) {
                $cb.IsEnabled = $false
                [void]$sp.Children.Add((New-Text (Tr 'Identifiant incomplet : mettez ce logiciel à jour depuis le logiciel lui-même.') '#F0B429' 12.5 -Margin (Th 21 4 0 0)))
            }
            $card.Child = $sp
            [void]$PanelWg.Children.Add($card)
            $script:WgBoxes.Add($cb)
        }
        Update-WgCount
    }

    $BtnWgAll.Add_Click({ foreach ($cb in $script:WgBoxes) { if ($cb.IsEnabled) { $cb.IsChecked = $true } }; Update-WgCount })
    $BtnWgNone.Add_Click({ foreach ($cb in $script:WgBoxes) { $cb.IsChecked = $false }; Update-WgCount })

    $BtnWgScan.Add_Click({
        $wg = Get-WingetPath
        if (-not $wg) {
            Show-WgMessage (Tr 'winget n''est pas disponible sur ce PC. Installez « Programme d''installation d''application » (App Installer) depuis le Microsoft Store, puis réessayez.') '#F0B429'
            try { Start-Process 'ms-windows-store://pdp/?PFN=Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' } catch { }
            return
        }
        Show-Busy (Tr 'Recherche des mises à jour avec winget...\nCela peut prendre une minute.')
        try {
            $job = Start-Job -ArgumentList $wg -ScriptBlock {
                param($wg)
                try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
                & $wg upgrade --accept-source-agreements 2>&1 | ForEach-Object { [string]$_ }
            }
            $out = @(Wait-JobUI $job -All)
            try { $out | Set-Content -LiteralPath (Join-Path $DataPath 'winget-derniere-recherche.txt') -Encoding UTF8 } catch { }
            $list = ConvertFrom-WingetTable $out
            if ($null -eq $list) {
                $last = [string](@(Split-OutputLines $out | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '\w{3}' }) | Select-Object -Last 1)
                if ($last.Length -gt 200) { $last = $last.Substring(0, 197) + '...' }
                $script:WgList = @()
                Show-WgMessage ((Tr 'Aucune mise à jour trouvée. Message de winget : {0}') -f $last) '#5BD48A'
                Write-Log ((Tr 'winget : ') + $last)
            } else {
                $script:WgList = @($list)
                if ($script:WgList.Count -eq 0) { Show-WgMessage (Tr 'Tous vos logiciels connus de winget sont à jour.') '#5BD48A' }
                else { Build-WgList $script:WgList }
                Write-Log ((Tr 'winget : {0} mise(s) à jour disponible(s).') -f $script:WgList.Count)
            }
        } finally { Hide-Busy }
    })

    $BtnWgUpdate.Add_Click({
        $sel = @($script:WgBoxes | Where-Object { $_.IsChecked -eq $true -and $_.IsEnabled } | ForEach-Object { $_.Tag })
        if ($sel.Count -eq 0) { Show-Info (Tr 'Aucun logiciel n''est coché.'); return }
        $names = @($sel | ForEach-Object { '{0}  ({1} → {2})' -f $_.Name, $_.Version, $_.Available })
        $msg = (Tr 'Vous allez mettre à jour {0} logiciel(s) avec winget, l''outil officiel de Microsoft :\n\n{1}\n\nFermez ces logiciels avant de continuer. Une mise à jour ne peut pas être annulée.\n\nConfirmez-vous ?') -f $sel.Count, (Format-Bullets $names)
        if (-not (Confirm-Action $msg)) { Write-Log (Tr 'Mises à jour annulées : non confirmées.'); return }
        $wg = Get-WingetPath
        $okCount = 0; $errors = @(); $done = @()
        Show-Busy (Tr 'Mise à jour des logiciels...')
        try {
            foreach ($p in $sel) {
                $TxtBusy.Text = (Tr 'Mise à jour : ') + $p.Name
                Invoke-UIPump
                $job = Start-Job -ArgumentList $wg, $p.Id -ScriptBlock {
                    param($wg, $id)
                    & $wg upgrade --id $id --exact --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
                    'EXIT:' + $LASTEXITCODE
                }
                $r = Wait-JobUI $job
                if ($r -eq 'EXIT:0') { $okCount++; $done += $p.Id; Write-Log ((Tr 'Mis à jour : ') + $p.Name + ' ' + $p.Available) }
                else {
                    $errors += ('{0} : {1}' -f $p.Name, $r)
                    Write-Log ((Tr 'ERREUR : ') + $p.Name + ' : ' + $r)
                }
            }
        } finally {
            Hide-Busy
            $script:WgList = @($script:WgList | Where-Object { $done -notcontains $_.Id })
            if ($script:WgList.Count) { Build-WgList $script:WgList } else { Show-WgMessage (Tr 'Tous vos logiciels connus de winget sont à jour.') '#5BD48A' }
        }
        $summary = (Tr '{0} logiciel(s) mis à jour sur {1}.') -f $okCount, $sel.Count
        if ($errors.Count) { Show-Info ($summary + "`n`n" + (Tr 'Erreurs :') + "`n" + (Format-Bullets $errors) + "`n`n" + (Tr 'Certains logiciels doivent être fermés, ou mis à jour depuis le logiciel lui-même.')) 'Warning' }
        else { Show-Info $summary }
    })

    # ------------------------- Actions des boutons -------------------------
    $BtnProfGame.Add_Click({ Select-Profile 'Jeux' })
    $BtnProfOffice.Add_Click({ Select-Profile 'Bureau' })
    $BtnProfHeat.Add_Click({ Select-Profile 'Chaleur' })
    $BtnProfNone.Add_Click({ foreach ($cb in $script:TweakBoxes) { $cb.IsChecked = $false }; Update-SelCount })

    $BtnApply.Add_Click({
        $sel = @($script:TweakBoxes | Where-Object { $_.IsChecked -eq $true -and $_.IsEnabled } | ForEach-Object { $_.Tag })
        if ($sel.Count -eq 0) {
            Show-Info (Tr 'Aucune case n''est cochée.\n\nCochez d''abord les optimisations souhaitées, ou utilisez un bouton « Suggestion ».')
            return
        }
        $names = @($sel | ForEach-Object { (Tr $_.Name) + $(if ($_.Reboot) { Tr '  [redémarrage]' } elseif (-not $_.Undoable) { Tr '  [définitif]' } else { '' }) })
        $msg = (Tr 'Vous allez modifier {0} réglage(s) de Windows :\n\n{1}\n\n') -f $sel.Count, (Format-Bullets $names)
        if ($ChkRestore.IsChecked) { $msg += (Tr 'Un point de restauration Windows sera créé avant.\n') }
        $msg += (Tr 'Vos réglages d''origine seront sauvegardés (onglet « Restaurer »).\n\nConfirmez-vous ces modifications ?')
        if (-not (Confirm-Action $msg)) { Write-Log (Tr 'Modifications annulées : non confirmées.'); return }

        if ($ChkRestore.IsChecked) {
            if (-not (New-RestorePointUI)) {
                if (-not (Confirm-Action (Tr 'Le point de restauration n''a pas été créé.\n\nContinuer quand même ?\nVos réglages d''origine restent sauvegardés par l''application et peuvent être restaurés.') 'Warning')) {
                    Write-Log (Tr 'Modifications annulées : pas de point de restauration.')
                    return
                }
            }
        }

        Show-Busy (Tr 'Application des réglages...')
        $okCount = 0; $errors = @(); $needReboot = $false
        try {
            foreach ($t in $sel) {
                $TxtBusy.Text = (Tr 'Application : ') + (Tr $t.Name)
                Invoke-UIPump
                try {
                    Invoke-Tweak $t
                    $okCount++
                    if ($t.Reboot) { $needReboot = $true }
                    Write-Log ((Tr 'Appliqué : ') + (Tr $t.Name))
                } catch {
                    $errors += ((Tr $t.Name) + ' : ' + $_.Exception.Message)
                    Write-Log ((Tr 'ERREUR : ') + (Tr $t.Name) + ' : ' + $_.Exception.Message)
                }
            }
        } finally {
            Hide-Busy
            Build-TweakList; Build-UndoList
        }

        $summary = (Tr '{0} réglage(s) appliqué(s) sur {1}.') -f $okCount, $sel.Count
        if ($errors.Count) { Show-Info ($summary + "`n`n" + (Tr 'Erreurs :') + "`n" + (Format-Bullets $errors)) 'Warning' }
        if ($needReboot) { Request-Restart ($summary + "`n" + (Tr 'Certains réglages prendront effet après un redémarrage.')) }
        elseif (-not $errors.Count) { Show-Info $summary }
    })

    $BtnAppsSuggest.Add_Click({ foreach ($cb in $script:AppBoxes) { $cb.IsChecked = [bool]$cb.Tag.Suggest }; Update-AppCount })
    $BtnAppsNone.Add_Click({ foreach ($cb in $script:AppBoxes) { $cb.IsChecked = $false }; Update-AppCount })
    $BtnAppsRefresh.Add_Click({ Show-Busy (Tr 'Recherche des applications...'); try { Build-AppList } finally { Hide-Busy } })

    $BtnRemoveApps.Add_Click({
        $sel = @($script:AppBoxes | Where-Object { $_.IsChecked -eq $true } | ForEach-Object { $_.Tag })
        if ($sel.Count -eq 0) { Show-Info (Tr 'Aucune application n''est cochée.'); return }
        $msg = (Tr 'Vous allez désinstaller {0} application(s) pour votre compte :\n\n{1}\n\nElles pourront être réinstallées gratuitement depuis le Microsoft Store (onglet « Restaurer »).\n\nConfirmez-vous la désinstallation ?') -f $sel.Count, (Format-Bullets @($sel | ForEach-Object { Tr $_.Name }))
        if (-not (Confirm-Action $msg 'Warning')) { Write-Log (Tr 'Désinstallation annulée : non confirmée.'); return }

        Show-Busy (Tr 'Désinstallation...')
        $okCount = 0; $errors = @()
        try {
            foreach ($a in $sel) {
                $TxtBusy.Text = (Tr 'Désinstallation : ') + (Tr $a.Name)
                Invoke-UIPump
                try {
                    Remove-AppxPackage -Package $a.FullName -ErrorAction Stop
                    [void]$RemovedApps.Add([pscustomobject]@{ Name = $a.Name; Family = $a.Family; PkgName = $a.PkgName; Date = (Get-Date).ToString('yyyy-MM-dd HH:mm') })
                    Save-Data
                    $okCount++
                    Write-Log ((Tr 'Désinstallée : ') + (Tr $a.Name))
                } catch {
                    $errors += ((Tr $a.Name) + ' : ' + $_.Exception.Message)
                    Write-Log ((Tr 'ERREUR : ') + (Tr $a.Name) + ' : ' + $_.Exception.Message)
                }
            }
        } finally {
            Build-AppList; Build-UndoList
            Hide-Busy
        }
        $summary = (Tr '{0} application(s) désinstallée(s) sur {1}.') -f $okCount, $sel.Count
        if ($errors.Count) { Show-Info ($summary + "`n`n" + (Tr 'Erreurs :') + "`n" + (Format-Bullets $errors)) 'Warning' } else { Show-Info $summary }
    })

    $BtnUndoAll.Add_Click({ foreach ($cb in $script:UndoBoxes) { $cb.IsChecked = $true }; Update-UndoCount })
    $BtnUndoNone.Add_Click({ foreach ($cb in $script:UndoBoxes) { $cb.IsChecked = $false }; Update-UndoCount })
    $BtnRstrui.Add_Click({ try { Start-Process 'rstrui.exe' } catch { Show-Info (Tr 'La Restauration du système est indisponible sur ce PC.') 'Warning' } })
    $BtnLogs.Add_Click({ Start-Process 'explorer.exe' -ArgumentList "`"$DataPath`"" })

    $BtnUndo.Add_Click({
        $sel = @($script:UndoBoxes | Where-Object { $_.IsChecked -eq $true } | ForEach-Object { $_.Tag })
        if ($sel.Count -eq 0) { Show-Info (Tr 'Aucun réglage n''est coché.'); return }
        $msg = (Tr 'Vous allez remettre {0} réglage(s) comme avant :\n\n{1}\n\nConfirmez-vous ?') -f $sel.Count, (Format-Bullets @($sel | ForEach-Object { if ($_.Kind -eq 'Startup') { (Tr 'Démarrage : ') + $_.Name } else { Tr $_.Name } }))
        if (-not (Confirm-Action $msg)) { Write-Log (Tr 'Restauration annulée : non confirmée.'); return }

        Show-Busy (Tr 'Restauration des réglages...')
        $okCount = 0; $errors = @(); $needReboot = $false
        try {
            foreach ($e in $sel) {
                $TxtBusy.Text = (Tr 'Restauration : ') + (Tr $e.Name)
                Invoke-UIPump
                try {
                    Undo-Tweak $e
                    $okCount++
                    if ($e.Reboot) { $needReboot = $true }
                    Write-Log ((Tr 'Restauré : ') + $(if ($e.Kind -eq 'Startup') { (Tr 'Démarrage : ') + $e.Name } else { Tr $e.Name }))
                } catch {
                    $errors += ((Tr $e.Name) + ' : ' + $_.Exception.Message)
                    Write-Log ((Tr 'ERREUR restauration : ') + (Tr $e.Name) + ' : ' + $_.Exception.Message)
                }
            }
        } finally {
            Hide-Busy
            Build-TweakList; Build-UndoList; Build-StartupList
        }
        $summary = (Tr '{0} réglage(s) restauré(s) sur {1}.') -f $okCount, $sel.Count
        if ($errors.Count) { Show-Info ($summary + "`n`n" + (Tr 'Erreurs :') + "`n" + (Format-Bullets $errors)) 'Warning' }
        if ($needReboot) { Request-Restart ($summary + "`n" + (Tr 'Certains réglages reviendront après un redémarrage.')) }
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
            try {
                # Compteurs bruts : utilisation = 1 - (temps d'inactivité / temps écoulé) entre deux mesures
                $r = Get-CimInstance Win32_PerfRawData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction Stop
                $cur = @{ Idle = [double]$r.PercentProcessorTime; Stamp = [double]$r.Timestamp_Sys100NS }
                if ($prevCpu -and $cur.Stamp -gt $prevCpu.Stamp) {
                    $u = (1 - ($cur.Idle - $prevCpu.Idle) / ($cur.Stamp - $prevCpu.Stamp)) * 100
                    $Sync.Cpu = [int][Math]::Round([Math]::Max(0, [Math]::Min(100, $u)))
                }
                $prevCpu = $cur
            } catch { $Sync.Cpu = $null }
            try {
                $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
                $Sync.Ram = [int](100 - 100 * $os.FreePhysicalMemory / $os.TotalVisibleMemorySize)
            } catch { $Sync.Ram = $null }
            try {
                # Compteurs bruts du moteur 3D de chaque processus : temps d'activité / temps écoulé
                $eng = @(Get-CimInstance Win32_PerfRawData_GPUPerformanceCounters_GPUEngine -ErrorAction Stop | Where-Object { $_.Name -like '*engtype_3D' })
                $curGpu = @{}; $sum = 0.0
                foreach ($e in $eng) {
                    $curGpu[$e.Name] = @([double]$e.UtilizationPercentage, [double]$e.Timestamp_Sys100NS)
                    if ($prevGpu -and $prevGpu.ContainsKey($e.Name)) {
                        $pv = $prevGpu[$e.Name]; $dt = $curGpu[$e.Name][1] - $pv[1]
                        if ($dt -gt 0) { $sum += ($curGpu[$e.Name][0] - $pv[0]) / $dt * 100 }
                    }
                }
                if ($prevGpu) { $Sync.Gpu = [int][Math]::Round([Math]::Max(0, [Math]::Min(100, $sum))) }
                $prevGpu = $curGpu
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
        if ($null -ne $s.Cpu) { $PbCpu.Value = $s.Cpu; $TxtCpuVal.Text = "$($s.Cpu) %" } else { $TxtCpuVal.Text = (Tr 'n/d') }
        $g = $s.Gpu
        if ($null -ne $s.GpuNv) { $g = $s.GpuNv }
        if ($null -ne $g) { $PbGpu.Value = $g; $TxtGpuVal.Text = "$g %" } else { $TxtGpuVal.Text = (Tr 'n/d') }
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
            $level = [Math]::Max($level, (Set-TempText $TxtCpuTemp $s.CpuTemp 80 90 (Tr '   (souvent la carte mère, pas le processeur)')))
        } else {
            $TxtCpuTemp.Text = Tr 'Non disponible sans l''outil du fabricant'; $TxtCpuTemp.Foreground = (Br '#97A1B3')
        }

        if ($level -ge 2) {
            $HeatBox.Background = (Br '#3A1618')
            $TxtHeat.Text = (Tr 'Température élevée ! Vérifiez que les aérations ne sont pas bouchées, dépoussiérez le PC, limitez les images par seconde dans vos jeux et essayez la « Suggestion Anti-surchauffe ».')
        } elseif ($level -eq 1) {
            $HeatBox.Background = (Br '#33290F')
            $TxtHeat.Text = (Tr 'Température soutenue : normal pendant un jeu exigeant. Si cela dure au repos, pensez au dépoussiérage et à la « Suggestion Anti-surchauffe ».')
        } elseif ($hasTemp) {
            $HeatBox.Background = (Br '#14301F')
            $TxtHeat.Text = (Tr 'Températures normales.')
        } else {
            $HeatBox.Background = (Br '#1B2130')
            $TxtHeat.Text = (Tr 'Ce PC ne donne pas accès à ses capteurs de température à Windows. Utilisez le logiciel du fabricant de votre carte graphique ou de votre PC pour les consulter.')
        }
    }

    $Timer = New-Object System.Windows.Threading.DispatcherTimer
    $Timer.Interval = [TimeSpan]::FromSeconds(2)
    $Timer.Add_Tick({ try { Update-Monitor } catch { } })

    $Window.Add_Loaded({ $Timer.Start() })

    if ($CaptureDir) {
        # Mode test : une image PNG par onglet, puis fermeture (aucun réglage n'est modifié)
        $script:CaptureTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:CaptureTimer.Interval = [TimeSpan]::FromSeconds(5)
        $script:CaptureTimer.Add_Tick({
            $script:CaptureTimer.Stop()
            try {
                if (-not (Test-Path -LiteralPath $CaptureDir)) { New-Item -ItemType Directory -Path $CaptureDir -Force | Out-Null }
                for ($i = 0; $i -lt $Tabs.Items.Count; $i++) {
                    $Tabs.SelectedIndex = $i
                    $Window.UpdateLayout(); Invoke-UIPump
                    $root = $Window.Content
                    $rtb = [System.Windows.Media.Imaging.RenderTargetBitmap]::new([int]$root.ActualWidth, [int]$root.ActualHeight, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
                    $bg = New-Object System.Windows.Media.DrawingVisual
                    $dc = $bg.RenderOpen()
                    $dc.DrawRectangle($Window.Background, $null, [System.Windows.Rect]::new(0, 0, $root.ActualWidth, $root.ActualHeight))
                    $dc.Close()
                    $rtb.Render($bg); $rtb.Render($root)
                    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
                    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
                    $fs = [IO.File]::Create((Join-Path $CaptureDir ('{0}-{1}.png' -f $Lang, $i)))
                    try { $enc.Save($fs) } finally { $fs.Close() }
                }
            } catch {
                Write-Log ('Capture : ' + $_.Exception.Message)
            }
            $Window.Close()
        })
        $Window.Add_ContentRendered({ $script:CaptureTimer.Start() })
    }
    $Window.Add_Closed({
        $Timer.Stop()
        $script:Sync.Run = $false
        try { [void]$MonPS.EndInvoke($MonHandle) } catch { }
        try { $MonPS.Dispose(); $MonRunspace.Dispose() } catch { }
    })

    # ------------------------- Langue -------------------------
    $script:LangReady = $false
    foreach ($code in @($Languages.Keys)) {
        $item = New-Object System.Windows.Controls.ComboBoxItem
        $item.Content = [string]$Languages[$code]['@langue']
        $item.Tag = $code
        [void]$CmbLang.Items.Add($item)
        if ($code -eq $Lang) { $CmbLang.SelectedItem = $item }
    }
    $script:LangReady = $true
    $CmbLang.Add_SelectionChanged({
        if (-not $script:LangReady -or -not $CmbLang.SelectedItem) { return }
        $code = [string]$CmbLang.SelectedItem.Tag
        if ($code -eq $Lang) { return }
        # La langue choisie est mémorisée, puis l'application redémarre dans cette langue.
        try { [pscustomobject]@{ Lang = $code } | ConvertTo-Json | Set-Content -LiteralPath $SettingsFile -Encoding UTF8 } catch { }
        $exe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        Start-Process -FilePath $exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`""
        $Window.Close()
    })

    # ------------------------- Démarrage -------------------------
    $script:TxtLog = $TxtLog
    Write-Log ((Tr '{0} {1} démarré - {2} {3} (build {4}).') -f $AppName, $AppVersion, $OsCaption, $DispVer, $Build)
    Build-TweakList
    Build-AppList
    Build-StartupList
    Show-WgMessage (Tr 'Cliquez sur « Rechercher les mises à jour » pour vérifier vos logiciels.')
    Build-UndoList
    if ($Backup.Count -gt 0) { Write-Log ((Tr '{0} réglage(s) modifié(s) précédemment peuvent être restaurés (onglet « Restaurer »).') -f $Backup.Count) }

    [void]$Window.ShowDialog()
} catch {
    Write-Log ((Tr 'Erreur inattendue :') + ' ' + $_.Exception.Message)
    [void][System.Windows.MessageBox]::Show((Tr 'Erreur inattendue :') + "`n" + $_.Exception.Message + "`n`n" + (Tr 'Journal : ') + $LogFile, $AppName, 'OK', 'Error')
}
