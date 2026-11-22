# Handoff : Herbier — herbier de terrain personnel (Android)

## Vue d'ensemble

Herbier est une application Android mono-utilisateur pour tenir un herbier de terrain : les plantes rencontrées, où, quand, avec ses propres photos, notes et tags. Ce n'est pas une app sociale. Ce n'était pas non plus un outil d'identification : depuis le **tour 6** (2026-11-16), Herbier peut demander à **Pl@ntNet** d'identifier une plante d'après ses photos (6a–6k, plus bas), comme une autre façon de la nommer. Le cœur est la **fiche espèce**, qui fusionne *mes données* et des *données de référence* récupérées de sources externes (GBIF, Pl@ntNet, Wikipédia, POWO, INPN, Tela Botanica). Les plantes entrent dans la collection surtout par **interception de liens** partagés depuis Pl@ntNet (vers GBIF, etc.), par la **prise de note rapide sur le terrain** et, depuis le tour 6, par l'**identification Pl@ntNet** depuis Noter.

## À propos des fichiers de design

`Herbier v2.dc.html` est une **référence de design en HTML** : des maquettes statiques montrant l'aspect et le comportement voulus. Ce n'est pas du code à réutiliser. La tâche est de **recréer ces écrans dans l'environnement Android cible** (Jetpack Compose recommandé, Material 3 comme base, thématisé avec les jetons ci-dessous). `Herbier.dc.html` contient l'historique des explorations (tours 1–3) ; seul **v2** fait foi, et à l'intérieur de v2, le **tour 5** (5a–5f) et le jeu consolidé (4a–4n) — les tours antérieurs sont conservés pour contexte. Le **tour 6** (identification Pl@ntNet, 6a–6k et le glyphe Identifier) est un canevas à part, dans `identification/` ; il fait foi pour ces écrans et pour ce qu'il change de 4d, 4g, 4k et 4m.

