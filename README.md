# ox_inventory - Version AscensionRP by CedricPoint

J'ai prepare cette version de `ox_inventory` (base `2.44.1`) pour AscensionRP, avec une UI Ascension, la gestion vetements integree et un systeme de clone ped pour l'apercu inventaire.

## Auteur

- Developpement et integration: `CedricPoint`

## Sommaire

- Apercu du projet
- Prerequis
- Installation
- Build de la NUI
- Modifications integrees
- Integrations externes
- Convars utiles
- Structure utile pour une release GitHub
- Credits et liens officiels
- Licence

## Apercu du projet

Cette version conserve le coeur de `ox_inventory` et ajoute mes adaptations orientees RP:

- UI inventory style Ascension
- panneau personnage dans l'inventaire
- slots vetements avec actions equipe/retire
- cooldown anti spam sur interactions vetements
- gestion clone ped pour l'apercu inventaire
- notifications fallback (`esx_notify` puis `ox_lib`)
- hooks pour shops/crafting dynamiques Ascension

## Prerequis

Dependances runtime utilisees:

- `FXServer` build `6116+` avec OneSync
- `oxmysql`
- `ox_lib`

Compatibilite framework:

- utilisation principale en `esx`
- adaptation automatique vers `qbx` cote client si detecte

## Installation

1. Place le dossier dans `resources/[ox]/ox_inventory`
2. Verifie l'ordre de demarrage dans `server.cfg`:
   - `ensure oxmysql`
   - `ensure ox_lib`
   - `ensure ox_inventory`
3. Verifie que `web/build/index.html` existe (obligatoire)
4. Configure ton framework via convar (`inventory:framework`) selon ta stack

## Build de la NUI

La ressource charge la NUI compilee via:

- `ui_page 'web/build/index.html'`

Pour rebuild en local:

```bash
cd web
npm install
npm run build
```

Important:

- pour un serveur en production, seul `web/build` est indispensable en runtime
- `web/src` et `web/node_modules` servent uniquement au developpement

## Modifications integrees

### 1) UI et experience joueur

- theme Ascension applique dans l'interface inventory
- panneau personnage avec interaction visuelle
- rotation ped via callback NUI `ascensionRotatePed`
- synchronisation viewport clone via `ascensionCloneViewport`

### 2) Slots vetements

- callback NUI `ascensionEquipClothing`
- logique equipe/retire avec memoire de slot
- gestion props/composants selon le type de slot
- cooldown anti spam par slot

### 3) Clone ped en inventaire

- module dedie: `modules/ascension_clone/client.lua`
- activation/desactivation via convar
- options distance, z-bias, sync interval, freeze joueur

### 4) Notifications

- priorite `esx_notify` si la ressource est demarree
- fallback automatique sur `ox_lib` si indisponible

### 5) Shops/Crafting dynamiques

Exports serveurs disponibles:

- `ClearAscensionDynamicShops`
- `ClearAscensionDynamicCrafting`
- + fonctions de sync/refresh builtin apres blacklist

## Integrations externes

### illenium-appearance

La ressource detecte `illenium-appearance` s'il est `started` et utilise ses exports pour fiabiliser la synchro tenue:

- `setPedComponent`
- `setPedProp`
- `getPedAppearance`
- `setPedAppearance`

Sans cette ressource, le systeme continue avec les natives GTA, mais l'integration appearance est recommandee pour limiter les desync.

### Item tenue personnalise

Dans `data/items.lua`, l'item `asc_outfit_item` est defini pour un usage via logique serveur/framework (ex: `RegisterUsableItem` cote ESX).

## Convars utiles

Convars Ascension exposes par cette version:

- `inventory:screenblur` (0 recommande pour vue perso nette)
- `inventory:ascension_clone`
- `inventory:ascension_clone_dist`
- `inventory:ascension_clone_zbias`
- `inventory:ascension_clone_ground`
- `inventory:ascension_clone_sync_ms`
- `inventory:ascension_freeze_player`

Exemple:

```cfg
setr inventory:framework "esx"
setr inventory:screenblur 0
setr inventory:ascension_clone 1
```

## Credits et liens officiels

- Projet original `ox_inventory`:
  - [https://github.com/overextended/ox_inventory](https://github.com/overextended/ox_inventory)
- Integration appearance `illenium-appearance`:
  - [https://github.com/iLLeniumStudios/illenium-appearance](https://github.com/iLLeniumStudios/illenium-appearance)
- Adaptation AscensionRP et maintenance de cette version: `CedricPoint`

## Licence

Cette version inclut du code provenant de projets open source tiers.

- Respecter la licence de `ox_inventory` et des dependances associees avant redistribution.
- Conserver les credits d'origine et les notices de licence.
