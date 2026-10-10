local addonName, ns = ...

local L = setmetatable({}, {
    __index = function(t, k)
        local v = tostring(k)
        rawset(t, k, v)
        return v
    end,
})
ns.L = L

local LOCALE = GetLocale()

if LOCALE == "enUS" then return end

-- ============================================================================
-- GERMAN
-- ============================================================================
if LOCALE == "deDE" then

-- General --------------------------------------------------------------------
L["Random"] = "Zufällige"

-- Maps: Battlegrounds --------------------------------------------------------
L["Random Battleground"] = "Zufälliges Schlachtfeld"
L["Warsong Gulch"] = "Kriegshymnenschlucht"
L["The Battle for Gilneas"] = "Schlacht um Gilneas"
L["Eye of the Storm"] = "Auge des Sturms"
L["Arathi Basin"] = "Arathibecken"
L["Alterac Valley"] = "Alteractal"
L["Isle of Conquest"] = "Insel der Eroberung"
L["Battle for Wintergrasp"] = "Schlacht um Tausendwinter"
L["Ashran"] = "Ashran"

-- Maps: Arenas ---------------------------------------------------------------
L["Random Arena"] = "Zufällige Arena"
L["Ruins of Lordaeron"] = "Ruinen von Lordaeron"
L["Dalaran Sewers"] = "Kanalisation von Dalaran"
L["Tol'Viron Arena"] = "Arena der Tol'vir"
L["The Tiger's Peak"] = "Tigergipfel"
L["Black Rook Hold Arena"] = "Arena der Rabenwehr"
L["Nagrand Arena"] = "Arena von Nagrand"
L["Ashamane's Fall"] = "Ashamanes Sturz"
L["Blade's Edge Arena"] = "Arena des Schergrats"
L["Hook Point"] = "Hakenkap"
L["Mugambala"] = "Mugambala"
L["The Robodrome"] = "Das Robodrom"
L["Maldraxxus Coliseum"] = "Kolosseum von Maldraxxus"

-- Modes ----------------------------------------------------------------------
L["Spectator Mode"] = "Zuschauermodus"

-- Leaderboard UI -------------------------------------------------------------
L["Leaderboard"] = "Bestenliste"
L["Current Season"] = "Aktuelle Saison"
L["Last Updated"] = "Zuletzt aktualisiert"
L["Armory"] = "Arsenal"
L["Copy Armory Link"] = "Arsenal-Link kopieren"
L["Copied to clipboard."] = "In die Zwischenablage kopiert."

-- Error Messages: Group Validation ------------------------------------------
L["Your group needs %d more |4player:players; to join this battleground."] = "Eure Gruppe benötigt noch %d Spieler, um einem Schlachtfeld beitreten zu können."
L["Your group needs %d less |4player:players; to join this battleground."] = "Eure Gruppe enthält %d Spieler zu viel, um einem Schlachtfeld beitreten zu können."
L["You cannot start a War Game while in a suspended queue state."] = "Du kannst kein Kräftemessen starten, während du dich im Status der angehaltenen Warteschlange befindest."
L["You cannot start a War Game because one of your group members is dead."] = "Ihr könnt keine Kriegsspiele beginnen, da eines Eurer Gruppenmitglieder tot ist."
L["You cannot start a War Game because one of your group members is disconnected."] = "Ihr könnt keine Kriegsspiele beginnen, da eines Eurer Gruppenmitglieder vom Spiel getrennt wurde."
L["You cannot start a War Game because one of your group members is in instance group."] = "Ihr könnt keine Kriegsspiele beginnen, da eines Eurer Gruppenmitglieder in einer Instanzgruppe ist."
L["You cannot start a War Game because both party leaders are not in the same level range."] = "Eure Gruppe kann keine Kriegsspiele beginnen, da sich beide Gruppenleiter nicht im gleichen Stufenbereich befinden."

-- Error Messages: Friend Validation -----------------------------------------
L["This friend is playing World of Warcraft in a different region."] = "Dieser Freund spielt World of Warcraft in einer anderen Region."

-- Error Messages: War Game Validation ---------------------------------------
L["Select a Battle.net friend to challenge, or check Target."] = "Wählen Sie einen Battle.net-Freund heraus, um ihn zu Kriegsspielen herauszufordern, oder überprüfen Sie das Ziel."
L["Select a Battle.net friend to challenge first."] = "Wählen Sie zuerst einen Battle.net-Freund heraus, um ihn zu Kriegsspielen herauszufordern."
L["Select two Battle.net friends to start a War Game."] = "Wählen Sie zwei Battle.net-Freunde aus, um ein Kriegsspiel zu starten."
L["No eligible map found."] = "Keine geeignete Karte gefunden."
L["You have no target selected."] = "Sie haben kein Ziel ausgewählt."
L["You cannot challenge a friend who is in your group."] = "Ihr könnt keinen Freund herausfordern, der sich in Eurer Gruppe befindet."
L["You cannot start a War Game because %s's group size does not match yours."] = "Ihr könnt keine Kriegsspiele beginnen, da die Gruppengröße von %s nicht mit Eurer übereinstimmt."
L["You cannot start a War Game because %s's group is in a suspended queue state."] = "Ihr könnt keine Kriegsspiele beginnen, da die Gruppe von %s sich im Status der angehaltenen Warteschlange befindet."
L["You cannot start a War Game because %s's group has an active LFG listing."] = "Ihr könnt keine Kriegsspiele beginnen, da die Gruppe von %s einen aktiven LFG-Eintrag hat."
L["You cannot start a War Game because one of %s's group members is disconnected."] = "Ihr könnt keine Kriegsspiele beginnen, da ein Mitglied der Gruppe von %s vom Spiel getrennt wurde."
L["You cannot start a War Game because one of %s's group members is in instance group."] = "Ihr könnt keine Kriegsspiele beginnen, da ein Mitglied der Gruppe von %s in einer Instanzgruppe ist."
L["You cannot start a War Game because one of %s's group members is dead."] = "Ihr könnt keine Kriegsspiele beginnen, da ein Mitglied der Gruppe von %s tot ist."
L["You cannot start a War Game because %s's leader is not in your friend list (%s)."] = "Ihr könnt keine Kriegsspiele beginnen, da der Gruppenanführer von %s nicht in Eurer Freundesliste ist (%s)."
L["You cannot start a War Game because you and the group leader of %s are in different level ranges."] = "Ihr könnt keine Kriegsspiele beginnen, da Ihr und der Gruppenleiter von %s nicht im gleichen Stufenbereich seid."
L["You cannot start a War Game because %s and %s are in the same group."] = "Ihr könnt keine Kriegsspiele beginnen, da %s und %s in der gleichen Gruppe sind."
L["You cannot start a War Game because %s and %s have different group sizes."] = "Ihr könnt keine Kriegsspiele beginnen, da %s und %s unterschiedliche Gruppengrößen haben."
L["You cannot start a War Game because %s and %s are not in the same level range."] = "Ihr könnt keine Kriegsspiele beginnen, da %s und %s nicht im gleichen Stufenbereich sind."

-- Chat Messages --------------------------------------------------------------
L["War Game request sent to "] = "Kräftemessen-Anfrage gesendet an "

return
end

-- ============================================================================
-- SPANISH (EU)
-- ============================================================================
if LOCALE == "esES" then

-- General --------------------------------------------------------------------
L["Random"] = "Aleatorios"

-- Maps: Battlegrounds --------------------------------------------------------
L["Random Battleground"] = "Campo de Batalla Aleatorio"
L["Warsong Gulch"] = "Garganta Grito de Guerra"
L["The Battle for Gilneas"] = "La Batalla por Gilneas"
L["Eye of the Storm"] = "Ojo de la Tormenta"
L["Arathi Basin"] = "Cuenca de Arathi"
L["Alterac Valley"] = "Valle de Alterac"
L["Isle of Conquest"] = "Isla de la Conquista"
L["Battle for Wintergrasp"] = "Batalla por Conquista del Invierno"
L["Ashran"] = "Ashran"

