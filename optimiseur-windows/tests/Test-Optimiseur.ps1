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
Check 'Liste des applications' { $a = @(Get-BloatApps); Write-Host "         $($a.Count) application(s) trouvée(s)"; $true }

# 3. Interface ---------------------------------------------------------------------------------
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Check 'Interface XAML' {
    $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$XamlText)))
    $null -ne $w.FindName('BtnApply') -and $null -ne $w.FindName('PanelTweaks')
}

# 4. Appliquer puis restaurer chaque réglage ---------------------------------------------------
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

Check 'Nettoyage des fichiers temporaires' { Invoke-Tweak ($Tweaks | Where-Object Id -eq 'TempClean'); $true }
Check 'Aucune sauvegarde restante' { $Backup.Count -eq 0 }

Remove-Item -LiteralPath $TestData -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
if ($script:Fail) { Write-Host "$($script:Fail) test(s) en échec" -ForegroundColor Red; exit 1 }
Write-Host 'Tous les tests sont passés.' -ForegroundColor Green
exit 0
