// Testi dell'interfaccia (italiano), in un unico punto.
// Generato da tool/l10n.py e poi rivisto a mano: le schermate non contengono
// testi hardcoded, usano `S.<chiave>`.
// ignore_for_file: constant_identifier_names

class S {
  S._();

  // Slider con input numerico
  static const sliderEditHint =
      'Tocca per scrivere un valore. Invio per confermare, Esc per annullare';

  static const automatica = 'Automatica';
  static const usaTrasparenzaEsistente = "Usa la trasparenza dell'immagine";
  static const rimuoviSempreSfondo = 'Rimuovi sempre lo sfondo';
  static const nessunaImmagineIntera = 'Nessuna (immagine intera)';
  static const traslucido = 'Traslucido';
  static const liquidGlass = 'Vetro';
  static const minimal = 'Minimale';
  static const darkFlat = 'Scuro piatto';
  static const custom = 'Personalizzato';
  static String png(Object? a, Object? b) => '${a}_$b.png';
  static const studio = 'Studio';
  static const packCleanup = 'Pulizia pack';
  static const pack = 'Pack';
  static const app = 'App';
  static const baseIcons = 'Icone base';
  static const impostazioni = 'Impostazioni';
  static const opzioni = 'Opzioni';
  static const baseAttivo = 'Icona base attiva';
  static const referenceTranslucent = 'Traslucido di riferimento';
  static String kb(Object? a) => '$a KB';
  static String mb(Object? a) => '$a MB';
  static const iconFormatter = 'Icon Formatter';
  static const icone = 'Icone';
  static const nessunaIconaSelezionata = 'Nessuna icona selezionata';
  static const ingrandisci = 'Ingrandisci';
  static const importaBaseIcon = 'Importa icona base';
  static const nomeDelBaseIcon = 'Nome dell\'icona base';
  static String baseImportatoCalibraloCirca20(Object? a, Object? b) =>
      'Icona base importata ($a×$b). Calibrala con una ventina di icone di esempio.';
  static String importNonRiuscito(Object? a) => 'Importazione non riuscita: $a';
  static String baseCreatoDalPreset(Object? a) =>
      'Icona base creata dal preset $a';
  static const ogniBaseHaCalibrazioneIndipendente =
      "Ogni icona base ha la sua calibrazione. Le icone escono alla stessa risoluzione dell'icona base.";
  static const importaBase = 'Importa icona base';
  static String creaPreset(Object? a) => 'Crea da preset "$a"';
  static const nessunBaseIcon = 'Nessuna icona base';
  static String px(Object? a, Object? b) => '$a×${b}px';
  static const nonCalibrato = 'Non calibrato';
  static String calibratoEsempiValidiGlyph(Object? a, Object? b, Object? c) =>
      'Calibrata su $a esempi ($b validi) · simbolo al $c%';
  static const usa = 'Usa';
  static const calibra = 'Calibra';
  static const ricalibra = 'Ricalibra';
  static const rinomina = 'Rinomina';
  static String eliminare(Object? a) => 'Eliminare "$a"?';
  static const vieneRimossaCopiaInternaSua =
      "Vengono eliminate la copia salvata nell'app e la sua calibrazione. I tuoi file originali restano dove sono.";
  static const elimina = 'Elimina';
  static String calibrazioneSalvata(Object? a) => 'Calibrazione salvata per $a';
  static const esempiCorrettamenteComposti = 'Esempi di icone già fatte bene';
  static String esempiSelezionatiConsigliatiCirca20(Object? a) =>
      '$a esempi scelti (ne servono una ventina). Lo sfondo degli esempi non conta: si misura solo il simbolo.';
  static const file = 'File';
  static const cartella = 'Cartella';
  static const svuota = 'Svuota';
  static const analizzaCalibra = 'Analizza e calibra';
  static const risultatiMedianaOutlierEsclusi =
      'Risultati (valore medio, esempi anomali esclusi)';
  static const esempiValidi = 'Esempi validi';
  static const latoGlyph = 'Lato del simbolo';
  static String mad(Object? a, Object? b) => '$a% (scarto $b)';
  static const areaOttica = 'Area visiva';
  static const centro = 'Centro';
  static const marginiLTRB = 'Margini (sinistra, sopra, destra, sotto)';
  static const proporzioneMedia = 'Proporzione media';
  static const correzioneManuale = 'Correzione manuale';
  static const centroX = 'Centro X';
  static const centroY = 'Centro Y';
  static const dimensioneOtticaArea = 'Dimensione visiva (area)';
  static const ripristinaMisurati = 'Torna ai valori misurati';
  static const salvaCalibrazione = 'Salva calibrazione';
  static const areaUtileSulBase = "Area utile sull'icona base";
  static const verificaEsempio = 'Verifica su un esempio';
  static const esempi = 'Esempi';
  static String calibrazione(Object? a) => 'Calibrazione · $a';
  static String iconaNonDisponibile(Object? a) =>
      'Icona non disponibile per $a';
  static const selezionaAlmenoApp = 'Seleziona almeno un\'app';
  static String appSenzaIconaLeggibileSono(Object? a) =>
      '$a app saltate: la loro icona non si può leggere';
  static const nessunaIconaElaborataAvviaPrima =
      'Nessuna icona pronta: premi prima Elabora';
  static String iconformatterPack(Object? a) => 'IconFormatter_pack_$a';
  static String iconeAppfilterXmlGenerato(Object? a, Object? b) =>
      '$a · $b icone, con il file degli abbinamenti (appfilter.xml)';
  static String exportNonRiuscito(Object? a) => 'Esportazione non riuscita: $a';
  static const ricarica = 'Ricarica';
  static const iconPackZipAppfilterXml = 'Icon pack in un file ZIP';
  static const iconPackCartella = 'Icon pack in cartella';
  static const soloPngIndividuali = 'Solo le immagini PNG';
  static const condividiZip = 'Condividi ZIP';
  static const cercaNomeOPackage = "Cerca un'app";
  static const soloNonElaborate = 'Solo da elaborare';
  static const selezionaTutte = 'Seleziona tutte';
  static const deseleziona = 'Deseleziona';
  static const toccaSelezionareTieniPremutoAnteprima =
      "Tocca per selezionare, tieni premuto per l'anteprima e le correzioni";
  static String appSelezionate(Object? a, Object? b) => '$b di $a selezionate';
  static const originalComposition = 'Composizione originale';
  static const customPreset = 'Preset personalizzato';
  static String impossibileLeggereApp(Object? a) =>
      'Non riesco a leggere le app: $a';
  static const annullato = 'Annullato';
  static const regolazioni = 'Regolazioni';
  static const stile = 'Personalizza';
  static const altro = 'Altro';
  static const pbApriPack = 'Apri un pack';
  static const pbCondividiApk = 'Condividi APK';
  static String pbApkPronto(Object? v) =>
      'APK del pack $v pronto da condividere';
  static const pbPackInstallato = 'Pack installato su questo telefono';
  static const pbPackInstallatoSub =
      'Riprendi il pack di Icon Formatter già installato';
  static const pbPackDaFile = 'Da file APK o ZIP';
  static const pbPackDaFileSub =
      'Un pack creato con Icon Formatter, anche su un altro telefono';
  static String pbPackAperto(Object? n) =>
      '$n icone del pack aperte: modificale e premi Installa e applica per aggiornarlo';
  static const pbPackVuoto = 'Nel file non ci sono icone collegate ad app';
  static const dpFirmaDiversa =
      'Il pack installato è stato creato su un altro telefono: per aggiornarlo va sostituito';
  static const dpSostituzione = 'Sostituzione del pack…';
  static const dpSostituireTitolo = 'Sostituire il pack installato?';
  static const dpSostituireTesto =
      "Il pack installato è stato creato su un altro telefono, quindi Android non permette di aggiornarlo. Icon Formatter lo disinstalla, installa quello nuovo con le stesse icone e le tue modifiche, e lo seleziona di nuovo nel launcher. Per un attimo il launcher può mostrare le icone di sistema.";
  static const dpSostituisci = 'Sostituisci';
  static const leTueApp = 'Le tue app';
  static const packCleanupSub = 'Ripulisci o unisci un icon pack esistente';
  static const mostraAppSistema = 'App di sistema';
  static const selezionaLeApp = 'Seleziona delle app';
  static const ricaricaSub = 'Rileggi le app installate';
  static const altreAzioni = 'Altre azioni';
  static const mandaAlPackSub = 'Usa le icone per creare il tuo icon pack';
  static const esportaCartellaSub = 'Salva i PNG in una cartella';
  static const esportaZipSub = 'Un unico file .zip';
  static const condividiSub = 'Invia lo ZIP a un\'altra app';
  static const svuotaSub =
      'Togli tutte le icone dalla lista (i file originali restano)';
  static const studioVuotoTitolo = 'Trasforma le tue icone';
  static const studioVuotoSub =
      'Parti da immagini, una cartella, un icon pack o dalle app del telefono.';
  static const studioVuotoSubWin =
      'Trascina qui immagini, cartelle, ZIP o APK, oppure premi Importa icone.';
  static const importaIcone = 'Importa icone';
  static const usaAppDelTelefono = 'Usa le app del telefono';
  static const usaAppDelTelefonoSub = 'Le icone delle app installate';
  static const importaImmagini = 'Immagini o icon pack';
  static const importaImmaginiSub =
      "PNG, JPG, WEBP o SVG, oppure lo ZIP o l'APK di un icon pack";
  static const dimensione = 'Dimensione';
  static const dimensioneIcona = 'Dimensione icona';
  static String dimensioneSub(int n) =>
      n == 1 ? 'Vale solo per questa icona' : 'Vale per le $n icone importate';
  static const fatto = 'Fatto';
  static String scegliIconeTitolo(int n) => 'Scegli le icone ($n)';
  static String aggiungiN(int n) => n == 0 ? 'Aggiungi' : 'Aggiungi $n';
  static const cercaIcone = 'Cerca per nome';
  static const importaCartella = 'Cartella';
  static const importaCartellaSub = 'Tutte le immagini di una cartella';
  static const importaPronti = 'Icone già pronte';
  static const importaProntiSub =
      'Le metti solo in posizione e alla dimensione giusta';
  static const aggiungi = 'Aggiungi';
  static const studioPasso1Breve = 'Importa le icone';
  static const studioPasso2Breve =
      'Personalizza lo stile e premi Elabora tutte';
  static const studioPasso3Breve = 'Manda al Pack o esporta';
  static const scontornoClassico =
      'Standard: sul telefono, veloce e gratuito (consigliato)';
  static const scontornoAiLocale =
      'AI sul telefono: più precisa sulle icone difficili (scarica un modello da 4,6 MB)';
  static const scontornoRemoveBg =
      'remove.bg: online, serve una chiave API e consuma crediti';
  static const stileTitolo = 'Stile delle icone';
  static const stileSpiegazione =
      "Scegli come trasformare le icone. Ogni modifica si vede subito nell'anteprima: trascina la linea bianca per confrontare prima e dopo.";
  static const hintVuoto = 'Inizia importando le icone da trasformare.';
  static const hintDaElaborare = 'Scegli lo stile, poi Elabora.';
  static const hintInCorso = 'Elaborazione in corso…';
  static String hintParziale(Object? a, Object? b) => '$a di $b pronte.';
  static const hintFatto =
      'Fatto. Apri Altro per esportarle o mandarle al Pack.';
  static String elaboraApp(Object? a) => 'Elabora $a app';
  static const iconPackZip = 'Icon pack (ZIP o APK)';
  static String impossibileAprirePack(Object? a) =>
      'Non riesco ad aprire il pack: $a';
  static const nessunRisultatoVerificare = 'Nessun risultato da verificare';
  static String esportazioneNonRiuscita(Object? a) =>
      'Esportazione non riuscita: $a';
  static const drawableMancanti = 'Immagini mancanti';
  static const iconeNonMappate = 'Icone senza app';
  static const altriFilePreservati = 'Altri file mantenuti';
  static const dettagli = 'Dettagli';
  static const prossimaVerificare = 'Prossima da verificare';
  static const apriCartella = 'Apri cartella';
  static const apriZip = 'Apri ZIP';
  static const apriIconPackCartellaO =
      "Apri un icon pack (cartella o ZIP).\nNomi dei file e abbinamenti restano com'erano;\ngli originali non vengono modificati.";
  static const elaborazione = 'Elaborazione…';
  static const uniformaPack = 'Uniforma il pack';
  static const rielaboraCorretteErrori = 'Rielabora quelle da correggere';
  static const esportaCartella = 'Esporta cartella';
  static const esportaZip = 'Esporta ZIP';
  static const condividi = 'Condividi';
  static const dettagliMapping = 'Dettagli degli abbinamenti';
  static const note = 'Note';
  static const drawableAppfilterXmlSenzaIcona =
      "App nell'elenco del pack senza immagine";
  static const iconeNonReferenziate = 'Immagini non collegate a nessuna app';
  static const chiudi = 'Chiudi';
  static const appearance = 'Aspetto';
  static const processing = 'Elaborazione';
  static const export = 'Esportazione';
  static const system = 'Sistema';
  static const accento = 'Colore di accento';
  static const animazioni = 'Animazioni';
  static const dimensioni = 'Dimensioni';
  static const originalCompositionUsaDimensioneDel =
      "Con Composizione originale le icone hanno la dimensione dell'icona base scelta. Con Lucent e i preset usano:";
  static const scalaPosizionePredefinite = 'Dimensione e posizione predefinite';
  static const scala = 'Dimensione';
  static const posizioneX = 'Posizione orizzontale';
  static const posizioneY = 'Posizione verticale';
  static const marginiDerivanoDallaCalibrazioneDel =
      "I margini vengono dalla calibrazione dell'icona base (Impostazioni › Icone base).";
  static const rimozioneSfondoIsolamento = 'Rimozione dello sfondo';
  static const sensibilita = 'Sensibilità';
  static const rimuoviSfondoRacchiusoBuchi =
      'Togli anche lo sfondo racchiuso nel simbolo';
  static const qualitaRifinituraBordiAntiAlias = 'Bordi più puliti';
  static const separaPixelBordoDalloSfondo =
      'Separa i pixel del bordo dallo sfondo per evitare aloni';
  static const batch = 'Elaborazione multipla';
  static const thread = 'Processori usati';
  static const presetStile = 'Preset di stile';
  static const predefinitoModificabile = 'predefinito, modificabile';
  static const modifica = 'Modifica';
  static const ripristina = 'Ripristina';
  static const salvaChiave = 'Salva chiave';
  static const rimuovi = 'Rimuovi';
  static String errore(Object? a) => 'Errore: $a';
  static const segmentazionePackCleanup = 'Scontorno per la Pulizia pack';
  static const rimuoviSfondoRacchiuso = 'Togli lo sfondo racchiuso';
  static const rifinisciBordi = 'Rifinisci i bordi';
  static const stileDestinazione = 'Stile di destinazione';
  static const originalCompositionBaseSelezionato =
      "Composizione originale (icona base scelta)";
  static const preset = 'Preset';
  static const presetModalitaPreset = 'Preset (modalità Preset)';
  static const risultatiAmbiguiGlyphSimileAllo =
      'I risultati incerti (simbolo simile allo sfondo, sfondi complessi) vengono segnati in giallo, così puoi correggerli a mano.';
  static const formato = 'Formato';
  static const pngRgbaTrasparenzaReale8 = 'PNG con trasparenza vera.';
  static const risoluzione = 'Risoluzione';
  static const risoluzionePersonalizzata = 'Risoluzione personalizzata';
  static const nomiFile = 'Nomi dei file';
  static const nomeOriginale = 'Nome originale';
  static const nomeDimensione = 'Nome + dimensione';
  static const prefissoNome = 'Prefisso + nome';
  static const prefisso = 'Prefisso';
  static String esempio(Object? a) => 'Esempio: $a';
  static const destinazione = 'Destinazione';
  static const sceltaOgniEsportazione = 'La scegli a ogni esportazione';
  static const windowsDialogNativoAndroidStorage =
      "Su Windows scegli la cartella dalla finestra di sistema, su Android la cartella o il menu Condividi. I file che esistono già non vengono mai sovrascritti.";
  static const preferisciZip = 'Esporta come ZIP';
  static const cache = 'File temporanei';
  static const fileTemporaneiImportZipEstratti =
      'File importati e ZIP estratti';
  static const risultatiDelleSessioni = 'Icone elaborate nelle sessioni';
  static const eliminareRisultatiInterni =
      "Eliminare le icone elaborate salvate nell'app?";
  static const esportazioniGiaSalvateAltroveNon =
      'Le icone che hai già esportato altrove non vengono toccate.';
  static const performance = 'Prestazioni';
  static String coreRustElaborazioneParallelaRayon(Object? a) =>
      'Elaborazione in parallelo su $a processori.';
  static const elaborazioneParallelaAuto = 'Elaborazione in parallelo, con il numero di processori scelto in automatico.';
  static const ripristino = 'Ripristino';
  static const ripristinareImpostazioni = 'Ripristinare le impostazioni?';
  static const presetAspettoEdExportTornano =
      "Preset, aspetto ed esportazione tornano come all'inizio. Le icone base restano.";
  static const ripristinaImpostazioniPredefinite =
      'Ripristina le impostazioni iniziali';
  static const versione = 'Versione';
  static String iconFormatterCore(Object? a, Object? b) =>
      'Icon Formatter $a · motore $b';
  static String datiApp(Object? a) => "Dati dell'app: $a";
  static const providerRimozioneSfondo = 'Come togliere lo sfondo';
  static const ogniImmagineVieneInviataRemove =
      "Ogni immagine viene inviata a remove.bg; l'app poi centra e compone il risultato sul telefono.";
  static const chiaveSalvataInserisciSostituire =
      'Chiave salvata · scrivine una nuova per sostituirla';
  static const apiKeyRemoveBg = 'Chiave API di remove.bg';
  static const apiKeyRemoveBgSalvata = 'Chiave API di remove.bg salvata';
  static const testCrediti = 'Verifica e crediti';
  static const listino = 'Prezzi';
  static const hex = 'Esadecimale';
  static const formatoRrggbb = 'Formato #RRGGBB';
  static const saturazione = 'Saturazione';
  static const luminosita = 'Luminosità';
  static const blur = 'Sfocatura';
  static const spessore = 'Spessore';
  static const rifrazione = 'Rifrazione';
  static const aberrCromatica = 'Separazione dei colori';
  static const frost = 'Smerigliatura';
  static const tintaVetro = 'Tinta del vetro';
  static const luce = 'Luce';
  static const intensita = 'Intensità';
  static const angoloLuce = 'Direzione della luce';
  static const rimLight = 'Luce sul bordo';
  static const lucentezza = 'Lucentezza';
  static const bordoLucido = 'Bordo lucido';
  static const vetroNativo = 'Vetro nativo';
  static const stileApp = 'Stile';
  static const stileNothing = 'Stile Nothing';
  static const stileNothingSub =
      'Nero, card grigie e testi puliti, come le app di sistema Nothing';
  static const stileVetro = 'Vetro';
  static const stileVetroSub =
      'Superfici in vetro con rifrazione, e colore di accento a scelta';
  static const smerigliatura = 'Smerigliatura';
  static const pellicola = 'Pellicola';
  static const schedaAttiva = 'Scheda attiva';
  static const luceBordo = 'Luce del bordo';
  static const spessoreBordo = 'Spessore del bordo';
  static const separazioneColori = 'Separazione dei colori';
  static const vetroNeiPannelliNativo = 'Vetro anche nelle card';
  static const vetroNativoSub =
      'Rifrazione, smerigliatura, bordo sottile e luce sul bordo. Completo con Qualità.';
  static const riflessoSpeculareSulBordoPiu =
      'Un riflesso sul bordo, più forte dal lato della luce';
  static const leggibilita = 'Leggibilità';
  static const ombraTesto = 'Ombra del testo';
  static const sfocaturaOmbra = "Morbidezza dell'ombra";
  static const scurezzaLente = 'Scheda attiva più scura';
  static const qualita = 'Qualità';
  static String iconeImportate(Object? a) => '$a icone importate';
  static String importazioneNonRiuscita(Object? a) =>
      'Importazione non riuscita: $a';
  static const nessunaIconaElaborataEsportare =
      'Nessuna icona elaborata da esportare';
  static String iconformatter(Object? a, Object? b) => 'IconFormatter_${a}_$b';
  static const svuotareLista = 'Svuotare la lista?';
  static const fileOriginaliNonVengonoToccati =
      'I tuoi file originali non vengono toccati.';
  static const elaboraTutte = 'Elabora tutte';
  static const rilasciaImportare = 'Rilascia per importare';
  static const apiKeyMancante = 'Chiave API mancante';
  static String erroreHttp(Object? a) => 'Errore HTTP $a';
  static const localeRustOfflineGratuita = 'Standard (sul telefono, gratuito)';
  static const removeBgCloudCrediti = 'remove.bg (online, a crediti)';
  static const removeBgConsuma1Credito =
      "remove.bg consuma un credito per ogni immagine; i nuovi account ricevono qualche credito gratuito al mese. I prezzi sono sul sito di remove.bg.";
  static String connessioneOkCreditiChiamateGratuite(Object? a, Object? b) =>
      'Collegamento riuscito · crediti: $a · chiamate gratuite rimaste: $b';
  static String errore3(Object? a, Object? b, Object? c) => 'Errore $a: $b$c';
  static const removeBgSelezionatoMaSenza =
      'Hai scelto remove.bg ma manca la chiave API: aggiungila in Impostazioni › Elaborazione.';
  static const salvaZip = 'Salva ZIP';
  static const zipSalvato = 'ZIP salvato';
  static String fileSalvatiNellaCartellaScelta(Object? a) =>
      '$a file salvati nella cartella scelta';
  static const scegliCartellaDestinazione =
      'Scegli la cartella di destinazione';
  static String zipCreatoFile(Object? a) => 'ZIP creato ($a file)';
  static String fileEsportati(Object? a) => '$a file esportati';
  static const salvaPng = 'Salva PNG';
  static const pngSalvato = 'PNG salvato';
  static const importaIconePngJpgWebp =
      'Importa icone (PNG, JPG, WEBP, ZIP o APK)';
  static const importaZip = 'Importa ZIP o APK';
  static const importaCartellaIcone = 'Importa una cartella di icone';
  static const prima = 'Prima';
  static const dopo = 'Dopo';
  static String completateRimanentiErrori(
    Object? a,
    Object? b,
    Object? c,
    Object? d,
    Object? e,
  ) => '$a · $b di $c pronte · $d rimaste · $e errori';
  static const annulla = 'Annulla';
  static const applica = 'Applica';
  static const coloreSceglitu = 'Scegli un colore qualsiasi';
  static const accentoTitolo = "Colore di accento";
  static const tintaTitolo = 'Tinta del vetro';
  static const conferma = 'Conferma';
  static const anteprima = 'Anteprima';
  static const rotellaPinchZoomTrascinaSpostare =
      'Rotella o due dita per ingrandire · trascina per spostare';
  static const riduciIcona = 'Riduci a icona';
  static const modalita = 'Modalità';
  static const original = 'Originale';
  static const translucent = 'Lucent';
  static const baseIcon = 'Icona base';
  static const nessunBaseIconImportaneUno =
      'Nessuna icona base: importane una in Impostazioni › Icone base.';
  static const baseNonCalibratoUsoProporzioni =
      'Icona base non calibrata: uso le proporzioni standard. Calibrala con una ventina di icone di esempio.';
  static String calibratoGlyphCentro(Object? a, Object? b, Object? c) =>
      'Calibrata: simbolo al $a% · centro ($b, $c)';
  static const salvaComeNuovoPreset = 'Salva come nuovo preset';
  static const nomeDelPreset = 'Nome del preset';
  static const ripristinaValori = 'Ripristina i valori';
  static const eliminaPreset = 'Elimina preset';
  static const eliminarePreset = 'Eliminare il preset?';
  static const composizione = 'Composizione';
  static const rimuoviCorrezioni = 'Togli le correzioni';
  static const correggiSoloLIconaSelezionata =
      "Modifica solo l'icona selezionata";
  static const uniformaGlyphLarghiStrettiArea =
      "Uniforma i simboli larghi e stretti in base all'area";
  static String areaUtileLatoGlyphCentro(Object? a, Object? b, Object? c) =>
      'Area utile: lato del simbolo $a% · centro ($b, $c)';
  static const isolamentoGlyph = 'Scontorno del simbolo';
  static const rifinisciBordiAntiAlias = 'Rifinisci i bordi';
  static String dimensioneDelBasePx(Object? a) =>
      "dimensione dell'icona base ($a px)";
  static String predefinita(Object? a) => 'Predefinita: $a';
  static const frosting = 'Smerigliatura';
  static const trasparenzaSim = 'Trasparenza';
  static const tintaNeutra = 'Tinta neutra';
  static const contrasto = 'Contrasto';
  static const bordi = 'Bordi';
  static const riflessi = 'Riflessi';
  static const profondita = 'Profondità';
  static const curvatura = 'Curvatura';
  static const dimensioneForma = 'Dimensione della forma';
  static const nonElaborata = 'Non elaborata';
  static const errore4 = 'Errore';
  static String verificare(Object? a) => 'Da verificare: $a';
  static String ok(Object? a) => 'OK · $a';
  static const includi = 'Includi';
  static const escludi = 'Escludi';
  static const rielaboraQuestaIcona = 'Rielabora questa icona';
  static const rimuoviDallaLista = 'Rimuovi dalla lista';
  static const selezionaOImportaIcona = 'Seleziona o importa un\'icona';
  static String pxConfidenza(Object? a, Object? b, Object? c, Object? d) =>
      '$a · $b px · $c · sicurezza $d%';
  static const salvaQuestaIconaPng = 'Salva questa icona (PNG)';
  static const risultatoAmbiguoVerifica = 'Risultato incerto, controlla: ';
  static const nessunaIcona = 'Nessuna icona';