-- Maps: Arenas ---------------------------------------------------------------
L["Random Arena"] = "Arena Aleatoria"
L["Ruins of Lordaeron"] = "Ruinas de Lordaeron"
L["Dalaran Sewers"] = "Cloacas de Dalaran"
L["Tol'Viron Arena"] = "Arena Tol'viron"
L["The Tiger's Peak"] = "La Cima del Tigre"
L["Black Rook Hold Arena"] = "Arena del Torreón Grajo Negro"
L["Nagrand Arena"] = "Arena de Nagrand"
L["Ashamane's Fall"] = "Caída de Crinceniza"
L["Blade's Edge Arena"] = "Arena Filospada"
L["Hook Point"] = "Puntagarfio"
L["Mugambala"] = "Mugambala"
L["The Robodrome"] = "Robotódromo"
L["Maldraxxus Coliseum"] = "Coliseo de Maldraxxus"

-- Modes ----------------------------------------------------------------------
L["Spectator Mode"] = "Modo espectador"

-- Leaderboard UI -------------------------------------------------------------
L["Leaderboard"] = "Tabla de clasificación"
L["Current Season"] = "Temporada actual"
L["Last Updated"] = "Última actualización"
L["Armory"] = "Arsenal"
L["Copy Armory Link"] = "Copiar enlace del Arsenal"
L["Copied to clipboard."] = "Copiado al portapapeles."

-- Error Messages: Group Validation ------------------------------------------
L["Your group needs %d more |4player:players; to join this battleground."] = "Tu grupo necesita %d |4jugador:jugadores; más para unirse a un campo de batalla."
L["Your group needs %d less |4player:players; to join this battleground."] = "Tu grupo necesita %d |4jugador:jugadores; menos para unirse a un campo de batalla."
L["You cannot start a War Game while in a suspended queue state."] = "No puedes iniciar un Juego de guerra mientras estás en estado de cola suspendida."
L["You cannot start a War Game because one of your group members is dead."] = "No puedes comenzar unos Juegos de guerra porque uno de los miembros de tu grupo está muerto."
L["You cannot start a War Game because one of your group members is disconnected."] = "No puedes comenzar unos Juegos de guerra porque uno de los miembros de tu grupo está desconectado."
L["You cannot start a War Game because one of your group members is in instance group."] = "No puedes comenzar unos Juegos de guerra porque uno de los miembros de tu grupo está en un grupo de instancia."
L["You cannot start a War Game because both party leaders are not in the same level range."] = "Tu grupo no puede comenzar unos Juegos de guerra porque ambos líderes de grupo no están en el mismo rango de niveles."

-- Error Messages: Friend Validation -----------------------------------------
L["This friend is playing World of Warcraft in a different region."] = "Este amigo está jugando a World of Warcraft en una región diferente."

-- Error Messages: War Game Validation ---------------------------------------
L["Select a Battle.net friend to challenge, or check Target."] = "Selecciona un amigo de Battle.net para desafiar, o verifica el Objetivo."
L["Select a Battle.net friend to challenge first."] = "Primero selecciona un amigo de Battle.net para desafiar."
L["Select two Battle.net friends to start a War Game."] = "Selecciona dos amigos de Battle.net para iniciar un Juego de guerra."
L["No eligible map found."] = "No se encontró ningún mapa elegible."
L["You have no target selected."] = "No tienes ningún objetivo seleccionado."
L["You cannot challenge a friend who is in your group."] = "No puedes desafiar a un amigo que está en tu grupo."
L["You cannot start a War Game because %s's group size does not match yours."] = "No puedes comenzar unos Juegos de guerra porque el tamaño del grupo de %s no coincide con el tuyo."
L["You cannot start a War Game because %s's group is in a suspended queue state."] = "No puedes comenzar unos Juegos de guerra porque el grupo de %s está en estado de cola suspendida."
L["You cannot start a War Game because %s's group has an active LFG listing."] = "No puedes comenzar unos Juegos de guerra porque el grupo de %s tiene una lista de LFG activa."
L["You cannot start a War Game because one of %s's group members is disconnected."] = "No puedes comenzar unos Juegos de guerra porque uno de los miembros del grupo de %s está desconectado."
L["You cannot start a War Game because one of %s's group members is in instance group."] = "No puedes comenzar unos Juegos de guerra porque uno de los miembros del grupo de %s está en un grupo de instancia."
L["You cannot start a War Game because one of %s's group members is dead."] = "No puedes comenzar unos Juegos de guerra porque uno de los miembros del grupo de %s está muerto."
L["You cannot start a War Game because %s's leader is not in your friend list (%s)."] = "No puedes comenzar unos Juegos de guerra porque el líder del grupo de %s no está en tu lista de amigos (%s)."
L["You cannot start a War Game because you and the group leader of %s are in different level ranges."] = "No puedes comenzar unos Juegos de guerra porque tú y el líder del grupo de %s no estáis en el mismo rango de niveles."
L["You cannot start a War Game because %s and %s are in the same group."] = "No puedes comenzar unos Juegos de guerra porque %s y %s están en el mismo grupo."
L["You cannot start a War Game because %s and %s have different group sizes."] = "No puedes comenzar unos Juegos de guerra porque %s y %s tienen tamaños de grupo diferentes."
L["You cannot start a War Game because %s and %s are not in the same level range."] = "No puedes comenzar unos Juegos de guerra porque %s y %s no están en el mismo rango de niveles."

-- Chat Messages --------------------------------------------------------------
L["War Game request sent to "] = "Solicitud de Juegos de guerra enviada a "

return
end

-- ============================================================================
-- SPANISH (LATIN AMERICA)
-- ============================================================================
if LOCALE == "esMX" then

-- General --------------------------------------------------------------------
L["Random"] = "Aleatorios"

-- Maps: Battlegrounds --------------------------------------------------------
L["Random Battleground"] = "Campo de batalla aleatorio"
L["Warsong Gulch"] = "Garganta Grito de Guerra"
L["The Battle for Gilneas"] = "La Batalla por Gilneas"
L["Eye of the Storm"] = "Ojo de la Tormenta"
L["Arathi Basin"] = "Cuenca de Arathi"
L["Alterac Valley"] = "Valle de Alterac"
L["Isle of Conquest"] = "Isla de la Conquista"
L["Battle for Wintergrasp"] = "Batalla por Conquista del Invierno"
L["Ashran"] = "Ashran"

-- Maps: Arenas ---------------------------------------------------------------
L["Random Arena"] = "Arena Aleatoria"
L["Ruins of Lordaeron"] = "Ruinas de Lordaeron"
L["Dalaran Sewers"] = "Cloacas de Dalaran"
L["Tol'Viron Arena"] = "Arena Tol'viron"
L["The Tiger's Peak"] = "La Cima del Tigre"
L["Black Rook Hold Arena"] = "Arena del Fuerte Torre Oscura"
L["Nagrand Arena"] = "Arena de Nagrand"
L["Ashamane's Fall"] = "Caída de Ashamane"
L["Blade's Edge Arena"] = "Arena Filospada"
L["Hook Point"] = "Punta Garfio"
L["Mugambala"] = "Mugambala"
L["The Robodrome"] = "El Robódromo"
L["Maldraxxus Coliseum"] = "Coliseo de Maldraxxus"

-- Modes ----------------------------------------------------------------------
L["Spectator Mode"] = "Modo espectador"

-- Leaderboard UI -------------------------------------------------------------
L["Leaderboard"] = "Tabla de clasificación"
L["Current Season"] = "Temporada actual"
L["Last Updated"] = "Última actualización"
L["Armory"] = "Arsenal"
L["Copy Armory Link"] = "Copiar enlace del Arsenal"
L["Copied to clipboard."] = "Copiado al portapapeles."

