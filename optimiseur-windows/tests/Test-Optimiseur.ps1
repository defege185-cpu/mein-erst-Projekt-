<#
    Tests automatiques de l'Optimiseur PC.
    À lancer dans une machine virtuelle ou un PC de test (Windows PowerShell 5.1, administrateur) :
        powershell -NoProfile -ExecutionPolicy Bypass -STA -File tests\Test-Optimiseur.ps1
    Chaque réglage est appliqué puis restauré, et on vérifie que l'état d'origine revient exactement.
#>
$ErrorActionPreference = 'Stop'
$Script = (Resolve-Path (Join-Path $PSScriptRoot '..\OptimiseurPC.ps1')).Path
$script:Fail = 0

function Check([string]$Name, [scriptblock]$Body) {
    try {
        $r = & $Body
        if ($r -is [bool] -and -not $r) { throw 'résultat inattendu' }
        Write-Host "[OK]     $Name"
    } catch {
        $script:Fail++
        Write-Host "[ÉCHEC]  $Name : $($_.Exception.Message)" -ForegroundColor Red
    }
}

# 1. Syntaxe et encodage --------------------------------------------------------------------
$tokens = $null; $parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($Script, [ref]$tokens, [ref]$parseErrors)
Check 'Syntaxe PowerShell' {
    if ($parseErrors.Count) { throw (($parseErrors | ForEach-Object { 'ligne {0} : {1}' -f $_.Extent.StartLineNumber, $_.Message }) -join ' | ') }
    $true
}
Check 'Encodage UTF-8 avec BOM (accents corrects sous Windows PowerShell 5.1)' {
    $b = [IO.File]::ReadAllBytes($Script)
    ($b[0] -eq 0xEF) -and ($b[1] -eq 0xBB) -and ($b[2] -eq 0xBF)
}
if ($parseErrors.Count) { exit 1 }

# 2. Chargement en mode test -----------------------------------------------------------------
$TestData = Join-Path $env:TEMP ('optimiseur-test-' + [guid]::NewGuid().ToString('N'))
. $Script -TestMode -DataPath $TestData
Write-Host "Windows build $Build - $(@($Tweaks).Count) réglages au catalogue"

