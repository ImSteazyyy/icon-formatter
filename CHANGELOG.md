# Novità

## 1.3.0 — 2026-11-05

### Correzioni
- **"Rimuovi sempre lo sfondo" cancellava i loghi.** Con sensibilità alta il controllo del piatto scambiava un anello multicolore (Chrome) per un piatto uniforme e toglieva tutto il logo. Ora il piatto è giudicato con una tolleranza stretta, un "piatto" che si porterebbe via quasi tutto viene mantenuto, e le sorgenti già scontornate saltano la rimozione.
- **Miniature vecchie.** Un'icona rielaborata nello stesso file continuava a mostrare l'immagine precedente. Ora le immagini sono identificate da percorso e data di modifica.
- **Icone sbagliate dalle app installate (KFC, Contatti, Smart Center, HoYoLAB…).** Per le icone adattive l'app leggeva il livello in primo piano a 108 dp interi, senza la maschera di sistema, così nell'icona finiva grafica che il launcher non mostra mai: strisce e linguette oltre il bordo, o un pallino rosso fuori dal piatto. Ora il livello è disegnato come lo disegna il launcher (i 72 dp centrali, ritagliati dalla maschera). I disegni che arrivano al bordo della maschera sono trattati come piastrelle piene.
- **Simbolo su piatto colorato.**
  - Vengono ricolorati anche i simboli grigio medio, per esempio un robot Android su un disco blu.
  - Il colore del piatto è calcolato con una mediana, quindi sfumature e riflessi non bloccano più il rilevamento.
  - Viene riconosciuto anche un disco colorato sopra una piastrella scura.
  - I simboli bianchi restano bianchi.
- **Puntini sulle sfumature (Fotocamera Nothing).** Lo schiarimento dei grigi sul piatto scuro usava una soglia netta sulla saturazione e schiariva un pixel sì e uno no sulle sfumature. Ora sfuma gradualmente.
- **Controller della sezione Pack**: veniva distrutto insieme alla schermata, anche se è condiviso da tutta l'app.

### Modifiche: un'interfaccia che si spiega da sola
- **Studio.**
  - Un solo pulsante "Importa icone" apre un menu pop-up in vetro: immagini, cartella, ZIP/APK, PNG pronti, app del telefono.
  - Il "+" in alto, accanto a "Personalizza", compare solo quando ci sono già icone.
  - La barra in basso ha un pulsante di avvio e "Altro" per tutte le altre azioni (manda al Pack, esporta, condividi, svuota), senza scorrimento orizzontale.
- **Menu pop-up stile iOS 26** in liquid glass, che si aprono dal controllo toccato. Sono usati per l'import, per "Altro", per il menu delle app nel Pack e per la scelta dello stile. Si chiudono toccando fuori o trascinando verso il basso.
- **Intestazioni uniformi.**
  - Titolo e sottotitolo stanno in una sola colonna, e i pulsanti non finiscono mai sopra il testo.
  - Il margine laterale è di 20 dp ovunque, e le barre flottanti sono allineate alla barra di navigazione.
- **Progresso e completamento** galleggiano sotto il titolo della sezione senza spostare il contenuto e si tolgono con uno swipe laterale (Studio, App, Pack).
- **App.**
  - Titolo breve, filtri a tutta larghezza, app di sistema visibili di default.
  - La scelta dello stile sta dentro "Personalizza"; ricarica ed esportazioni sono in "Altro".
- **AI.**
  - Due schede, "Tema AI online" e "AI locale", e il modello locale si scarica con un tocco.
  - Le impostazioni "Servizio AI" spiegano che per lo scontorno non serve una chiave API.
  - I metodi di scontorno sono elencati con la spiegazione di ciascuno.
- **Valori predefiniti del Liquid Glass**: quelli scelti sul Nothing Phone (2a) Plus.
  - Sfocatura 22,6, smerigliatura 61, saturazione 2,5, tinta 8.
  - Spessore 0, rifrazione 1,0, aberrazione 12, profondità attiva.
  - Luce 0, angolo luce 74°, bordo lucido spento.
- **Scorrimento fluido.** Le celle delle griglie lunghe e le card delle pagine che scorrono sono superfici antracite piene. Un pannello in vetro ricattura e sfoca ciò che ha dietro a ogni movimento, e decine di pannelli rendevano costoso ogni frame. Il vetro resta su barre, pulsanti, pannelli fissi e menu.