-- Error Messages: Group Validation ------------------------------------------
L["Your group needs %d more |4player:players; to join this battleground."] = "Tu grupo necesita %d |4jugador:jugadores; más para unirse a un campo de batalla."
L["Your group needs %d less |4player:players; to join this battleground."] = "Tu grupo necesita %d |4jugador:jugadores; menos para unirse a un campo de batalla."
L["You cannot start a War Game while in a suspended queue state."] = "No puedes iniciar un Juego de guerra mientras estás en estado de cola suspendida."
L["You cannot start a War Game because one of your group members is dead."] = "No puedes comenzar unos Juegos de guerra porque uno de los miembros de tu grupo está muerto."
L["You cannot start a War Game because one of your group members is disconnected."] = "No puedes comenzar unos Juegos de guerra porque uno de los miembros de tu grupo está desconectado."
L["You cannot start a War Game because one of your group members is in instance group."] = "No puedes comenzar unos Juegos de guerra porque uno de los miembros de tu grupo está en un grupo de instancia."
L["You cannot start a War Game because both party leaders are not in the same level range."] = "Tu grupo no puede comenzar unos Juegos de guerra porque ambos líderes de grupo no están en el mismo rango de niveles."

-- Error Messages: Friend Validation -----------------------------------------
L["This friend is playing World of Warcraft in a different region."] = "Este amigo está jugando a World of Warcraft en una región diferente."

-- Error Messages: War Game Validation ---------------------------------------
L["Select a Battle.net friend to challenge, or check Target."] = "Selecciona un amigo de Battle.net para desafiar, o verifica el Objetivo."
L["Select a Battle.net friend to challenge first."] = "Primero selecciona un amigo de Battle.net para desafiar."
L["Select two Battle.net friends to start a War Game."] = "Selecciona dos amigos de Battle.net para iniciar un Juego de guerra."
L["No eligible map found."] = "No se encontró ningún mapa elegible."
L["You have no target selected."] = "No tienes ningún objetivo seleccionado."
L["You cannot challenge a friend who is in your group."] = "No puedes desafiar a un amigo que está en tu grupo."
L["You cannot start a War Game because %s's group size does not match yours."] = "No puedes comenzar unos Juegos de guerra porque el tamaño del grupo de %s no coincide con el tuyo."
L["You cannot start a War Game because %s's group is in a suspended queue state."] = "No puedes comenzar unos Juegos de guerra porque el grupo de %s está en estado de cola suspendida."
L["You cannot start a War Game because %s's group has an active LFG listing."] = "No puedes comenzar unos Juegos de guerra porque el grupo de %s tiene una lista de LFG activa."
L["You cannot start a War Game because one of %s's group members is disconnected."] = "No puedes comenzar unos Juegos de guerra porque uno de los miembros del grupo de %s está desconectado."
L["You cannot start a War Game because one of %s's group members is in instance group."] = "No puedes comenzar unos Juegos de guerra porque uno de los miembros del grupo de %s está en un grupo de instancia."
L["You cannot start a War Game because one of %s's group members is dead."] = "No puedes comenzar unos Juegos de guerra porque uno de los miembros del grupo de %s está muerto."
L["You cannot start a War Game because %s's leader is not in your friend list (%s)."] = "No puedes comenzar unos Juegos de guerra porque el líder del grupo de %s no está en tu lista de amigos (%s)."
L["You cannot start a War Game because you and the group leader of %s are in different level ranges."] = "No puedes comenzar unos Juegos de guerra porque tú y el líder del grupo de %s no están en el mismo rango de niveles."
L["You cannot start a War Game because %s and %s are in the same group."] = "No puedes comenzar unos Juegos de guerra porque %s y %s están en el mismo grupo."
L["You cannot start a War Game because %s and %s have different group sizes."] = "No puedes comenzar unos Juegos de guerra porque %s y %s tienen tamaños de grupo diferentes."
L["You cannot start a War Game because %s and %s are not in the same level range."] = "No puedes comenzar unos Juegos de guerra porque %s y %s no están en el mismo rango de niveles."

-- Chat Messages --------------------------------------------------------------
L["War Game request sent to "] = "Solicitud de Juegos de guerra enviada a "

return
end

-- ============================================================================
-- FRENCH
-- ============================================================================
if LOCALE == "frFR" then

-- General --------------------------------------------------------------------
L["Random"] = "Aléatoire"

-- Maps: Battlegrounds --------------------------------------------------------
L["Random Battleground"] = "Champ de bataille aléatoire"
L["Warsong Gulch"] = "Goulet des Chanteguerres"
L["The Battle for Gilneas"] = "La bataille de Gilnéas"
L["Eye of the Storm"] = "L'Œil du cyclone"
L["Arathi Basin"] = "Bassin Arathi"
L["Alterac Valley"] = "Vallée d'Alterac"
L["Isle of Conquest"] = "Île des Conquérants"
L["Battle for Wintergrasp"] = "Bataille de Joug-d'Hiver"
L["Ashran"] = "A'shran"

-- Maps: Arenas ---------------------------------------------------------------
L["Random Arena"] = "Arène aléatoire"
L["Ruins of Lordaeron"] = "Ruines de Lordaeron"
L["Dalaran Sewers"] = "Égouts de Dalaran"
L["Tol'Viron Arena"] = "Arène Tol'viron"
L["The Tiger's Peak"] = "Le croc du Tigre"
L["Black Rook Hold Arena"] = "Arène du bastion du Freux"
L["Nagrand Arena"] = "Arène de Nagrand"
L["Ashamane's Fall"] = "Chute d'Ashamane"
L["Blade's Edge Arena"] = "Arène des Tranchantes"
L["Hook Point"] = "Pointe du Crochet"
L["Mugambala"] = "Mugambala"
L["The Robodrome"] = "Le Robodrome"
L["Maldraxxus Coliseum"] = "Maldraxxus Coliseum"

-- Modes ----------------------------------------------------------------------
L["Spectator Mode"] = "Mode spectateur"

-- Leaderboard UI -------------------------------------------------------------
L["Leaderboard"] = "Classement"
L["Current Season"] = "Saison en cours"
L["Last Updated"] = "Dernière mise à jour"
L["Armory"] = "Armurerie"
L["Copy Armory Link"] = "Copier le lien de l'Armurerie"
L["Copied to clipboard."] = "Copié dans le presse-papiers."

-- Error Messages: Group Validation ------------------------------------------
L["Your group needs %d more |4player:players; to join this battleground."] = "Votre groupe doit compter %d |4joueur:joueurs; de plus pour rejoindre un champ de bataille."
L["Your group needs %d less |4player:players; to join this battleground."] = "Votre groupe doit compter %d |4joueur:joueurs; de moins pour rejoindre un champ de bataille."
L["You cannot start a War Game while in a suspended queue state."] = "Tu ne peux pas lancer un Jeu de guerre pendant que tu es en état de file d'attente suspendue."
L["You cannot start a War Game because one of your group members is dead."] = "Vous ne pouvez pas commencer les Jeux de guerre car l'un des membres de votre groupe est mort."
L["You cannot start a War Game because one of your group members is disconnected."] = "Vous ne pouvez pas commencer les Jeux de guerre car l'un des membres de votre groupe est déconnecté."
L["You cannot start a War Game because one of your group members is in instance group."] = "Vous ne pouvez pas commencer les Jeux de guerre car l'un des membres de votre groupe est dans un groupe d'instance."
L["You cannot start a War Game because both party leaders are not in the same level range."] = "Votre groupe ne peut pas commencer les Jeux de guerre car les deux chefs de groupe ne font pas partie de la même fourchette de niveaux."

-- Error Messages: Friend Validation -----------------------------------------
L["This friend is playing World of Warcraft in a different region."] = "Cet ami joue à World of Warcraft dans un secteur différent."

