# Mise à jour automatique de SimsCraft, lancée par Modrinth App avant chaque démarrage du jeu (Hooks > Pre-launch).
# Version 2 (11/11) : demande au PC du serveur (port 8765, dossier telechargements/mise_a_jour) :
#  1. ce script lui-même (script.txt : son empreinte) : s'il a changé, la nouvelle version servira au prochain lancement ;
#  2. le jar SimsCraft en service (version.txt : nom, empreinte) : téléchargé, vérifié, il remplace l'ancien ;
#  3. les autres mods publiés (mods.txt : une ligne « nom.jar|empreinte » par mod, fichiers dans mods/) : les manquants sont
#     téléchargés et vérifiés ; un mod que CE script avait installé et qui n'est plus publié est retiré. Les mods installés par
#     Modrinth App ou à la main (absents de mods_geres.txt) ne sont JAMAIS touchés.
# Si le PC du serveur ne répond pas (joueurs à distance), le jar SimsCraft vient de GitHub (dépôt public Hadriel33/simscraft-maj,
# 25/11) ; si rien ne répond, ne fait rien : le jeu démarre quand même. Journal : maj_simscraft.log.
$mods = Join-Path $PSScriptRoot 'mods'
$journal = Join-Path $PSScriptRoot 'maj_simscraft.log'
$geres = Join-Path $PSScriptRoot 'mods_geres.txt'
function Note($t) { Add-Content $journal ((Get-Date -Format 'dd/MM HH:mm:ss ') + $t) }
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12   # GitHub : TLS 1.2
function Lire($u, $t = 5) { (Invoke-WebRequest $u -UseBasicParsing -TimeoutSec $t).Content }
function Prendre($u, $dest, $sha) {
    $tmp = "$dest.part"
    Invoke-WebRequest $u -OutFile $tmp -UseBasicParsing -TimeoutSec 300
    if ((Get-FileHash $tmp -Algorithm SHA256).Hash.ToLower() -ne $sha) { Remove-Item $tmp -ErrorAction SilentlyContinue; throw "empreinte différente ($u)" }
    if (Test-Path $dest) { Remove-Item $dest -Force }
    Rename-Item $tmp (Split-Path $dest -Leaf)
}
$hote = $null; $infos = $null
$hotes = if ($env:MAJ_HOTE) { @($env:MAJ_HOTE) } else { @('DESKTOP-CKB7P86', '192.168.1.99') }   # MAJ_HOTE : tests seulement
foreach ($h in $hotes) {
    try { $infos = (Lire "http://${h}:8765/version.txt" 3) -split "`n"; $hote = $h; break } catch {}
}
if ($hote) { $base = "http://${hote}:8765" }
else {
    # 25/11 : pas sur le réseau de la maison (joueurs à distance) : GitHub
    $base = if ($env:MAJ_GITHUB) { $env:MAJ_GITHUB } else { 'https://raw.githubusercontent.com/Hadriel33/simscraft-maj/main' }   # MAJ_GITHUB : tests seulement
    try { $infos = (Lire "$base/version.txt" 15) -split "`n"; $hote = 'github' } catch { Note "serveur et GitHub injoignables, rien à faire ($_)"; exit 0 }
}

# 1. Le script lui-même (pour le prochain lancement)
try {
    $shaScript = (Lire "$base/script.txt").Trim().ToLower()
    $moi = $MyInvocation.MyCommand.Path
    if ($shaScript -and $moi -and (Get-FileHash $moi -Algorithm SHA256).Hash.ToLower() -ne $shaScript) {
        Prendre "$base/maj_simscraft.ps1" $moi $shaScript
        Note 'script de mise à jour remplacé (servira au prochain lancement)'
    }
} catch { if ("$_" -notmatch '404') { Note "script : $_" } }