  // Lucent
  static const lucentTitle = 'Lucent';
  static const lucentInfo =
      "Piatto traslucido scuro o chiaro sulla forma dell'icona originale. Il simbolo resta quello originale, con i suoi colori.";
  static const lucentScuro = 'Scuro';
  static const lucentChiaro = 'Chiaro';
  static const lucentForma = 'Forma del piatto';
  static const lucentFormaOriginale = "Forma dell'icona originale";
  static const lucentFormaCerchio = 'Cerchio';
  static const lucentFormaSquircle = 'Squircle (consigliata)';
  static const lucentOpacitaPiatto = 'Opacità del piatto';
  static const lucentScalaGlifo = 'Dimensione del simbolo';
  static const lucentBordoLuce = 'Bordo luminoso';
  static const lucentMantieniComposizione =
      'Mantieni la composizione originale';
  static const lucentMantieniComposizioneSub =
      "Il simbolo resta dov'era e grande com'era nell'icona di partenza. Disattivato: tutti i simboli prendono la stessa dimensione.";
  static const lucentMonocromatico = 'Simbolo in un solo colore';
  static const lucentMonocromaticoSub =
      'Il simbolo prende il colore del tema del launcher. Disattivato: colori originali';
  static const lucentOmbraLauncher =
      "Aggiungi l'ombra del launcher all'immagine";
  static const lucentCodificaLauncher = 'Adatta per Nothing Launcher';
  static const lucentCodificaLauncherSub =
      'Compensa il doppio disegno e le ombre del launcher. Solo per pack usati con Nothing Launcher.';