-- Error Messages: War Game Validation ---------------------------------------
L["Select a Battle.net friend to challenge, or check Target."] = "Sélectionnez un ami Battle.net à défier, ou vérifiez la Cible."
L["Select a Battle.net friend to challenge first."] = "Sélectionnez d'abord un ami Battle.net à défier."
L["Select two Battle.net friends to start a War Game."] = "Sélectionnez deux amis Battle.net pour lancer un Jeu de guerre."
L["No eligible map found."] = "Aucune carte admissible trouvée."
L["You have no target selected."] = "Vous n'avez pas de cible sélectionnée."
L["You cannot challenge a friend who is in your group."] = "Vous ne pouvez pas défier un ami qui se trouve dans votre groupe."
L["You cannot start a War Game because %s's group size does not match yours."] = "Vous ne pouvez pas commencer les Jeux de guerre car la taille du groupe de %s ne correspond pas à la vôtre."
L["You cannot start a War Game because %s's group is in a suspended queue state."] = "Vous ne pouvez pas commencer les Jeux de guerre car le groupe de %s est en état de file d'attente suspendue."
L["You cannot start a War Game because %s's group has an active LFG listing."] = "Vous ne pouvez pas commencer les Jeux de guerre car le groupe de %s a une liste LFG active."
L["You cannot start a War Game because one of %s's group members is disconnected."] = "Vous ne pouvez pas commencer les Jeux de guerre car un membre du groupe de %s est déconnecté."
L["You cannot start a War Game because one of %s's group members is in instance group."] = "Vous ne pouvez pas commencer les Jeux de guerre car un membre du groupe de %s est dans un groupe d'instance."
L["You cannot start a War Game because one of %s's group members is dead."] = "Vous ne pouvez pas commencer les Jeux de guerre car un membre du groupe de %s est mort."
L["You cannot start a War Game because %s's leader is not in your friend list (%s)."] = "Vous ne pouvez pas commencer les Jeux de guerre car le chef de groupe de %s n'est pas dans votre liste d'amis (%s)."
L["You cannot start a War Game because you and the group leader of %s are in different level ranges."] = "Vous ne pouvez pas commencer les Jeux de guerre car vous et le chef de groupe de %s ne faites pas partie de la même fourchette de niveaux."
L["You cannot start a War Game because %s and %s are in the same group."] = "Vous ne pouvez pas commencer les Jeux de guerre car %s et %s sont dans le même groupe."
L["You cannot start a War Game because %s and %s have different group sizes."] = "Vous ne pouvez pas commencer les Jeux de guerre car %s et %s ont des tailles de groupe différentes."
L["You cannot start a War Game because %s and %s are not in the same level range."] = "Vous ne pouvez pas commencer les Jeux de guerre car %s et %s ne sont pas dans la même fourchette de niveaux."

-- Chat Messages --------------------------------------------------------------
L["War Game request sent to "] = "Demande de Jeux de guerre envoyée à "

return
end

-- ============================================================================
-- ITALIAN
-- ============================================================================
if LOCALE == "itIT" then

-- General --------------------------------------------------------------------
L["Random"] = "Casuale"

-- Maps: Battlegrounds --------------------------------------------------------
L["Random Battleground"] = "Campo di battaglia casuale"
L["Warsong Gulch"] = "Forra dei Cantaguerra"
L["The Battle for Gilneas"] = "Battaglia per Gilneas"
L["Eye of the Storm"] = "Occhio del Ciclone"
L["Arathi Basin"] = "Bacino d'Arathi"
L["Alterac Valley"] = "Valle d'Alterac"
L["Isle of Conquest"] = "Isola della Conquista"
L["Battle for Wintergrasp"] = "Battaglia per Lungoinverno"
L["Ashran"] = "Ashran"

-- Maps: Arenas ---------------------------------------------------------------
L["Random Arena"] = "Arena casuale"
L["Ruins of Lordaeron"] = "Rovine di Lordaeron"
L["Dalaran Sewers"] = "Fogne di Dalaran"
L["Tol'Viron Arena"] = "Arena Tol'viron"
L["The Tiger's Peak"] = "Picco della Tigre"
L["Black Rook Hold Arena"] = "Arena del Forte Corvonero"
L["Nagrand Arena"] = "Arena di Nagrand"
L["Ashamane's Fall"] = "Caduta di Grigiomanto"
L["Blade's Edge Arena"] = "Arena di Spinaguzza"
L["Hook Point"] = "Presidio della Pesca"
L["Mugambala"] = "Mugambala"
L["The Robodrome"] = "Robodromo"
L["Maldraxxus Coliseum"] = "Maldraxxus Coliseum"

-- Modes ----------------------------------------------------------------------
L["Spectator Mode"] = "Modalità spettatore"

-- Leaderboard UI -------------------------------------------------------------
L["Leaderboard"] = "Classifica"
L["Current Season"] = "Stagione corrente"
L["Last Updated"] = "Ultimo aggiornamento"
L["Armory"] = "Armeria"
L["Copy Armory Link"] = "Copia link dell'Armeria"
L["Copied to clipboard."] = "Copiato negli appunti."

-- Error Messages: Group Validation ------------------------------------------
L["Your group needs %d more |4player:players; to join this battleground."] = "Il tuo gruppo ha bisogno di %d |4giocatore:giocatori; in più per unirsi a un campo di battaglia."
L["Your group needs %d less |4player:players; to join this battleground."] = "Il tuo gruppo ha bisogno di %d |4giocatore:giocatori; in meno per unirsi a un campo di battaglia."
L["You cannot start a War Game while in a suspended queue state."] = "Non puoi avviare una Prova di guerra mentre sei in stato di coda sospesa."
L["You cannot start a War Game because one of your group members is dead."] = "Non puoi iniziare le Prove di guerra perché uno dei membri del tuo gruppo è morto."
L["You cannot start a War Game because one of your group members is disconnected."] = "Non puoi iniziare le Prove di guerra se un membro del tuo gruppo è disconnesso."
L["You cannot start a War Game because one of your group members is in instance group."] = "Non puoi iniziare le Prove di guerra perché uno dei membri del tuo gruppo è in un gruppo di istanza."
L["You cannot start a War Game because both party leaders are not in the same level range."] = "Il tuo gruppo non può iniziare le Prove di guerra perché entrambi i capigruppo non sono nello stesso intervallo di livello."

-- Error Messages: Friend Validation -----------------------------------------
L["This friend is playing World of Warcraft in a different region."] = "Questo amico sta giocando a World of Warcraft in una regione diversa."

-- Error Messages: War Game Validation ---------------------------------------
L["Select a Battle.net friend to challenge, or check Target."] = "Seleziona un amico Battle.net da sfidare, o controlla l'Obiettivo."
L["Select a Battle.net friend to challenge first."] = "Seleziona prima un amico Battle.net da sfidare."
L["Select two Battle.net friends to start a War Game."] = "Seleziona due amici Battle.net per avviare una Prova di guerra."
L["No eligible map found."] = "Nessuna mappa idonea trovata."
L["You have no target selected."] = "Non hai un bersaglio selezionato."
L["You cannot challenge a friend who is in your group."] = "Non puoi sfidare un amico che fa parte del tuo gruppo."
L["You cannot start a War Game because %s's group size does not match yours."] = "Non puoi iniziare le Prove di guerra perché la dimensione del gruppo di %s non corrisponde alla tua."
L["You cannot start a War Game because %s's group is in a suspended queue state."] = "Non puoi iniziare le Prove di guerra perché il gruppo di %s è in stato di coda sospesa."
L["You cannot start a War Game because %s's group has an active LFG listing."] = "Non puoi iniziare le Prove di guerra perché il gruppo di %s ha una lista LFG attiva."
L["You cannot start a War Game because one of %s's group members is disconnected."] = "Non puoi iniziare le Prove di guerra perché un membro del gruppo di %s è disconnesso."
L["You cannot start a War Game because one of %s's group members is in instance group."] = "Non puoi iniziare le Prove di guerra perché un membro del gruppo di %s è in un gruppo di istanza."
L["You cannot start a War Game because one of %s's group members is dead."] = "Non puoi iniziare le Prove di guerra perché un membro del gruppo di %s è morto."
L["You cannot start a War Game because %s's leader is not in your friend list (%s)."] = "Non puoi iniziare le Prove di guerra perché il capogruppo di %s non è nella tua lista amici (%s)."
L["You cannot start a War Game because you and the group leader of %s are in different level ranges."] = "Non puoi iniziare le Prove di guerra perché tu e il capogruppo di %s non siete nello stesso intervallo di livello."
L["You cannot start a War Game because %s and %s are in the same group."] = "Non puoi iniziare le Prove di guerra perché %s e %s sono nello stesso gruppo."
L["You cannot start a War Game because %s and %s have different group sizes."] = "Non puoi iniziare le Prove di guerra perché %s e %s hanno dimensioni di gruppo diverse."
L["You cannot start a War Game because %s and %s are not in the same level range."] = "Non puoi iniziare le Prove di guerra perché %s e %s non sono nello stesso intervallo di livello."