# 2. Le jar SimsCraft
$nom, $sha = $infos[0].Trim(), $infos[1].Trim().ToLower()
if (Test-Path (Join-Path $mods $nom)) { Note "à jour ($nom)" }
else {
    try {
        $tmp = Join-Path $mods "$nom.part"
        $url = if ($infos.Count -ge 3 -and $infos[2].Trim() -like 'https://*') { $infos[2].Trim() } else { "$base/$nom" }   # GitHub : l'adresse du jar (Releases)
        Invoke-WebRequest $url -OutFile $tmp -UseBasicParsing -TimeoutSec 300
        if ((Get-FileHash $tmp -Algorithm SHA256).Hash.ToLower() -ne $sha) { throw 'empreinte différente' }
        Get-ChildItem $mods -Filter 'villagevivant-*.jar' | Remove-Item -Force
        Rename-Item $tmp $nom
        Note "mis à jour : $nom"
    } catch { Remove-Item (Join-Path $mods "$nom.part") -ErrorAction SilentlyContinue; Note "échec : $_" }
}

# 3. Les autres mods publiés
try { $liste = Lire "$base/mods.txt" } catch { exit 0 }   # pas de liste publiée : rien à faire
$voulus = @{}
foreach ($l in ($liste -split "`n")) {
    $p = $l.Trim() -split '\|'
    if ($p.Count -eq 2 -and $p[0] -like '*.jar' -and $p[0] -notmatch '[\\/]') { $voulus[$p[0]] = $p[1].ToLower() }
}
$avant = if (Test-Path $geres) { @(Get-Content $geres | Where-Object { $_ -like '*.jar' }) } else { @() }
$ok = @()
foreach ($m in $voulus.Keys) {
    $dest = Join-Path $mods $m
    if (Test-Path $dest) { if ($avant -contains $m) { $ok += $m }; continue }   # déjà là : à nous seulement si NOUS l'avions mis
    try { Prendre "$base/mods/$m" $dest $voulus[$m]; $ok += $m; Note "mod ajouté : $m" } catch { Note "mod $m : $_" }
}
foreach ($m in $avant) {
    if (-not $voulus.ContainsKey($m) -and (Test-Path (Join-Path $mods $m))) { Remove-Item (Join-Path $mods $m) -Force; Note "mod retiré : $m" }
}
Set-Content $geres $ok

# 4. Les packs de ressources publiés (packs.txt : « nom.zip|empreinte », fichiers dans packs/) : même règle que les mods ; ils
#    arrivent dans resourcepacks/ et s'activent dans le jeu (Options > Packs de ressources). Ceux mis à la main ne sont jamais touchés.
try { $listeP = Lire "$base/packs.txt" } catch { exit 0 }
$packs = Join-Path $PSScriptRoot 'resourcepacks'
if (-not (Test-Path $packs)) { New-Item -ItemType Directory $packs | Out-Null }
$geresP = Join-Path $PSScriptRoot 'packs_geres.txt'
$voulusP = @{}
foreach ($l in ($listeP -split "`n")) {
    $p = $l.Trim() -split '\|'
    if ($p.Count -eq 2 -and $p[0] -like '*.zip' -and $p[0] -notmatch '[\\/]') { $voulusP[$p[0]] = $p[1].ToLower() }
}
$avantP = if (Test-Path $geresP) { @(Get-Content $geresP | Where-Object { $_ -like '*.zip' }) } else { @() }
$okP = @()
foreach ($m in $voulusP.Keys) {
    $dest = Join-Path $packs $m
    if (Test-Path $dest) { if ($avantP -contains $m) { $okP += $m }; continue }
    try { Prendre "$base/packs/$m" $dest $voulusP[$m]; $okP += $m; Note "pack ajouté : $m" } catch { Note "pack $m : $_" }
}
foreach ($m in $avantP) {
    if (-not $voulusP.ContainsKey($m) -and (Test-Path (Join-Path $packs $m))) { Remove-Item (Join-Path $packs $m) -Force; Note "pack retiré : $m" }
}
Set-Content $geresP $okP
exit 0