  // AI locale
  static const aiLocaleOffline =
      'AI sul telefono (offline, modello da scaricare)';
  static const aiModelU2netpNote =
      "Leggero: circa 1 secondo per icona su PC, qualche secondo sul telefono, senza bloccare l'app.";
  static const aiModelIsnetNote =
      'Più preciso sui bordi sottili: circa 7 secondi per icona su PC. Troppo pesante per il telefono.';
  static const aiTagTelefono = 'Telefono';
  static const aiTagWindows = 'Windows';
  static const aiTagSoloWindows = 'Solo Windows';
  static String aiDownloadFallito(Object? e) => 'Download non riuscito: $e';
  static const aiLocaleInfo =
      "Scontorno con una rete neurale che gira sul dispositivo: nessuna immagine esce dal telefono. Se l'icona ha già lo sfondo trasparente il passaggio viene saltato, e i risultati incerti vengono segnalati.";
  static String aiModelloDettagli(Object? size, Object? ram) =>
      "Download $size · memoria durante l'uso circa $ram MB";
  static const aiEliminaModello = 'Elimina il modello';
  static const aiScarica = 'Scarica';
  static const aiSogliaBassa = 'Soglia bassa';
  static const aiSogliaAlta = 'Soglia alta';
  static const aiProvaMaschera = "Prova su un'immagine";
  static const aiModelloMancante =
      'Modello non scaricato: finché manca si usa lo scontorno standard.';
  static const aiMascheraTitolo = 'Anteprima scontorno AI';
  static const aiOriginale = 'Originale';
  static const aiMaschera = 'Maschera';
  static const aiRisultato = 'Risultato';
  static const aiNonNecessaria = 'Non serve: lo sfondo è già trasparente.';
  static const aiIncerto =
      "Risultato incerto: l'icona verrà segnalata. Regola le soglie o usa lo scontorno standard per questa icona.";
  static String aiAffidabile(Object? c) =>
      'Scontorno affidabile · sicurezza $c%';
  static const aiCorrezioneInfo =
      'Sotto la soglia bassa il pixel diventa trasparente, sopra quella alta resta pieno; in mezzo sfuma.';
  static const aiAnteprimaMascheraSelezionata =
      "Anteprima scontorno AI dell'icona selezionata";
  static const zipOApk = 'ZIP o APK';