-- Chat Messages --------------------------------------------------------------
L["War Game request sent to "] = "Richiesta di Prove di guerra inviata a "

return
end

-- ============================================================================
-- BRAZILIAN PORTUGUESE
-- ============================================================================
if LOCALE == "ptBR" then

-- General --------------------------------------------------------------------
L["Random"] = "Aleatórios"

-- Maps: Battlegrounds --------------------------------------------------------
L["Random Battleground"] = "Campo de Batalha aleatório"
L["Warsong Gulch"] = "Ravina Brado Guerreiro"
L["The Battle for Gilneas"] = "A Batalha por Guilnéas"
L["Eye of the Storm"] = "Olho da Tormenta"
L["Arathi Basin"] = "Bacia Arathi"
L["Alterac Valley"] = "Vale Alterac"
L["Isle of Conquest"] = "Ilha da Conquista"
L["Battle for Wintergrasp"] = "Batalha por Invérnia"
L["Ashran"] = "Ashran"

-- Maps: Arenas ---------------------------------------------------------------
L["Random Arena"] = "Arena Aleatória"
L["Ruins of Lordaeron"] = "Ruínas de Lordaeron"
L["Dalaran Sewers"] = "Esgotos de Dalaran"
L["Tol'Viron Arena"] = "Arena Tol'viron"
L["The Tiger's Peak"] = "O Pico do Tigre"
L["Black Rook Hold Arena"] = "Arena do Castelo Corvo Negro"
L["Nagrand Arena"] = "Arena de Nagrand"
L["Ashamane's Fall"] = "Queda de Ashamane"
L["Blade's Edge Arena"] = "Arena da Lâmina Afiada"
L["Hook Point"] = "Ponta do Gancho"
L["Mugambala"] = "Mugambala"
L["The Robodrome"] = "Robódromo"
L["Maldraxxus Coliseum"] = "Coliseu de Maldraxxus"

-- Modes ----------------------------------------------------------------------
L["Spectator Mode"] = "Modo espectador"

-- Leaderboard UI -------------------------------------------------------------
L["Leaderboard"] = "Classificação"
L["Current Season"] = "Temporada atual"
L["Last Updated"] = "Última atualização"
L["Armory"] = "Arsenal"
L["Copy Armory Link"] = "Copiar link do Arsenal"
L["Copied to clipboard."] = "Copiado para a área de transferência."

-- Error Messages: Group Validation ------------------------------------------
L["Your group needs %d more |4player:players; to join this battleground."] = "Seu grupo precisa de mais %d |4jogador:jogadores; para participar de um Campo de Batalha."
L["Your group needs %d less |4player:players; to join this battleground."] = "Seu grupo precisa ter %d |4jogador:jogadores; a menos para participar de um Campo de Batalha."
L["You cannot start a War Game while in a suspended queue state."] = "Não é possível iniciar um Jogo de guerra enquanto estiver em estado de fila suspensa."
L["You cannot start a War Game because one of your group members is dead."] = "Você não pode entrar nos Jogos de Guerra porque um dos membros do seu grupo está morto."
L["You cannot start a War Game because one of your group members is disconnected."] = "Você não pode entrar nos Jogos de Guerra porque um dos membros do seu grupo está desconectado."
L["You cannot start a War Game because one of your group members is in instance group."] = "Você não pode entrar nos Jogos de Guerra porque um dos membros do seu grupo está em um grupo de instância."
L["You cannot start a War Game because both party leaders are not in the same level range."] = "Seu grupo não pode entrar nos Jogos de guerra, a menos que ambos os líderes de grupo estejam no mesmo intervalo de nível."

-- Error Messages: Friend Validation -----------------------------------------
L["This friend is playing World of Warcraft in a different region."] = "Este amigo está jogando World of Warcraft em uma região diferente."

-- Error Messages: War Game Validation ---------------------------------------
L["Select a Battle.net friend to challenge, or check Target."] = "Selecione um amigo Battle.net para desafiar ou verifique o Alvo."
L["Select a Battle.net friend to challenge first."] = "Selecione primeiro um amigo Battle.net para desafiar."
L["Select two Battle.net friends to start a War Game."] = "Selecione dois amigos Battle.net para iniciar um Jogo de Guerra."
L["No eligible map found."] = "Nenhum mapa elegível encontrado."
L["You have no target selected."] = "Você não tem um alvo selecionado."
L["You cannot challenge a friend who is in your group."] = "Você não pode desafiar um amigo que está no seu grupo."
L["You cannot start a War Game because %s's group size does not match yours."] = "Você não pode entrar nos Jogos de Guerra porque o tamanho do grupo de %s não corresponde ao seu."
L["You cannot start a War Game because %s's group is in a suspended queue state."] = "Você não pode entrar nos Jogos de Guerra porque o grupo de %s está em estado de fila suspensa."
L["You cannot start a War Game because %s's group has an active LFG listing."] = "Você não pode entrar nos Jogos de Guerra porque o grupo de %s tem uma listagem LFG ativa."
L["You cannot start a War Game because one of %s's group members is disconnected."] = "Você não pode entrar nos Jogos de Guerra porque um membro do grupo de %s está desconectado."
L["You cannot start a War Game because one of %s's group members is in instance group."] = "Você não pode entrar nos Jogos de Guerra porque um membro do grupo de %s está em um grupo de instância."
L["You cannot start a War Game because one of %s's group members is dead."] = "Você não pode entrar nos Jogos de Guerra porque um membro do grupo de %s está morto."
L["You cannot start a War Game because %s's leader is not in your friend list (%s)."] = "Você não pode entrar nos Jogos de Guerra porque o líder do grupo de %s não está na sua lista de amigos (%s)."
L["You cannot start a War Game because you and the group leader of %s are in different level ranges."] = "Você não pode entrar nos Jogos de Guerra porque você e o líder do grupo de %s não estão no mesmo intervalo de nível."
L["You cannot start a War Game because %s and %s are in the same group."] = "Você não pode entrar nos Jogos de Guerra porque %s e %s estão no mesmo grupo."
L["You cannot start a War Game because %s and %s have different group sizes."] = "Você não pode entrar nos Jogos de Guerra porque %s e %s têm tamanhos de grupo diferentes."
L["You cannot start a War Game because %s and %s are not in the same level range."] = "Você não pode entrar nos Jogos de Guerra porque %s e %s não estão no mesmo intervalo de nível."

-- Chat Messages --------------------------------------------------------------
L["War Game request sent to "] = "Solicitação de Jogos de Guerra enviada para "

return
end

-- ============================================================================
-- RUSSIAN
-- ============================================================================
if LOCALE == "ruRU" then

-- General --------------------------------------------------------------------
L["Random"] = "Случайные"

