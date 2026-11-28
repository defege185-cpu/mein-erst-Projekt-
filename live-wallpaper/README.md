# Live Wallpaper für Windows

Ein Video als bewegter Desktop-Hintergrund, hinter den Desktop-Symbolen, und so sparsam wie möglich.

## Warum es so wenig Leistung braucht
- **Grafikkarte statt Prozessor:** Das Video wird vom Video-Decoder der Grafikkarte entpackt und
  angezeigt (Windows Media Foundation). Der Prozessor hat dabei fast nichts zu tun.
- **Winzig:** Eine einzige Datei mit 250 KB. Kein Installer, kein Browser, kein .NET.
  Es gibt kein Fenster, nur ein Symbol im Infobereich der Taskleiste.
- **Automatische Pause**, wenn niemand den Desktop sieht. Dann braucht die App praktisch null Leistung
  und gibt ihren Arbeitsspeicher wieder frei. Das passiert,
  - wenn ein Spiel oder ein Video im Vollbild läuft,
  - wenn ein Fenster maximiert ist (abschaltbar),
  - wenn der PC gesperrt ist oder der Bildschirm aus ist,
  - wenn der Laptop im Akkubetrieb läuft (abschaltbar).
- **Kein Ton:** Das Video läuft immer stumm.

## Installation
1. Lade den Ordner herunter und entpacke ihn, z. B. nach `C:\LiveWallpaper`.
2. Starte `LiveWallpaper.exe`. Beim ersten Start nimmt die App das erste Video aus dem Ordner
   `videos`. Ein anderes wählst du mit Rechtsklick auf das Symbol und „Video wählen…“.
3. Windows zeigt eventuell „Der Computer wurde durch Windows geschützt“, weil die App nicht signiert ist.
   Klicke dann auf **Weitere Informationen** und anschließend auf **Trotzdem ausführen**.

## Menü (Rechtsklick auf das Symbol in der Taskleiste)
| Eintrag | Funktion |
|---|---|
| Video wählen… | MP4, MKV, MOV, M4V, WMV oder AVI auswählen |
| Pause / Fortsetzen | Hält das Video an. Doppelklick auf das Symbol bewirkt dasselbe. |
| Bildschirm ausfüllen | Füllt den ganzen Bildschirm und schneidet dafür die Ränder ab. Ausgeschaltet bleibt das ganze Video sichtbar, mit schwarzen Balken. |
| Pausieren, wenn ein Fenster maximiert ist | Spart am meisten Leistung |
| Im Akkubetrieb pausieren | Für Laptops |
| Mit Windows starten | Startet die App automatisch nach der Anmeldung |
| Beenden | Stellt den normalen Hintergrund wieder her |

## Tipps für minimalen Verbrauch
- Nimm ein Video in der **Auflösung deines Bildschirms**. Für einen Full-HD-Bildschirm reichen die
  `*-1080p.mp4`-Videos. Ein 4K-Video auf einem 1080p-Bildschirm kostet nur unnötig Leistung.
- Das Format **MP4 (H.264)** wird von jeder Grafikkarte direkt entschlüsselt.
- Das Video wird nur auf dem Hauptbildschirm abgespielt. Weitere Bildschirme behalten ihren normalen Hintergrund.

## Einstellungen und Protokoll
`%APPDATA%\LiveWallpaper\settings.ini` und `%APPDATA%\LiveWallpaper\log.txt`.
Im Protokoll steht unter anderem, ob die Grafikkarte das Video entschlüsselt („GPU decoding on: …“).

## Selbst bauen
- Visual Studio: siehe `.github/workflows/live-wallpaper.yml` (Build mit `cl` + `rc`).
- MinGW unter Linux: `./build-mingw.sh`

---

### En bref (français)
Fond d'écran vidéo léger : la vidéo est décodée par la carte graphique, l'application fait 250 Ko et se met
en pause toute seule pendant un jeu en plein écran, si une fenêtre est agrandie, si le PC est verrouillé
ou si le portable est sur batterie. Lancer `LiveWallpaper.exe`, puis clic droit sur l'icône pour choisir
une vidéo. Le menu est en français si Windows est en français.