### Aggiunte
- **Avvisi in alto** sullo schermo, che si tolgono con uno swipe laterale. Togliere un avviso non interrompe il lavoro in corso.
- **Swipe tra le sezioni** su Android. La barra in basso segue, e le sezioni restano in memoria, quindi non vengono ricaricate.
- **Catalogo completo delle app nel Pack.** Compaiono tutte le app con icona nel launcher: quelle di sistema (Fotocamera, Telefono, Contatti, Impostazioni), Icon Formatter stesso e i suoi pack.
  - Stati: Abbinata, Da verificare (il nome corrisponde ma il disegno è diverso), Dubbia, Icona mancante, Verificata, Esclusa.
  - La schermata mostra quante app del launcher rileva Android.
- **Modifica icona** (tenendo premuta un'app nel Pack).
  - Si importa un PNG, JPG o WEBP e lo si elabora con la pipeline del pack.
  - Trattamenti disponibili:
    - Automatica, Colore del piatto, Bordo pieno, Normale;
    - "Solo posizione e dimensione": nessuno scontorno, il PNG viene solo ritagliato al contenuto, centrato e dimensionato come le altre icone sullo sfondo del pack;
    - "così com'è".
  - Si confronta Prima/Dopo, poi si conferma o si annulla. "Ripristina icona precedente" annulla la modifica.
  - L'icona resta collegata a package e activity, e il pack installato con Shizuku viene ricostruito.
- **Apri un pack (Pack › passo 2).**
  - Apre un pack creato con Icon Formatter: quello installato sul telefono, oppure un APK/ZIP da un altro telefono. Le icone tornano collegate alle loro app e si possono modificare.
  - "Installa e applica" aggiorna poi quel pack, e la numerazione delle versioni continua (la versione di un APK aperto viene ricordata).
  - Android non permette di aggiornare un pack firmato su un altro telefono. Dopo una conferma esplicita Icon Formatter lo sostituisce tramite Shizuku e lo riseleziona.
  - Verificato sull'emulatore: cancellati dati e chiave di firma, pack 1.3 aperto e sostituito, ora 1.4, selezione nel launcher ripristinata.
- **Condividi APK (Pack › Esporta, Android).** L'APK del pack viene creato e firmato sul telefono e passato al foglio di condivisione, senza installarlo.
- **Studio › Importa icone › PNG pronti.** I PNG già pronti non vengono scontornati né ricolorati: sono solo ritagliati al contenuto, centrati e dimensionati sullo sfondo delle icone. "Modifica icona" nel Pack ha lo stesso trattamento ("Solo posizione e dimensione").
- **Persistenza.** Gli elenchi del Pack (icone generate, importate e modificate a mano) restano dopo il riavvio.

### Prestazioni e batteria
- **Abbinamento.** Le firme visive sono calcolate su una copia a 160 px e messe in cache per file, e le chiavi di testo una volta per icona invece che per coppia. Con 250 + 250 icone su PC l'abbinamento richiede 0,11 s invece di 1,41 s, e 0,02 s quando viene ripetuto.
- **Catalogo.** Le icone vengono generate una volta su un piccolo pool nativo e salvate su disco; si rigenerano solo per le app aggiornate.
- **Griglia del Pack.** È caricata solo dove serve (sliver), e le miniature sono decodificate alla dimensione mostrata.
- **Misure sull'emulatore** (stessa schermata Pack, scorrimento, tempi dei frame da SurfaceFlinger):
  - 1.2.0: circa 175 ms per frame (≈6 fps) con 5 card;
  - 1.3.0: mediana di circa 17 ms con 24 card, p90 19 ms, solo il 5% dei frame oltre 20 ms;
  - schermate ferme: nessun frame disegnato, 0% di CPU.
- **Android.**
  - I thread Rust sono limitati a 4 di default (il Dimensity 7350 Pro ha 2 core grandi e 6 piccoli).
  - Durante i batch l'interfaccia si aggiorna al massimo 4 volte al secondo, quindi ci sono meno ridisegni sotto le barre in vetro sfocate.

## 1.2.0 — 2026-11-05

### Aggiunte
- **Applicazione del pack sul telefono con Shizuku (senza PC, senza root).** Icon Formatter crea l'APK del pack sul telefono, lo firma, lo installa e lo seleziona in Nothing Launcher.
  - **Creazione:** l'APK base (`assets/iconpack_base.apk`, 2000 slot drawable vuoti, creato da `tool/make_base_apk.py`) viene riempito con i PNG del pack, più `appfilter.xml` / `drawable.xml` binari, `mapping.json` e `pack.json`. Poi viene firmato con apksig, con una chiave tenuta nell'Android Keystore.
  - **Installazione e selezione:** `pm install`, poi la sequenza di IconGen: il selettore di icon pack di Nothing Launcher si apre dietro l'app, e `nothing_icon_pack` viene impostato a `THEMED_ICONS_NOTHING` e riportato al pack 0,5 s dopo.
  - **Un'app separata:** il pack ha il suo package (`com.iconformatter.pack.device`), quindi i pack di sistema non vengono toccati. Ogni build lo aggiorna con una versione progressiva (1.0, 1.1, 1.2, …), e "Ripristina pack precedente" rimette la selezione precedente.
  - **Permessi:** il permesso Shizuku viene chiesto all'avvio, solo se manca.
  - **Senza Shizuku:** l'installazione passa dall'installer di sistema con conferma, e il pack si sceglie a mano nel launcher.
- **Studio → Pack:** un pulsante "Manda al Pack" e un passaggio automatico facoltativo dopo "Elabora tutte"; entrambi alimentano il passo 2 del Pack e abbinano subito.
- **Rigenera con modalità… (per singola icona):**
  - Automatica.
  - Colore del piatto: il simbolo prende il colore del piatto originale.
  - Bordo pieno: da bordo a bordo, come Mappe o Gboard.
  - Normale.
- **Ricolorazione automatica:** un simbolo scuro e neutro su un disco o una piastrella colorati (per esempio un cartellino scuro su un disco giallo) prende il colore del piatto, e i buchi nel simbolo diventano trasparenti. I simboli bianchi restano bianchi.
- **Scheda AI › Modelli locali:**
  - U²-Net-p, per telefono e Windows (~0,9 s per icona su PC).
  - ISNet General, solo Windows (~7,5 s per icona, ingresso 1024 px).
  - Scarica, elimina e scegli il modello, con l'interruttore facoltativo "Usa il modello AI locale". L'algoritmo classico resta quello predefinito.
- **Nuove icone:** l'icona dell'app e quella dei pack hanno sfondo trasparente, bordi puliti e le stesse proporzioni delle altre icone.

### Modifiche
- **Nuova interfaccia**, seguendo gli screenshot di riferimento:
  - Impostazioni: home con titolo grande, card profilo e griglia di categorie a due colonne. Le pagine hanno un pulsante indietro rotondo e un titolo grande, le sezioni sono card scure con separatori sottili, gli slider hanno icona, nome e valore in alto con il controllo sotto, e interruttori e liste di scelta sono moderni.
  - Pack: passi numerati.
  - Studio: quando è vuoto mostra una guida in 3 passi.
  - Ovunque: titoli grandi, pulsanti in vetro nelle intestazioni, finestre, fogli e menu ridisegnati.
- **Liquid Glass globale (Impostazioni › Vetro):**
  - I parametri guidano ogni superficie in vetro: barra in basso, pannelli e card, pulsanti e finestre (con lo schermo dietro sfocato).
  - L'effetto si applica in tempo reale, senza riavvio.
  - Impostazioni: qualità (Più veloce / Bilanciato / Qualità), sfocatura, smerigliatura, saturazione, colore e intensità della tinta, spessore, curvatura, rifrazione, aberrazione cromatica, profondità (ombra), luce, bordo lucido, leggibilità, lente e dove usarlo.
  - L'anteprima fissa in alto riproduce la schermata base dello Studio.
  - La riduzione automatica della qualità del pacchetto è disattivata, così viene rispettata la qualità scelta.
- **Icone a tutto bordo:** una piastrella piena con margine trasparente (come la restituiscono i launcher) ora viene riconosciuta, quindi icone come Mappe e Gboard non escono più piccole dentro il piatto.
- **Prestazioni su Android:** le icone delle griglie sono decodificate alla dimensione mostrata (`cacheWidth`) dentro un `RepaintBoundary`.

### Correzioni
- **Barre d'azione scorrevoli:** in Studio, AI e App le azioni non vengono più tagliate da una linea dritta e seguono il bordo arrotondato.
- **Barra di avanzamento:** quando ha finito si chiude con uno swipe verso il basso (o con ×).

## 1.1.1 — 2026-11-05

### Correzioni
- Lucent: le icone prese dalle app installate (icone adattive rese come piastrella arrotondata piena, per esempio Google Maps o Gboard) perdevano gran parte del contenuto, perché la segmentazione esterna trattava tutta la piastrella come un logo nudo. Quando la sorgente è essa stessa una piastrella piena, ora il suo sfondo interno viene rimosso direttamente. Il contenuto (strade, tasti, figure) resta intero, arriva al bordo del piatto ed è ritagliato su di esso, sia nell'anteprima sia nell'esportazione.

## 1.1.0 — 2026-11-05

### Aggiunte
- **Render Lucent (Nothing OS 5.0)**: un nuovo modulo Rust (`lucent.rs`) porta il metodo di [Nothing IconGen](https://github.com/linuxct/nothing-icongen) (commit `02c915f`, AGPL-3.0). Comprende il piatto smerigliato `#66000000` / `#66FFFFFF`, la conversione luminanza→inchiostro del launcher (facoltativa) e la compensazione `PackIconEncoder` per Nothing Launcher.
  - Il glifo mantiene i colori originali.
  - Il piatto è lo squircle di riferimento; sono disponibili anche il cerchio o la sagoma dell'icona caricata.
  - Il contenuto è ritagliato sul bordo del piatto.
  - Anteprima ed esportazione usano la stessa funzione.
- **"Icona dentro l'icona"**: quando un'icona è essa stessa una piastrella piena con sfondo scuro (icone già a tema), lo sfondo viene rimosso con una crescita per regioni (ombre e sfumature comprese). Gli oggetti restano interi e arrivano al bordo del piatto. I bordi morbidi usano una maschera di luminanza, e grigi scuri o glifi bianchi diventano leggibili sia su piatti scuri sia chiari.
- **Icon Pack Builder**:
  - Gli originali possono venire da app installate, cartella, ZIP o APK. Per gli APK è supportato `appfilter.xml` binario e viene tenuta la densità più alta.
  - Le icone si generano con lo Studio o si importano.
  - L'abbinamento automatico usa nome dell'app, package, nome del file e somiglianza visiva.
  - I risultati compaiono in una griglia Prima/Dopo con gli stati Sicura/Dubbia/Mancante/Esclusa/Verificata.
  - Le associazioni si correggono con la ricerca, si sostituiscono con un file, si escludono, si verificano o si rielaborano. Le correzioni vengono salvate tra una sessione e l'altra.
  - Esportazione in cartella o ZIP con `appfilter.xml`.
- **APK dell'icon pack** (Windows, con Android SDK + JDK): "Crea APK" produce un icon pack installabile (intent di ADW/Nova/Lawnchair…). Al suo interno un visualizzatore di icone nello stile dell'app mostra per ogni icona l'app e il package, e se l'app è installata.
- **Scontorno con AI locale**: modello facoltativo U²-Net-p (4,6 MB, Apache-2.0) eseguito con `tract` (Rust puro, CPU) su Windows e Android.
  - Il modello si scarica e si carica su richiesta e resta in cache in memoria.
  - La rimozione viene saltata se lo sfondo è già trasparente.
  - Un'anteprima della maschera alpha offre soglie regolabili.
  - I risultati incerti vengono segnalati.
- **Automazione Android**: controllo leggero con un job JobScheduler persistente (6 ore) e un controllo allo sblocco finché l'app è in memoria.
  - `getChangedPackages` evita ogni lavoro se nulla è cambiato.
  - Rileva app installate, disinstallate e aggiornate, e icone cambiate.
  - Notifica silenziosa, pulsante "Controlla ora" e rielaborazione delle sole app cambiate.
- **Slider con valore numerico**: si tocca il valore, si scrive, poi Invio o un tocco fuori per confermare, Esc per annullare. Con controllo di minimo/massimo, virgola decimale e aggancio alle divisioni.
- Testi in italiano centralizzati (`lib/l10n/strings.dart`), con tutte le schermate tradotte.
- Nuova icona dell'app (`.ico` per Windows, icona adattiva Android con sfondo trasparente, barra del titolo).

### Modifiche
- Navigazione in basso: lente di selezione grigio scuro con accento rosa-lilla desaturato.
- I pulsanti di import "ZIP" ora sono "ZIP o APK".
- Composizione su una base: i glifi che arrivano al bordo (o le piastrelle) vengono mappati sul piatto e ritagliati sulla sua forma.
- Licenza: AGPL-3.0-only (per il codice derivato da Nothing IconGen).

### Note e limiti
- L'aggiornamento silenzioso del pack nel launcher non è disponibile: vedi README › Limiti.
- I modelli Silueta / IS-Net sono stati provati con `tract`: circa 93 s per icona su CPU, quindi non sono proposti.