  // Icon Pack Builder
  static const pbTitolo = 'Icon Pack Builder';
  static const pbOriginali = 'Originali';
  static const pbGeneraDaStudio = 'Crea con lo Studio';
  static const pbImportaGenerate = 'Importa icone';
  static const pbAbbina = 'Abbina';
  static const pbLetturaApp = 'Leggo le app installate…';
  static const pbLettura = 'Lettura…';
  static String pbOriginaliCaricati(Object? n) => '$n app';
  static String pbGenerateCaricate(Object? n) => '$n icone nuove';
  static String pbGenerazione(Object? a, Object? b) => 'Creazione $a di $b';
  static const pbAbbinamento = 'Abbino le icone…';
  static String pbRisultatoAbbinamento(Object? a, Object? b) =>
      '$a app su $b hanno la loro icona';
  static const pbRielaborata = 'Rielaborata dallo Studio';
  static const pbCorrezioneSalvata = 'Correzione salvata';
  static const pbAssegnataManualmente = 'Scelta a mano';
  static String pbEsportate(Object? n) => '$n icone nel pack';
  static const pbEsportaZip = 'Esporta ZIP';
  static const pbNienteDaEsportare = 'Nessuna icona abbinata da esportare';
  static const pbSicura = 'Abbinata';
  static const pbVerificata = 'Verificata';
  static const pbDubbia = 'Incerta';
  static const pbMancante = 'Icona mancante';
  static const pbDaVerificare = 'Da verificare';
  static const pbNessunaIcona =
      "Nel pack non c'è ancora un'icona per questa app";
  static const pbSistema = 'Sistema';
  static const pbIconaPersonalizzata = 'Icona modificata a mano';
  static const pbRipristinata = 'Icona precedente ripristinata';
  static String pbIconaAggiornata(Object? a) =>
      'Icona di $a aggiornata nel pack';
  static String pbIconaRipristinata(Object? a) =>
      'Icona precedente di $a ripristinata';
  static const pbModificaIcona = 'Modifica icona';
  static const pbRipristinaPrecedente = 'Ripristina icona precedente';
  static const cercaNomeFile = 'Cerca per nome file';
  static const cancellaRicerca = 'Cancella ricerca';
  static String nessunRisultato(String q) => 'Nessuna icona contiene "$q"';
  static const dpRimosso =
      'Il pack è stato disinstallato. Puoi rigenerarlo e reinstallarlo da qui.';
  static const dpRimossoRipristinato =
      'Il pack è stato disinstallato: il launcher è tornato alle icone di prima.';
  static String dpResiduo(Object? v) =>
      'Pack disinstallato, ma Android conserva ancora i suoi dati${v == null ? '' : ' (versione $v)'}, anche per un altro utente del telefono. La prossima installazione continua la numerazione.';
  static const dpPulisciResidui = 'Elimina i dati rimasti';
  static const dpResiduiPuliti = 'Dati del pack eliminati.';
  static const dpResiduiRimasti =
      'Restano copie del pack che non si possono eliminare da qui (per esempio nello Spazio privato bloccato).';
  static const pbDaStudio = 'Icona dallo Studio (ha la precedenza)';
  static String iconeDelPack(String p) => 'Icone del pack in uso: $p';
  static const mantieniBiancoInterno = 'Mantieni il bianco interno';
  static const togliBiancoInterno = 'Togli il bianco interno';
  static const modoSenzaAlone = 'Bordo pieno senza alone';
  static const modoSenzaAloneDesc =
      "Per icone a tutto schermo già nello stile: l'alone scuro attorno alle strisce colorate sul bordo prende il colore del piatto. Le strisce restano.";
  static const calendarioDaPack = 'Calendario da un icon pack';
  static const calendarioDaPackSub =
      'Solo le icone del calendario che cambiano ogni giorno';
  static const calendarioNonInstallati = 'Nessuna delle app calendario del pack è installata su questo telefono';
  static const calendarioNessuno =
      'Questo icon pack non ha icone calendario che cambiano';
  static String calendarioImportato(int n, int apps) =>
      '$n icone calendario importate (${apps == 1 ? '1 app' : '$apps app'}): elaborale e mandale al Pack';
  static String calendarioNelPack(int apps) =>
      'Calendario nel pack (${apps == 1 ? '1 app' : '$apps app'}): il launcher mostra il giorno di oggi';
  static const modoPagina = 'Pagina intera';
  static const modoPaginaDesc =
      "L'icona intera (per esempio un calendario) arriva fino al bordo del piatto, senza togliere niente e con i suoi colori.";
  static const vetroQualitaNonDisponibile =
      "Su questo computer la qualità massima del vetro non è disponibile: si usa Bilanciato, così l'app non si blocca.";
  static const stileSpiegazioneModifica =
      'Le stesse regolazioni dello Studio: valgono per questa icona e per le prossime create nel Pack.';
  static const pbTieniPremuto =
      "Tieni premuto su un'app per modificarne l'icona";
  static const pbPasso1Catalogo = 'App installate';
  static const pbCatalogoLettura = 'Leggo le app installate…';
  static String pbCatalogoInfo(Object? n, Object? v) => '$n app installate';
  static String pbCatalogo(Object? n, Object? v) =>
      '$n app ($v viste da Android)';
  static const pbAggiornaCatalogo = 'Aggiorna elenco';
  static const pbImmagine = 'Immagine';
  static const pbFormatiImmagine = 'PNG, JPG o WEBP';
  static const pbScegliImmagine = 'Scegli immagine';
  static const pbCambiaImmagine = 'Cambia immagine';
  static const pbScegliImmagineHint =
      "Scegli un'immagine per vedere il risultato";
  static const pbTrattamento = 'Trattamento';
  static const pbTrattamentoSub = "Come trattare l'immagine";
  static const pbSoloPosizione =
      'Solo posizione e dimensione, sullo sfondo delle icone';
  static const pbUsaComeE = "Usa l'immagine così com'è";
  static const pbConfermaSostituzione = 'Conferma';
  static const scorriPerChiudereAvviso = 'Scorri di lato per chiudere';
  static const pbEsclusa = 'Esclusa';
  static const pbPerPackage = 'stesso package';
  static const pbPerNomeApp = 'stesso nome';
  static const pbPerNomeFile = 'nome del file';
  static String pbSomiglianza(Object? n) => 'somiglianza $n%';
  static String pbSoloSomiglianza(Object? n) => 'solo somiglianza visiva $n%';
  static const vaiInCima = 'Vai in cima';
  static const vaiInFondo = 'Vai in fondo';
  static const modalitaChiara = 'Modalità chiara';
  static const sfondoComePack = 'Sfondo come il pack';
  static const sfondoComePackSub = 'Porta la trasparenza dello sfondo a quella delle altre icone';
  static const sfondoNientePack = 'Elabora prima le icone';
  static const sfondoGiaUguale = 'Lo sfondo ha già la trasparenza del pack';
  static String sfondoUniformato(Object? n, Object? pct) => 'Sfondo uniformato su $n icone (trasparenza $pct%)';
  static const calGiornaliero = 'Giorno del calendario';
  static const calGiornalieroInfo = 'Ogni mattina nel pack (serve Shizuku)';
  static const calAggiornaOra = 'Aggiorna giorno';
  static String calAggiornato(Object? n) => 'Giorno aggiornato su $n icone';
  static const calGiaOggi = 'Il pack mostra già il giorno di oggi';
  static const calServeShizuku = 'Serve Shizuku per aggiornare il pack da solo';
  static const calNessuno = 'Il pack installato non ha un calendario da aggiornare';
  static String pbTutte(Object? n) => 'Tutte $n';
  static const pbVuoto = 'Aggiungi le app per iniziare.';
  static const pbPremiAbbina =
      'Crea le icone con lo Studio o importale, poi premi Abbina.';
  static const pbScegliIcona = 'Scegli icona';
  static const pbRielabora = 'Rielabora';
  static const pbSegnaVerificata = 'Segna come verificata';
  static const pbEscludi = 'Escludi';
  static const pbIncludi = 'Includi';
  static const pbCercaGenerate = 'Cerca tra le icone nuove';

