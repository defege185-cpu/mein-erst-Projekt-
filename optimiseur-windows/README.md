# Optimiseur PC — Windows 10 et 11

Application gratuite, simple et sans installation pour rendre Windows plus fluide **en jeu** et en
**télétravail**, **sans surchauffe**. Fonctionne avec toutes les cartes graphiques (NVIDIA GeForce RTX/GTX,
AMD Radeon, Intel Arc/Iris) et tous les processeurs Intel et AMD, car elle ne touche à aucun pilote ni
au matériel.

## Démarrer
1. Télécharger **`OptimiseurPC-<version>.zip`** sur la page des publications :
   https://github.com/defege185-cpu/mein-erst-Projekt-/releases/latest
   puis clic droit → **Extraire tout**.
2. Double-cliquer sur **`Lancer-Optimiseur.bat`**.
3. Répondre **Oui** quand Windows demande l'autorisation administrateur.

> Si Windows affiche « Windows a protégé votre ordinateur », cliquer sur **Informations complémentaires → Exécuter quand même**
> (c'est normal pour un programme téléchargé qui n'est pas signé).

Rien d'autre à installer : l'application utilise Windows PowerShell 5.1, déjà présent dans Windows 10 et 11.

## Langues
Français, English, Deutsch. L'application s'ouvre dans la langue de Windows (anglais si elle n'est pas disponible).
Pour changer : menu **Langue** en haut à droite de la fenêtre ; l'application redémarre aussitôt dans la langue choisie
et s'en souvient. Gardez le dossier `langues` à côté de `OptimiseurPC.ps1`.

Ajouter une langue : copier `langues/en.json` sous le nom du code de la langue (par ex. `es.json`), changer `@langue`
(nom affiché dans le menu), puis traduire chaque valeur (à droite) sans toucher aux textes français (à gauche) ni aux `{0}`, `{1}`.
Le test automatique signale tout texte oublié.

## Les onglets
| Onglet | Rôle |
|---|---|
| **Tableau de bord** | Matériel détecté, utilisation processeur / carte graphique / mémoire en direct, températures (carte NVIDIA via le pilote officiel, capteur ACPI si disponible), conseils et liens vers les pilotes **officiels** du fabricant. |
| **Optimisations** | ~28 réglages expliqués, rangés par thème. Boutons « Suggestion Jeux / Bureau / Anti-surchauffe » qui **cochent seulement** des cases. |
| **Applications inutiles** | Applications préinstallées détectées (Actualités, Solitaire avec pubs, Candy Crush, Cortana…). Désinstallation pour votre compte, réinstallables depuis le Microsoft Store. |
| **Restaurer** | Remet chaque réglage comme avant, lien vers le Store pour les applications, accès à la Restauration du système. |
| **À propos** | Ce que fait et ne fait pas l'application, mentions légales. |

## Sécurité : rien sans votre accord
- **Aucune case n'est cochée au démarrage.** Rien ne change tant que vous n'avez pas coché une case **et** confirmé.
- Avant chaque modification, une fenêtre récapitule **la liste exacte** des changements et demande **Oui / Non** (Non par défaut).
- Un **point de restauration Windows** est proposé avant chaque série de modifications.
- Les valeurs d'origine sont sauvegardées dans `%LOCALAPPDATA%\OptimiseurPC\sauvegarde.json` ; un journal est tenu dans `journal.log`.
- Les réglages déjà actifs sont signalés « Déjà actif » et ne peuvent pas être recochés.

## Les réglages proposés
**Jeux et carte graphique** : Mode Jeu, planification GPU à accélération matérielle (nécessaire au DLSS Frame Generation),
arrêt de l'enregistrement vidéo permanent de la Game Bar, optimisations des jeux en fenêtré (Windows 11),
désactivation de l'accélération de la souris, raccourci des touches rémanentes.

**Température et énergie** : mode d'alimentation Équilibré (« Utilisation normale »), limite du processeur à 99 %
qui désactive le Turbo (portables qui chauffent), applications du Store en arrière-plan.

**Fluidité** : transparence, animations des fenêtres.

**Publicités et suggestions** : suggestions du menu Démarrer et de l'écran de verrouillage, installation automatique
d'applications sponsorisées, écran « Tirons encore plus parti de Windows », Widgets / Actualités, recherche Bing.

**Confidentialité** : identifiant de publicité, données de diagnostic au minimum prévu par Microsoft, service de télémétrie,
historique des activités, Recall (PC Copilot+), partage des mises à jour avec d'autres PC sur Internet.

**Bureau et télétravail** : extensions de fichiers visibles, Explorateur ouvert sur « Ce PC », historique du
presse-papiers (Windows + V), Assistant Stockage.

**Entretien** : nettoyage des fichiers temporaires de plus de 2 jours (seule action non annulable, signalée comme telle).

### Ce qui est volontairement absent
Les « astuces » sans effet prouvé ou risquées ne sont pas proposées : désactivation de Windows Update, de Defender,
du pare-feu ou de services système, modifications réseau « magiques », mode « Performances ultimes », suppression des
applications Xbox (utiles pour Game Pass, la Game Bar et les manettes) ou du Microsoft Store.

## Légalité
- Uniquement des **réglages officiels et documentés** de Windows : options des Paramètres, stratégies de groupe publiées par
  Microsoft, `powercfg`, services Windows, désinstallation d'applications du Store par la commande officielle `Remove-AppxPackage`.
- **Aucun** overclocking, undervolting, réglage de ventilateur, de BIOS ou de firmware : pas de risque pour la garantie.
- **Aucun** pilote NVIDIA, AMD ou Intel n'est modifié ni redistribué : l'application ouvre seulement leurs sites officiels.
- **Aucun** contournement d'activation ou de licence. Aucune donnée envoyée sur Internet, aucune publicité.
- Application indépendante, non affiliée à Microsoft, NVIDIA, Intel ou AMD. Les marques citées appartiennent à leurs
  propriétaires et ne servent qu'à indiquer la compatibilité.
- Licence MIT, fournie sans garantie.

## Limites
- Les réglages « par utilisateur » s'appliquent au compte qui accepte la demande administrateur. Si un autre compte
  (administrateur) donne son autorisation, ils s'appliquent à ce compte-là.
- La température processeur n'est lisible que si le PC fournit un capteur ACPI à Windows ; sinon utilisez le logiciel du fabricant.
  La température carte graphique est lue pour les cartes NVIDIA (outil `nvidia-smi` installé avec le pilote officiel).

## Tests
`tests/Test-Optimiseur.ps1` vérifie la syntaxe, l'interface, que chaque texte est traduit dans toutes les langues, et **applique puis restaure chaque réglage** pour contrôler
que l'état d'origine revient exactement. À lancer uniquement sur une machine de test. Ces tests tournent automatiquement
sur Windows Server 2022 et 2025 (GitHub Actions) à chaque modification du dossier.