Check 'Catalogue chargé' { @($Tweaks).Count -ge 20 }
Check 'Identifiants uniques' { @($Tweaks | Select-Object -ExpandProperty Id -Unique).Count -eq @($Tweaks).Count }
Check 'Catégories et profils valides' {
    foreach ($t in $Tweaks) {
        if (@($Categories.Id) -notcontains $t.Cat) { throw "catégorie inconnue : $($t.Id)" }
        foreach ($p in $t.Profiles) { if (-not $ProfileLabels.ContainsKey($p)) { throw "profil inconnu : $($t.Id)/$p" } }
        if (-not $t.Name -or -not $t.Desc) { throw "texte manquant : $($t.Id)" }
        if (@($t.Reg).Count -eq 0 -and -not $t.Apply) { throw "réglage vide : $($t.Id)" }
    }
    $true
}
Check 'Set-KVString' {
    ((Set-KVString '' 'SwapEffectUpgradeEnable' '1') -eq 'SwapEffectUpgradeEnable=1;') -and
    ((Set-KVString 'VRROptimizeEnable=0;SwapEffectUpgradeEnable=0;' 'SwapEffectUpgradeEnable' '1') -eq 'VRROptimizeEnable=0;SwapEffectUpgradeEnable=1;') -and
    ((Set-KVString 'AutoHDREnable=1;' 'SwapEffectUpgradeEnable' '1') -eq 'AutoHDREnable=1;SwapEffectUpgradeEnable=1;')
}
Check 'Mode d''alimentation lisible' { [bool](Get-ActiveScheme) }
Check 'Réglage processeur lisible' { $null -ne (Get-PowerSetting (Get-ActiveScheme) 'SUB_PROCESSOR' 'PROCTHROTTLEMAX') }
Check 'Reconnaissance des applications' {
    $cases = @{
        'Facebook.InstagramBeta' = 'Instagram - sponsorisé'; 'Facebook.Facebook' = 'Facebook - sponsorisé'
        'Microsoft.WindowsFeedbackHub' = 'Hub de commentaires'; 'king.com.CandyCrushSaga' = 'Jeux King (Candy Crush...) - sponsorisé'
        'Microsoft.WindowsCalculator' = $null; 'Microsoft.GamingApp' = $null; 'Microsoft.XboxGamingOverlay' = $null
        'Microsoft.WindowsStore' = $null; 'Microsoft.Paint' = $null; 'MSTeams' = $null
    }
    foreach ($k in $cases.Keys) {
        $e = Get-CatalogEntry $k
        $got = if ($e) { $e.N } else { $null }
        if ($got -ne $cases[$k]) { throw "$k -> « $got » au lieu de « $($cases[$k]) »" }
    }
    $true
}
Check 'Détection Intel Core 13e/14e génération (bureau)' {
    $yes = 'Intel(R) Core(TM) i5-14600K', 'Intel(R) Core(TM) i9-13900KS', 'Intel(R) Core(TM) i7-13700', 'Intel(R) Core(TM) i7-14700KF', 'Intel(R) Core(TM) i5-13600KF'
    $no  = 'Intel(R) Core(TM) i7-13700H', 'Intel(R) Core(TM) i9-14900HX', 'Intel(R) Core(TM) i5-12600K', 'Intel(R) Core(TM) i7-1355U', 'Intel(R) Core(TM) Ultra 7 265K', 'AMD Ryzen 7 7800X3D 8-Core Processor', 'Intel(R) Core(TM) i5-13400T'
    foreach ($n in $yes) { if (-not (Test-IntelRaptorDesktop $n)) { throw "non détecté : $n" } }
    foreach ($n in $no)  { if (Test-IntelRaptorDesktop $n) { throw "détecté à tort : $n" } }
    $true
}
Check 'Liste des applications' { $a = @(Get-BloatApps); Write-Host "         $($a.Count) application(s) trouvée(s)"; $true }

# 3. Interface ---------------------------------------------------------------------------------
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Check 'Interface XAML' {
    $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$XamlText)))
    $null -ne $w.FindName('BtnApply') -and $null -ne $w.FindName('PanelTweaks')
}

# 4. Langues -----------------------------------------------------------------------------------
$Texts = New-Object 'System.Collections.Generic.HashSet[string]'
function Add-Text([string]$t) { if ($t -and $t -match '\p{L}') { [void]$Texts.Add($t.Replace('\n', "`n")) } }
$scriptAst = [System.Management.Automation.Language.Parser]::ParseFile($Script, [ref]$null, [ref]$null)
$trCalls = $scriptAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Tr' }, $true)
foreach ($c in $trCalls) {
    $a = $c.CommandElements[1]
    if ($a -is [System.Management.Automation.Language.StringConstantExpressionAst]) { Add-Text $a.Value }
}
foreach ($t in $Tweaks) { Add-Text $t.Name; Add-Text $t.Desc; Add-Text $t.Warn }
foreach ($c in $Categories) { Add-Text $c.Title; Add-Text $c.Sub }
foreach ($a in $AppCatalog) { Add-Text $a.N; Add-Text $a.Note }
foreach ($v in $ProfileLabels.Values) { Add-Text $v }
foreach ($node in ([xml]$XamlText).SelectNodes('//*')) {
    foreach ($attr in 'Text', 'Content', 'Header', 'Title') { $v = $node.GetAttribute($attr); if ($v -notmatch '^\{') { Add-Text $v } }
}
Write-Host "         $($Texts.Count) textes à traduire"
Check 'Langues anglais et allemand chargées' { $Languages.Contains('en') -and $Languages.Contains('de') }
foreach ($code in @($Languages.Keys | Where-Object { $_ -ne 'fr' })) {
    Check "Traduction complète : $code" {
        $missing = @($Texts | Where-Object { -not $Languages[$code].ContainsKey($_) })
        if ($missing.Count) { throw ('{0} texte(s) sans traduction, ex. : {1}' -f $missing.Count, (($missing | Select-Object -First 5) -join ' | ')) }
        $true
    }
    Check "Paramètres {0} conservés : $code" {
        foreach ($k in $Texts) {
            $v = $Languages[$code][$k]
            $a = @([regex]::Matches($k, '\{\d[^}]*\}') | ForEach-Object Value | Sort-Object) -join ','
            $b = @([regex]::Matches($v, '\{\d[^}]*\}') | ForEach-Object Value | Sort-Object) -join ','
            if ($a -ne $b) { throw "« $k »" }
        }
        $true
    }
    Check "Interface traduite : $code" {
        $Lang = $code; $Dict = $Languages[$code]
        $x = [xml]$XamlText
        Convert-XamlLanguage $x
        $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $x))
        $cmb = $w.FindName('CmbLang')
        $ok = $null -ne $cmb
        # Les modèles sombres (liste déroulante, barres de défilement) doivent se construire sans erreur
        $w.Measure([System.Windows.Size]::new(1200, 800)); $w.Arrange([System.Windows.Rect]::new(0, 0, 1200, 800)); $w.UpdateLayout()
        if ($cmb.ApplyTemplate() -or $cmb.Template) { $ok = $ok -and ($null -ne $cmb.Template.FindName('PART_Popup', $cmb)) }
        $Lang = 'fr'; $Dict = $Languages['fr']
        $ok
    }
}