  // Automazione Android
  static const asTitolo = 'Aggiornamento automatico del pack';
  static const asMai = 'Nessun controllo eseguito';
  static String asUltimo(Object? t) => 'Ultimo controllo: $t';
  static const asInfo =
      "Il controllo parte allo sblocco del telefono e ogni 6 ore, senza root e senza servizi sempre attivi. Se nessuna app è cambiata non fa niente; se qualcosa è cambiato ricevi una notifica silenziosa.";
  static const asControllaOra = 'Controlla ora';
  static String asRielabora(Object? n) => 'Rielabora $n app';
  static String asAltre(Object? n) => '…e altre $n';

  // APK del pack
  static const apkCrea = 'Crea APK';
  static const apkNome = 'Nome del pack';
  static const apkCompilazione = "Creo l'APK del pack…";
  static const apkPronto = 'APK del pack pronto';
  static const apkSalva = "Salva l'APK del pack";
  static const apkSalvato = 'APK salvato';
  static const apkSdkMancante =
      'Android SDK non trovato: installalo e imposta ANDROID_HOME.';
  static String apkFallita(Object? e) => "Non sono riuscito a creare l'APK: $e";
  static const asSegnaViste = 'Segna come viste';

  // Applica nel launcher (Shizuku)
  static const dpTitolo = 'Applica nel launcher';
  static const dpInfo =
      "Il pack è un'app a parte: le icone di sistema non vengono toccate. Con Shizuku Icon Formatter lo installa e lo seleziona nel launcher, senza PC e senza root.";
  static const dpApplica = 'Installa e applica';
  static const dpSoloInstalla = 'Installa (con conferma di sistema)';
  static const dpConcedi = 'Concedi il permesso a Shizuku';
  static const dpApriShizuku = 'Apri Shizuku';
  static const dpRipristina = 'Torna al pack precedente';
  static const dpScegliManuale = 'Scegli il pack nel launcher';
  static const dpShizukuMancante =
      'Shizuku non è installato. Installalo per applicare il pack in automatico; senza Shizuku puoi installare il pack con la conferma di sistema e sceglierlo a mano.';
  static const dpShizukuFermo =
      "Shizuku è installato ma non è attivo: aprilo e premi Avvia (serve il Debug wireless, non il PC). Dopo ogni riavvio del telefono va avviato di nuovo.";
  static const dpShizukuNegato =
      'Icon Formatter non ha ancora il permesso di Shizuku.';
  static const dpShizukuVecchio = 'Shizuku è troppo vecchio: aggiornalo.';
  static const dpShizukuOk = 'Shizuku attivo e autorizzato';
  static const dpNoLauncher =
      'Nothing Launcher non trovato: il pack viene installato, poi sceglilo nelle impostazioni del tuo launcher.';
  static String dpLauncher(Object v) => 'Nothing Launcher $v';
  static String dpSelettore(Object? v) => 'Pack selezionato: ${v ?? '—'}';
  static const dpCompilazione = 'Creo il pack sul telefono…';
  static const dpInstallazione = 'Installo il pack…';
  static const dpApplicazione = 'Seleziono il pack nel launcher…';
  static String dpFatto(int n, String v) => 'Pack $v applicato: $n icone.';
  static const dpNonVerificato =
      "Pack installato, ma il launcher non conferma la selezione: sceglilo a mano.";
  static String dpInstallato(int n, String v) =>
      'Pack $v installato ($n icone). Sceglilo nelle impostazioni del launcher.';
  static const dpConfermaSistema =
      "Conferma l'installazione nella finestra di sistema, poi scegli il pack nel launcher.";
  static String dpRipristinato(Object? v) =>
      'Selezione ripristinata: ${v ?? 'predefinita'}';
  static const scorriGiuPerChiudere = 'Chiudi (o scorri di lato)';
  static const indietro = 'Indietro';

