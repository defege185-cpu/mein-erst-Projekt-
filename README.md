# Détecteur Caméra & Micro

Application web (fonctionne dans le navigateur du téléphone, sans rien installer) pour aider à repérer
les caméras cachées (mini caméras, micro-caméras, caméras infrarouges) et les micros.

**100 % gratuit, aucune bibliothèque externe, aucune donnée envoyée sur Internet.**
Les photos restent stockées sur le téléphone.

## Fonctions
- Ouvre la caméra arrière du téléphone et analyse l'image en direct (~15 fois/seconde).
- **Mode « Reflet d'objectif »** : avec la lampe allumée, repère les petits points brillants et ronds
  que renvoient les lentilles de caméra (murs, plafond, étagères, jouets, miroirs, objets…).
- **Mode « Infrarouge »** : dans le noir, repère les LED infrarouges des caméras de vision nocturne.
- **Photo automatique** dès qu'un point suspect reste visible plusieurs images de suite (cercle rouge + date).
- Bip + vibration à chaque alerte.
- **Détecteur magnétique** (si le téléphone le permet) pour les micros et circuits électroniques.
- Galerie des photos avec enregistrement et suppression.

## Utilisation
La caméra ne fonctionne qu'en **HTTPS**. Le plus simple (gratuit) : activer **GitHub Pages**
(Settings → Pages → Branch → dossier `/`), puis ouvrir sur le téléphone :
`https://<votre-nom>.github.io/<dépôt>/app/`
Ensuite « Ajouter à l'écran d'accueil » pour l'utiliser comme une vraie application.

## Limites
Aucune application ne détecte 100 % des caméras ou micros. Des fausses alertes sont possibles
(vis brillantes, bijoux, gouttes d'eau). Vérifiez toujours chaque alerte à l'œil.
