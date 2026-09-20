# Fix : noms des auteurs de statuts affichés comme « Prestataire »

## Problème

Sur la page **Statuts & Annonces** (`statuts_prestataires_screen.dart`), le nom de l’auteur d’un statut s’affiche par le libellé générique **« Prestataire »** au lieu du vrai prénom/nom de l’utilisateur.

### Hypothèse racine

L’API ne renvoie pas systématiquement `prestataire_detail` ni un objet `utilisateur` bien formé dans la réponse des statuts. Le parsing actuel ne couvre qu’un nombre limité de clés, donc :

- `StatutPrestataire.prestataireDetail` reste `null` → le fallback UI affiche « Prestataire ».
- Ou `Prestataire.fromJson` reçoit un objet `prestataire` qui contient l’utilisateur sous une clé alternative (`user`, `auteur`, etc.) → l’utilisateur est créé avec des champs vides → `displayName` retourne « Utilisateur ».

## Plan d’action

### 1. `lib/core/models/prestataire_models.dart` — robustesse du parsing `Prestataire`

- Ajouter un helper `_utilisateurJson(Map<String, dynamic>)` qui scrute plusieurs clés candidates : `utilisateur`, `user`, `auteur`, `createur`, `proprietaire`, `owner`.
- Remplacer la condition actuelle `json['utilisateur'] is Map<String, dynamic>` par l’utilisation de ce helper.
- Si aucune clé ne matche, conserver le `Utilisateur` vide par défaut (comportement existant).

### 2. `lib/core/models/statut_prestataire_models.dart` — enrichissement auteur dans `StatutPrestataire.fromJson`

- Ajouter un helper `_hasMeaningfulName(Utilisateur u)`.
- Après le bloc existant qui construit `prestataireDetail` depuis `utilisateur`/`auteur`/`user`, ajouter un second bloc :
  - Si `prestataireDetail` est `null` **ou** si son `utilisateur` n’a pas de nom significatif, essayer les mêmes clés candidates au niveau du statut (`utilisateur`, `auteur`, `user`, `createur`, `proprietaire`, `owner`).
  - Si une carte est trouvée et contient un nom, construire un `Prestataire` minimal avec cet utilisateur.

### 3. `lib/core/services/statut_realtime_service.dart` — merge de `prestataireDetail`

- Dans `_applyStatutRaw`, lorsque `existing != null` :
  - Extraire un éventuel `prestataire_detail` ou `prestataire` depuis le payload brut.
  - Le parser via `Prestataire.fromJson` si c’est une carte valide.
  - Le passer dans `copyWith(prestataireDetail: ...)` en préférant la nouvelle valeur seulement si elle contient un nom significatif, sinon garder l’existante.

### 4. `lib/screens/statuts_prestataires_screen.dart` — enrichissement UI et cache

- Dans `_enrichMissingPrestataires()` (écrans `StatutsPrestatairesScreen`, `HomeStatutsStories`, `StatutViewerScreen`) :
  - Ajouter à `missingIds` les statuts dont `prestataireDetail` existe mais dont l’utilisateur n’a pas de nom significatif.
- Dans `_PrestataireDetailCache` :
  - Quand `getPrestataire` retourne un `Prestataire` avec utilisateur vide, ne pas le mettre en cache (ou le marquer) pour éviter de figer un nom vide.

## Validation

- Lancer l’app et publier un statut.
- Vérifier dans la page **Statuts & Annonces** que le nom de l’auteur correspond au prénom/nom réel et non à « Prestataire ».
- Vérifier le viewer plein écran et la barre de stories.
- Vérifier qu’un like/commentaire reçu en temps réel ne fait pas disparaître le nom.

## Risques

- Le helper `_utilisateurJson` peut absorber des clés inattendues si l’API ajoute des champs ; c’est volontairement défensif.
- `Prestataire.fromJson` est utilisé dans d’autres écrans (`home_screen`, `profile_screen`, etc.) ; l’ajout de clés candidates ne casse rien, ne fait qu’élargir la tolérance.