  // Impostazioni (home a griglia) e Vetro
  static const vetro = 'Vetro';
  static const info = 'Info';
  static const lingua = 'Lingua';
  static const setupBenvenuto = 'Benvenuto';
  static const setupSub =
      'Due scelte e sei pronto. Puoi cambiarle quando vuoi in Impostazioni.';
  static const setupAuto = 'Aggiornamento automatico';
  static const setupAutoSub =
      "Ti avvisa quando un'app nuova o aggiornata ha bisogno della sua icona. Chiede il permesso per le notifiche.";
  static const setupShizuku = 'Shizuku (facoltativo)';
  static const setupShizukuSub =
      'Con Shizuku il pack si installa e si applica da solo, senza PC. Senza Shizuku lo installi con la conferma di sistema e lo scegli a mano nel launcher.';
  static const setupInizia = 'Inizia';
  static const elaborataBreve = 'elaborata';
  static const baseSquircle = 'Squircle';
  static const baseCerchio = 'Cerchio';
  static const creaDaPreset = 'Da un preset';
  static const inUso = 'In uso';
  static const calibrata = 'Calibrata';
  static const daCalibrare = 'Da calibrare';
  static String packViewerSub(Object? n, Object? m) =>
      '$n icone · $m app installate su questo telefono';
  static const packViewerSearch = 'Cerca per nome o package';
  static const packViewerCopy = 'Copia package';
  static const packViewerOpen = 'Apri app';
  static const packViewerCopied = 'Package copiato';
  static const packViewerFilterAll = 'Tutte';
  static const packViewerFilterInstalled = 'Installate';
  static const packViewerFilterMissing = 'Mancanti';
  static const packViewerSortName = 'A–Z';
  static const packViewerSortInstalled = 'Installate prima';
  static const linguaSistema = 'Come il telefono';
  static const interfaccia = 'Interfaccia';
  static const apri = 'Apri';
  static String versioneBreve(Object v) => 'Versione $v';
  static const catAspettoDesc = 'Stile, animazioni e densità';
  static const catVetroDesc = 'Vetro di barra, pannelli, pulsanti e finestre';
  static const catElaborazioneDesc = 'Dimensioni e rimozione dello sfondo';
  static const catBaseDesc = 'Sfondi e calibrazione delle icone';
  static const catPackDesc = 'Come ripulire gli icon pack';
  static const catExportDesc = 'Formato, nomi e destinazione';
  static const catSistemaDesc = 'File temporanei, ripristino e versione';
  static const materiale = 'Materiale';
  static const vetroVeloce = 'Più veloce';
  static const vetroBilanciato = 'Bilanciato';
  static const colore = 'Colore';
  static const tinta = 'Tinta';
  static const nessuna = 'Nessuna';
  static const bordoProfondita = 'Bordo e profondità';
  static const profonditaSub = 'Ombra morbida sotto le superfici in vetro';
  static const vetroNotaQualita =
      'Rifrazione e separazione dei colori sono complete solo con Qualità; negli altri livelli restano sfocatura, saturazione, tinta, luce e bordo.';
  static const doveUsarlo = 'Dove usarlo';
  static const vetroBarra = 'Vetro nella barra in basso';
  static const vetroPannelli = 'Vetro nelle card';
  static const vetroPulsanti = 'Vetro nei pulsanti';
  static const vetroDialoghi = 'Vetro nelle finestre di dialogo';
  // Pack Builder a passi
  static const pbSottotitoloBreve = 'Crea il tuo icon pack in pochi passi.';
  static const pbPasso1 = 'App';
  static const pbPasso1Sub = 'Le app a cui dare le nuove icone';
  static String pbOriginaliN(int n) => '$n app caricate';
  static const pbDaFile = 'Da file';
  static const pbPasso2 = 'Icone nuove';
  static const pbPasso2Sub = 'Creale con lo Studio o importale, poi abbinale';
  static const pbEsporta = 'Esporta';
  static const pbEsportaSub = 'Cartella, ZIP o APK';
  static String dpVersioneInstallata(Object v) =>
      'Pack installato: versione $v';
  // Rigenera › Modalità del simbolo (per singola app)
  static const rigeneraConModalita = 'Rigenera in un altro modo…';
  static String modalitaSimbolo(Object n) => 'Come prendere il simbolo · $n';
  static const modalitaSimboloInfo =
      "Se il riconoscimento automatico sbaglia, scegli tu come prendere il simbolo da questa icona (solo stile Lucent).";
  static const modoAuto = 'Automatica';
  static const modoAutoDesc =
      "Decide l'app: apre le icone a piastrella piena e ricolora i simboli scuri sui piatti colorati";
  static const modoColorePiatto = 'Colore del piatto';
  static const modoColorePiattoDesc =
      'Il simbolo prende il colore dello sfondo originale';
  static const modoBordoPieno = 'Bordo pieno';
  static const modoBordoPienoDesc =
      "L'icona originale arriva fino al bordo (mappe, tastiere…)";
  static const modoNormale = 'Normale';
  static const modoNormaleDesc =
      "Il simbolo scontornato così com'è, senza modifiche";
  // Studio -> Pack
  static const mandaAlPack = 'Manda al Pack';
  static String mandateAlPack(int n) => '$n icone mandate al Pack';
  static const autoMandaAlPack = 'Dopo "Elabora tutte" manda le icone al Pack';
  static const autoMandaAlPackSub =
      'Le icone dello Studio arrivano da sole nel Pack e vengono abbinate';
  // Funzioni extra
  static const packPersonalizzato = 'Il tuo pack';
  static const packNome = 'Nome del pack';
  static const packColore = 'Colore del pack';
  static const asOgni = 'Controlla ogni';
  static String asOre(int h) => '$h ore';
  static const asSoloInCarica = 'Solo mentre è in carica';
  static const bkTitolo = 'Backup';
  static const bkSalva = 'Salva il backup';
  static const bkSalvaSub = 'Aspetto, stili e preferenze in un file';
  static const bkRipristina = 'Ripristina da backup';
  static const bkRipristinaSub = 'Sostituisce le impostazioni attuali';
  static const bkSalvato = 'Backup salvato';
  static const bkRipristinato = 'Impostazioni ripristinate';
  static const bkNonValido = 'Il file non è un backup valido';
  static const sostieniTitolo = 'Sostieni il progetto';
  static const sostieniSub = "L'app è gratuita. Se ti piace, puoi offrirmi un caffè su Ko-fi.";
  static const applicaATutte = 'Applica a tutte le icone';
  static const applicaATutteOk = 'Applica';
  static String applicaATutteConferma(Object? n) => 'Icone da aggiornare: $n. Le correzioni di questa icona verranno copiate su tutte le altre e rielaborate.';
  static String applicaATutteFatto(Object? n) => 'Correzioni applicate: $n';
  static const cercaLista = 'Cerca nella lista';
  static const anteprimaHome = 'Anteprima home';
  static const anteprimaTitolo = 'Anteprima schermata home';
  static const anteprimaScuro = 'Scuro';
  static const anteprimaChiaro = 'Chiaro';
  static const anteprimaVuota = 'Nessuna icona generata da mostrare.';
  static const confrontoTitolo = 'Prima e dopo';
  static const confrontoSuggerimento = 'Trascina la linea per confrontare.';
  static const presetCondividiCondividi = 'Condividi preset';
  static const presetCondividiImporta = 'Importa preset';
  static const presetCondividiSalvato = 'Preset salvato';
  static const presetCondividiNonValido = 'File non valido: non contiene preset di Icon Formatter.';
  static String presetCondividiImportati(Object? n) => 'Preset importati: $n';
  static const comodoOrarioGiorno = 'Aggiorna il giorno alle';
  static const comodoAllaPrimaOccasione = 'Alla prima occasione';
  static const comodoOrarioGiornoAzzera = 'Azzera orario';
  static const extraSfondo = 'Sfondo';
  static const extraConfrontaStili = 'Confronta stili';
  static const extraStileA = 'Stile A';
  static const extraStileB = 'Stile B';
  static const extraNessunCampione = 'Nessuna icona da confrontare: importane una prima.';
  static const comodoTema = 'Tema';
  static const comodoTemaSistema = 'Segui il telefono';
  static const comodoTemaChiaro = 'Chiaro';
  static const comodoTemaScuro = 'Scuro';
  static const comodoBkPromemoria = 'Hai cambiato molte impostazioni: salva una copia di sicurezza.';
  static const comodoBkFai = 'Fai il backup';
  static const comodoBkPiuTardi = 'Più tardi';
  static const comodoRisparmio = 'Risparmio energetico';
  static const comodoRisparmioSub = 'Meno effetti e animazioni, più autonomia';
  static const packQualita = 'Controllo qualità';
  static String packQualitaScan(Object? a, Object? b) => 'Controllo $a di $b';
  static const packQualitaOk = 'Nessun problema trovato nelle icone';
  static String packQualitaN(Object? n) => '$n icone da controllare';
  static String packQualitaRielabora(Object? n) => 'Rielabora $n';
  static const packProbVuota = 'Quasi vuota';
  static const packProbPiccola = 'Troppo piccola';
  static const packProbDecentrata = 'Fuori centro';
  static const packProbScura = 'Troppo scura';
  static String packMancanti(Object? n) => 'Elabora $n mancanti';
  static const packRegistro = 'Registro del pack';
  static const packRegistroVuoto = 'Nessuna operazione registrata';
  static const packRegistroCopia = 'Copia';
  static const packRegistroCopiato = 'Registro copiato negli appunti';
  static String packLogCreate(Object? n) => 'Create $n icone';
  static String packLogRielabora(Object? n) => 'Rielaborate $n icone';
  static String packLogEsportata(Object? n, Object? nuove, Object? cambiate, Object? rimosse) => 'Esportate $n icone: $nuove nuove, $cambiate cambiate, $rimosse rimosse';
  static String packLogEsportataPrima(Object? n) => 'Esportate $n icone (prima esportazione)';
  static String packLogEsportataSolo(Object? n) => 'Esportate solo le modificate: $n icone';
  static String packLogApplicato(Object? n, Object? v) => 'Pack applicato sul telefono: $n icone, versione $v';
  static String packLogProfilo(Object? name) => 'Caricato il pack salvato $name';
  static const packProfili = 'Pack salvati';
  static const packSalvaCome = 'Salva pack come…';
  static const packProfiliVuoto = 'Nessun pack salvato';
  static String packProfiloN(Object? n, Object? data) => '$n correzioni · $data';
  static String packSalvato(Object? name) => 'Pack salvato come $name';
  static String packCaricaConferma(Object? name) => 'Caricare $name?';
  static const packCaricaCorpo = 'Le correzioni attuali vengono sostituite. Le icone fatte a mano restano.';
  static const packCarica = 'Carica';
  static String packEliminaConferma(Object? name) => 'Eliminare $name?';
  static const packEliminaCorpo = 'Il pack salvato viene rimosso. Le correzioni attuali restano.';
  static const packEsportaModificate = 'Solo le modificate';
  static const packEsportaModificateSub = 'Cambiate dall\'ultima esportazione';
  static const packEsportaPrimaSub = 'Prima esportazione: solo quelle fatte a mano';
  static const packNessunaModificata = 'Nessuna icona modificata da esportare';
  static const tourSalta = 'Salta';
  static const tourAvanti = 'Avanti';
  static const tourIndietro = 'Indietro';
  static const tourInizia = 'Inizia';
  static const tourBenvenutoSub = 'Crea pacchetti di icone per il tuo telefono, in pochi tocchi.';
  static const tourStileSub = 'Puoi cambiarlo quando vuoi.';
  static const tourStileNothing = 'Nero, piatto, con rosso Nothing';
  static const tourStileVetro = 'Superfici in vetro traslucido';
  static const tourPermessi = 'Permessi';
  static const tourPermSub = 'Tutto facoltativo. Ogni scelta si cambia più tardi dalle Impostazioni.';
  static const tourNotifiche = 'Notifiche';
  static const tourNotificheDesc = 'Avvisa quando una app nuova ha bisogno della sua icona.';
  static const tourSorgenti = 'Installa app sconosciute';
  static const tourSorgentiDesc = 'Serve solo per installare il pacchetto. Il sistema lo chiede da solo al momento giusto.';
  static const tourShizukuDesc = 'Facoltativo: installa e applica il pacchetto senza passare dal sistema.';
  static const tourStatoConcesso = 'Concesso';
  static const tourStatoNonConcesso = 'Non concesso';
  static const tourStatoInfo = 'Chiesto in fase di installazione';
  static const tourConcedi = 'Concedi';
  static const tourLinguaSub = 'Puoi cambiarla in qualsiasi momento.';
  static const tourFineTitolo = 'Tutto pronto';
  static const tourFineSub = 'Tre cose utili da sapere.';
  static const tourFine1 = 'Nello Studio modifichi le icone e crei il pacchetto.';
  static const tourFine2 = 'Nelle Impostazioni trovi stile, lingua e permessi.';
  static const tourFine3 = 'Puoi rivedere questa guida dalle Impostazioni.';

