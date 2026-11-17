# ProxiVox

Chat vocal de proximité pour World of Warcraft « Forever » 1.60.1 (`## Interface: 16001`).

Le volume de chaque participant suit la distance : proche = fort, loin = faible, très loin = muet,
et une flèche indique qui vous parle quand il est hors de votre champ de vision.

## Ce que fait l'addon

- Au premier lancement, une fenêtre de configuration demande votre accord : **rien n'est rejoint
  et aucune position n'est envoyée avant que vous ayez accepté**. Le refus est enregistré et
  l'addon reste inactif ; `/pvx setup` rouvre la fenêtre plus tard.
- Tout le monde rejoint automatiquement un canal de discussion personnalisé avec vocal,
  `ProxiVoxVoice`, masqué des fenêtres de discussion : c'est le point de rendez-vous des
  utilisateurs de l'addon.
- Votre position part sur ce canal en message addon caché, préfixe `ProxiVox` : toutes les 1,5 s
  quand vous bougez de plus d'un yard, toutes les 10 s à l'arrêt, jamais si les messages addon
  sortants sont restreints. En instance, la position est remplacée par `-` : les autres savent
  seulement que vous êtes là.
- Chaque auditeur règle localement le volume de chaque membre vocal :
  - plein régime jusqu'à `fullRange` mètres (10 par défaut) ;
  - fondu doux `(1 - t)^2` jusqu'à `maxRange` mètres (400 par défaut) ;
  - silence au-delà.
- Atténuation arrière : une voix venue de derrière est réduite linéairement de 1 (à 90°) à
  `behindFactor` (0,6 par défaut) à 180°.
- Flèche à l'écran pendant qu'un membre parle : elle tourne autour du centre de l'écran, pointe
  vers la personne et affiche son nom. Elle se rafraîchit au maximum toutes les 0,1 s, uniquement
  pendant que quelqu'un parle, sans animation. Elle ne s'affiche que si l'addon est actif dans le
  contexte courant ; quand plusieurs personnes parlent, la plus proche l'emporte.
- Instances : dans un contexte activé, les membres de votre groupe sont à plein volume et tous les
  autres sont muets. Dans un contexte désactivé (monde, donjon, raid, JcJ), l'addon ne touche plus
  aux volumes et remet tout le monde à plein volume.
- Morts : un auditeur vivant n'entend pas un mort ; deux morts s'entendent normalement ; un
  auditeur mort entend les vivants normalement.
- Pair inconnu ou silencieux depuis 30 s : muet (sauf membre du groupe dans une instance activée).
- Alerte de portée : quand un pair passe de hors portée à dans la portée maximale, un message
  « <nom> est à portée de voix » s'affiche une seule fois et un son est joué, jusqu'à ce qu'il
  ressorte de la portée.

## Installation