-- Maps: Battlegrounds --------------------------------------------------------
L["Random Battleground"] = "Случайное поле боя"
L["Warsong Gulch"] = "Ущелье Песни Войны"
L["The Battle for Gilneas"] = "Битва за Гилнеас"
L["Eye of the Storm"] = "Око Бури"
L["Arathi Basin"] = "Низина Арати"
L["Deepwind Gorge"] = "Каньон Суровых Ветров"
L["Alterac Valley"] = "Альтеракская долина"
L["Isle of Conquest"] = "Остров Завоеваний"
L["Battle for Wintergrasp"] = "Битва за озеро Ледяных Оков"
L["Ashran"] = "Ашран"

-- Maps: Arenas ---------------------------------------------------------------
L["Random Arena"] = "Случайная арена"
L["Ruins of Lordaeron"] = "Руины Лордерона"
L["Dalaran Sewers"] = "Стоки Даларана"
L["Tol'Viron Arena"] = "Арена Тол'вир"
L["The Tiger's Peak"] = "Пик Тигра"
L["Black Rook Hold Arena"] = "Арена крепости Черной Ладьи"
L["Nagrand Arena"] = "Арена Награнда"
L["Ashamane's Fall"] = "Последнее пристанище Пеплошкурой"
L["Blade's Edge Arena"] = "Арена Острогорья"
L["Hook Point"] = "Большой Крюк"
L["Mugambala"] = "Мугамбала"
L["The Robodrome"] = "Рободром"
L["Maldraxxus Coliseum"] = "Колизей Малдраксуса"

-- Modes ----------------------------------------------------------------------
L["Spectator Mode"] = "Режим наблюдателя"

-- Leaderboard UI -------------------------------------------------------------
L["Leaderboard"] = "Таблица лидеров"
L["Current Season"] = "Текущий сезон"
L["Last Updated"] = "Последнее обновление"
L["Armory"] = "Оружейная"
L["Copy Armory Link"] = "Копировать ссылку Оружейной"
L["Copied to clipboard."] = "Скопировано в буфер обмена."

-- Error Messages: Group Validation ------------------------------------------
L["Your group needs %d more |4player:players; to join this battleground."] = "В вашей группе должно быть на %d |4игрока:игрока:игроков; больше, чтобы она могла попасть на поле боя."
L["Your group needs %d less |4player:players; to join this battleground."] = "В вашей группе должно быть на %d |4игрока:игрока:игроков; меньше, чтобы она могла попасть на поле боя."
L["You cannot start a War Game while in a suspended queue state."] = "Ваша группа не может начать маневры, находясь в состоянии приостановленной очереди."
L["You cannot start a War Game because one of your group members is dead."] = "Ваша группа не может начать маневры, так как один из её участников мёртв."
L["You cannot start a War Game because one of your group members is disconnected."] = "Ваша группа не может начать маневры, так как один из её участников потерял связь с сервером."
L["You cannot start a War Game because one of your group members is in instance group."] = "Ваша группа не может начать маневры, так как один из её участников находится в группе подземелья."
L["You cannot start a War Game because both party leaders are not in the same level range."] = "Ваша группа не может начать маневры, так как оба лидера группы относятся к разным уровневым диапазонам."

-- Error Messages: Friend Validation -----------------------------------------
L["This friend is playing World of Warcraft in a different region."] = "Этот друг играет в World of Warcraft в другом регионе."

-- Error Messages: War Game Validation ---------------------------------------
L["Select a Battle.net friend to challenge, or check Target."] = "Выберите Battle.net друга, с которым хотите сразиться, или же отметьте Цель"
L["Select a Battle.net friend to challenge first."] = "Сначала выберите Battle.net друга, с которым хотите сразиться."
L["Select two Battle.net friends to start a War Game."] = "Выберите двух друзей Battle.net, чтобы начать маневры."
L["No eligible map found."] = "Подходящее поле боя не найдено."
L["You have no target selected."] = "У вас не выбрана цель."
L["You cannot challenge a friend who is in your group."] = "Вы не можете вызвать на маневры друга, который находится в вашей группе."
L["You cannot start a War Game because %s's group size does not match yours."] = "Ваша группа не может начать маневры, так как размер группы %s не совпадает с вашим."
L["You cannot start a War Game because %s's group is in a suspended queue state."] = "Ваша группа не может начать маневры, так как группа %s находится в состоянии приостановленной очереди."
L["You cannot start a War Game because %s's group has an active LFG listing."] = "Ваша группа не может начать маневры, так как у группы %s есть активная запись в заранее собранных группах."
L["You cannot start a War Game because one of %s's group members is disconnected."] = "Ваша группа не может начать маневры, так как один из участников группы %s потерял связь с сервером."
L["You cannot start a War Game because one of %s's group members is in instance group."] = "Ваша группа не может начать маневры, так как один из участников группы %s находится в группе подземелья."
L["You cannot start a War Game because one of %s's group members is dead."] = "Ваша группа не может начать маневры, так как один из участников группы %s мёртв."
L["You cannot start a War Game because %s's leader is not in your friend list (%s)."] = "Ваша группа не может начать маневры, так как лидер группы %s не в вашем списке друзей (%s)."
L["You cannot start a War Game because you and the group leader of %s are in different level ranges."] = "Ваша группа не может начать маневры, так как вы и лидер группы %s относитесь к разным уровневым диапазонам."
L["You cannot start a War Game because %s and %s are in the same group."] = "Ваша группа не может начать маневры, так как %s и %s находятся в одной группе."
L["You cannot start a War Game because %s and %s have different group sizes."] = "Ваша группа не может начать маневры, так как у %s и %s разный размер группы."
L["You cannot start a War Game because %s and %s are not in the same level range."] = "Ваша группа не может начать маневры, так как %s и %s относятся к разным уровневым диапазонам."

-- Chat Messages --------------------------------------------------------------
L["War Game request sent to "] = "Запрос на маневры отправлен "

return
end

-- ============================================================================
-- KOREAN
-- ============================================================================
if LOCALE == "koKR" then

-- General --------------------------------------------------------------------
L["Random"] = "무작위"

-- Maps: Battlegrounds --------------------------------------------------------
L["Random Battleground"] = "무작위 전장"
L["Warsong Gulch"] = "전쟁노래 협곡"
L["Twin Peaks"] = "쌍둥이 봉우리"
L["The Battle for Gilneas"] = "길니아스 전투지"
L["Eye of the Storm"] = "폭풍의 눈"
L["Arathi Basin"] = "아라시 분지"
L["Alterac Valley"] = "알터랙 계곡"
L["Isle of Conquest"] = "정복의 섬"
L["Battle for Wintergrasp"] = "격전의 겨울손아귀"
L["Ashran"] = "아쉬란"

-- Maps: Arenas ---------------------------------------------------------------
L["Random Arena"] = "무작위 투기장"
L["Ruins of Lordaeron"] = "로데론의 폐허"
L["Dalaran Sewers"] = "달라란 하수도"
L["Tol'Viron Arena"] = "톨비론 투기장"
L["The Tiger's Peak"] = "범의 봉우리"
L["Black Rook Hold Arena"] = "검은 떼까마귀 요새 투기장"
L["Nagrand Arena"] = "나그란드 투기장"
L["Ashamane's Fall"] = "아샤메인의 몰락지"
L["Blade's Edge Arena"] = "칼날 산맥 투기장"
L["Hook Point"] = "갈고리 시장"
L["Mugambala"] = "무감발라"
L["The Robodrome"] = "로봇 전투장"
L["Maldraxxus Coliseum"] = "말드락서스 대경기장"

-- Modes ----------------------------------------------------------------------
L["Spectator Mode"] = "관전 모드"

-- Leaderboard UI -------------------------------------------------------------
L["Leaderboard"] = "순위표"
L["Current Season"] = "현재 시즌"
L["Last Updated"] = "마지막 업데이트"
L["Armory"] = "무기고"
L["Copy Armory Link"] = "무기고 링크 복사"
L["Copied to clipboard."] = "클립보드에 복사되었습니다."

