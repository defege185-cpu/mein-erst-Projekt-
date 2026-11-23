// Traductions de l'application. Pour ajouter une langue : copier le bloc "en" et traduire.
(function (root) {
  'use strict';
  const T = {
    fr: {
      _name: 'Français',
      title: 'Détecteur Caméra & Micro',
      tabScan: 'Scanner', tabPhotos: 'Photos', tabGuide: 'Guide',
      statusIdle: 'Appuyez sur « Démarrer le scan »',
      start: '▶ Démarrer le scan', stop: '⏹ Arrêter', torch: '🔦 Lampe', photo: '📷 Photo', switchCam: '🔄 Caméra',
      mode: 'Mode', modeReflect: "Reflet d'objectif (lampe allumée)", modeIR: 'Infrarouge (pièce dans le noir)',
      sensitivity: 'Sensibilité',
      autoShot: "Photo automatique dès qu'une caméra est suspectée", sound: 'Bip + vibration',
      magTitle: '🧲 Détecteur magnétique (micros, électronique)',
      magInit: 'Le magnétomètre sera activé au démarrage du scan si votre téléphone le permet.',
      magHint: "Approchez le téléphone (à 2–5 cm) des objets : une forte hausse peut signaler un micro, une batterie ou un circuit électronique caché.",
      magNotSupported: 'Magnétomètre non accessible depuis le navigateur sur cet appareil. Sur Android/Chrome : chrome://flags → « Generic Sensor Extra Classes » → Enabled.',
      magUnavailable: 'Magnétomètre indisponible : {e}',
      magField: 'Champ : {v} µT • écart : {d} µT', magWarn: ' ⚠️ électronique/métal proche !',
      photosTitle: 'Photos des détections', clearAll: '🗑 Tout effacer',
      photosHint: "Les photos restent sur votre téléphone (rien n'est envoyé sur Internet). Touchez « Enregistrer » pour les garder dans vos fichiers.",
      noPhotos: 'Aucune photo pour le moment.', save: '💾 Enregistrer', share: '📤 Partager', confirmClear: 'Effacer toutes les photos ?',
      scanning: 'Scan en cours… balayez lentement', nothing: 'Scan en cours… rien de suspect',
      noisy: "Trop de reflets ici (surface brillante) — changez d'angle",
      alertLens: 'Objectif de caméra suspect !', alertIR: 'LED infrarouge suspecte !', stopped: 'Scan arrêté',
      noCamera: 'Caméra non disponible. Ouvrez la page en HTTPS dans Chrome ou Safari.',
      cameraDenied: "Accès à la caméra refusé. Autorisez la caméra dans les réglages du navigateur.",
      cameraError: 'Erreur caméra : {e}', cameraLost: 'La caméra a été coupée. Relancez le scan.',
      torchFail: "Impossible d'allumer la lampe", torchUnsupported: 'Lampe non pilotable sur cet appareil',
      saveFail: "Impossible d'enregistrer la photo (stockage plein ou navigation privée ?)",
      storageFail: 'Stockage des photos indisponible (navigation privée ?)',
      photoManual: 'Photo manuelle', photoPoints: '{n} point(s) suspect(s) — {m}',
      modeNameReflect: "reflet d'objectif", modeNameIR: 'infrarouge', auto: '(auto)', language: 'Langue',
      guideTitle: 'Comment scanner une pièce',
      guide: [
        "<b>Mode « Reflet d'objectif »</b> : baissez la lumière, allumez la lampe 🔦. Les lentilles de caméra renvoient la lumière comme un petit point brillant. Balayez <b>lentement</b> murs, plafond, étagères, jouets, miroirs, détecteurs de fumée, prises, chargeurs, réveils, cadres…",
        "Tenez le téléphone à la <b>hauteur de vos yeux</b> : le reflet est plus fort quand la lampe et la caméra sont alignées avec l'objectif.",
        "<b>Mode « Infrarouge »</b> : éteignez toutes les lumières. Les caméras de vision nocturne ont des LED infrarouges invisibles à l'œil mais visibles par le téléphone (points violets/blancs). Astuce : touchez 🔄 pour utiliser la caméra <b>avant</b>, qui voit souvent mieux l'infrarouge.",
        "Quand un point brillant reste visible plusieurs images de suite, un cercle rouge apparaît et une <b>photo est prise automatiquement</b>.",
        "<b>Micros</b> : un micro ne se voit pas à la caméra. Utilisez le détecteur magnétique en approchant le téléphone des objets suspects, et vérifiez à la main les petits trous suspects.",
        "<b>Miroir sans tain</b> : posez le bout du doigt sur le miroir. S'il n'y a <b>aucun espace</b> entre le doigt et son reflet, éclairez-le avec la lampe collée au verre pour voir s'il y a quelque chose derrière."
      ],
      warn: "<b>⚠️ Limites :</b> aucune application ne peut garantir de trouver 100 % des caméras ou micros. Il peut y avoir de fausses alertes (vis brillantes, bijoux, gouttes d'eau, LED d'appareils). Vérifiez toujours chaque alerte à l'œil. En cas de doute sérieux, contactez la police ou un professionnel."
    },
    en: {
      _name: 'English',
      title: 'Camera & Mic Detector',
      tabScan: 'Scan', tabPhotos: 'Photos', tabGuide: 'Guide',
      statusIdle: 'Tap “Start scan”',
      start: '▶ Start scan', stop: '⏹ Stop', torch: '🔦 Light', photo: '📷 Photo', switchCam: '🔄 Camera',
      mode: 'Mode', modeReflect: 'Lens reflection (light on)', modeIR: 'Infrared (dark room)',
      sensitivity: 'Sensitivity',
      autoShot: 'Take a photo automatically when a camera is suspected', sound: 'Beep + vibration',
      magTitle: '🧲 Magnetic detector (microphones, electronics)',
      magInit: 'The magnetometer will start with the scan if your phone allows it.',
      magHint: 'Hold the phone 2–5 cm from objects: a strong rise may indicate a hidden microphone, battery or electronic circuit.',
      magNotSupported: 'The magnetometer is not available in the browser on this device. On Android/Chrome: chrome://flags → “Generic Sensor Extra Classes” → Enabled.',
      magUnavailable: 'Magnetometer unavailable: {e}',
      magField: 'Field: {v} µT • change: {d} µT', magWarn: ' ⚠️ electronics/metal nearby!',
      photosTitle: 'Detection photos', clearAll: '🗑 Delete all',
      photosHint: 'Photos stay on your phone (nothing is sent to the Internet). Tap “Save” to keep them in your files.',
      noPhotos: 'No photos yet.', save: '💾 Save', share: '📤 Share', confirmClear: 'Delete all photos?',
      scanning: 'Scanning… move slowly', nothing: 'Scanning… nothing suspicious',
      noisy: 'Too many reflections here (shiny surface) — change the angle',
      alertLens: 'Suspected camera lens!', alertIR: 'Suspected infrared LED!', stopped: 'Scan stopped',
      noCamera: 'Camera not available. Open the page over HTTPS in Chrome or Safari.',
      cameraDenied: 'Camera access denied. Allow the camera in your browser settings.',
      cameraError: 'Camera error: {e}', cameraLost: 'The camera was turned off. Start the scan again.',
      torchFail: 'Could not turn on the light', torchUnsupported: 'Light cannot be controlled on this device',
      saveFail: 'Could not save the photo (storage full or private browsing?)',
      storageFail: 'Photo storage unavailable (private browsing?)',
      photoManual: 'Manual photo', photoPoints: '{n} suspicious point(s) — {m}',
      modeNameReflect: 'lens reflection', modeNameIR: 'infrared', auto: '(auto)', language: 'Language',
      guideTitle: 'How to scan a room',
      guide: [
        '<b>“Lens reflection” mode</b>: dim the lights and turn on the light 🔦. Camera lenses reflect light back as a small bright dot. <b>Slowly</b> sweep walls, ceiling, shelves, toys, mirrors, smoke detectors, sockets, chargers, clocks, picture frames…',
        'Hold the phone at <b>eye level</b>: the reflection is strongest when the light and the camera are lined up with the lens.',
        '<b>“Infrared” mode</b>: turn off all lights. Night-vision cameras have infrared LEDs that are invisible to the eye but visible to the phone (purple/white dots). Tip: tap 🔄 to use the <b>front</b> camera, which often sees infrared better.',
        'When a bright dot stays visible for several frames, a red circle appears and a <b>photo is taken automatically</b>.',
        '<b>Microphones</b>: a microphone cannot be seen by the camera. Use the magnetic detector by holding the phone close to suspicious objects, and check small suspicious holes by hand.',
        '<b>Two-way mirror</b>: touch the mirror with your fingertip. If there is <b>no gap</b> between your finger and its reflection, press the light against the glass to see if something is behind it.'
      ],
      warn: '<b>⚠️ Limits:</b> no app can guarantee finding 100% of cameras or microphones. False alarms can happen (shiny screws, jewellery, water drops, device LEDs). Always check each alert with your own eyes. If you have serious doubts, contact the police or a professional.'
    },
    de: {
      _name: 'Deutsch',
      title: 'Kamera- & Mikrofon-Detektor',
      tabScan: 'Scannen', tabPhotos: 'Fotos', tabGuide: 'Anleitung',
      statusIdle: 'Tippen Sie auf „Scan starten“',
      start: '▶ Scan starten', stop: '⏹ Stopp', torch: '🔦 Licht', photo: '📷 Foto', switchCam: '🔄 Kamera',
      mode: 'Modus', modeReflect: 'Linsenreflexion (Licht an)', modeIR: 'Infrarot (dunkler Raum)',
      sensitivity: 'Empfindlichkeit',
      autoShot: 'Automatisch ein Foto machen, wenn eine Kamera vermutet wird', sound: 'Piepton + Vibration',
      magTitle: '🧲 Magnetdetektor (Mikrofone, Elektronik)',
      magInit: 'Das Magnetometer startet mit dem Scan, wenn Ihr Handy es erlaubt.',
      magHint: 'Halten Sie das Handy 2–5 cm vor Gegenstände: Ein starker Anstieg kann auf ein verstecktes Mikrofon, einen Akku oder eine Elektronik hinweisen.',
      magNotSupported: 'Das Magnetometer ist im Browser dieses Geräts nicht verfügbar. Unter Android/Chrome: chrome://flags → „Generic Sensor Extra Classes“ → Enabled.',
      magUnavailable: 'Magnetometer nicht verfügbar: {e}',
      magField: 'Feld: {v} µT • Abweichung: {d} µT', magWarn: ' ⚠️ Elektronik/Metall in der Nähe!',
      photosTitle: 'Fotos der Funde', clearAll: '🗑 Alle löschen',
      photosHint: 'Die Fotos bleiben auf Ihrem Handy (nichts wird ins Internet gesendet). Tippen Sie auf „Speichern“, um sie in Ihren Dateien zu behalten.',
      noPhotos: 'Noch keine Fotos.', save: '💾 Speichern', share: '📤 Teilen', confirmClear: 'Alle Fotos löschen?',
      scanning: 'Scan läuft… langsam bewegen', nothing: 'Scan läuft… nichts Verdächtiges',
      noisy: 'Zu viele Reflexionen hier (glänzende Fläche) — Winkel ändern',
      alertLens: 'Verdächtige Kameralinse!', alertIR: 'Verdächtige Infrarot-LED!', stopped: 'Scan gestoppt',
      noCamera: 'Kamera nicht verfügbar. Öffnen Sie die Seite über HTTPS in Chrome oder Safari.',
      cameraDenied: 'Kamerazugriff verweigert. Erlauben Sie die Kamera in den Browser-Einstellungen.',
      cameraError: 'Kamerafehler: {e}', cameraLost: 'Die Kamera wurde beendet. Starten Sie den Scan erneut.',
      torchFail: 'Licht konnte nicht eingeschaltet werden', torchUnsupported: 'Licht auf diesem Gerät nicht steuerbar',
      saveFail: 'Foto konnte nicht gespeichert werden (Speicher voll oder privates Surfen?)',
      storageFail: 'Fotospeicher nicht verfügbar (privates Surfen?)',
      photoManual: 'Manuelles Foto', photoPoints: '{n} verdächtige(r) Punkt(e) — {m}',
      modeNameReflect: 'Linsenreflexion', modeNameIR: 'Infrarot', auto: '(auto)', language: 'Sprache',
      guideTitle: 'So scannen Sie einen Raum',
      guide: [
        '<b>Modus „Linsenreflexion“</b>: Licht dimmen, Lampe 🔦 einschalten. Kameralinsen werfen das Licht als kleinen hellen Punkt zurück. Wände, Decke, Regale, Spielzeug, Spiegel, Rauchmelder, Steckdosen, Ladegeräte, Wecker, Bilderrahmen <b>langsam</b> abscannen…',
        'Halten Sie das Handy auf <b>Augenhöhe</b>: Die Reflexion ist am stärksten, wenn Licht und Kamera auf die Linse ausgerichtet sind.',
        '<b>Modus „Infrarot“</b>: Alle Lichter ausschalten. Nachtsichtkameras haben Infrarot-LEDs, die für das Auge unsichtbar, für das Handy aber sichtbar sind (violette/weiße Punkte). Tipp: Tippen Sie auf 🔄, um die <b>Frontkamera</b> zu nutzen, die Infrarot oft besser sieht.',
        'Bleibt ein heller Punkt mehrere Bilder lang sichtbar, erscheint ein roter Kreis und ein <b>Foto wird automatisch aufgenommen</b>.',
        '<b>Mikrofone</b>: Ein Mikrofon ist für die Kamera nicht sichtbar. Nutzen Sie den Magnetdetektor, indem Sie das Handy nah an verdächtige Gegenstände halten, und prüfen Sie kleine verdächtige Löcher von Hand.',
        '<b>Spionspiegel</b>: Legen Sie die Fingerspitze auf den Spiegel. Gibt es <b>keinen Abstand</b> zwischen Finger und Spiegelbild, halten Sie die Lampe direkt ans Glas, um zu sehen, ob sich etwas dahinter befindet.'
      ],
      warn: '<b>⚠️ Grenzen:</b> Keine App kann garantieren, 100 % der Kameras oder Mikrofone zu finden. Fehlalarme sind möglich (glänzende Schrauben, Schmuck, Wassertropfen, Geräte-LEDs). Prüfen Sie jeden Alarm immer mit eigenen Augen. Bei ernsthaftem Verdacht wenden Sie sich an die Polizei oder einen Fachmann.'
    },
    es: {
      _name: 'Español',
      title: 'Detector de Cámaras y Micrófonos',
      tabScan: 'Escanear', tabPhotos: 'Fotos', tabGuide: 'Guía',
      statusIdle: 'Pulse «Iniciar escaneo»',
      start: '▶ Iniciar escaneo', stop: '⏹ Detener', torch: '🔦 Linterna', photo: '📷 Foto', switchCam: '🔄 Cámara',
      mode: 'Modo', modeReflect: 'Reflejo de lente (linterna encendida)', modeIR: 'Infrarrojo (habitación a oscuras)',
      sensitivity: 'Sensibilidad',
      autoShot: 'Tomar una foto automáticamente al sospechar una cámara', sound: 'Pitido + vibración',
      magTitle: '🧲 Detector magnético (micrófonos, electrónica)',
      magInit: 'El magnetómetro se activará al iniciar el escaneo si su teléfono lo permite.',
      magHint: 'Acerque el teléfono a 2–5 cm de los objetos: una subida fuerte puede indicar un micrófono, una batería o un circuito electrónico oculto.',
      magNotSupported: 'El magnetómetro no está disponible en el navegador de este dispositivo. En Android/Chrome: chrome://flags → «Generic Sensor Extra Classes» → Enabled.',
      magUnavailable: 'Magnetómetro no disponible: {e}',
      magField: 'Campo: {v} µT • diferencia: {d} µT', magWarn: ' ⚠️ ¡electrónica/metal cerca!',
      photosTitle: 'Fotos de las detecciones', clearAll: '🗑 Borrar todo',
      photosHint: 'Las fotos se quedan en su teléfono (no se envía nada a Internet). Pulse «Guardar» para conservarlas en sus archivos.',
      noPhotos: 'Todavía no hay fotos.', save: '💾 Guardar', share: '📤 Compartir', confirmClear: '¿Borrar todas las fotos?',
      scanning: 'Escaneando… muévase despacio', nothing: 'Escaneando… nada sospechoso',
      noisy: 'Demasiados reflejos aquí (superficie brillante): cambie el ángulo',
      alertLens: '¡Posible lente de cámara!', alertIR: '¡Posible LED infrarrojo!', stopped: 'Escaneo detenido',
      noCamera: 'Cámara no disponible. Abra la página con HTTPS en Chrome o Safari.',
      cameraDenied: 'Acceso a la cámara denegado. Permita la cámara en los ajustes del navegador.',
      cameraError: 'Error de cámara: {e}', cameraLost: 'La cámara se ha apagado. Inicie el escaneo de nuevo.',
      torchFail: 'No se pudo encender la linterna', torchUnsupported: 'La linterna no se puede controlar en este dispositivo',
      saveFail: 'No se pudo guardar la foto (¿almacenamiento lleno o navegación privada?)',
      storageFail: 'Almacenamiento de fotos no disponible (¿navegación privada?)',
      photoManual: 'Foto manual', photoPoints: '{n} punto(s) sospechoso(s) — {m}',
      modeNameReflect: 'reflejo de lente', modeNameIR: 'infrarrojo', auto: '(auto)', language: 'Idioma',
      guideTitle: 'Cómo escanear una habitación',
      guide: [
        '<b>Modo «Reflejo de lente»</b>: baje la luz y encienda la linterna 🔦. Las lentes de las cámaras devuelven la luz como un pequeño punto brillante. Recorra <b>despacio</b> paredes, techo, estanterías, juguetes, espejos, detectores de humo, enchufes, cargadores, relojes, marcos…',
        'Sostenga el teléfono a la <b>altura de los ojos</b>: el reflejo es más fuerte cuando la linterna y la cámara están alineadas con la lente.',
        '<b>Modo «Infrarrojo»</b>: apague todas las luces. Las cámaras de visión nocturna tienen LED infrarrojos invisibles para el ojo pero visibles para el teléfono (puntos violetas/blancos). Consejo: pulse 🔄 para usar la cámara <b>frontal</b>, que a menudo ve mejor el infrarrojo.',
        'Cuando un punto brillante permanece visible varias imágenes seguidas, aparece un círculo rojo y se <b>toma una foto automáticamente</b>.',
        '<b>Micrófonos</b>: un micrófono no se ve con la cámara. Use el detector magnético acercando el teléfono a los objetos sospechosos y revise a mano los pequeños agujeros sospechosos.',
        '<b>Espejo espía</b>: ponga la punta del dedo sobre el espejo. Si <b>no hay espacio</b> entre el dedo y su reflejo, apoye la linterna contra el cristal para ver si hay algo detrás.'
      ],
      warn: '<b>⚠️ Límites:</b> ninguna aplicación puede garantizar encontrar el 100 % de las cámaras o micrófonos. Puede haber falsas alarmas (tornillos brillantes, joyas, gotas de agua, LED de aparatos). Compruebe siempre cada alerta con sus propios ojos. Ante una duda seria, contacte con la policía o con un profesional.'
    },
    it: {
      _name: 'Italiano',
      title: 'Rilevatore di Telecamere e Microfoni',
      tabScan: 'Scansione', tabPhotos: 'Foto', tabGuide: 'Guida',
      statusIdle: 'Tocca «Avvia scansione»',
      start: '▶ Avvia scansione', stop: '⏹ Ferma', torch: '🔦 Torcia', photo: '📷 Foto', switchCam: '🔄 Fotocamera',
      mode: 'Modalità', modeReflect: 'Riflesso dell’obiettivo (torcia accesa)', modeIR: 'Infrarossi (stanza al buio)',
      sensitivity: 'Sensibilità',
      autoShot: 'Scatta una foto automaticamente quando si sospetta una telecamera', sound: 'Bip + vibrazione',
      magTitle: '🧲 Rilevatore magnetico (microfoni, elettronica)',
      magInit: 'Il magnetometro si attiverà con la scansione se il telefono lo consente.',
      magHint: 'Avvicina il telefono a 2–5 cm dagli oggetti: un forte aumento può indicare un microfono, una batteria o un circuito elettronico nascosto.',
      magNotSupported: 'Il magnetometro non è disponibile nel browser di questo dispositivo. Su Android/Chrome: chrome://flags → «Generic Sensor Extra Classes» → Enabled.',
      magUnavailable: 'Magnetometro non disponibile: {e}',
      magField: 'Campo: {v} µT • scarto: {d} µT', magWarn: ' ⚠️ elettronica/metallo vicino!',
      photosTitle: 'Foto dei rilevamenti', clearAll: '🗑 Elimina tutto',
      photosHint: 'Le foto restano sul telefono (nulla viene inviato su Internet). Tocca «Salva» per conservarle nei tuoi file.',
      noPhotos: 'Nessuna foto per ora.', save: '💾 Salva', share: '📤 Condividi', confirmClear: 'Eliminare tutte le foto?',
      scanning: 'Scansione in corso… muoviti lentamente', nothing: 'Scansione in corso… niente di sospetto',
      noisy: 'Troppi riflessi qui (superficie lucida): cambia angolazione',
      alertLens: 'Possibile obiettivo di telecamera!', alertIR: 'Possibile LED a infrarossi!', stopped: 'Scansione fermata',
      noCamera: 'Fotocamera non disponibile. Apri la pagina in HTTPS con Chrome o Safari.',
      cameraDenied: 'Accesso alla fotocamera negato. Consenti la fotocamera nelle impostazioni del browser.',
      cameraError: 'Errore fotocamera: {e}', cameraLost: 'La fotocamera è stata spenta. Riavvia la scansione.',
      torchFail: 'Impossibile accendere la torcia', torchUnsupported: 'Torcia non controllabile su questo dispositivo',
      saveFail: 'Impossibile salvare la foto (memoria piena o navigazione privata?)',
      storageFail: 'Archivio foto non disponibile (navigazione privata?)',
      photoManual: 'Foto manuale', photoPoints: '{n} punto/i sospetto/i — {m}',
      modeNameReflect: 'riflesso dell’obiettivo', modeNameIR: 'infrarossi', auto: '(auto)', language: 'Lingua',
      guideTitle: 'Come scansionare una stanza',
      guide: [
        '<b>Modalità «Riflesso dell’obiettivo»</b>: abbassa le luci e accendi la torcia 🔦. Gli obiettivi delle telecamere riflettono la luce come un piccolo punto luminoso. Passa <b>lentamente</b> su pareti, soffitto, scaffali, giocattoli, specchi, rilevatori di fumo, prese, caricatori, sveglie, cornici…',
        'Tieni il telefono all’<b>altezza degli occhi</b>: il riflesso è più forte quando torcia e fotocamera sono allineate con l’obiettivo.',
        '<b>Modalità «Infrarossi»</b>: spegni tutte le luci. Le telecamere a visione notturna hanno LED a infrarossi invisibili all’occhio ma visibili al telefono (punti viola/bianchi). Suggerimento: tocca 🔄 per usare la fotocamera <b>anteriore</b>, che spesso vede meglio gli infrarossi.',
        'Quando un punto luminoso resta visibile per diversi fotogrammi, appare un cerchio rosso e viene <b>scattata automaticamente una foto</b>.',
        '<b>Microfoni</b>: un microfono non si vede con la fotocamera. Usa il rilevatore magnetico avvicinando il telefono agli oggetti sospetti e controlla a mano i piccoli fori sospetti.',
        '<b>Specchio spia</b>: appoggia la punta del dito sullo specchio. Se <b>non c’è spazio</b> tra il dito e il suo riflesso, appoggia la torcia al vetro per vedere se c’è qualcosa dietro.'
      ],
      warn: '<b>⚠️ Limiti:</b> nessuna app può garantire di trovare il 100% delle telecamere o dei microfoni. Possono esserci falsi allarmi (viti lucide, gioielli, gocce d’acqua, LED di apparecchi). Verifica sempre ogni allarme con i tuoi occhi. In caso di serio dubbio, contatta la polizia o un professionista.'
    },
    pt: {
      _name: 'Português',
      title: 'Detetor de Câmaras e Microfones',
      tabScan: 'Analisar', tabPhotos: 'Fotos', tabGuide: 'Guia',
      statusIdle: 'Toque em «Iniciar análise»',
      start: '▶ Iniciar análise', stop: '⏹ Parar', torch: '🔦 Lanterna', photo: '📷 Foto', switchCam: '🔄 Câmara',
      mode: 'Modo', modeReflect: 'Reflexo da lente (lanterna ligada)', modeIR: 'Infravermelho (divisão às escuras)',
      sensitivity: 'Sensibilidade',
      autoShot: 'Tirar uma foto automaticamente quando houver suspeita de câmara', sound: 'Bip + vibração',
      magTitle: '🧲 Detetor magnético (microfones, eletrónica)',
      magInit: 'O magnetómetro será ativado ao iniciar a análise, se o telemóvel o permitir.',
      magHint: 'Aproxime o telemóvel a 2–5 cm dos objetos: um aumento forte pode indicar um microfone, uma bateria ou um circuito eletrónico escondido.',
      magNotSupported: 'O magnetómetro não está disponível no navegador deste aparelho. No Android/Chrome: chrome://flags → «Generic Sensor Extra Classes» → Enabled.',
      magUnavailable: 'Magnetómetro indisponível: {e}',
      magField: 'Campo: {v} µT • diferença: {d} µT', magWarn: ' ⚠️ eletrónica/metal perto!',
      photosTitle: 'Fotos das deteções', clearAll: '🗑 Apagar tudo',
      photosHint: 'As fotos ficam no seu telemóvel (nada é enviado para a Internet). Toque em «Guardar» para as manter nos seus ficheiros.',
      noPhotos: 'Ainda não há fotos.', save: '💾 Guardar', share: '📤 Partilhar', confirmClear: 'Apagar todas as fotos?',
      scanning: 'A analisar… mova devagar', nothing: 'A analisar… nada suspeito',
      noisy: 'Demasiados reflexos aqui (superfície brilhante) — mude o ângulo',
      alertLens: 'Possível lente de câmara!', alertIR: 'Possível LED infravermelho!', stopped: 'Análise parada',
      noCamera: 'Câmara indisponível. Abra a página em HTTPS no Chrome ou no Safari.',
      cameraDenied: 'Acesso à câmara recusado. Permita a câmara nas definições do navegador.',
      cameraError: 'Erro da câmara: {e}', cameraLost: 'A câmara foi desligada. Inicie a análise novamente.',
      torchFail: 'Não foi possível ligar a lanterna', torchUnsupported: 'A lanterna não pode ser controlada neste aparelho',
      saveFail: 'Não foi possível guardar a foto (armazenamento cheio ou navegação privada?)',
      storageFail: 'Armazenamento de fotos indisponível (navegação privada?)',
      photoManual: 'Foto manual', photoPoints: '{n} ponto(s) suspeito(s) — {m}',
      modeNameReflect: 'reflexo da lente', modeNameIR: 'infravermelho', auto: '(auto)', language: 'Idioma',
      guideTitle: 'Como analisar uma divisão',
      guide: [
        '<b>Modo «Reflexo da lente»</b>: baixe a luz e ligue a lanterna 🔦. As lentes das câmaras devolvem a luz como um pequeno ponto brilhante. Percorra <b>devagar</b> paredes, teto, prateleiras, brinquedos, espelhos, detetores de fumo, tomadas, carregadores, despertadores, molduras…',
        'Segure o telemóvel à <b>altura dos olhos</b>: o reflexo é mais forte quando a lanterna e a câmara estão alinhadas com a lente.',
        '<b>Modo «Infravermelho»</b>: apague todas as luzes. As câmaras de visão noturna têm LED infravermelhos invisíveis ao olho, mas visíveis para o telemóvel (pontos roxos/brancos). Dica: toque em 🔄 para usar a câmara <b>frontal</b>, que muitas vezes vê melhor o infravermelho.',
        'Quando um ponto brilhante fica visível durante várias imagens seguidas, aparece um círculo vermelho e é <b>tirada uma foto automaticamente</b>.',
        '<b>Microfones</b>: um microfone não se vê com a câmara. Use o detetor magnético aproximando o telemóvel dos objetos suspeitos e verifique à mão os pequenos furos suspeitos.',
        '<b>Espelho espião</b>: encoste a ponta do dedo ao espelho. Se <b>não houver espaço</b> entre o dedo e o reflexo, encoste a lanterna ao vidro para ver se há algo atrás.'
      ],
      warn: '<b>⚠️ Limites:</b> nenhuma aplicação pode garantir encontrar 100% das câmaras ou microfones. Podem ocorrer falsos alarmes (parafusos brilhantes, joias, gotas de água, LED de aparelhos). Verifique sempre cada alerta com os seus próprios olhos. Em caso de dúvida séria, contacte a polícia ou um profissional.'
    },
    tr: {
      _name: 'Türkçe',
      title: 'Kamera ve Mikrofon Dedektörü',
      tabScan: 'Tara', tabPhotos: 'Fotoğraflar', tabGuide: 'Rehber',
      statusIdle: '“Taramayı başlat”a dokunun',
      start: '▶ Taramayı başlat', stop: '⏹ Durdur', torch: '🔦 Fener', photo: '📷 Fotoğraf', switchCam: '🔄 Kamera',
      mode: 'Mod', modeReflect: 'Lens yansıması (fener açık)', modeIR: 'Kızılötesi (karanlık oda)',
      sensitivity: 'Hassasiyet',
      autoShot: 'Kameradan şüphelenildiğinde otomatik fotoğraf çek', sound: 'Bip sesi + titreşim',
      magTitle: '🧲 Manyetik dedektör (mikrofonlar, elektronik)',
      magInit: 'Telefonunuz izin veriyorsa manyetometre taramayla birlikte başlar.',
      magHint: 'Telefonu nesnelere 2–5 cm yaklaştırın: güçlü bir artış gizli bir mikrofon, pil veya elektronik devreye işaret edebilir.',
      magNotSupported: 'Bu cihazda manyetometreye tarayıcıdan erişilemiyor. Android/Chrome: chrome://flags → “Generic Sensor Extra Classes” → Enabled.',
      magUnavailable: 'Manyetometre kullanılamıyor: {e}',
      magField: 'Alan: {v} µT • sapma: {d} µT', magWarn: ' ⚠️ yakında elektronik/metal var!',
      photosTitle: 'Tespit fotoğrafları', clearAll: '🗑 Tümünü sil',
      photosHint: 'Fotoğraflar telefonunuzda kalır (internete hiçbir şey gönderilmez). Dosyalarınızda saklamak için “Kaydet”e dokunun.',
      noPhotos: 'Henüz fotoğraf yok.', save: '💾 Kaydet', share: '📤 Paylaş', confirmClear: 'Tüm fotoğraflar silinsin mi?',
      scanning: 'Taranıyor… yavaşça hareket ettirin', nothing: 'Taranıyor… şüpheli bir şey yok',
      noisy: 'Burada çok fazla yansıma var (parlak yüzey) — açıyı değiştirin',
      alertLens: 'Şüpheli kamera lensi!', alertIR: 'Şüpheli kızılötesi LED!', stopped: 'Tarama durduruldu',
      noCamera: 'Kamera kullanılamıyor. Sayfayı Chrome veya Safari’de HTTPS ile açın.',
      cameraDenied: 'Kamera erişimi reddedildi. Tarayıcı ayarlarından kameraya izin verin.',
      cameraError: 'Kamera hatası: {e}', cameraLost: 'Kamera kapandı. Taramayı yeniden başlatın.',
      torchFail: 'Fener açılamadı', torchUnsupported: 'Bu cihazda fener kontrol edilemiyor',
      saveFail: 'Fotoğraf kaydedilemedi (depolama dolu veya gizli gezinme?)',
      storageFail: 'Fotoğraf depolama kullanılamıyor (gizli gezinme?)',
      photoManual: 'Manuel fotoğraf', photoPoints: '{n} şüpheli nokta — {m}',
      modeNameReflect: 'lens yansıması', modeNameIR: 'kızılötesi', auto: '(otomatik)', language: 'Dil',
      guideTitle: 'Bir oda nasıl taranır',
      guide: [
        '<b>“Lens yansıması” modu</b>: ışıkları kısın ve feneri 🔦 açın. Kamera lensleri ışığı küçük parlak bir nokta olarak geri yansıtır. Duvarları, tavanı, rafları, oyuncakları, aynaları, duman dedektörlerini, prizleri, şarj cihazlarını, saatleri, çerçeveleri <b>yavaşça</b> tarayın…',
        'Telefonu <b>göz hizasında</b> tutun: fener ve kamera lensle aynı hizadayken yansıma en güçlüdür.',
        '<b>“Kızılötesi” modu</b>: tüm ışıkları kapatın. Gece görüşlü kameralarda gözle görülmeyen ama telefonun görebildiği kızılötesi LED’ler vardır (mor/beyaz noktalar). İpucu: kızılötesini genellikle daha iyi gören <b>ön</b> kamerayı kullanmak için 🔄’e dokunun.',
        'Parlak bir nokta birkaç kare boyunca görünür kalırsa kırmızı bir daire belirir ve <b>otomatik olarak fotoğraf çekilir</b>.',
        '<b>Mikrofonlar</b>: mikrofon kamerayla görülemez. Telefonu şüpheli nesnelere yaklaştırarak manyetik dedektörü kullanın ve küçük şüpheli delikleri elle kontrol edin.',
        '<b>Casus ayna</b>: parmak ucunuzu aynaya dokundurun. Parmağınızla yansıması arasında <b>hiç boşluk yoksa</b>, arkasında bir şey olup olmadığını görmek için feneri cama dayayın.'
      ],
      warn: '<b>⚠️ Sınırlar:</b> hiçbir uygulama kameraların veya mikrofonların %100’ünü bulmayı garanti edemez. Yanlış alarmlar olabilir (parlak vidalar, takılar, su damlaları, cihaz LED’leri). Her uyarıyı mutlaka kendi gözünüzle kontrol edin. Ciddi şüpheniz varsa polise veya bir uzmana başvurun.'
    },
    ar: {
      _name: 'العربية', _rtl: true,
      title: 'كاشف الكاميرات والميكروفونات',
      tabScan: 'فحص', tabPhotos: 'الصور', tabGuide: 'الدليل',
      statusIdle: 'اضغط على «بدء الفحص»',
      start: '▶ بدء الفحص', stop: '⏹ إيقاف', torch: '🔦 المصباح', photo: '📷 صورة', switchCam: '🔄 الكاميرا',
      mode: 'الوضع', modeReflect: 'انعكاس العدسة (المصباح مضاء)', modeIR: 'الأشعة تحت الحمراء (غرفة مظلمة)',
      sensitivity: 'الحساسية',
      autoShot: 'التقاط صورة تلقائيًا عند الاشتباه بوجود كاميرا', sound: 'صفير + اهتزاز',
      magTitle: '🧲 الكاشف المغناطيسي (ميكروفونات، إلكترونيات)',
      magInit: 'سيبدأ مقياس المغناطيسية مع الفحص إذا كان هاتفك يسمح بذلك.',
      magHint: 'قرّب الهاتف من الأشياء على بعد 2–5 سم: الارتفاع القوي قد يدل على ميكروفون أو بطارية أو دائرة إلكترونية مخفية.',
      magNotSupported: 'مقياس المغناطيسية غير متاح في متصفح هذا الجهاز. على أندرويد/كروم: chrome://flags ← «Generic Sensor Extra Classes» ← Enabled.',
      magUnavailable: 'مقياس المغناطيسية غير متاح: {e}',
      magField: 'المجال: {v} µT • الفرق: {d} µT', magWarn: ' ⚠️ إلكترونيات/معدن قريب!',
      photosTitle: 'صور الاكتشافات', clearAll: '🗑 حذف الكل',
      photosHint: 'تبقى الصور على هاتفك (لا يُرسل أي شيء إلى الإنترنت). اضغط على «حفظ» للاحتفاظ بها في ملفاتك.',
      noPhotos: 'لا توجد صور بعد.', save: '💾 حفظ', share: '📤 مشاركة', confirmClear: 'حذف جميع الصور؟',
      scanning: 'جارٍ الفحص… تحرّك ببطء', nothing: 'جارٍ الفحص… لا شيء مريب',
      noisy: 'انعكاسات كثيرة هنا (سطح لامع) — غيّر الزاوية',
      alertLens: 'عدسة كاميرا مشتبه بها!', alertIR: 'مصباح أشعة تحت حمراء مشتبه به!', stopped: 'توقف الفحص',
      noCamera: 'الكاميرا غير متاحة. افتح الصفحة عبر HTTPS في كروم أو سفاري.',
      cameraDenied: 'تم رفض الوصول إلى الكاميرا. اسمح بالكاميرا في إعدادات المتصفح.',
      cameraError: 'خطأ في الكاميرا: {e}', cameraLost: 'تم إيقاف الكاميرا. أعد بدء الفحص.',
      torchFail: 'تعذّر تشغيل المصباح', torchUnsupported: 'لا يمكن التحكم بالمصباح على هذا الجهاز',
      saveFail: 'تعذّر حفظ الصورة (الذاكرة ممتلئة أو تصفح خاص؟)',
      storageFail: 'تخزين الصور غير متاح (تصفح خاص؟)',
      photoManual: 'صورة يدوية', photoPoints: '{n} نقطة مشتبه بها — {m}',
      modeNameReflect: 'انعكاس العدسة', modeNameIR: 'أشعة تحت حمراء', auto: '(تلقائي)', language: 'اللغة',
      guideTitle: 'كيف تفحص غرفة',
      guide: [
        '<b>وضع «انعكاس العدسة»</b>: خفّف الإضاءة وشغّل المصباح 🔦. تعكس عدسات الكاميرات الضوء على شكل نقطة لامعة صغيرة. مرّر الهاتف <b>ببطء</b> على الجدران والسقف والرفوف والألعاب والمرايا وكواشف الدخان والمقابس والشواحن والساعات والإطارات…',
        'أمسك الهاتف <b>بمستوى عينيك</b>: يكون الانعكاس أقوى عندما يكون المصباح والكاميرا على خط واحد مع العدسة.',
        '<b>وضع «الأشعة تحت الحمراء»</b>: أطفئ جميع الأضواء. لكاميرات الرؤية الليلية مصابيح أشعة تحت حمراء لا تراها العين لكن يراها الهاتف (نقاط بنفسجية/بيضاء). نصيحة: اضغط على 🔄 لاستخدام الكاميرا <b>الأمامية</b> التي غالبًا ما ترى الأشعة تحت الحمراء بشكل أفضل.',
        'عندما تبقى نقطة لامعة ظاهرة لعدة صور متتالية، تظهر دائرة حمراء و<b>تُلتقط صورة تلقائيًا</b>.',
        '<b>الميكروفونات</b>: لا يمكن رؤية الميكروفون بالكاميرا. استخدم الكاشف المغناطيسي بتقريب الهاتف من الأشياء المشبوهة، وافحص الثقوب الصغيرة المشبوهة بيدك.',
        '<b>المرآة ذات الاتجاهين</b>: ضع طرف إصبعك على المرآة. إذا <b>لم توجد مسافة</b> بين إصبعك وانعكاسه، ألصق المصباح بالزجاج لترى إن كان هناك شيء خلفه.'
      ],
      warn: '<b>⚠️ الحدود:</b> لا يمكن لأي تطبيق أن يضمن العثور على 100٪ من الكاميرات أو الميكروفونات. قد تحدث إنذارات خاطئة (براغٍ لامعة، مجوهرات، قطرات ماء، مصابيح أجهزة). تحقّق دائمًا من كل تنبيه بعينيك. إذا كان لديك شك جدي، اتصل بالشرطة أو بمختص.'
    }
  };

  // Aide pour autoriser la caméra (un site web ne peut pas ouvrir les réglages lui-même).
  const PERM = {
    fr: {
      permTitle: '📷 Autoriser la caméra',
      permIntro: "Pour votre sécurité, aucune page web ne peut ouvrir elle-même les réglages. Suivez ces étapes, le scan démarrera tout seul dès que la caméra sera autorisée :",
      permAndroid: ["En haut de Chrome, touchez l'icône à gauche de l'adresse (🔒 ou ⚙️).", "Touchez « Autorisations », puis « Caméra ».", "Choisissez « Autoriser ».", "Si ça ne marche toujours pas : Réglages du téléphone → Applications → Chrome → Autorisations → Caméra → Autoriser."],
      permIOS: ["Dans Safari, touchez « aA » à gauche de l'adresse.", "Touchez « Réglages du site web », puis « Caméra ».", "Choisissez « Autoriser ».", "Si ça ne marche toujours pas : Réglages de l'iPhone → Safari → Caméra → Autoriser."],
      permDesktop: ["Cliquez sur l'icône à gauche de l'adresse (🔒 ou ⓘ).", "À côté de « Caméra », choisissez « Autoriser ».", "Fermez les autres applications qui utilisent la webcam (Zoom, Teams…)."],
      permFile: "La caméra est bloquée car l'application est ouverte comme un fichier. Sur téléphone, ouvrez-la depuis son adresse en ligne (https://…).",
      retry: '🔄 Réessayer', close: 'Fermer', delete: 'Supprimer'
    },
    en: {
      permTitle: '📷 Allow the camera',
      permIntro: 'For your security, no web page can open the settings by itself. Follow these steps; the scan will start automatically as soon as the camera is allowed:',
      permAndroid: ['At the top of Chrome, tap the icon to the left of the address (🔒 or ⚙️).', 'Tap “Permissions”, then “Camera”.', 'Choose “Allow”.', 'If it still does not work: phone Settings → Apps → Chrome → Permissions → Camera → Allow.'],
      permIOS: ['In Safari, tap “aA” to the left of the address.', 'Tap “Website Settings”, then “Camera”.', 'Choose “Allow”.', 'If it still does not work: iPhone Settings → Safari → Camera → Allow.'],
      permDesktop: ['Click the icon to the left of the address (🔒 or ⓘ).', 'Next to “Camera”, choose “Allow”.', 'Close other apps using the webcam (Zoom, Teams…).'],
      permFile: 'The camera is blocked because the app was opened as a file. On a phone, open it from its online address (https://…).',
      retry: '🔄 Try again', close: 'Close', delete: 'Delete'
    },
    de: {
      permTitle: '📷 Kamera erlauben',
      permIntro: 'Aus Sicherheitsgründen kann keine Webseite die Einstellungen selbst öffnen. Folgen Sie diesen Schritten – der Scan startet automatisch, sobald die Kamera erlaubt ist:',
      permAndroid: ['Tippen Sie oben in Chrome auf das Symbol links neben der Adresse (🔒 oder ⚙️).', 'Tippen Sie auf „Berechtigungen“ und dann auf „Kamera“.', 'Wählen Sie „Zulassen“.', 'Falls es immer noch nicht geht: Handy-Einstellungen → Apps → Chrome → Berechtigungen → Kamera → Zulassen.'],
      permIOS: ['Tippen Sie in Safari links neben der Adresse auf „aA“.', 'Tippen Sie auf „Website-Einstellungen“ und dann auf „Kamera“.', 'Wählen Sie „Erlauben“.', 'Falls es immer noch nicht geht: iPhone-Einstellungen → Safari → Kamera → Erlauben.'],
      permDesktop: ['Klicken Sie auf das Symbol links neben der Adresse (🔒 oder ⓘ).', 'Wählen Sie neben „Kamera“ die Option „Zulassen“.', 'Schließen Sie andere Apps, die die Webcam nutzen (Zoom, Teams…).'],
      permFile: 'Die Kamera ist blockiert, weil die App als Datei geöffnet wurde. Öffnen Sie sie auf dem Handy über ihre Online-Adresse (https://…).',
      retry: '🔄 Erneut versuchen', close: 'Schließen', delete: 'Löschen'
    },
    es: {
      permTitle: '📷 Permitir la cámara',
      permIntro: 'Por su seguridad, ninguna página web puede abrir los ajustes por sí misma. Siga estos pasos; el escaneo empezará solo en cuanto se permita la cámara:',
      permAndroid: ['En la parte superior de Chrome, toque el icono a la izquierda de la dirección (🔒 o ⚙️).', 'Toque «Permisos» y luego «Cámara».', 'Elija «Permitir».', 'Si sigue sin funcionar: Ajustes del teléfono → Aplicaciones → Chrome → Permisos → Cámara → Permitir.'],
      permIOS: ['En Safari, toque «aA» a la izquierda de la dirección.', 'Toque «Ajustes del sitio web» y luego «Cámara».', 'Elija «Permitir».', 'Si sigue sin funcionar: Ajustes del iPhone → Safari → Cámara → Permitir.'],
      permDesktop: ['Haga clic en el icono a la izquierda de la dirección (🔒 o ⓘ).', 'Junto a «Cámara», elija «Permitir».', 'Cierre otras aplicaciones que usen la webcam (Zoom, Teams…).'],
      permFile: 'La cámara está bloqueada porque la aplicación se abrió como archivo. En el teléfono, ábrala desde su dirección en línea (https://…).',
      retry: '🔄 Reintentar', close: 'Cerrar', delete: 'Eliminar'
    },
    it: {
      permTitle: '📷 Consenti la fotocamera',
      permIntro: 'Per la tua sicurezza, nessuna pagina web può aprire da sola le impostazioni. Segui questi passaggi: la scansione partirà da sola appena la fotocamera sarà consentita:',
      permAndroid: ['In alto in Chrome, tocca l’icona a sinistra dell’indirizzo (🔒 o ⚙️).', 'Tocca «Autorizzazioni», poi «Fotocamera».', 'Scegli «Consenti».', 'Se ancora non funziona: Impostazioni del telefono → App → Chrome → Autorizzazioni → Fotocamera → Consenti.'],
      permIOS: ['In Safari, tocca «aA» a sinistra dell’indirizzo.', 'Tocca «Impostazioni sito web», poi «Fotocamera».', 'Scegli «Consenti».', 'Se ancora non funziona: Impostazioni iPhone → Safari → Fotocamera → Consenti.'],
      permDesktop: ['Fai clic sull’icona a sinistra dell’indirizzo (🔒 o ⓘ).', 'Accanto a «Fotocamera», scegli «Consenti».', 'Chiudi le altre app che usano la webcam (Zoom, Teams…).'],
      permFile: 'La fotocamera è bloccata perché l’app è stata aperta come file. Sul telefono, aprila dal suo indirizzo online (https://…).',
      retry: '🔄 Riprova', close: 'Chiudi', delete: 'Elimina'
    },
    pt: {
      permTitle: '📷 Permitir a câmara',
      permIntro: 'Por segurança, nenhuma página web pode abrir as definições sozinha. Siga estes passos; a análise começa sozinha assim que a câmara for permitida:',
      permAndroid: ['No topo do Chrome, toque no ícone à esquerda do endereço (🔒 ou ⚙️).', 'Toque em «Autorizações» e depois em «Câmara».', 'Escolha «Permitir».', 'Se ainda não funcionar: Definições do telemóvel → Aplicações → Chrome → Autorizações → Câmara → Permitir.'],
      permIOS: ['No Safari, toque em «aA» à esquerda do endereço.', 'Toque em «Definições do site» e depois em «Câmara».', 'Escolha «Permitir».', 'Se ainda não funcionar: Definições do iPhone → Safari → Câmara → Permitir.'],
      permDesktop: ['Clique no ícone à esquerda do endereço (🔒 ou ⓘ).', 'Ao lado de «Câmara», escolha «Permitir».', 'Feche outras aplicações que usem a webcam (Zoom, Teams…).'],
      permFile: 'A câmara está bloqueada porque a aplicação foi aberta como ficheiro. No telemóvel, abra-a a partir do endereço online (https://…).',
      retry: '🔄 Tentar novamente', close: 'Fechar', delete: 'Apagar'
    },
    tr: {
      permTitle: '📷 Kameraya izin verin',
      permIntro: 'Güvenliğiniz için hiçbir web sayfası ayarları kendi başına açamaz. Bu adımları izleyin; kameraya izin verilir verilmez tarama kendiliğinden başlar:',
      permAndroid: ['Chrome’un üst kısmında adresin solundaki simgeye (🔒 veya ⚙️) dokunun.', '“İzinler”e, ardından “Kamera”ya dokunun.', '“İzin ver”i seçin.', 'Hâlâ çalışmıyorsa: Telefon Ayarları → Uygulamalar → Chrome → İzinler → Kamera → İzin ver.'],
      permIOS: ['Safari’de adresin solundaki “aA”ya dokunun.', '“Web Sitesi Ayarları”na, ardından “Kamera”ya dokunun.', '“İzin Ver”i seçin.', 'Hâlâ çalışmıyorsa: iPhone Ayarları → Safari → Kamera → İzin Ver.'],
      permDesktop: ['Adresin solundaki simgeye (🔒 veya ⓘ) tıklayın.', '“Kamera”nın yanında “İzin ver”i seçin.', 'Web kamerasını kullanan diğer uygulamaları kapatın (Zoom, Teams…).'],
      permFile: 'Uygulama dosya olarak açıldığı için kamera engellendi. Telefonda uygulamayı çevrimiçi adresinden (https://…) açın.',
      retry: '🔄 Tekrar dene', close: 'Kapat', delete: 'Sil'
    },
    ar: {
      permTitle: '📷 السماح بالكاميرا',
      permIntro: 'لأسباب أمنية، لا يمكن لأي صفحة ويب فتح الإعدادات بنفسها. اتبع هذه الخطوات، وسيبدأ الفحص تلقائيًا بمجرد السماح بالكاميرا:',
      permAndroid: ['في أعلى كروم، اضغط على الرمز الموجود يسار العنوان (🔒 أو ⚙️).', 'اضغط على «الأذونات» ثم «الكاميرا».', 'اختر «السماح».', 'إذا لم ينجح ذلك: إعدادات الهاتف ← التطبيقات ← Chrome ← الأذونات ← الكاميرا ← السماح.'],
      permIOS: ['في سفاري، اضغط على «aA» يسار العنوان.', 'اضغط على «إعدادات موقع الويب» ثم «الكاميرا».', 'اختر «السماح».', 'إذا لم ينجح ذلك: إعدادات iPhone ← Safari ← الكاميرا ← السماح.'],
      permDesktop: ['انقر على الرمز الموجود يسار العنوان (🔒 أو ⓘ).', 'بجانب «الكاميرا»، اختر «السماح».', 'أغلق التطبيقات الأخرى التي تستخدم كاميرا الويب (Zoom وTeams…).'],
      permFile: 'الكاميرا محظورة لأن التطبيق فُتح كملف. على الهاتف، افتحه من عنوانه على الإنترنت (https://…).',
      retry: '🔄 إعادة المحاولة', close: 'إغلاق', delete: 'حذف'
    }
  };
  for (const k in PERM) Object.assign(T[k], PERM[k]);

  let lang = 'fr';
  function detect() {
    let saved = null;
    try { saved = localStorage.getItem('lang'); } catch (e) {}
    if (saved && T[saved]) return saved;
    const prefs = (navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language || 'fr']);
    for (const p of prefs) { const c = String(p).slice(0, 2).toLowerCase(); if (T[c]) return c; }
    return 'en';
  }
  function t(key, vars) {
    let s = (T[lang] && T[lang][key] != null) ? T[lang][key] : (T.en[key] != null ? T.en[key] : key);
    if (vars && typeof s === 'string') s = s.replace(/\{(\w+)\}/g, (m, k) => (vars[k] != null ? vars[k] : m));
    return s;
  }
  function apply() {
    document.documentElement.lang = lang;
    document.documentElement.dir = T[lang]._rtl ? 'rtl' : 'ltr';
    document.title = t('title');
    document.querySelectorAll('[data-i18n]').forEach(el => { el.textContent = t(el.dataset.i18n); });
    const ol = document.getElementById('guideList');
    if (ol) {
      ol.innerHTML = '';
      t('guide').forEach(h => { const li = document.createElement('li'); li.innerHTML = h; ol.appendChild(li); });
    }
    const w = document.getElementById('guideWarn');
    if (w) w.innerHTML = t('warn');
  }
  function set(code) {
    if (!T[code]) return;
    lang = code;
    try { localStorage.setItem('lang', code); } catch (e) {}
    apply();
    document.dispatchEvent(new CustomEvent('langchange'));
  }
  lang = detect();
  root.I18N = { t, set, apply, get lang() { return lang; }, languages: Object.keys(T).map(k => ({ code: k, name: T[k]._name })), _T: T };
})(this);