1. Copier le dossier `ProxiVox` dans
   `World of Warcraft\_forever_\Interface\AddOns\`.
2. Redémarrer le jeu ou `/reload`.
3. Vérifier que l'addon est activé à l'écran des addons.

Le vocal doit être activé dans les options du jeu. Au premier login, la fenêtre de configuration
s'ouvre : acceptez-la pour que ProxiVox rejoigne `ProxiVoxVoice` (le canal est rejoint
automatiquement ensuite).

## Premier lancement (assistant)

L'assistant s'ouvre au premier login, et à tout moment avec `/pvx setup` (les valeurs sont
pré-remplies avec les réglages enregistrés). Il se ferme uniquement par ses boutons :

1. **Bienvenue** : ProxiVox rejoint un canal caché `ProxiVoxVoice` avec le vocal et partage votre
   position avec les autres utilisateurs de l'addon (toutes les 1,5 s quand vous bougez). Chaque
   personne calcule les volumes de son côté. Incompatible avec ForeverVoice et Prox Voice Party.
   « Refuser » enregistre le refus et laisse l'addon coupé ; « Accepter » passe à la suite.
2. **Portée** : portée maximale (50 à 1000 m, pas de 10), plein volume jusqu'à (0 à 50 m, toujours
   ≤ portée maximale), voix derrière toi (0 à 100 %, pas de 5).
3. **Où l'activer** : Monde / Donjons / Raids / JcJ, et l'alerte quand quelqu'un arrive à portée.
4. **Vocal** : « Activer le vocal ProxiVox automatiquement » (`autoActivate`, activé par défaut).
   Ce réglage bascule le vocal du jeu sur `ProxiVoxVoice` quand vous êtes dedans : WoW ne garde
   qu'un seul canal vocal actif, donc cela remplace le vocal de groupe ou de guilde. L'activation
   n'est faite qu'une fois par session, et jamais si vous avez changé de canal entre-temps.
   « Terminer » enregistre tout, rejoint le canal et applique les volumes.

Les réglages ne sont écrits dans `ProxiVoxDB` qu'avec « Terminer » : « Précédent » et « Suivant »
travaillent sur un brouillon, donc quitter au milieu ne change rien. Le refus et l'accord sont
eux aussi enregistrés (`consent`) et ne sont plus redemandés à chaque login.

## Bouton minimap

Un bouton autour de la minimap (déplaçable, position sauvegardée), repris par MinimapButtonButton,
et une entrée dans le compartiment d'addons :

- clic gauche : ouvre les réglages (l'assistant) ;
- clic droit : active / désactive ProxiVox ;
- survol : état, connexion au vocal ProxiVox, nombre de joueurs à portée.

## Commandes

- `/pvx setup` : rouvre l'assistant (accord et réglages).
- `/pvx minimap on|off|reset` : affiche, cache ou replace le bouton minimap.
- `/pvx status` : canal rejoint, identifiant du canal vocal, pairs avec distance en mètres et
  volume calculé.
- `/pvx on` / `/pvx off` : active ou coupe l'addon (les volumes sont rendus à la normale). Sans
  accord enregistré, `/pvx on` ouvre l'assistant au lieu d'activer.
- `/pvx range <m>` : portée maximale en mètres (400 par défaut).
- `/pvx full <m>` : distance de plein régime en mètres (10 par défaut).
- `/pvx behind <0-1>` : facteur d'atténuation arrière (0,6 par défaut).
- `/pvx world|dungeon|raid|pvp on|off` : active ou coupe l'addon par contexte.
- `/pvx alert on|off` : alerte de portée.
- `/pvx debug` : votre `posA`/`posB`/orientation, puis pour chaque pair la distance et l'angle
  relatif en degrés (pour calibrer les axes en jeu).

Réglages sauvegardés dans `ProxiVoxDB` (`consent`, `setupDone`, `autoActivate`, portées,
contextes, alerte).

## Accord et confidentialité

Sans `consent = true`, ProxiVox ne rejoint aucun canal, n'envoie aucune position et ne touche à
aucun volume : `/pvx setup` est le seul moyen de donner l'accord. `consent` et `setupDone` ne sont
jamais remplis par les valeurs par défaut : une installation neuve les a à `nil`, donc l'assistant
s'ouvre. Refuser écrit `consent = false`, `enabled = false` et `setupDone = true`.

## Incompatibilités

ProxiVox n'est **pas** compatible avec **ForeverVoice** ni **Prox Voice Party** : ces addons
pilotent eux aussi les volumes des membres vocaux, et les deux réglages se battent en permanence.
ProxiVox affiche un avertissement au login si l'un des deux est chargé.

## Points non vérifiés en jeu

Vérifiés comme existants dans l'API (warcraft.wiki.gg) mais **pas** testés sur ce client :

- **Échelle du volume** : `C_VoiceChat.SetMemberVolume` attend peut-être 0..1, peut-être 0..100.
  Un seul réglage à changer dans `Voice.lua` : la constante `VOLUME_MAX` (1 par défaut).
- **Orientation des axes** : `UnitPosition` est traité comme `posA` = X (nord) et `posB` = Y
  (ouest), et `GetPlayerFacing` comme 0 = nord, croissant vers l'ouest. `/pvx debug` permet de
  vérifier les angles, et la flèche la plus simple à contrôler est « devant » (en haut de l'écran).
- **Canal personnalisé avec vocal** : `JoinChannelByName(name, nil, nil, true)` doit créer ou
  rejoindre un canal vocal sur Forever ; si le vocal n'est pas actif, aucun volume n'est appliqué.
- **Retrouver le canal vocal après un /reload** : `C_VoiceChat.GetActiveChannelID()` puis
  `C_VoiceChat.GetChannelForChannelType(Enum.ChatChannelType.Custom)` servent à retrouver
  `ProxiVoxVoice` quand l'évènement d'arrivée dans le canal ne se déclenche pas. Si `Enum` ou
  `GetChannelForChannelType` n'existent pas sur ce client, la recherche se limite au canal actif.
- **Assistant** : les gabarits `UIPanelButtonTemplate`, `OptionsSliderTemplate` et
  `UICheckButtonTemplate` sont utilisés s'ils existent ; sinon les contrôles sont créés sans
  gabarit (texte et valeurs restent fonctionnels, la mise en page est plus simple).
- **Texture de la flèche** : `Interface\Minimap\MiniMap-DeadArrow` et sa rotation d'origine.
- **Restauration** : quand un contexte est coupé, `ResetMemberVolume` n'est pas utilisée, les
  volumes sont remis à `VOLUME_MAX` un par un, ce qui écrase aussi les volumes réglés à la main
  pendant que l'addon tourne.