-- Error Messages: Group Validation ------------------------------------------
L["Your group needs %d more |4player:players; to join this battleground."] = "전장에 참여하려면 파티원 %d명이 더 필요합니다."
L["Your group needs %d less |4player:players; to join this battleground."] = "전장에 참여하려면 파티원 %d명이 제외되어야 합니다."
L["You cannot start a War Game while in a suspended queue state."] = "대기열 일시 중단 상태에서는 모의전을 시작할 수 없습니다."
L["You cannot start a War Game because one of your group members is dead."] = "파티원 중 한 명이 사망 상태이므로 모의전을 시작할 수 없습니다."
L["You cannot start a War Game because one of your group members is disconnected."] = "파티원 중 한 명이 오프라인 상태이므로 모의전을 시작할 수 없습니다."
L["You cannot start a War Game because one of your group members is in instance group."] = "파티원 중 한 명이 인스턴스 그룹에 있으므로 모의전을 시작할 수 없습니다."
L["You cannot start a War Game because both party leaders are not in the same level range."] = "두 파티장의 레벨이 동일하지 않아 파티에서 모의전을 시작할 수 없습니다."

-- Error Messages: Friend Validation -----------------------------------------
L["This friend is playing World of Warcraft in a different region."] = "해당 친구는 다른 지역의 월드 오브 워크래프트에 접속 중입니다."

-- Error Messages: War Game Validation ---------------------------------------
L["Select a Battle.net friend to challenge, or check Target."] = "Battle.net 친구를 선택하여 도전하거나 대상을 확인하십시오."
L["Select a Battle.net friend to challenge first."] = "먼저 도전할 Battle.net 친구를 선택하십시오."
L["Select two Battle.net friends to start a War Game."] = "모의전을 시작하려면 Battle.net 친구 두 명을 선택하십시오."
L["No eligible map found."] = "적절한 지도를 찾을 수 없습니다."
L["You have no target selected."] = "선택한 대상이 없습니다."
L["You cannot challenge a friend who is in your group."] = "같은 그룹에 있는 친구에게는 도전할 수 없습니다."
L["You cannot start a War Game because %s's group size does not match yours."] = "모의전을 시작할 수 없습니다. %s의 그룹 크기가 귀하의 그룹 크기와 일치하지 않습니다."
L["You cannot start a War Game because %s's group is in a suspended queue state."] = "모의전을 시작할 수 없습니다. %s의 그룹이 대기열 일시 중단 상태입니다."
L["You cannot start a War Game because %s's group has an active LFG listing."] = "모의전을 시작할 수 없습니다. %s의 그룹에 활성 LFG 목록이 있습니다."
L["You cannot start a War Game because one of %s's group members is disconnected."] = "모의전을 시작할 수 없습니다. %s의 그룹에 오프라인 상태인 멤버가 있습니다."
L["You cannot start a War Game because one of %s's group members is in instance group."] = "모의전을 시작할 수 없습니다. %s의 그룹에 다른 인스턴스에 있는 멤버가 있습니다."
L["You cannot start a War Game because one of %s's group members is dead."] = "모의전을 시작할 수 없습니다. %s의 그룹에 사망한 멤버가 있습니다."
L["You cannot start a War Game because %s's leader is not in your friend list (%s)."] = "모의전을 시작할 수 없습니다. %s의 그룹 리더가 귀하의 친구 목록에 없습니다(%s)."
L["You cannot start a War Game because you and the group leader of %s are in different level ranges."] = "모의전을 시작할 수 없습니다. 귀하와 %s의 그룹 리더가 같은 레벨 범위에 있지 않습니다."
L["You cannot start a War Game because %s and %s are in the same group."] = "모의전을 시작할 수 없습니다. %s와 %s은(는) 같은 그룹에 있습니다."
L["You cannot start a War Game because %s and %s have different group sizes."] = "모의전을 시작할 수 없습니다. %s와 %s의 그룹 크기가 다릅니다."
L["You cannot start a War Game because %s and %s are not in the same level range."] = "모의전을 시작할 수 없습니다. %s와 %s은(는) 같은 레벨 범위에 있지 않습니다."

-- Chat Messages --------------------------------------------------------------
L["War Game request sent to "] = "모의전 요청을 다음으로 전송했습니다 "

return
end

-- ============================================================================
-- SIMPLIFIED CHINESE
-- ============================================================================
if LOCALE == "zhCN" then

-- General --------------------------------------------------------------------
L["Random"] = "随机"

-- Maps: Battlegrounds --------------------------------------------------------
L["Random Battleground"] = "随机战场"
L["Warsong Gulch"] = "战歌峡谷"
L["The Battle for Gilneas"] = "吉尔尼斯之战"
L["Eye of the Storm"] = "风暴之眼"
L["Arathi Basin"] = "阿拉希盆地"
L["Alterac Valley"] = "奥特兰克山谷"
L["Isle of Conquest"] = "征服之岛"
L["Battle for Wintergrasp"] = "冬拥湖之战"
L["Ashran"] = "阿什兰"

-- Maps: Arenas ---------------------------------------------------------------
L["Random Arena"] = "随机竞技场"
L["Ruins of Lordaeron"] = "洛丹伦废墟"
L["Dalaran Sewers"] = "达拉然下水道"
L["Tol'Viron Arena"] = "托维尔隆竞技场"
L["The Tiger's Peak"] = "虎踞峰"
L["Black Rook Hold Arena"] = "黑鸦堡垒竞技场"
L["Nagrand Arena"] = "纳格兰竞技场"
L["Ashamane's Fall"] = "阿莎曼之墓"
L["Blade's Edge Arena"] = "刀锋山竞技场"
L["Hook Point"] = "锚角港"
L["Mugambala"] = "穆贾巴拉"
L["The Robodrome"] = "机械天穹"
L["Maldraxxus Coliseum"] = "玛卓克萨斯角斗场"

-- Modes ----------------------------------------------------------------------
L["Spectator Mode"] = "观战模式"

-- Leaderboard UI -------------------------------------------------------------
L["Leaderboard"] = "排行榜"
L["Current Season"] = "当前赛季"
L["Last Updated"] = "最后更新"
L["Armory"] = "英雄榜"
L["Copy Armory Link"] = "复制英雄榜链接"
L["Copied to clipboard."] = "已复制到剪贴板。"

-- Error Messages: Group Validation ------------------------------------------
L["Your group needs %d more |4player:players; to join this battleground."] = "要加入战场，你的团队需要增加%d名玩家。"
L["Your group needs %d less |4player:players; to join this battleground."] = "要加入战场，你的团队需要减少%d名玩家。"
L["You cannot start a War Game while in a suspended queue state."] = "在队列暂停状态下无法开始战争游戏。"
L["You cannot start a War Game because one of your group members is dead."] = "你的队伍无法开始战争游戏，因为一名成员已死亡。"
L["You cannot start a War Game because one of your group members is disconnected."] = "你的队伍中有成员掉线，无法开始战争游戏。"
L["You cannot start a War Game because one of your group members is in instance group."] = "你的队伍无法开始战争游戏，因为一名成员在副本队伍中。"
L["You cannot start a War Game because both party leaders are not in the same level range."] = "你的队伍的领袖需要在同一个等级限制范围内，否则无法开始战争游戏。"

-- Error Messages: Friend Validation -----------------------------------------
L["This friend is playing World of Warcraft in a different region."] = "这名好友正在不同的地区游玩魔兽世界。"