Les lieux et espèces des maquettes (Arnica, Col de la Schlucht, la flore « Europe de l'Ouest »…) sont des exemples, pas des exigences.

Les photos des maquettes sont chargées à la volée depuis Wikimedia pour illustrer ; dans l'app, elles viennent de l'appareil, de Google Photos/Drive, ou des sources de référence.

## Fidélité

**Haute fidélité** pour la mise en page, la hiérarchie, les couleurs, la typographie, les espacements et les états. Les icônes des maquettes sont des glyphes Unicode de substitution (▦ ◎ ≡ ⚙ ⌕ ✎) — remplacer par Material Symbols (outlined) : `grid_view`, `map`, `list`, `settings`, `search`, `edit`, `close`, `arrow_back`, `more_horiz`, `my_location`, `add`, `check`, `refresh`.

---

## Architecture de l'information

```
Entrées                          Cœur                         Lentilles
─────────                        ────                         ─────────
+ Noter (terrain)      ──►   Fiche espèce (Plante)   ◄──   Collection (par nom, filtres tags)
Lien intercepté        ──►     ├─ Mes photos                Carte (par lieu)
Recherche / coller     ──►     ├─ Mes observations          Journal (par date)
Identifier (Pl@ntNet)  ──►     ├─ Mes notes, tags
                               └─ Référence (externe)
```

**Navigation** : barre inférieure à 5 emplacements — `Collection · Carte · [+ Noter] · Journal · Réglages`. Le bouton central Noter (60 px, vert mousse, débordant de 28 px vers le haut) ouvre l'appareil photo en modal plein écran. Les tags **ne sont pas** une destination : ce sont des filtres persistants partagés par Collection, Carte et Journal. « À identifier » est aussi un filtre (ocre) qui fait office de file.

**Écrans modaux** (sans barre) : Chercher, Lien intercepté, À identifier → lier, Tags, Fiche espèce, Observation, Modifier la fiche, Déplacer le point, Changer d'espèce, Gérer les tags (*supprimé par M8.77*), Visionneuse photo, Noter, Enregistré (*supprimé par M8.76*). L'identification Pl@ntNet (6b–6g) s'ouvre par-dessus l'Observation (4h, *depuis M8.76* ; plus par-dessus Noter, *supprimé par M8.75/M8.76*), À identifier ou la fiche nom libre, et y revient toujours.

---

## Modèle de données

```kotlin
data class Plant(
  val id: Id,
  val displayName: String,              // nom affiché, choisi par l'utilisateur (fr)
  val aliases: List<String>,            // autres noms, pour la recherche
  val scientificName: String?,          // null si « nom libre » non lié
  val authorship: String?,              // "L."
  val refs: Map<RefSource, String>,     // GBIF taxonKey, PLANTNET slug, WIKIPEDIA fr title, POWO ipni, INPN cd_nom, TELABOTANICA num, EPPO code
  val notes: String,                    // markdown léger, éditable
  val notesUpdatedAt: Instant,
  val tagIds: Set<Id>,
  val coverPhotoId: Id?,
  val reference: ReferenceSnapshot?,    // cache des données externes
  val createdAt: Instant
)

data class Observation(
  val id: Id, val plantId: Id?,         // null ⇒ « À identifier »
  val at: Instant,
  val point: GeoPoint?,                 // lat, lon, accuracyM (jamais affichée en texte)
  val placeLabel: String?,              // nom donné par l'utilisateur au lieu/grappe
  val placeDerived: String?,            // géocodage inverse « Près de Colmar » (cache)
  val note: String?,
  val photoIds: List<Id>
)

data class Photo(
  val id: Id, val observationId: Id,
  val source: PhotoSource,              // DEVICE, GOOGLE_PHOTOS, GOOGLE_DRIVE
  val remoteId: String?,                // mediaItemId / fileId une fois envoyé
  val localPreviewPath: String,         // copie compressée ≤1600 px, toujours présente
  val uploadState: UploadState,         // PENDING, UPLOADED, FAILED, ORIGINAL_MISSING
  val takenAt: Instant
)

data class Tag(val id: Id, val name: String)

data class ReferenceSnapshot(
  val fetchedAt: Instant,
  val vernacular: Map<Lang, List<String>>,   // fr, de, en, it…
  val family: String?,
  val lifeForm: String?,                     // « Herbacée bisannuelle, 50–150 cm »
  val nativeRange: String?, val introducedRange: String?,   // POWO
  val frStatus: FrStatus?,                   // INDIGENE / INTRODUITE / INVASIVE (INPN)
  val frProtection: String?,                 // « Non protégée » / « Protégée (Alsace) »
  val redList: String?,                      // « LC · préoccupation mineure »
  val floweringMonths: Set<Int>?,            // 1..12 (Tela Botanica)
  val habitat: String?, val ecology: List<String>?,   // chips : mi-ombre, sol acide…
  val altitudeRange: String?,
  val toxicity: String?,                     // Wikipédia
  val organPhotos: List<OrganPhoto>?,        // Pl@ntNet : url, organ, localThumbPath
  val links: Map<RefSource, Url>
)
```

Règles :
- Une **Plante** peut avoir 0 observation (ajoutée par lien, position retirée).
- Une **Observation** avec `plantId == null` est « À identifier » ; elle apparaît dans Journal et Carte (point ocre), jamais dans Collection.
- Supprimer une photo dans Herbier **délie** ; l'original Google n'est jamais touché. Original supprimé côté Google ⇒ `ORIGINAL_MISSING`, l'aperçu local reste affiché avec la mention « original introuvable ».
- Les **noms libres** (`scientificName == null`) sont des fiches valides ; lier plus tard remplit `refs` et déclenche la récupération de référence ; le nom libre devient un alias.

---

## Jetons de design

### Couleurs
| Jeton | Hex | Usage |
|---|---|---|
| `paper` | `#f6f1e7` | fond des écrans, cartes « moi » |
| `sand` | `#ece5d6` | champs, cartes secondaires, **bloc Référence** |
| `sandDeep` | `#e2dbcb` | fond des vignettes en chargement (rayures 135° avec `sand`, pas 8 px) |
| `line` | `#cfc6b3` | séparateurs de listes (après passage plein soleil) |
| `lineSoft` | `#d9d1c0` | filets faibles (poignée de tiroir, bordure barre d'onglets) |
| `ink` | `#1d1a14` | texte principal, bordures des pastilles de tags, onglet actif |
| `inkSoft` | `#3d3830` | texte courant secondaire (descriptions) |
| `muted` | `#5a5449` | dates, lieux, sources, libellés (≥ 6,3:1 sur `paper`) |
| `hint` | `#9a9385` | bordures pointillées « + tag », cases à cocher vides |
| `moss` | `#4f6b3a` | action principale, liens, pastille « Référence », points carte |
| `mossDark` | `#3a5029` | hover/pressed de `moss` |
| `mossLight` | `#8fbf6a` | point « position acquise » sur fond sombre |
| `ochre` | `#b8781a` | « À identifier », « ↑ en attente » |
| `danger` | `#a3402f` | supprimer, toxicité |
| `dark` | `#1d1a14` | fond Noter / visionneuse ; voiles `rgba(29,26,20,.6)` |
| `canvasBg` | `#e9e2d4` | fond hors app (maquette seulement) |

Ombres : cartes/tiroirs `0 14px 44px rgba(40,30,10,.18)` ; bouton Noter `0 8px 20px rgba(79,107,58,.4)` ; barre de recherche flottante sur carte `0 6px 18px rgba(0,0,0,.14)` ; tiroir bas `0 -10px 30px rgba(0,0,0,.14)`.

Dégradés sur photo (légendes) : `linear-gradient(to top, rgba(29,26,20,.92), rgba(29,26,20,.35) 45%, transparent 65%)`. Héros de fiche : `to bottom, rgba(29,26,20,.4), transparent 28%, transparent 50%, rgba(29,26,20,.82)`.

### Typographie
- **Manrope** (Google Fonts, 400–800) : toute l'interface, noms vernaculaires.
- **Newsreader** italique (400–500, optical size auto) : noms scientifiques, mes notes, citations de notes d'observation.

| Rôle | Police | Taille / graisse | Divers |
|---|---|---|---|
| Titre d'écran | Manrope | 34 / 800 | letter-spacing −0,03em, line-height 1 |
| Nom d'espèce héros | Manrope | 36 / 800 | −0,03em, sur photo, crème |
| Nom scientifique héros | Newsreader ital | 24 | auteur en romain 15 / opacité .85 |
| Titre de feuille / section | Manrope | 22–26 / 800 | −0,02em |
| Nom dans liste | Manrope | 16–17 / 800 | |
| Nom scientifique liste | Newsreader ital | 14–15 | couleur `inkSoft` |
| Corps | Manrope | 15 / 400 | line-height 1,45 |
| Mes notes | Newsreader | 20 | line-height 1,35 |
| Métadonnées | Manrope | 12–13 / 400–600 | `muted` |
| Libellé de section | Manrope | 11 / 700 | majuscules, letter-spacing .18em, `muted` (ou `moss` pour « Référence ») |
| Barre d'onglets | Manrope | 12 / 700 | icône 20 px au-dessus |
| Bouton principal | Manrope | 17 / 800 | |
| Bouton secondaire | Manrope | 15 / 700 | |

### Espacements & rayons
- Marge latérale d'écran : **20 px**. Barre d'état 16 px du haut (sur Android : `WindowInsets`).
- Rayons : phone 30 (maquette) ; cartes/champs **14 px** ; vignettes de grille **16 px** ; vignettes petites **10–12 px** ; tiroir bas **26 px** haut ; pastilles et boutons **999 (pill)**.
- Hauteurs : bouton principal **60 px** ; secondaire **52 px** ; ligne de liste ≈ 72 px (vignette 52–64) ; champ de recherche 44–48 ; bouton Noter 60 ; cible tactile minimale 44.
- Grille Collection : 2 colonnes, gap 10, ratio 3:4.

---

## Écrans

Numérotation = identifiants dans `Herbier v2.dc.html`.

### 4a Collection (onglet)
Titre 34 + compteur « 47 plantes · 112 observations ». Barre de recherche `sand` (placeholder « Nom, tag, lieu… », lien « Coller un lien » à droite en `moss` 12/700). Rangée de filtres défilante : pastille pleine `ink` « Toutes », pastilles bordées 1 px `ink` par tag, dernier élément « Tags › » (`moss`) ouvre 4l. Grille 2 colonnes de cartes 3:4 : photo de couverture, dégradé, nom 16/800 crème + latin Newsreader 14 ital. États : **chargement** = fond rayé `sandDeep`/`sand` + libellé monospace 10 « Google Photos… » ; **sans photo** = fond `sand`, texte `ink`, mention « sans photo · 4 obs. ».
Tri par défaut : dernière observation. Recherche : nom affiché, alias, latin, noms vernaculaires de référence, tags, lieux.
*Ajout des retours de Tristan du 2026-11-21 (plan M8.82) : appui long sur une carte → confirmation « Supprimer « <nom> » ? » (ce qui part avec la plante, comme 5a), « Supprimer » / « Annuler » ; la suppression de 5a reste.*

### 4b Carte (onglet)
Carte plein écran (tuiles OSM désaturées : `saturate(.55) sepia(.25)` — en prod, style de carte clair et peu saturé, p. ex. MapLibre + style « paper »). Barre de recherche flottante `paper` avec ombre, bouton `my_location` à droite. Filtres actifs sous la barre. Points : observation = 18 px `ink` bordure 3 px `paper` ; grappe sélectionnée = point `moss` 20 px + halo `rgba(79,107,58,.25)` 56 px ; à identifier = `ochre`. **Tiroir bas** (`paper`, rayon 26) : nom du lieu 22/800 + « rayon 500 m · 6 observations · 4 plantes », « Renommer » ; liste des observations du lieu (vignette 48, nom, date · photos, chevron). Replié sur une ligne si rien n'est sélectionné. La barre d'onglets est *dans* le tiroir.
Grappes : regroupement des observations à < 500 m ; un nom donné (« Renommer ») est stocké sur chaque observation de la grappe (`placeLabel`).

### 4c Journal (onglet)
Titre + « 112 observations ». Filtres : année (pastille pleine = active), « À identifier · 3 » bordé 1,5 px `ochre`, tags. Liste groupée **par jour** : en-tête 18/800 « Ven. 12 juin » + lieu du jour à droite en `moss` 13/700 « Col de la Schlucht ◎ » (bordure basse 1 px `ink`). Lieu du jour = `placeLabel` majoritaire, sinon `placeDerived` (« Près de Colmar »), sinon coordonnées. Le ◎ ouvre la Carte centrée. Lignes = observations : vignette 52, nom 800 (ou « À identifier » en `ochre`), méta 12 `muted` « 14:32 · 2 photos · note », chevron. Ligne → 4h ; ligne « À identifier » → 4k.
*Ajout des retours de Tristan du 2026-11-21 (plan M8.82) : appui long sur une ligne → confirmation « Supprimer cette observation ? » (comme 4h), « Supprimer » / « Annuler » ; la suppression de 4h reste.*

### 4d Noter (modal plein écran, fond sombre)
Viseur caméra plein écran. Haut : ✕ dans voile rond 40 px ; pastille « hors-ligne · 2 en attente » si besoin ; pastille « Position acquise » avec point `mossLight` (pas de valeur de précision). Bas, sur dégradé sombre : rangée de vignettes 56 px (prises, dernière bordée crème 2 px ; case pointillée « galerie / G Photos » ouvre le sélecteur système + Google Photos Picker) ; champ « Nom de la plante — *facultatif* » (voile `rgba(246,241,231,.12)`, bordure `.25`) ; suggestions en pastilles : d'abord ma collection (« Arnica montana · déjà en collection »), puis plantes vues à < 500 m (« Vues ici ↓ ») ; rangée `[↻ 56] [Enregistrer (2 photos) 64 crème] [● 56 moss]`. Le déclencheur est le rond `moss`.
Comportement : la position GPS est demandée à l'ouverture, jamais bloquante ; enregistrer sans nom crée une observation « À identifier » ; **jamais** d'attente réseau.
Tour 6 : bouton Identifier dans le champ du nom et « Identifier dès la photo » (6a), espèce choisie (6e). *Remplacé par les retours de Tristan du 2026-11-19 (plan M8.75, M8.76) : Noter n'a plus de bouton Identifier ni d'ouverture de 6b à la première photo ; l'identification passe à l'observation (4h).*

**Changement (retours de Tristan, 2026-11-19, plan M8.75)** : la rangée du bas devient `[⇄ cameraswitch 56 voile] [● photo_camera 72 moss, anneau crème] [✓ 56 crème « Enregistrer »]`. Le déclencheur est au centre avec l'icône appareil photo ; « Enregistrer » est un rond de la taille du bouton de gauche, icône `check` `ink`, libellé accessible « Enregistrer », grisé (opacité .5, désactivé) tant que la rangée n'a pas de photo (et pendant une prise en cours) ; le compte de photos n'y figure plus. Le bouton de gauche (changer de caméra) prend l'icône `cameraswitch`, plus la flèche circulaire qui faisait « recommencer ». Au toucher du déclencheur, une vignette rayée (rayures sombres de 6d) apparaît aussitôt dans la rangée, remplacée par l'aperçu quand la photo est prise, retirée si la prise échoue.

### 4e Enregistré
*Supprimé par les retours de Tristan du 2026-11-19 (plan M8.76) : Enregistrer mène directement à l'observation (4h) ; la carte Drive y passe (tant qu'une photo attend son envoi), la confirmation devient un toast « Enregistrée · ajoutée à <plante> » / « Enregistrée · à identifier » (2,5 s) ; « Corriger la position » = toucher la mini-carte de 4h ; « Noter une autre plante » et « Voir la fiche » ne sont pas repris. Ce qui suit est l'état du tour 5.*
Confirmation `paper` : rond `moss` 64 ✓, « Enregistré » 30/800, « Observation ajoutée à **Arnica** / Le Hohneck · 48.0331, 7.0028 · 14:07 ». Deux vignettes 1:1 avec badge `ochre` « ↑ en attente ». Carte `sand` avec « G » : « 2 photos → Google Photos, album Herbier / Envoi dès le retour du réseau. Copies compressées gardées sur le téléphone. » Deux lignes d'action `sand` : « Ajouter une note à cette observation », « Corriger la position sur la carte » (→ 5b). Bas : « Noter une autre plante » (60, moss) ; « Voir la fiche Arnica » (52, bordé).

### 4f Fiche espèce (modal, défilement)
1. **Héros** ratio 3:4, photo de couverture, dégradé, boutons ← et ✎ (40 px, `rgba(246,241,231,.9)`), indicateurs de pagination (points 8 px à droite : balayage entre mes photos), badge de provenance (« Google Photos » / « local ») + « Col de la Schlucht · 12 juin » 11 majuscules, nom 36/800, latin 24 ital + auteur.
2. **Tags** : pastilles bordées 1,5 px `ink` 13/600, « + tag » pointillé `hint`.
3. **Mes photos · 5** + « + Depuis Google Photos » : grille 4 colonnes, vignettes 1:1 rayon 10 ; badge rond 14 px « G » en bas-gauche (Google Photos), étiquette « local », badge `ochre` « ↑ » en haut-droite si envoi en attente ; état chargement = anneau 18 px.
4. **Mes observations · 3** + « + Revue ailleurs » : lignes bordées (`line`) « 12 juin 2026 · 14:32 / Col de la Schlucht · 2 photos · note » → 4h.
5. **Mes notes** + « modifié le 13 juin » : Newsreader 20, tap = édition en place.
6. **Bloc Référence** (`sand`, plein largeur, padding 20, marge haute 26) : en-tête « RÉFÉRENCE » (`moss`) + « mis à jour il y a 3 sem. · ↻ ». Lignes clé/valeur en grille `104px 1fr`, gap 12, padding 10 vertical, séparées par 1 px `#ddd5c4`, ordre **botanique d'abord** :
   - **Noms** — vernaculaires par langue (`fr` en premier, gras sur le code langue) ; sous-ligne source 12 `muted` « Plantaginaceae · GBIF, Pl@ntNet »
   - **Type** — « Herbacée bisannuelle, 50–150 cm » · Tela Botanica
   - **Origine** — aire native / introduite · POWO
   - **En France** — pastilles `paper` rayon 6, 13/700 : statut (Indigène/Introduite/Invasive), protection, liste rouge · INPN
   - **Floraison** — 12 cases mois (lettre 10/700 ; actif `moss` texte crème, inactif `sandDeep` texte `muted`, rayon 4, gap 3) + « juin – août · Tela Botanica »
   - **Habitat** — phrase + chips bordées 1 px `hint` 12 (mi-ombre, sol acide, frais, 300–1 500 m) · Tela Botanica
   - **Toxicité** — titre en gras `danger` + phrase · Wikipédia
   - **Photos par organe** — grille 4, vignettes 1:1 rayon 10, bandeau bas `rgba(29,26,20,.7)` 10/700 « fleur / feuille / fruit / port » · Pl@ntNet · disponibles hors-ligne
   - Rangée de liens `paper` rayon 10 13/700 : GBIF ↗, Pl@ntNet ↗, Wikipédia ↗, POWO ↗, INPN ↗, Tela Botanica ↗
   **Une ligne sans donnée disparaît.** Toute donnée cite sa source.

*Ajouts des retours de Tristan du 2026-11-21 (plan M4.80) : **Noms** en français seul (sans code de langue), « Autres langues › » déplie en, de, it (sans nom français, les autres langues s'affichent directement) ; **Origine** en français (noms des aires WGSRPD), triée dans l'ordre français ; **Photos par organe** : toucher une vignette ouvre la visionneuse (5e) en lecture seule (balayage entre les organes, crédit « auteur · licence · Pl@ntNet », ni ⋯ ni pastilles) ; « disponibles hors-ligne » retiré.*

*Ajouts du 2026-11-21 (plan M4.81, décisions de Tristan) : ligne **Utilisations** après « Toxicité » — d'abord les usages de Pl@ntUse en pastilles (la liste « Résumé des usages » de sa page, telle qu'écrite) et une ou deux lignes de sa section « Usages », crédit lien « Pl@ntUse · CC BY-SA » ; puis le premier paragraphe de la section « Usages » / « Utilisation » de l'article Wikipédia (fr, sinon en, non traduit ; quand la section n'a que des sous-sections, celui de ses sous-sections, celles d'usages d'abord, un « Historique » en dernier), crédit lien « Wikipédia (en) · « titre de la section » · CC BY-SA · extrait automatique » (le paragraphe est choisi par le titre de la section : heuristique, d'où « extrait automatique ») ; la ligne disparaît quand aucune des deux sources n'a de donnée ; Pl@ntUse ↗ ferme la rangée de liens. **Textes longs** (« paragraphe étendable en cliquant dessus ») : tout texte long de 4f (Utilisations, Habitat, Toxicité, et tout autre paragraphe de plusieurs lignes) s'affiche replié sur 3 lignes, la dernière en fondu ; un toucher le déplie, un second le replie (bouton `aria-expanded`) ; un texte court (≤ 140 caractères, une seule ligne) s'affiche en entier, sans bouton. Les pastilles (Pl@ntUse, « En France », habitat) et les listes de noms ne se replient pas : ce sont des listes, pas des paragraphes. Le seuil de 140 caractères vaut pour un téléphone tenu droit ; à l'horizontale, un texte juste au-dessus peut tenir en 3 lignes et garder le fondu.*

*Retours du 2026-11-22 (plan M8.86) : plus de sous-ligne source sous les lignes (ni « · Tela Botanica », ni les crédits liens d'« Utilisations », ni « Photos par organe · Pl@ntNet » et ses crédits, qui restent dans la visionneuse 5e) ; le bloc se termine par **Sources** (titre 13/700 `muted`, filet 1 px `#ddd5c4` au-dessus) : une ligne 12 `muted` par source des lignes affichées, une seule fois, dans l'ordre de la rangée de liens (GBIF, Pl@ntNet, Wikipédia, POWO, INPN, Tela Botanica, puis les autres), le nom souligné en lien vers la page d'où vient la donnée, puis « · licence » quand elle est requise (Wikipédia, Pl@ntUse : CC BY-SA ; Pl@ntNet : les licences des photos) ; l'extrait d'« Utilisations » a sa ligne « Wikipédia (en) · « titre de la section » · CC BY-SA · extrait automatique », liée à la section. La rangée de liens y est fondue : seules restent, en pastilles sous la liste, les sources qu'aucune ligne ne cite (POWO ↗…). La famille reste sous les noms.*

### 4g Fiche sans référence (nom libre, hors-ligne)
Comme 4f, mais : badge « local », latin remplacé par « nom libre — espèce non liée » (Newsreader ital 19, opacité .8), bloc Référence réduit à un texte « Aucune espèce de référence liée. Hors-ligne : la recherche de noms reviendra avec le réseau. » + bouton bordé 52 « Lier à une espèce de référence » (opacité .5 tant que hors-ligne).
Tour 6 : en ligne, deux boutons « Identifier » et « Chercher un nom » (6k).

### 4h Observation (modal)
En-tête : ←, centre « OBSERVATION / Digitale pourpre › » (lien vers la fiche), « Terminé ». Mosaïque photos : grande 4:3 (2/3) + colonne (1/3) avec petite photo et case « + » pointillée. Carte `sand` **Date** « Ven. 12 juin 2026 · 14:32 » + « Modifier ». Carte lieu : mini-carte 130 px avec point `moss` et **cercle de précision** (44 px, `rgba(79,107,58,.18)`, bordure `.6`) — seule représentation de la précision GPS ; sous la carte, nom du lieu + coordonnées + libellé, « Déplacer » → 5b. Carte « Note de cette rencontre » Newsreader 18. Bas : liste d'actions bordées « Changer d'espèce › » (5c), « Voir dans le journal › », « Supprimer l'observation › » en `danger`.
*Ajouts des retours de Tristan du 2026-11-19 (plan M8.76) : 4h est l'écran d'arrivée après Enregistrer (Android back revient là d'où Noter a été ouvert). Tant que l'observation est « À identifier », bouton « Identifier avec Pl@ntNet » (glyphe, comme 6i) sous la mosaïque : grisé hors-ligne, sans photo ou sans clé, avec la ligne hors-ligne ou sans photo, sans ligne sur la clé ; il ouvre la couche d'identification avec « Lier » / « + Créer » (6j) ; avec « Identifier dès la photo », la couche s'ouvre à l'arrivée depuis Noter. La ligne d'action « Identifier › » devient « Chercher un nom › » (4k). Carte Drive (venue de 4e) tant qu'une photo attend son envoi ; la carte « photos gardées » de 4e (photos sur le téléphone seulement) n'est pas reprise : le badge « local » des vignettes de la mosaïque et de la visionneuse le dit déjà. La confirmation de 4e devient un toast de 2,5 s (« Enregistrée · ajoutée à … » / « Enregistrée · à identifier »). Toucher la mini-carte ouvre 5b (au lieu de la Carte centrée).*

### 4i Chercher / résoudre (modal)
Champ actif 17 avec curseur. Section « DANS MA COLLECTION · 1 » (ligne vignette 56, « Ouvrir › »). Section « RÉFÉRENCE · GBIF » + « Europe · Plantae » : lignes latin Newsreader ital 18 + auteur 13 `muted`, vernaculaires 14 `inkSoft`, bouton rond 36 `sand` « + ». Pied : carte pointillée « Coller un lien / GBIF, Pl@ntNet, Wikipédia, POWO… / Coller ». « + » → 4j pré-remplie.
Recherche référence : GBIF `species/suggest` (rank=SPECIES, kingdom Plantae) + noms vernaculaires ; débounce 300 ms ; hors-ligne → « recherche indisponible » + bouton « Créer avec un nom libre ».

### 4j Lien intercepté (feuille basse sur l'app d'origine)
Feuille `paper` rayon 26, poignée 40×4 `lineSoft`. En-tête « HERBIER · LIEN GBIF RECONNU » (`moss`) + ✕. Carte espèce : vignette 84 rayon 16, nom 26/800, latin 19 ital, « Gentianaceae · GBIF · Pl@ntNet · Wikipédia fr ». Carte `sand` **« Première observation ici »** point `moss` 10, « Le Hohneck · 48.0331, 7.0028 · maintenant », **« Enlever »** (retire la position ⇒ plante sans observation). Carte tags pré-remplis (tags récents). Bouton 60 « Ajouter à ma collection ». Ligne basse : « Pas la bonne espèce ? **Chercher** » / « **Ouvrir la fiche après** ».
Variante : espèce déjà en collection ⇒ titre « Déjà dans ma collection », bouton « Ajouter cette observation ».
Android : `intent-filter` `VIEW` + `BROWSABLE` sur `gbif.org/species/*`, `identify.plantnet.org/*/species/*`, `*.wikipedia.org/wiki/*`, `powo.science.kew.org/taxon/*`, `inpn.mnhn.fr/espece/cd_nom/*` ; plus `SEND text/plain` pour la feuille de partage. Résolution : URL → identifiant → GBIF `species/match` ou `species/{key}` → `ReferenceSnapshot` partiel immédiat (nom, famille), complet en arrière-plan.

### 4k À identifier → lier (modal)
En-tête ← / « À IDENTIFIER · 1 / 3 » (`ochre`) / « Suivante › ». Carte `sand` de l'observation (vignette 96, date, lieu, note en Newsreader 16 entre guillemets). Champ de recherche. « Dans ma collection » → bouton « Lier › » (rattache l'observation à la plante existante). « Référence · GBIF » → « + » (crée la plante puis rattache). Pied : deux boutons bordés 52 « Coller un lien » / « Nom libre » (crée une fiche 4g).
Tour 6 : bouton principal « Identifier avec Pl@ntNet » sous la carte, la recherche « ou par le nom » en dessous (6i), propositions dans la file (6j).

### 4l Tags (modal)
←, « Gérer » (→ 5d). Titre « Tags » + « 12 tags · touchez pour filtrer la collection ». Grille 2 colonnes de cartes 1:1 rayon 18 (photo de couverture de la plante la plus récente du tag, nom 20/800, « 18 plantes ») pour les 4 tags les plus utilisés ; puis pastilles bordées 1,5 px 14/600 avec compteur `muted` pour le reste. Tap = applique le filtre et revient à Collection.
*Ajouts des retours de Tristan du 2026-11-19 (plan M8.77) : plus de « Gérer » ; ✎ sur chaque carte et pastille, appui long aussi, ouvre la boîte du tag (renommer, renommer en un nom existant = fusionner, supprimer avec confirmation) ; gros « + » en bas à droite (style du bouton Noter) pour créer un tag. Les tags n'ont pas de couleur.*

### 4m Réglages (onglet)
Titre. Carte compte : avatar rond `moss` 44 initiale, « Compte Google connecté / n…@gmail.com · Photos, Drive », « Changer ». Section **Où vont mes photos** (radio, 3 options dans une carte `sand` rayon 16, lignes séparées 1 px `line`) : « Google Photos · album “Herbier” — Originaux dans ma bibliothèque, aperçus gardés sur le téléphone. » / « Google Drive · dossier “Herbier” — Un sous-dossier par espèce. » / « Dans Herbier seulement — Compressées à 1600 px · limité à 200 Mo. ». Section **Sur le téléphone** : interrupteur « Copie compressée hors-ligne » (on), « Envoyer seulement en Wi-Fi » (off), « Données hors-ligne — Aperçus photos 48 Mo · Fiches de référence 12 Mo / **Libérer** ». Section **File d'envoi** : « 3 photos en attente / Dernier envoi : hier, 19:42 / **Envoyer maintenant** ».
Note d'implémentation (M7.62, la maquette reste la référence visuelle) : la carte compte est le compte Google de la synchronisation (Supabase) ; « · Photos, Drive » n'y figure plus, car Drive a son propre compte. Sous les radios, un bouton « Dossier Drive › » (dossier · adresse du compte Drive) ouvre une feuille plein écran : « Compte : … » avec le lien « Utiliser un autre compte » (12/700 `moss`) dans une carte `sand`, puis le dossier (voir M7.79).
Note d'implémentation (M7.72) : l'option s'intitule « Google Drive » ; sous elle, une fois choisis, « <dossier> · <adresse> ». La choisir ouvre le choix du compte (s'il n'y en a pas) ; annuler laisse l'option précédente et n'enregistre rien. Sans configuration Google, l'option est désactivée avec sa raison sur une ligne. « Dossier Drive › » sert à changer ce choix.
Note d'implémentation (M7.79, décision après l'essai sur le téléphone du 2026-11-21 : Google Picker retiré) : la feuille « Dossier Drive » montre « Compte : … » / « Utiliser un autre compte », puis « Nom du dossier » (« Herbier » par défaut) dans un champ avec « Renommer » (un nom vide est refusé), et la ligne « Pour le ranger ailleurs, déplacez ce dossier dans Google Drive : Herbier le suit. ». Choisir « Google Drive » ne fait que choisir le compte ; le dossier est créé au premier envoi ou au renommage.
Vocabulaire : jamais « cache », « vignettes », « sync » face à l'utilisateur.
Tour 6 : nouvelle section « Identification » en tête, sous la carte du compte (6h), avec la ligne « Clé API Pl@ntNet » ajoutée à la maquette (voir 6h).

### 4n Premier lancement (Collection vide)
Titre « Collection / 0 plante ». Centre : emplacement d'illustration 4:3 rayon 20 (à fournir), « La première plante s'ajoute dehors ou depuis un lien. » 26/800, texte explicatif 15, boutons « + Noter ma première plante » (60 moss) et « Coller un lien Pl@ntNet / GBIF » (52 bordé), note « Google Photos se connecte plus tard, à la première photo. » Pas de tunnel d'onboarding ; la connexion Google est demandée à la première photo à sauver.

### 5a Modifier la fiche (modal)
En-tête « Annuler / Modifier / Enregistrer ». Cartes `sand` : **Nom affiché** (18/800 éditable) + alias en pastilles `paper` avec ✕ et « + alias » ; **Espèce de référence** (latin) + « Changer › » (→ recherche, relie à un autre taxon, rafraîchit la référence, ne touche pas mes données) ; **Liens de référence** liste « GBIF · 2927899 ✕ … » + « + Coller un lien (POWO, EPPO…) » ; **Tags** avec ✕ ; **Photo de couverture** rangée de vignettes 56, sélection bordée 2,5 px `moss`. Pied : « Supprimer la plante et ses 3 observations › » `danger` (confirmation ; les photos Google restent).

### 5b Déplacer le point (modal carte)
Carte plein écran, **point fixe au centre** (24 px `moss` + tige 2×16 + cercle de précision), la carte glisse dessous. Haut : ✕, pastille « Glissez la carte sous le point », bouton `my_location`. Point gris 18 px opacité .7 = position d'origine. Tiroir bas : nom du lieu 20/800 + « 48.0633, 7.0081 · déplacé de 96 m », « Chercher un lieu » (géocodage) ; boutons « Point d'origine » (bordé) / « Valider » (moss).

### 5c Changer d'espèce (modal)
En-tête ← / « CHANGER D'ESPÈCE / Observation du 12 juin ». Carte `sand` « Actuellement **Digitale pourpre** / Les 2 photos et la note suivent l'observation. » Recherche ; « Dans ma collection » (ligne « Choisir › » ; l'espèce actuelle grisée .5) ; « Référence · GBIF » (« + » crée puis déplace). Pied : bouton bordé `ochre` « Remettre “À identifier” ». Si la plante d'origine n'a plus d'observation : dialogue « Garder la fiche / Supprimer la fiche ».

### 5d Gérer les tags (modal)
*Remplacé par les retours de Tristan du 2026-11-19 (plan M8.77) : écran supprimé, ses actions sont dans 4l.*
En-tête « Annuler / Gérer les tags / Terminé ». Lignes : case 22 rayon 6 (vide bordure `hint` ; cochée `moss` avec ✓), nom 700, compteur 13 `muted`, ✎ (renomme en place : le nom devient un champ `sand` rayon 10 avec « OK »). Barre basse `sand` quand ≥ 1 coché : « 2 sélectionnés », « Supprimer » (bordé `danger`), « Fusionner en “tourbière” » (moss ; le nom le plus fréquent gagne ; visible si ≥ 2 cochés).

### 5e Visionneuse photo (modal sombre)
Photo en `contain` sur `dark`. Haut : ✕, « 2 / 5 », ⋯ (voiles ronds 40). Bas sur dégradé : badge provenance + « COUVERTURE » si c'est la couverture ; nom 22/800 ; « Ven. 12 juin 2026 · 14:32 · Col de la Schlucht » ; pastilles `rgba(246,241,231,.14)` 13/700 : « Voir l'observation », « Ouvrir dans Google Photos ↗ », « Retirer d'Herbier ». ⋯ : « Définir comme couverture », « Déplacer vers une autre observation ». Balayage horizontal entre toutes les photos de la plante ; pincer pour zoomer.

### 5f Lisibilité plein soleil (règles globales, déjà appliquées aux jetons)
Texte secondaire `#5a5449` (≥ 6,3:1) ; séparateurs `#cfc6b3` ; libellés d'onglets 12 px ; dégradés sous les noms sur photo à .92. Pas de « mode extérieur », pas de mode sombre (Noter et la visionneuse sont sombres par nature).

### Tour 6 · Identifier avec Pl@ntNet (6a–6k)
Canevas « Herbier · Identification Pl@ntNet » (2026-11-16), dans `identification/` : 13 planches et `canvas.json` (titres des planches et notes). Identifier est une autre façon de nommer une plante : les photos partent chez Pl@ntNet, ses propositions reviennent, et en choisir une nomme la plante. Règles du tour :
- Noter n'attend jamais le réseau : on peut toujours repartir vers Noter, photo gardée.
- Choisir une proposition lie le taxon GBIF renvoyé par Pl@ntNet ; la référence se charge comme après un lien intercepté (4j).
- Même taxon qu'une de mes plantes : l'observation lui est ajoutée, pas de doublon.
- Pl@ntNet est nommé sur chaque écran ; ses photos sont créditées (6d).
- Les photos des maquettes sont des emplacements rayés (le canevas ne charge pas d'images).

*Parcours remplacé pour Noter par les retours de Tristan du 2026-11-19 (plan M8.75, M8.76) : plus d'entrée depuis Noter (ni bouton, ni première photo) ; l'entrée est l'observation (4h) après Enregistrer.* **Le parcours** (`Main.dc.html`) : trois entrées mènent au même écran de choix (6b puis 6c) : Noter, photo prise, en ligne avec « Identifier dès la photo » actif (par défaut) ; Noter, bouton Identifier (après « Continuer sans attendre », ou réglage coupé) ; À identifier (6i) et fiche nom libre (6k), pour une plante notée hors-ligne et identifiée plus tard. Sorties : retour à Noter (6e : « Choisir » remplit nom et latin, « Aucune ne correspond » laisse le nom vide, puis Enregistrer → 4e ; *depuis M8.76 : Enregistrer → 4h, couche ouverte si le réglage est actif*) ; rattachée (6j : « Lier » à ma plante ou « + Créer » la fiche). Hors-ligne, le bouton Identifier est grisé : rien n'attend le réseau, la plante patiente dans « À identifier ». ←, « Continuer sans attendre » et « Aucune ne correspond » reviennent toujours à Noter, photo gardée.

#### 6a Noter — bouton Identifier
*Remplacé par les retours de Tristan du 2026-11-19 (plan M8.75, M8.76) : le bouton Identifier, ses lignes hors-ligne et sans clé, et l'ouverture de 6b à la première photo quittent Noter ; l'identification se fait depuis l'observation (4h, M8.76), et « Identifier dès la photo » s'y applique à l'enregistrement. Ce qui suit est l'état du tour 6.*
4d, avec dans le champ du nom, à droite, un rond `paper` 36 px (cible 44) portant le glyphe Identifier en `ink` : il envoie les photos déjà prises (5 au plus). Avec « Identifier dès la photo » (actif par défaut, 6h), la première photo, appareil ou galerie, ouvre directement 6b. Hors-ligne : le rond à opacité .5, désactivé, et sous le champ la ligne 12 « Hors-ligne : l'identification reviendra avec le réseau. Sans nom, la plante part dans « À identifier ». »

#### 6b Identification — envoi
Fond `paper`. En-tête ← / « PL@NTNET » (11/700 majuscules `moss`) sur « Identification » 15/800. Vignette de ma photo 64 rayon 12, « Envoi à Pl@ntNet… » 15/700, « Pl@ntNet ne conserve pas la photo. » 12 `muted`. Libellé « PROPOSITIONS » et, à droite, la flore (12/600 `muted`). Trois cartes squelettes `sand` rayon 16 : quatre vignettes 1:1 rayées (rayon 10), barre de score vide, deux lignes ; « Pl@ntNet… » monospace 10 après 600 ms, comme les photos qui chargent. Pied fixe : « Continuer sans attendre » (bordé 52). Rien ne bloque : ce bouton et ← reviennent à Noter, photo gardée. *Remplacé par les retours de Tristan du 2026-11-19 (plan M8.75, M8.76) : Noter n'ouvre plus l'identification ; le retour à Noter et le passage à 6e ne valent que pour l'ancien parcours depuis Noter.*

#### 6c Identification — propositions
Même en-tête. Rangée de mes photos (64, rayon 12), l'organe détecté en bandeau bas « fleur ▾ » (on le corrige), puis une case pointillée `hint` « + feuille » et « Une feuille en plus départage les espèces proches. » 12 `muted` ; « + feuille » relance avec 2 photos (5 au plus). « PROPOSITIONS · 4 » et la flore en menu (« … ▾ »). Une carte `sand` rayon 16 par espèce, dans l'ordre et avec le score de Pl@ntNet : les 4 photos de l'espèce les plus proches de la mienne (1:1 rayon 10, bandeau d'organe 10/700), la dernière voilée avec « +N » ; barre de score 6 px `moss` sur `line` et pourcentage 13/800 ; latin Newsreader ital 19 et auteur romain 13 `muted` ; noms français 14 `inkSoft` séparés par « · » ; famille 12 `muted` ; « Choisir » (bordé 44). Si une de mes plantes a ce taxon GBIF, pied de carte (filet 1 px `#ddd5c4`) « ✓ Dans ma collection · Arnica · 2 obs. » 13/700 `moss` : l'observation lui sera ajoutée. Une vignette ou « +N » ouvre 6d. Pied fixe : « Aucune ne correspond » (bordé 52).

#### 6d Comparer
Fond `dark`. ✕ (voile rond 40) et pastille « Proposition 1 / 4 ». Deux photos de 280 px rayon 16 : en haut ma photo (pastille « Ma photo · fleur »), en bas celle de l'espèce (pastilles « Pl@ntNet · fleur » et « 3 / 15 », bandeau bas 11 « © [auteur] · CC BY-SA · Pl@ntNet »). Bas : latin 21 ital et auteur, « nom · famille » 13, « ✓ Dans ma collection · … » `mossLight`, score 17/800 ; rangée ‹ (52) / « Choisir cette espèce » (56, crème) / › (52). Facultatif : on n'y arrive qu'en touchant une photo d'espèce dans 6c ; « Choisir » de 6c valide directement (→ 6e). *Remplacé par les retours de Tristan du 2026-11-19 (plan M8.75, M8.76) : Noter n'ouvre plus l'identification ; le retour à Noter et le passage à 6e ne valent que pour l'ancien parcours depuis Noter.* Ma photo en haut, celles de l'espèce en bas, même organe d'abord. Balayer : photo suivante ; ‹ › : proposition voisine. Chaque photo porte son auteur, sa licence et Pl@ntNet.

#### 6e Noter — espèce choisie
*Remplacé par les retours de Tristan du 2026-11-19 (plan M8.75, M8.76) : Noter n'a plus de bouton Identifier, cet écran n'est plus atteint ; le choix d'une proposition se fait depuis l'observation (4h, M8.76), avec « Lier » / « + Créer » comme 6j. Ce qui suit est l'état du tour 6.*
Noter, le champ du nom devenu la carte du choix : bordure 1,5 px `mossLight`, ✓ `mossLight`, nom 16/800, sous-ligne « *latin* · Pl@ntNet 82 % » (Newsreader ital 14), ✕ (cible 44) qui efface le choix. Ligne 12 « Déjà dans ma collection : l'observation s'ajoutera à Arnica. » Le nom affiché est mon nom d'affichage si l'espèce est dans ma collection, sinon le nom français de Pl@ntNet (la fiche est créée et liée à GBIF à l'enregistrement).

#### 6f Propositions incertaines
6c avec un cadre `ochre` 1,5 px rayon 16 autour de mes photos, et la case de l'organe utile mise en avant (« + fleur », pointillé et texte `moss` 800) : le meilleur score est bas ou talonné (seuils à régler, par exemple < 50 % ou moins de 15 points d'écart). L'action utile est la photo d'un autre organe ; « + fleur » relance.

#### 6g Aucune plante reconnue
Même en-tête ; ma photo et une case « + photo ». Centre : glyphe 48 `hint`, « Aucune plante reconnue » 26/800, « Pas de plante détectée sur cette photo. » 15 ; « Reprendre la photo » (60 `moss`, icône appareil), « Garder la photo, sans nom » (bordé 52), lien 14/700 `moss` « Voir quand même les propositions peu probables ». Pl@ntNet a répondu « Species not found » : pas de plante sur la photo ; « Voir quand même » relance avec `no-reject`. Même écran si Pl@ntNet ne répond pas, avec « Réessayer ».

#### 6h Réglages — Identification
Nouvelle section en tête de 4m, sous la carte du compte : « IDENTIFICATION », carte `sand` rayon 16 avec l'interrupteur « Identifier dès la photo » (« Pl@ntNet propose les espèces avant de nommer. En ligne seulement. », actif par défaut) et la ligne « Flore Pl@ntNet » (valeur 13 `muted`, chevron). Note 12 `muted` : « Pl@ntNet ne conserve pas les photos envoyées. Jusqu'à 500 identifications par jour. » La flore est le projet Pl@ntNet de la requête. **Changement par rapport à la maquette (décision de Tristan, 2026-11-16)** : la flore par défaut est « Automatique » (`all`, Pl@ntNet choisit la flore à chaque requête), pas « Europe de l'Ouest » comme sur la maquette (« using 'europe de l'ouest' would make it harder to identify non-indigenous plants ») ; la liste des flores reste au choix dans 4m et 6c. Le reste des réglages ne change pas.

**Ajout à la maquette (2026-11-16, décision de Tristan sur la clé API, plan « Clé API Pl@ntNet »)** : la clé API Pl@ntNet est celle de l'utilisateur, saisie dans Réglages, une par personne ; le canevas n'a pas cette ligne. Dans la carte Identification, une ligne « Clé API Pl@ntNet » : valeur masquée 13 `muted` (« •••• » et les quatre derniers caractères, ou « Aucune clé »), « Modifier » (champ pour coller ou taper la clé ; vide = l'effacer), et une note 12 `muted` : « Clé gratuite et personnelle, à créer sur my.plantnet.org. Dans votre compte Pl@ntNet, cochez « expose my API key » et ajoutez https://localhost aux domaines autorisés. », « my.plantnet.org » en lien (`moss`) vers https://my.plantnet.org/. La clé reste sur le téléphone : jamais envoyée à Supabase, hors des sauvegardes Android, jamais dans les journaux ; l'identification marche sans être connecté. Sans clé, les boutons Identifier (6a, 6i, 6k) sont désactivés avec une ligne 12 qui renvoie à Réglages, « Ajoutez votre clé API Pl@ntNet dans Réglages pour identifier. » (comme la ligne « Dossier Drive » sans numéro de projet), et « Identifier dès la photo » ne fait rien.

#### 6i À identifier — Pl@ntNet
4k gagne un bouton principal 60 `moss` « Identifier avec Pl@ntNet » (glyphe 22) sous la carte de l'observation, qui envoie les photos de l'observation. En dessous, séparateur « OU PAR LE NOM », champ « Nom, latin, alias… », et en pied « Coller un lien » / « Nom libre » (bordés 52), inchangés.

#### 6j Propositions — À identifier
Même écran que 6c, dans la file À identifier : en-tête « À IDENTIFIER · 1 / 3 » `ochre` sur « Identification », la note de l'observation (Newsreader 15) à côté de sa photo, « PROPOSITIONS PL@NTNET · 3 ». « Lier » rattache l'observation à ma plante ; « + Créer » crée la fiche liée et l'y range, comme le « + » de 4k. Puis l'observation suivante. « Aucune ne correspond » revient à 6i.

#### 6k Fiche nom libre — Pl@ntNet
Fiche nom libre (4g), réseau revenu. Bloc Référence : « Aucune espèce de référence liée. » et deux boutons 52 : « Identifier » (`moss`, glyphe 20) et « Chercher un nom » (bordé). Pl@ntNet reçoit les photos d'une seule observation : il suppose un seul individu. Lier garde le nom libre en alias, comme « Lier » aujourd'hui.

#### Bouton Identifier · glyphe
Un cadre de visée autour d'une feuille : identifier cette plante d'après la photo. Grille 24, trait 2 px, coins r 1, feuille pleine, nervure évidée (trait 1,4), pour voisiner avec les Material Symbols Outlined de l'app (qui n'ont pas ce glyphe). Tailles 48, 24, 20. En place : rond crème dans le champ du nom de Noter (6a, cible 44 px) ; bouton plein `moss` avec libellé « Identifier avec Pl@ntNet » (6i, 6k) ; 48 `hint` dans 6g. Variante retenue : A, cadre et feuille (encadrée dans la planche) ; B (loupe et feuille) et C (feuille seule) sont écartées. Tracé (`Icone.dc.html`) :
```
cadre    M4 9V5a1 1 0 0 1 1-1h4M15 4h4a1 1 0 0 1 1 1v4M20 15v4a1 1 0 0 1-1 1h-4M9 20H5a1 1 0 0 1-1-1v-4  (trait 2)
feuille  M8 16C8 11.6 11.6 8 16 8C16 12.4 12.4 16 8 16Z                                                  (plein)
nervure  M9.7 14.3L13.6 10.4                                                                             (trait 1,4, rond, évidé)
```

---

## Interactions & comportements

- **Transitions** : modaux depuis le bas (300 ms, decelerate) ; feuilles basses avec poignée, glisser pour fermer ; fiche espèce = héros partagé depuis la carte de Collection (shared element, 350 ms). Onglets sans animation.
- **Pressed** : boutons pleins → `mossDark` ; pastilles bordées → fond `sand` ; lignes de liste → fond `sand`.
- **Chargement des photos** : toujours le fond rayé `sandDeep`/`sand` (jamais une case vide ni un spinner seul) ; libellé monospace 10 `muted` de la source si > 600 ms ; anneau 18 px sur les petites vignettes.
- **Hors-ligne** : bandeau discret dans la barre d'état « hors-ligne · N en attente ». Noter, Observation (Enregistré jusqu'à M8.76), Fiche (mes données + référence en cache), Journal, Carte (tuiles en cache) fonctionnent. Recherche référence, « Lier » et « Identifier » (tour 6) sont désactivés (.5) avec texte explicite.
- **File d'envoi** : WorkManager, contrainte réseau (Wi-Fi si réglage), réessais exponentiels ; badge `ochre` « ↑ » par photo tant que `PENDING`.
- **Référence** : récupération à la liaison, puis rafraîchie sur demande (↻) ou si > 90 jours à l'ouverture avec réseau. Vignettes des photos de référence (≈ 300 px) et textes conservés en local ; « Libérer » les efface.
- **Google** : sign-in unique différé à la première photo à sauver ; Photos Library API (album « Herbier ») ou Drive API (dossier « Herbier »/espèce) selon le réglage ; le sélecteur « Depuis Google Photos » utilise Google Photos Picker API.
- **Interception** : voir 4j. Si l'utilisateur n'a pas défini Herbier comme gestionnaire par défaut, la feuille de partage mène au même écran.
- **Suppression** : plante ⇒ dialogue listant N observations et M photos ; les photos Google ne sont jamais supprimées, seulement déliées.