# 5. Appliquer puis restaurer chaque réglage ---------------------------------------------------
function Get-State($t) {
    $parts = @(foreach ($r in $t.Reg) { $c = Read-Reg $r.Path $r.Name; '{0}={1}|{2}' -f $r.Name, $c.Exists, $c.Value })
    $parts += 'applied=' + (Test-TweakApplied $t)
    if ($t.Id -like 'Power*') { $parts += 'scheme=' + (Get-ActiveScheme) }
    if ($t.Id -eq 'CpuNoBoost') { $v = Get-PowerSetting (Get-ActiveScheme) 'SUB_PROCESSOR' 'PROCTHROTTLEMAX'; $parts += "max=$($v.AC)/$($v.DC)" }
    if ($t.Id -eq 'DiagTrack') { $s = Get-Service DiagTrack -ErrorAction SilentlyContinue; if ($s) { $parts += 'svc=' + $s.StartType } }
    if ($t.Id -eq 'DXWindowed') { $parts += 'dx=' + (Read-Reg 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' 'DirectXUserGlobalSettings').Value }
    return ($parts -join ';')
}

foreach ($t in @($Tweaks | Where-Object { (Test-TweakAvailable $_) -and $_.Undoable })) {
    Check "Appliquer puis restaurer : $($t.Id)" {
        $before = Get-State $t
        Invoke-Tweak $t
        if (-not (Test-TweakApplied $t)) { throw 'non détecté comme appliqué' }
        if (-not $Backup.ContainsKey($t.Id)) { throw 'aucune sauvegarde' }
        # Recharge depuis le fichier JSON, comme après un redémarrage de l'application
        Import-Data
        Undo-Tweak $Backup[$t.Id]
        $after = Get-State $t
        if ($before -ne $after) { throw "état non restauré`n   avant : $before`n   après : $after" }
        $true
    }
}

# 6. Nouveautés 1.1 ---------------------------------------------------------------------------
function Row($a, $b, $c, $d, $e) { '{0,-29}{1,-28}{2,-13}{3,-13}{4}' -f $a, $b, $c, $d, $e }
Check 'winget : lecture du tableau (anglais, avec animation)' {
    $txt = @("   - `r   \ `r", (Row 'Name' 'Id' 'Version' 'Available' 'Source'), ('-' * 92),
             (Row 'Mozilla Firefox (x64 en-US)' 'Mozilla.Firefox' '120.0' '121.0' 'winget'),
             (Row 'Steam' 'Valve.Steam' '2.10.91.91' '3.0' 'winget'),
             (Row 'Very Long Application Name…' 'Some.VeryLongIdentifierTha…' '1.0' '2.0' 'winget'),
             '3 upgrades available.')
    $r = ConvertFrom-WingetTable $txt
    if (@($r).Count -ne 3) { throw "$(@($r).Count) lignes" }
    if ($r[0].Id -ne 'Mozilla.Firefox' -or $r[0].Available -ne '121.0' -or $r[0].Name -ne 'Mozilla Firefox (x64 en-US)') { throw 'ligne 1 incorrecte' }
    if ($r[1].Version -ne '2.10.91.91' -or $r[1].Source -ne 'winget') { throw 'ligne 2 incorrecte' }
    if (-not $r[2].Truncated -or $r[0].Truncated) { throw 'identifiant tronqué mal détecté' }
    $true
}
Check 'winget : lecture du tableau (français) et absence de mises à jour' {
    $txt = @((Row 'Nom' 'ID' 'Version' 'Disponible' 'Source'), ('-' * 92), (Row 'Discord' 'Discord.Discord' '1.0.9' '1.0.10' 'winget'), '')
    $r = ConvertFrom-WingetTable $txt
    if (@($r).Count -ne 1 -or $r[0].Available -ne '1.0.10') { throw 'tableau français mal lu' }
    $none = ConvertFrom-WingetTable @('No installed package found matching input criteria.')
    $null -eq $none
}
function Facts([hashtable]$h) {
    $d = @{ Displays = @(); RamModules = 2; RamType = 34; RamMHz = 6000; RamGB = 32; IsLaptop = $false; OnBattery = $false
            SysFreePct = 60; SysFreeGB = 500; SysMedia = 'SSD'; SysHealth = 'Healthy'; Gpus = @(); UptimeDays = 1; RebootPending = $false }
    foreach ($k in $h.Keys) { $d[$k] = $h[$k] }
    [pscustomobject]$d
}
Check 'Astuces : PC en bon état = aucun conseil' {
    $t = @(Get-SmartTips (Facts @{ Displays = @([pscustomobject]@{ Index = 1; Width = 2560; Height = 1440; Current = 144; Max = 144 })
                                   Gpus = @([pscustomobject]@{ Name = 'GPU'; DriverDate = (Get-Date).AddDays(-20) }) }))
    if ($t.Count) { throw ($t.Text -join ' | ') }
    $true
}
Check 'Astuces : écran 60 Hz, disque plein, HDD, mémoire, pilote ancien, redémarrage' {
    $t = @(Get-SmartTips (Facts @{ Displays = @([pscustomobject]@{ Index = 1; Width = 1920; Height = 1080; Current = 60; Max = 144 })
                                   RamModules = 1; RamType = 26; RamMHz = 2133; RamGB = 8; SysFreePct = 9; SysFreeGB = 20; SysMedia = 'HDD'
                                   Gpus = @([pscustomobject]@{ Name = 'GPU'; DriverDate = (Get-Date).AddDays(-400) }); UptimeDays = 12; RebootPending = $true }))
    if ($t.Count -ne 9) { throw "$($t.Count) conseils : " + ($t.Text -join ' | ') }
    if (@($t | Where-Object { $_.Level -eq 'warn' }).Count -ne 3) { throw 'niveaux incorrects' }
    if (-not ($t[0].Text -match '144') -or $t[0].Action -ne 'ms-settings:display') { throw 'conseil écran incorrect' }
    $true
}
Check 'Astuces : portable sur batterie (pas de conseil mémoire)' {
    $t = @(Get-SmartTips (Facts @{ IsLaptop = $true; OnBattery = $true; RamModules = 1; RamType = 26; RamMHz = 2133 }))
    ($t.Count -eq 1) -and ($t[0].Level -eq 'info')
}
Check 'Analyse du PC (lecture seule)' {
    $f = Get-SystemFacts
    Write-Host ("         écrans : {0} · mémoire : {1} Go, {2} MT/s · disque : {3} {4} % libres · allumé depuis {5} j" -f `
        (@($f.Displays | ForEach-Object { "$($_.Current)/$($_.Max) Hz" }) -join ', '), $f.RamGB, $f.RamMHz, $f.SysMedia, $f.SysFreePct, $f.UptimeDays)
    $null -ne $f
}
Check 'Démarrage : état des octets StartupApproved' {
    (Test-StartupEnabled $null) -and (Test-StartupEnabled ([byte[]](2, 0, 0))) -and (Test-StartupEnabled ([byte[]](6, 0))) -and
    -not (Test-StartupEnabled ([byte[]](3, 0, 0))) -and -not (Test-StartupEnabled ([byte[]](7)))
}
$RunKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; $TestName = 'OptimiseurPC-Test'
function Get-TestEntry { @(Get-StartupEntries | Where-Object { $_.ValueName -eq $TestName })[0] }
Check 'Démarrage : désactiver puis restaurer depuis l''onglet Restaurer' {
    Write-Reg $RunKey $TestName 'C:\Windows\System32\notepad.exe' 'String'
    $e = Get-TestEntry
    try {
        if (-not $e -or -not $e.Enabled) { throw 'entrée de test introuvable ou désactivée' }
        Set-StartupEnabled $e $false
        if ((Get-TestEntry).Enabled) { throw 'toujours activé' }
        if (([byte[]](Read-Reg $e.Approved $TestName).Value)[0] -ne 3) { throw 'octet StartupApproved incorrect' }
        Import-Data
        Undo-Tweak $Backup[$e.Id]
        if (-not (Get-TestEntry).Enabled) { throw 'non réactivé' }
        if ((Read-Reg $e.Approved $TestName).Exists) { throw 'valeur StartupApproved non supprimée' }
        $true
    } finally {
        Remove-ItemProperty -LiteralPath $RunKey -Name $TestName -ErrorAction SilentlyContinue
        if ($e) { Remove-ItemProperty -LiteralPath $e.Approved -Name $TestName -ErrorAction SilentlyContinue }
    }
}
Check 'Démarrage : désactiver puis réactiver depuis l''onglet Démarrage' {
    Write-Reg $RunKey $TestName 'C:\Windows\System32\notepad.exe' 'String'
    $e = Get-TestEntry
    try {
        Set-StartupEnabled $e $false
        Set-StartupEnabled (Get-TestEntry) $true
        if (-not (Get-TestEntry).Enabled) { throw 'non réactivé' }
        if ($Backup.ContainsKey($e.Id)) { throw 'sauvegarde restante' }
        -not (Read-Reg $e.Approved $TestName).Exists
    } finally {
        Remove-ItemProperty -LiteralPath $RunKey -Name $TestName -ErrorAction SilentlyContinue
        if ($e) { Remove-ItemProperty -LiteralPath $e.Approved -Name $TestName -ErrorAction SilentlyContinue }
    }
}
Check 'Liste des programmes au démarrage (lecture)' { $l = @(Get-StartupEntries); Write-Host "         $($l.Count) programme(s) au démarrage"; $true }
Check 'winget (information)' {
    $wg = Get-WingetPath
    if ($wg) { Write-Host "         winget : $wg" } else { Write-Host '         winget absent sur cette machine' }
    $true
}

Check 'Nettoyage des fichiers temporaires' { Invoke-Tweak ($Tweaks | Where-Object Id -eq 'TempClean'); $true }
Check 'Aucune sauvegarde restante' { $Backup.Count -eq 0 }

Remove-Item -LiteralPath $TestData -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
if ($script:Fail) { Write-Host "$($script:Fail) test(s) en échec" -ForegroundColor Red; exit 1 }
Write-Host 'Tous les tests sont passés.' -ForegroundColor Green
exit 0