-- Error Messages: War Game Validation ---------------------------------------
L["Select a Battle.net friend to challenge, or check Target."] = "选择一个 Battle.net 好友来挑战，或检查目标。"
L["Select a Battle.net friend to challenge first."] = "首先选择一个 Battle.net 好友来挑战。"
L["Select two Battle.net friends to start a War Game."] = "选择两个 Battle.net 好友来开始战争游戏。"
L["No eligible map found."] = "未找到合适的地图。"
L["You have no target selected."] = "你没有选择目标。"
L["You cannot challenge a friend who is in your group."] = "你不能挑战与你同一队伍的好友。"
L["You cannot start a War Game because %s's group size does not match yours."] = "无法开始战争游戏，因为 %s 的队伍规模与你的不匹配。"
L["You cannot start a War Game because %s's group is in a suspended queue state."] = "无法开始战争游戏，因为 %s 的队伍处于队列暂停状态。"
L["You cannot start a War Game because %s's group has an active LFG listing."] = "无法开始战争游戏，因为 %s 的队伍有活动的 LFG 列表。"
L["You cannot start a War Game because one of %s's group members is disconnected."] = "无法开始战争游戏，因为 %s 的队伍有离线成员。"
L["You cannot start a War Game because one of %s's group members is in instance group."] = "无法开始战争游戏，因为 %s 的队伍有成员在其他副本中。"
L["You cannot start a War Game because one of %s's group members is dead."] = "无法开始战争游戏，因为 %s 的队伍有死亡成员。"
L["You cannot start a War Game because %s's leader is not in your friend list (%s)."] = "无法开始战争游戏，因为 %s 的队长不在你的好友列表中(%s)。"
L["You cannot start a War Game because you and the group leader of %s are in different level ranges."] = "无法开始战争游戏，因为你和 %s 的队伍队长不在同一等级范围内。"
L["You cannot start a War Game because %s and %s are in the same group."] = "无法开始战争游戏，因为 %s 和 %s 在同一队伍中。"
L["You cannot start a War Game because %s and %s have different group sizes."] = "无法开始战争游戏，因为 %s 和 %s 的队伍规模不同。"
L["You cannot start a War Game because %s and %s are not in the same level range."] = "无法开始战争游戏，因为 %s 和 %s 不在同一等级范围内。"

-- Chat Messages --------------------------------------------------------------
L["War Game request sent to "] = "战争游戏请求已发送给 "

return
end

-- ============================================================================
-- TRADITIONAL CHINESE
-- ============================================================================
if LOCALE == "zhTW" then

-- General --------------------------------------------------------------------
L["Random"] = "隨機"

-- Maps: Battlegrounds --------------------------------------------------------
L["Random Battleground"] = "隨機戰場"
L["Warsong Gulch"] = "戰歌峽谷"
L["The Battle for Gilneas"] = "吉爾尼斯之戰"
L["Eye of the Storm"] = "暴風之眼"
L["Arathi Basin"] = "阿拉希盆地"
L["Alterac Valley"] = "奧特蘭克山谷"
L["Isle of Conquest"] = "征服之島"
L["Battle for Wintergrasp"] = "冬握湖戰鬥"
L["Ashran"] = "艾斯蘭"

-- Maps: Arenas ---------------------------------------------------------------
L["Random Arena"] = "隨機競技場"
L["Ruins of Lordaeron"] = "羅德隆廢墟"
L["Dalaran Sewers"] = "達拉然下水道"
L["Tol'Viron Arena"] = "托維恩競技場"
L["The Tiger's Peak"] = "猛虎峰"
L["Black Rook Hold Arena"] = "玄鴉堡競技場"
L["Nagrand Arena"] = "納葛蘭競技場"
L["Ashamane's Fall"] = "亞夏曼之殞"
L["Blade's Edge Arena"] = "劍刃競技場"
L["Hook Point"] = "勾角地"
L["Mugambala"] = "穆干巴拉"
L["The Robodrome"] = "超爆機械鬥場"
L["Maldraxxus Coliseum"] = "瑪卓薩斯大競技場"

-- Modes ----------------------------------------------------------------------
L["Spectator Mode"] = "觀戰模式"

-- Leaderboard UI -------------------------------------------------------------
L["Leaderboard"] = "排行榜"
L["Current Season"] = "當前賽季"
L["Last Updated"] = "最後更新"
L["Armory"] = "英雄榜"
L["Copy Armory Link"] = "複製英雄榜連結"
L["Copied to clipboard."] = "已複製到剪貼簿。"

-- Error Messages: Group Validation ------------------------------------------
L["Your group needs %d more |4player:players; to join this battleground."] = "你的隊伍還需要加入%d名玩家才能加入戰場。"
L["Your group needs %d less |4player:players; to join this battleground."] = "你的隊伍還需要減少%d名玩家才能加入戰場。"
L["You cannot start a War Game while in a suspended queue state."] = "在隊列暫停狀態下無法開始戰爭比賽。"
L["You cannot start a War Game because one of your group members is dead."] = "你的隊伍無法開始戰爭比賽，因為一名成員已死亡。"
L["You cannot start a War Game because one of your group members is disconnected."] = "無法開始戰爭比賽因為你的團隊隊員已經斷線。"
L["You cannot start a War Game because one of your group members is in instance group."] = "你的隊伍無法開始戰爭比賽，因為一名成員在副本隊伍中。"
L["You cannot start a War Game because both party leaders are not in the same level range."] = "你的隊伍無法開始戰爭比賽，因為雙方隊伍領袖未處於相同的等級範圍內。"

-- Error Messages: Friend Validation -----------------------------------------
L["This friend is playing World of Warcraft in a different region."] = "該名好友正在不同地區遊玩魔獸世界。"

-- Error Messages: War Game Validation ---------------------------------------
L["Select a Battle.net friend to challenge, or check Target."] = "選擇一個 Battle.net 朋友來挑戰，或檢查目標。"
L["Select a Battle.net friend to challenge first."] = "首先選擇一個 Battle.net 朋友來挑戰。"
L["Select two Battle.net friends to start a War Game."] = "選擇兩個 Battle.net 好友來開始戰爭比賽。"
L["No eligible map found."] = "找不到合適的地圖。"
L["You have no target selected."] = "你沒有選擇目標。"
L["You cannot challenge a friend who is in your group."] = "你不能挑戰與你同一隊伍的好友。"
L["You cannot start a War Game because %s's group size does not match yours."] = "無法開始戰爭比賽，因為 %s 的隊伍規模與你的不匹配。"
L["You cannot start a War Game because %s's group is in a suspended queue state."] = "無法開始戰爭比賽，因為 %s 的隊伍處於隊列暫停狀態。"
L["You cannot start a War Game because %s's group has an active LFG listing."] = "無法開始戰爭比賽，因為 %s 的隊伍有活動的 LFG 列表。"
L["You cannot start a War Game because one of %s's group members is disconnected."] = "無法開始戰爭比賽，因為 %s 的隊伍有離線成員。"
L["You cannot start a War Game because one of %s's group members is in instance group."] = "無法開始戰爭比賽，因為 %s 的隊伍有成員在其他副本中。"
L["You cannot start a War Game because one of %s's group members is dead."] = "無法開始戰爭比賽，因為 %s 的隊伍有死亡成員。"
L["You cannot start a War Game because %s's leader is not in your friend list (%s)."] = "無法開始戰爭比賽，因為 %s 的隊長不在你的好友列表中(%s)。"
L["You cannot start a War Game because you and the group leader of %s are in different level ranges."] = "無法開始戰爭比賽，因為你和 %s 的隊伍隊長不在同一等級範圍內。"
L["You cannot start a War Game because %s and %s are in the same group."] = "無法開始戰爭比賽，因為 %s 和 %s 在同一隊伍中。"
L["You cannot start a War Game because %s and %s have different group sizes."] = "無法開始戰爭比賽，因為 %s 和 %s 的隊伍規模不同。"
L["You cannot start a War Game because %s and %s are not in the same level range."] = "無法開始戰爭比賽，因為 %s 和 %s 不在同一等級範圍內。"

-- Chat Messages --------------------------------------------------------------
L["War Game request sent to "] = "戰爭比賽請求已發送給 "

return
end