## État (par écran, indicatif)

- Global : `filters { tagIds, year, unidentifiedOnly }` partagé Collection/Carte/Journal ; `network { online, pendingUploads }` ; `account { googleSignedIn, storageTarget }`.
- Collection : `query`, `plants` (triées), `loadingCovers`.
- Carte : `viewport`, `selectedCluster`, `clusters`.
- Journal : `groupsByDay`, `expandedYear`.
- Noter : `photos[]`, `gps { point?, acquired }`, `query`, `suggestions`, `saving`.
- Fiche : `plant`, `reference?`, `refreshing`, `photoIndex`.
- Résolveur (4i/4j/4k/5c) : `input`, `collectionMatches`, `referenceMatches`, `resolving`, `prefill { point?, tags }`.

## Sources externes (à confirmer côté ingénierie)

| Source | Usage | API |
|---|---|---|
| GBIF | recherche/suggestion d'espèces, noms vernaculaires, résolution des liens | `api.gbif.org/v1/species/suggest`, `/species/{key}`, `/species/{key}/vernacularNames`, `/species/match` |
| Pl@ntNet | identification par photos (tour 6) ; photos par organe ; résolution des liens species | identification : `my-api.plantnet.org/v2/identify/{flore}` (clé API de l'utilisateur, saisie dans 4m, 500 identifications par jour gratuites ; `docs/exploratory_research/plantnet-identify-api.md`) ; photos par organe : jeu Pl@ntNet de GBIF (scraping exclu) |
| Wikipédia | toxicité / résumé, image | REST `page/summary/{title}` (fr puis en) |
| POWO (Kew) | aire native / introduite | `powo.science.kew.org/api/2/taxon/{ipni}` (non officielle) |
| INPN / TaxRef | statut FR, protection, liste rouge | `taxref.mnhn.fr/api` (OpenAPI) |
| Tela Botanica | floraison, type biologique, écologie | eFlore API / Baseflor (stabilité à vérifier) |
| OSM / MapLibre | fond de carte, tuiles hors-ligne | style clair peu saturé ; respecter la politique de tuiles |
| Géocodage inverse | « Près de Colmar » | Nominatim (usage léger) ou Android Geocoder |

## Assets

- Polices : Manrope, Newsreader (Google Fonts, licence OFL).
- Icônes : Material Symbols Outlined (voir liste plus haut).
- Illustration « planche d'herbier vide » (4n) : à créer.
- Photos des maquettes : Wikimedia Commons, à titre illustratif uniquement — ne pas embarquer.

## Fichiers

- `Herbier v2.dc.html` — **référence** : jeu consolidé 4a–4n + tour 5 (5a–5f). Ancre `#4f` etc. pour chaque écran.
- `Herbier.dc.html` — historique des explorations (tours 1–3, alternatives de navigation 1a/1b/1c). Contexte uniquement.
- `identification/` — **référence** du tour 6 (canevas « Herbier · Identification Pl@ntNet ») : `Main.dc.html` (le parcours), `Icone.dc.html` (glyphe), `Noter-Identifier` (6a), `Envoi` (6b), `Propositions` (6c), `Comparer` (6d), `Noter-Choisie` (6e), `Incertain` (6f), `Aucune` (6g), `Reglages` (6h), `A-identifier` (6i), `A-identifier-Propositions` (6j), `Nom-libre` (6k), tous en `.dc.html`, et `canvas.json` (position et titre des planches, et les notes : règles du tour et une note par écran). Ces fichiers chargent `./support.js`, non fourni avec le tour : pour en ouvrir un dans un navigateur, copier `../support.js` à côté (il porte les mêmes balises `x-dc`, `sc-if`, `DCLogic` ; rendu non vérifié).
- `support.js` — runtime des maquettes, sans intérêt pour l'implémentation.