  static const studioDuplicato = "Stesso file di un'altra icona";
  static const studioGuidaArea = 'Guida area sicura';
  static const studioGuidaAreaSub = "Contorno del piatto e croce al centro, solo nell'anteprima";
  static const studioAltreIcona = 'Altre azioni per questa icona';
  static const studioOrdinaFiltra = 'Ordina e filtra';
  static const studioFiltroSub = 'Solo elenco: Elabora tutte lavora comunque su tutte le icone attive';
  static const studioOrdineAggiunta = 'Ordine di importazione';
  static const studioOrdinaNome = 'Nome';
  static const studioOrdinaStato = 'Stato';
  static const studioFiltroTutte = 'Tutte';
  static const studioFiltroModificate = 'Solo modificate';
  static const studioFiltroErrori = 'Solo con errori';
  static const studioFiltroEscluse = 'Solo escluse';
  static const studioNessunaIconaFiltrata = 'Nessuna icona con questo filtro';
  static String studioSelezionate(Object? n) => 'Selezionate: $n';
  static const studioApplicaCorrezioni = 'Applica correzioni';
  static const studioNessunaCorrezione = "Nessuna correzione da copiare: correggi prima l'icona in anteprima";
  static String studioCorrezioniApplicate(Object? n) => 'Correzioni applicate a $n icone';
  static const studioEscludi = 'Escludi';
  static const studioRimuovi = 'Rimuovi';
  static String studioRimuoviSelezioneTitolo(Object? n) => 'Rimuovere $n icone dalla lista?';
  static const studioRimuoviSelezioneSub = 'Le icone escono dalla lista. I file originali non vengono toccati.';
  static const studioDeselezionaTutte = 'Deseleziona tutte';
  static const studioIncollaAppunti = 'Incolla dagli appunti';
  static const studioIncollaAppuntiSub = 'Immagine copiata o file copiato in Esplora';
  static const studioAppuntiVuoti = 'Negli appunti non ci sono immagini o file immagine.';
  static const studioAnnullaModifica = 'Annulla modifica';
  static const studioAnnullaModificaSub = 'Torna alla correzione precedente';
  static const studioRipristinaModifica = 'Ripristina modifica';
  static const studioRipristinaModificaSub = 'Rifà la correzione annullata';
  static const studioEscludiDuplicati = 'Escludi duplicati';
  static String studioEscludiDuplicatiSub(Object? n) => 'Icone con lo stesso file: $n';
  static String studioDuplicatiEsclusi(Object? n) => 'Duplicati esclusi: $n';

