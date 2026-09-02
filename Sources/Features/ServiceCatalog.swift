//
//  ServiceCatalog.swift · MacTuner
//
import SwiftUI

// MARK: - Rôle de chaque service du catalogue

/// Ce que fait, concrètement, chaque service référencé par une fiche.
///
/// L'onglet Services s'en sert pour expliquer service par service ce qu'une
/// fiche arrête. Une entrée manquante fait échouer `tools/verify-labels.py`,
/// donc la compilation : le catalogue et cette table ne peuvent pas diverger.
let serviceRoles: [String: LStr] = [
    "com.apple.corespotlightd":
        LStr("Index CoreSpotlight des apps : Mail, Notes, Messages.",
             "Apps' CoreSpotlight index: Mail, Notes, Messages."),
    "com.apple.sharingd":
        LStr("Annonce le Mac aux appareils voisins : AirDrop, partage.",
             "Advertises the Mac to nearby devices: AirDrop, sharing."),
    "com.apple.linkd":
        LStr("Handoff et presse-papiers universel entre appareils.",
             "Handoff and universal clipboard across devices."),
    "com.apple.textunderstandingd":
        LStr("Analyse sémantique du texte pour Apple Intelligence.",
             "Semantic text analysis for Apple Intelligence."),
    "com.apple.chronod":
        LStr("Héberge et rafraîchit les widgets et activités en direct.",
             "Hosts and refreshes widgets and Live Activities."),
    "com.apple.replayd":
        LStr("ReplayKit : encodage de l'enregistrement d'écran.",
             "ReplayKit: screen-recording encoding."),
    "com.apple.GamePolicyAgent":
        LStr("Détecte les jeux et bascule macOS en mode Jeu.",
             "Detects games and switches macOS into Game Mode."),
    "com.apple.Siri.agent":
        LStr("Interface de Siri : fenêtre, écoute, réponses.",
             "Siri's interface: window, listening, answers."),
    "com.apple.assistantd":
        LStr("Cœur de l'assistant : reçoit et route chaque requête.",
             "Assistant core: receives and routes every request."),
    "com.apple.assistant_service":
        LStr("Exécution des requêtes transmises par l'assistant.",
             "Runs the requests handed over by the assistant."),
    "com.apple.siriactionsd":
        LStr("Raccourcis déclenchés à la voix.",
             "Voice-triggered Shortcuts."),
    "com.apple.siriknowledged":
        LStr("Base de connaissances locale de Siri.",
             "Siri's local knowledge base."),
    "com.apple.sirittsd":
        LStr("Synthèse de la voix de Siri.",
             "Siri voice synthesis."),
    "com.apple.siriinferenced":
        LStr("Inférence locale : compréhension hors ligne.",
             "On-device inference: offline understanding."),
    "com.apple.assistant_cdmd":
        LStr("Gestionnaire de dialogue : conversations suivies.",
             "Dialog manager: follow-up conversations."),
    "com.apple.corespeechd":
        LStr("Écoute permanente du mot-clé « Dis Siri ».",
             "Continuous listening for the “Hey Siri” keyword."),
    "com.apple.siriappintentsd":
        LStr("Intentions que les apps exposent à Siri.",
             "Intents that apps expose to Siri."),
    "com.apple.speechmaintenanced":
        LStr("Entretien des modèles de reconnaissance embarqués.",
             "Maintains the on-device recognition models."),
    "com.apple.SiriTTSTrainingAgent":
        LStr("Entraînement local de la voix de Siri.",
             "Local training of the Siri voice."),
    "com.apple.DictationIM":
        LStr("Méthode de saisie de la dictée vocale (fn fn).",
             "Voice dictation input method (fn fn)."),
    "com.apple.speech.speechdatainstallerd":
        LStr("Téléchargement des paquets de données vocales.",
             "Downloads the voice data packages."),
    "com.apple.campo":
        LStr("Application Siri AI de macOS 26/27.",
             "The Siri AI application of macOS 26/27."),
    "com.apple.corespeechd_system":
        LStr("Écoute « Dis Siri » hors session, en root.",
             "“Hey Siri” listening outside the session, as root."),
    "com.apple.intelligenceplatformd":
        LStr("Plateforme d'intelligence : orchestre les modèles.",
             "Intelligence platform: orchestrates the models."),
    "com.apple.generativeexperiencesd":
        LStr("Outils d'écriture, résumés de notifications, Genmoji.",
             "Writing Tools, notification summaries, Genmoji."),
    "com.apple.knowledgeconstructiond":
        LStr("Construit la base de connaissances locale.",
             "Builds the local knowledge base."),
    "com.apple.GenerativeFunctions.agentstored":
        LStr("Sessions d'agent génératif.",
             "Generative agent sessions."),
    "com.apple.intelligencecontextd":
        LStr("Contexte fourni aux modèles : ce que vous faites.",
             "Context fed to the models: what you're doing."),
    "com.apple.intelligenceflowd":
        LStr("Enchaîne les étapes d'une requête générative.",
             "Chains the steps of a generative request."),
    "com.apple.intelligencetasksd":
        LStr("File des tâches d'intelligence en arrière-plan.",
             "Background intelligence task queue."),
    "com.apple.visualintelligenced":
        LStr("Intelligence visuelle : analyse ce qui est à l'écran.",
             "Visual intelligence: analyses what is on screen."),
    "com.apple.callintelligenced":
        LStr("Résumés et transcription des appels.",
             "Call summaries and transcription."),
    "com.apple.mlhostd":
        LStr("Hôte d'exécution des modèles génératifs.",
             "Runtime host for the generative models."),
    "com.apple.modelmanagerd":
        LStr("Téléchargement et mise à jour des modèles (plusieurs Go).",
             "Downloads and updates the models (several GB)."),
    "com.apple.duetexpertd":
        LStr("Apprend vos habitudes : apps, horaires, lieux.",
             "Learns your habits: apps, times, places."),
    "com.apple.proactived":
        LStr("Propose apps et actions au bon moment.",
             "Offers apps and actions at the right moment."),
    "com.apple.knowledge-agent":
        LStr("Agrège les connaissances d'usage.",
             "Aggregates usage knowledge."),
    "com.apple.spotlightknowledged":
        LStr("Graphe de connaissances de Spotlight.",
             "Spotlight's knowledge graph."),
    "com.apple.spotlightknowledged.updater":
        LStr("Met à jour le graphe de connaissances.",
             "Updates the knowledge graph."),
    "com.apple.spotlightknowledged.importer":
        LStr("Importe de nouvelles données dans le graphe.",
             "Imports new data into the graph."),
    "com.apple.proactiveeventtrackerd":
        LStr("Suit les événements qui nourrissent les suggestions.",
             "Tracks the events that feed the suggestions."),
    "com.apple.coreduetd":
        LStr("Moteur d'apprentissage CoreDuet, côté système.",
             "The CoreDuet learning engine, system side."),
    "com.apple.suggestd":
        LStr("Analyse en local mails et messages : contacts, événements.",
             "Locally analyses mail and messages: contacts, events."),
    "com.apple.parsecd":
        LStr("Suggestions Spotlight et Safari via les serveurs Apple.",
             "Spotlight and Safari suggestions via Apple's servers."),
    "com.apple.parsec-fbf":
        LStr("Renvoie à Apple ce que vous faites des suggestions.",
             "Reports back to Apple what you do with suggestions."),
    "com.apple.hybridsearchd":
        LStr("Recherche hybride : interroge Apple à chaque frappe.",
             "Hybrid search: queries Apple on every keystroke."),
    "com.apple.tipsd":
        LStr("Notifications « Astuces » de macOS.",
             "macOS “Tips” notifications."),
    "com.apple.followupd":
        LStr("Rappels de configuration : Apple ID, iCloud, mises à jour.",
             "Setup reminders: Apple ID, iCloud, updates."),
    "com.apple.analyticsagent":
        LStr("Collecte les analyses d'usage, côté session.",
             "Collects usage analytics, session side."),
    "com.apple.inputanalyticsd":
        LStr("Analyse de la saisie au clavier.",
             "Keyboard input analytics."),
    "com.apple.geoanalyticsd":
        LStr("Analyse de localisation anonymisée.",
             "Anonymised location analytics."),
    "com.apple.ap.adprivacyd":
        LStr("Confidentialité publicitaire : identifiants tournants.",
             "Ad privacy: rotating identifiers."),
    "com.apple.metrickitd":
        LStr("Métriques de performance remontées par les apps.",
             "Performance metrics reported by apps."),
    "com.apple.analyticsd":
        LStr("Agrège toutes les analyses, en root.",
             "Aggregates all analytics, as root."),
    "com.apple.osanalytics.osanalyticshelper":
        LStr("Assistant d'analyse du système d'exploitation.",
             "Operating-system analytics helper."),
    "com.apple.rtcreportingd":
        LStr("Rapports temps réel : FaceTime, audio et vidéo.",
             "Real-time reporting: FaceTime, audio and video."),
    "com.apple.cloudtelemetryd":
        LStr("Télémétrie des services iCloud.",
             "Telemetry for the iCloud services."),
    "com.apple.wifianalyticsd":
        LStr("Analyse des connexions Wi-Fi.",
             "Wi-Fi connection analytics."),
    "com.apple.audioanalyticsd":
        LStr("Analyse de l'usage audio.",
             "Audio usage analytics."),
    "com.apple.ecosystemanalyticsd":
        LStr("Analyse l'écosystème d'apps installées.",
             "Analyses the installed app ecosystem."),
    "com.apple.libsqlite3.dbtelemetryd":
        LStr("Télémétrie des bases SQLite du système.",
             "Telemetry of the system's SQLite databases."),
    "com.apple.usbctelemetryd":
        LStr("Télémétrie des ports USB-C.",
             "USB-C port telemetry."),
    "com.apple.memoryanalyticsd":
        LStr("Analyse de l'usage mémoire.",
             "Memory usage analytics."),
    "com.apple.ap.promotedcontentd":
        LStr("Récupère les contenus promus : App Store, News.",
             "Fetches promoted content: App Store, News."),
    "com.apple.diagnostics_agent":
        LStr("Prépare les rapports de diagnostic.",
             "Prepares the diagnostic reports."),
    "com.apple.DiagnosticsReporter":
        LStr("Fenêtre « L'application a quitté de manière imprévue ».",
             "The “application quit unexpectedly” dialog."),
    "com.apple.ReportCrash":
        LStr("Écrit les rapports de plantage (.ips) des apps.",
             "Writes the app crash reports (.ips)."),
    "com.apple.spindump_agent":
        LStr("Rapports de blocage, côté session.",
             "Hang reports, session side."),
    "com.apple.diagnosticextensionsd":
        LStr("Extensions de diagnostic : Spotlight, Time Machine.",
             "Diagnostic extensions: Spotlight, Time Machine."),
    "com.apple.SubmitDiagInfo":
        LStr("Envoie les rapports à Apple.",
             "Sends the reports to Apple."),
    "com.apple.spindump":
        LStr("Analyse les processus bloqués, en root.",
             "Analyses stalled processes, as root."),
    "com.apple.tailspind":
        LStr("Traces de performance enregistrées en continu.",
             "Performance traces recorded continuously."),
    "com.apple.ReportCrash.Root":
        LStr("Rapports de plantage des processus root.",
             "Crash reports for root processes."),
    "com.apple.diagnosticservicesd":
        LStr("Coordonne les services de diagnostic.",
             "Coordinates the diagnostic services."),
    "com.apple.CrashReporterSupportHelper":
        LStr("Assistant du rapporteur de plantage.",
             "Support helper for the crash reporter."),
    "com.apple.ReportMemoryException":
        LStr("Rapports de dépassement mémoire.",
             "Memory exception reports."),
    "com.apple.diagnosticd":
        LStr("Collecte de traces système à la demande.",
             "On-demand system trace collection."),
    "com.apple.ScreenTimeAgent":
        LStr("Comptabilise le temps passé dans chaque app.",
             "Counts the time spent in each app."),
    "com.apple.ScreenTimeSettingsAgent":
        LStr("Réglages et limites de Temps d'écran.",
             "Screen Time settings and limits."),
    "com.apple.UsageTrackingAgent":
        LStr("Suivi d'usage pour les rapports hebdomadaires.",
             "Usage tracking for the weekly reports."),
    "com.apple.cloudphotod":
        LStr("Synchronisation de la photothèque iCloud.",
             "iCloud Photo Library synchronisation."),
    "com.apple.SafariBookmarksSyncAgent":
        LStr("Synchronise signets et onglets Safari via iCloud.",
             "Syncs Safari bookmarks and tabs through iCloud."),
    "com.apple.itunescloudd":
        LStr("Bibliothèque musicale iCloud et correspondance de titres.",
             "iCloud Music Library and track matching."),
    "com.apple.familycircled":
        LStr("Partage familial : membres, abonnements, achats.",
             "Family Sharing: members, subscriptions, purchases."),
    "com.apple.familynotificationd":
        LStr("Notifications du partage familial.",
             "Family Sharing notifications."),
    "com.apple.passd":
        LStr("Wallet, Apple Pay et cartes enregistrées.",
             "Wallet, Apple Pay and stored cards."),
    "com.apple.sidecar-relay":
        LStr("Relais Sidecar : l'iPad comme second écran.",
             "Sidecar relay: the iPad as a second display."),
    "com.apple.AirPlayUIAgent":
        LStr("Menu AirPlay de la barre des menus.",
             "The AirPlay menu in the menu bar."),
    "com.apple.sidecar-display-agent":
        LStr("Relais clavier et souris vers l'iPad.",
             "Keyboard and mouse relay to the iPad."),
    "com.apple.rapportd":
        LStr("Détecte en permanence les appareils Apple voisins.",
             "Continuously detects nearby Apple devices."),
    "com.apple.RapportUIAgent":
        LStr("Interface de Rapport : invitations de proximité.",
             "Rapport interface: proximity invitations."),
    "com.apple.AirPlayXPCHelper":
        LStr("Transport AirPlay, en root.",
             "AirPlay transport, as root."),
    "com.apple.photoanalysisd":
        LStr("Analyse des photos : visages, scènes, souvenirs.",
             "Photo analysis: faces, scenes, memories."),
    "com.apple.mediaanalysisd":
        LStr("Analyse des médias : texte, objets, recherche visuelle.",
             "Media analysis: text, objects, visual look up."),
    "com.apple.weatherd":
        LStr("Données météo du widget et du Centre de notifications.",
             "Weather data for the widget and Notification Centre."),
    "com.apple.newsd":
        LStr("Données d'Apple News.",
             "Apple News data."),
    "com.apple.financed":
        LStr("Cours de Bourse et suivi de portefeuille.",
             "Stock quotes and portfolio tracking."),
    "com.apple.gamed":
        LStr("Game Center : profil, amis, classements.",
             "Game Center: profile, friends, leaderboards."),
    "com.apple.gamesaved":
        LStr("Sauvegardes de jeux dans iCloud.",
             "Game saves in iCloud."),
    "com.apple.AMPArtworkAgent":
        LStr("Pochettes d'albums de Musique.",
             "Album artwork for Music."),
    "com.apple.AMPLibraryAgent":
        LStr("Bibliothèque Musique locale.",
             "The local Music library."),
    "com.apple.AMPDeviceDiscoveryAgent":
        LStr("Découverte des appareils iOS connectés.",
             "Discovery of connected iOS devices."),
    "com.apple.AMPDevicesAgent":
        LStr("Synchronisation avec les appareils iOS.",
             "Synchronisation with iOS devices."),
    "com.apple.AMPSystemPlayerAgent":
        LStr("Lecteur système : touches média du clavier.",
             "System player: the keyboard's media keys."),
    "com.apple.amp.mediasharingd":
        LStr("Partage à domicile de la bibliothèque.",
             "Home Sharing of the library."),
    "com.apple.videosubscriptionsd":
        LStr("Abonnements vidéo : Apple TV et chaînes.",
             "Video subscriptions: Apple TV and channels."),
    "com.apple.avatarsd":
        LStr("Memoji et avatars de contact.",
             "Memoji and contact avatars."),
    "com.apple.homed":
        LStr("HomeKit : accessoires, scènes, automatisations.",
             "HomeKit: accessories, scenes, automations."),
    "com.apple.homeenergyd":
        LStr("Suivi de consommation énergétique HomeKit.",
             "HomeKit energy usage tracking."),
    "com.apple.homeeventsd":
        LStr("Déclencheurs d'événements HomeKit.",
             "HomeKit event triggers."),
    "com.apple.CallHistoryPluginHelper":
        LStr("Enregistre l'historique d'appels local.",
             "Records the local call history."),
    "com.apple.CallHistorySyncHelper":
        LStr("Synchronise l'historique d'appels via iCloud.",
             "Syncs the call history through iCloud."),
    "com.apple.callhistoryd":
        LStr("Base de données de l'historique d'appels.",
             "The call-history database."),
    "com.apple.TMHelperAgent":
        LStr("Rappels de sauvegarde Time Machine.",
             "Time Machine backup reminders."),
]