  // Auto-update ignore list (Android)
  static const androidIgnorateTitolo = 'App escluse dagli aggiornamenti';
  static const androidIgnorateSub = 'Queste app non compaiono nelle modifiche né nelle notifiche';
  static const androidIgnorateCerca = 'Cerca app';
  static const androidIgnorateSalva = 'Salva';
  static const androidIgnorateNessuna = 'Nessuna app trovata';
  static String androidIgnorateConteggio(Object? n) => '$n ignorate';

  // Extra 2: copia info, Novità, backup automatico, scorciatoie
  static const extra2DiagTitolo = 'Copia info per segnalare un problema';
  static const extra2DiagSub = 'Versione, sistema e impostazioni, senza dati personali';
  static const extra2DiagCopiata = 'Info copiate negli appunti';
  static const extra2NovitaTitolo = 'Novità';
  static const extra2NovitaSub = 'Cosa cambia in questa versione';
  static const extra2BkAutoTitolo = 'Backup automatico';
  static const extra2BkAutoSub = 'Dopo molte modifiche salva una copia nella cartella, tenendo le ultime 3';
  static const extra2BkAutoCartella = 'Cartella del backup';
  static const extra2BkAutoNonScrivibile = 'Non posso scrivere in questa cartella. Su Android scegline una dove l app può salvare, per esempio Download.';
  static const extra2BkAutoFallito = 'Il backup automatico non è riuscito. Riprova dopo altre modifiche.';
  static const extra2ScorTitolo = 'Scorciatoie da tastiera';
  static const extra2ScorSub = 'Tasti per il computer. Con Ctrl funzionano anche nei campi di testo.';
  static const extra2ScorTileSub = 'Elenco dei tasti per il computer';
  static const extra2ScorTab = 'Apre le prime quattro sezioni della barra laterale';
  static const extra2ScorImp = 'Apre le Impostazioni';
  static const extra2ScorTema = 'Passa dal tema chiaro a quello scuro';
  static const vetroApplico = 'Applico la qualità…';
  static const pack2Anteprima = 'Esporta anteprima';
  static const pack2AnteprimaVuota = 'Nessuna icona generata da mostrare.';
  static String pack2AnteprimaProgresso(Object? n, Object? m) => 'Anteprima: $n di $m icone';
  static const pack2AnteprimaTitolo = 'Anteprima icone';
  static const pack2UsaPerAltre = 'Usa per altre app…';
  static const pack2AliasTitolo = 'Usa per altre app';
  static const pack2AliasCerca = 'Cerca app';
  static const pack2AliasVuoto = "Nessun'altra app da scegliere.";
  static const pack2Rinomina = 'Rinomina nel pack';
  static const pack2RinominaTitolo = 'Nome nel pack';
  static String pack2Copertura(Object? n, Object? m, Object? p) => '$n icone su $m app installate ($p%)';
  static const pack2Varianti = 'Varianti';
  static const pack2VarianteAggiungi = 'Aggiungi variante';
  static const pack2VariantiMax = 'Massimo tre icone per app.';
  static const pack2VarianteTogli = 'Tieni premuta una variante per toglierla';
  static const pack2VarianteScelta = 'Variante scelta';
  static const pack2ProbContrasto = 'Contrasto basso';
  static const pack2OriginaleCambiata = "L'icona originale è cambiata";
  static const studio2Ricolora = 'Ricolora';
  static const studio2ColoreSimbolo = 'Colore del simbolo';
  static const studio2PiattoDalSimbolo = 'Piatto dal simbolo';
  static const studio2Nitidezza = 'Nitidezza';
  static const studio2CentraturaOttica = 'Centratura ottica';
  static const studio2FormaPiattoMenu = 'Forma del piatto…';
  static const studio2ColorePiattoMenu = 'Colore del piatto…';
  static const studio2FormaPredefinita = 'Predefinita';
  static const studio2PredefinitoColore = 'Predefinito';
  static const studio2ColorePiattoTitolo = 'Colore del piatto';
  static const studio2ColoreScegli = 'Scegli un colore';
  static const studio2Applica = 'Applica';
  static const pack3Conflitti = 'Conflitti';
  static const pack3ConflittiOk = 'Nessun conflitto tra le icone.';
  static String pack3ConflittiN(Object? n) => '$n conflitti';
  static const pack3ConflittoCondiviso = 'Stesso disegno per più app';
  static const pack3ConflittoComponente = 'Stesso componente, disegni diversi';
  static const pack3ConflittoVuoto = 'Disegno vuoto';
  static const pack3ConflittoPacchetto = 'Pacchetto vuoto';
  static const pack3Suggerisci = 'Suggerisci';
  static const pack3SuggerimentiTitolo = 'Icone suggerite';
  static const pack3NessunSuggerimento = 'Nessuna icona adatta tra quelle libere.';
  static const pack3ImportaAbbinamenti = 'Importa abbinamenti da un pack';
  static const pack3ImportaSub = 'APK o ZIP di un altro pack';
  static const pack3AbbinamentiTitolo = 'Abbinamenti trovati';
  static const pack3ImportaNessuno = 'Nessun abbinamento per le app senza icona.';
  static const pack3MatchComponente = 'Componente esatto';
  static const pack3MatchPacchetto = 'Stesso pacchetto';
  static const pack3MatchEtichetta = 'Stesso nome';
  static const pack3Applica = 'Applica';
  static String pack3AbbinamentiApplicati(Object? n) => '$n icone assegnate.';
  static const pack3Liste = 'Liste';
  static const pack3ListeSub = 'Salva e carica selezioni di app';
  static const pack3ListeTitolo = 'Liste di app';
  static const pack3ListaSalvaSelezione = 'Salva la selezione come lista';
  static const pack3ListaSalvaCome = 'Nome della lista';
  static const pack3ListaVuota = 'Nessuna lista salvata.';
  static const pack3ListaSelezioneVuota = 'Seleziona prima almeno una app.';
  static String pack3ListaN(Object? n) => '$n app';
  static const pack3ListaCarica = 'Carica';
  static const pack3ListaRinomina = 'Rinomina';
  static const pack3ListaRinominaTitolo = 'Nuovo nome';
  static String pack3ListaCaricata(Object? name) => 'Lista caricata: $name.';
  static String pack3ListaSalvata(Object? name) => 'Lista salvata: $name.';
  static String pack3ListaEliminaConferma(Object? name) => 'Eliminare la lista $name?';
  static const pack3ListaEliminaCorpo = 'La lista viene tolta: le app non cambiano.';
  static const tourRivedi = 'Rivedi il tour';

  // wire: auto-update card, ignored apps, watched folder
  static const wireAppIgnorate = 'App ignorate';
  static String wireAppIgnorateN(int n) => 'App ignorate ($n)';
  static String wireNuovaVersione(Object? v) => 'Nuova versione $v disponibile';
  static const wireControllaAggiornamenti = 'Controlla gli aggiornamenti';
  static const wireControllaAggiornamentiSub = 'Una volta per avvio, verso GitHub. Spento: nessuna richiesta di rete.';
  static const wireCartellaOsservata = 'Cartella osservata';
  static const wireCartellaOsservataSub = 'Le nuove immagini qui vengono importate nello Studio';
  static const wireScegliCartella = 'Scegli la cartella da osservare';
  static const wireCartellaNonLeggibile = 'Cartella non leggibile da qui';
  static const wireRimuoviCartella = 'Rimuovi cartella';
  static const batchElaborazione = 'Elaborazione';
  static const batchCompletato = 'Completato';
}
