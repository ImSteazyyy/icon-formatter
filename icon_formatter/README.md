# Icon Formatter

App per Windows e Android che compone, stilizza e ripulisce le icone dei launcher.

## La 1.3.0 in breve

- **Pack.**
  - Elenca tutte le app con icona nel launcher, comprese quelle di sistema, e mostra quante ne rileva Android.
  - Stati: Abbinata, Da verificare, Dubbia, Icona mancante, Verificata, Esclusa.
  - Tenendo premuta un'app si apre un menu contestuale in vetro. "Modifica icona" importa un PNG, JPG o WEBP, lo elabora, mostra Prima/Dopo e poi conferma, annulla o ripristina.
  - "Apri un pack" riapre il pack installato o un APK/ZIP creato su un altro telefono. Un pack firmato su un altro telefono viene sostituito solo dopo conferma, e la numerazione delle versioni continua.
  - "Condividi APK" condivide l'APK del pack.
- **Interfaccia.**
  - Un'azione principale per schermata e menu pop-up in vetro stile iOS 26.
  - Il progresso galleggia sotto il titolo e si toglie con uno swipe laterale; gli avvisi compaiono in alto.
  - Si passa da una sezione all'altra con uno swipe.
  - Le superfici piene dentro le liste che scorrono mantengono lo scorrimento fluido.
- **Prestazioni.**
  - Firme visive dell'abbinamento in cache e griglia caricata solo dove serve.
  - Sui telefoni Rust usa 4 thread, e durante le elaborazioni gli aggiornamenti dell'interfaccia sono diradati.
  - Le schermate ferme non disegnano frame.

## Architettura

| Livello | Percorso | Ruolo |
|---|---|---|
| Core Rust | `native/icon_core` | Segmentazione e isolamento del glifo, squircle, render "Nothing Translucent", composizione, calibrazione, batch in parallelo (rayon) annullabile, lettura/scrittura dei pack (cartella/ZIP, `appfilter.xml`), esportazione di icon pack Android. Rust puro, testabile con `cargo test`. |
| Ponte FFI | `rust/` (crate `icon_bridge`) | `flutter_rust_bridge` 2.13: DTO, funzioni asincrone sui thread di lavoro, `Stream` per l'avanzamento dei batch, `CancelToken` opaco. |
| Interfaccia Flutter | `lib/` | Windows (barra laterale, trascinamento, finestre native) e Android (barra in basso / rail, edge-to-edge, SAF, condivisione). |
| Android nativo | `android/app/src/main/kotlin/.../MainActivity.kt` | Lettura delle app installate (PackageManager, icone adattive), Storage Access Framework (scelta cartelle, lettura e scrittura). |

Quando possibile le immagini attraversano l'FFI come percorsi di file (i batch leggono e scrivono direttamente in Rust). I byte PNG si usano solo per le anteprime e per le icone che arrivano da Android.

## Pipeline

- **Composizione originale**: il glifo isolato viene composto sull'icona base scelta, con la calibrazione di quella base.
- **Lucent (Nothing OS 5.0)**: `native/icon_core/src/lucent.rs`, porting del metodo di [Nothing IconGen](https://github.com/linuxct/nothing-icongen) (AGPL-3.0, commit `02c915f`):
  - piatto smerigliato `container_frosted_backdrop` (`#66000000` scuro / `#66FFFFFF` chiaro);
  - conversione facoltativa luminanza → inchiostro (`PortableMonochrome`);
  - compensazione facoltativa `PackIconEncoder` per Nothing Launcher (sorgente → ombre → sorgente, verificata con test di andata e ritorno).

  Il glifo mantiene i suoi colori. Il piatto è lo squircle di riferimento (disponibili anche cerchio e sagoma della sorgente) e il contenuto viene ritagliato su di esso. L'"icona dentro l'icona" (icone a tema con piastrella scura) viene aperta con una crescita per regioni, e il contenuto arriva al bordo del piatto. Un simbolo scuro o grigio su un disco colorato prende il colore del disco.
- **Preset personalizzati**: Liquid Glass, Nothing Translucent, Minimale, Scuro piatto, Personalizzato e i preset dell'utente (modificabili e salvati).
- **Tema icone AI**: fornitore esterno (OpenAI Images, Google Gemini, endpoint compatibile OpenAI). La chiave sta nell'archivio sicuro di sistema. Senza chiave non viene generato né simulato nulla.
- **Pulizia pack**: apre una cartella o uno ZIP, mantiene percorsi e nomi dei file, copia `appfilter.xml` e gli altri metadati e segnala i drawable mancanti o ambigui.
- **App installate** (solo Android): elenco delle activity del launcher tramite `<queries>` MAIN/LAUNCHER, senza `QUERY_ALL_PACKAGES` e senza root. Esporta un icon pack come res/assets + `appfilter.xml`.

## Interfaccia

- **Liquid glass**: [`liquid_glass_widgets`](https://github.com/sdegenaar/liquid_glass_widgets) 1.16 (rifrazione, aberrazione cromatica, luce speculare).
  - Su Android la navigazione è una `GlassTabBar.bottom` flottante con lente scura; le barre d'azione galleggiano sopra e il contenuto scorre sotto.
  - Un solo `GlassConfig` (Impostazioni › Vetro) guida in tempo reale tutte le superfici in vetro (`LiquidGlass` con un `GlassRole`: panel, button, nav, lens), la barra in basso, le finestre (`showAppDialog` sfoca lo schermo dietro) e il tema (finestre, fogli, menu).
  - Ogni superficie può diventare antracite piena.
  - Livelli di qualità: Più veloce = `minimal`, Bilanciato = `standard`, Qualità = `premium`. Rifrazione e aberrazione sono complete solo in Qualità.
  - Le celle delle griglie lunghe e le card delle pagine che scorrono sono superfici piene: un pannello in vetro ricattura e sfoca lo sfondo a ogni movimento.
  - Menu pop-up in vetro (`widgets/glass_menu.dart`) che si aprono dal controllo toccato.
- **Layout**:
  - Impostazioni è una home a griglia con pagine annidate (`SettingsList` + `SettingsCard`).
  - Componenti condivisi in `widgets/common.dart`: `IconChip`, `LargeHeader`, `SettingSwitch`, `ChoiceRows`, `StepCard`, `Tile`; avvisi in `widgets/toasts.dart`.
- **Windows**: barra del titolo personalizzata (`window_manager` 0.5, barra nativa nascosta).
- **Accento**: rosa predefinito #BA4CD4 (preso dall'icona Start di Windows), con preset, codice esadecimale e cursori HSL.

## Rimozione dello sfondo

Motori (Impostazioni › Elaborazione):
- **Locale Rust (predefinito)**: segmentazione deterministica, offline, gratuita.
- **AI locale**: modello facoltativo U²-Net-p (4,6 MB, Apache-2.0, scaricato dalle release di rembg), eseguito con `tract` (Rust puro, CPU, nessun runtime nativo).
  - Circa 0,8 s per icona (i5-13500H), circa 350 MB di RAM durante l'uso.
  - Il modello si carica una volta e resta in memoria.
  - La rimozione viene saltata se lo sfondo è già trasparente.
  - Anteprima della maschera con soglie; i risultati incerti vengono segnalati.
  - ISNet General (170 MB, ingresso 1024 px) è disponibile solo su Windows: circa 7,5 s per icona sullo stesso PC, troppo lento per un telefono.
  - Silueta richiedeva circa 89 s per icona con `tract` e non è proposto. `tract` non usa la GPU.

Opzione: **remove.bg** (Impostazioni › Elaborazione), con la chiave API nell'archivio sicuro, un test che mostra i crediti rimasti e una chiamata per immagine messa in cache per la sessione. In un batch le chiamate partono prima (3 in parallelo, annullabili), poi Rust compone il ritaglio senza segmentarlo di nuovo.

## Isolamento del glifo

Deterministico, senza modelli di machine learning: riempimento dai bordi con cluster dei colori di bordo (OKLab + alpha), rilevamento del "piatto" (sfondi arrotondati o semitrasparenti) giudicato con una tolleranza stretta, rimozione facoltativa dei buchi e separazione premoltiplicata dei bordi anti-alias. Le parti del glifo con colori simili allo sfondo restano se sono separate da un bordo. Se lo sfondo è già trasparente, anche con "Rimuovi sempre lo sfondo" la rimozione viene saltata. I casi incerti vengono segnalati (giallo) per la correzione manuale.

ONNX Runtime (modelli tipo U²-Net/BiRefNet) è stato valutato e scartato: aggiunge 20–40 MB di runtime nativo per ABI più 40–170 MB di modello, ed è addestrato su foto e non su loghi piatti. Sulle icone di riferimento la segmentazione deterministica isola tutti i 26 glifi; 2 (`apk toolbox 2`, `tiktok plugin`) vengono segnalati per una verifica manuale per via di ampie zone interne del colore dello sfondo.

## Icone di riferimento

Le icone di riferimento usate per calibrare e testare (192 px, squircle 0,93 × esponente 4,25, piatto nero semitrasparente α 105→176) sono icone di app di terzi: restano solo sul PC di sviluppo e **non sono incluse nella repository**, perché loghi e marchi appartengono ai rispettivi proprietari. I test che le usano (`native/icon_core/tests/reference.rs`) le cercano nella cartella del progetto e si saltano se non ci sono. La base "Reference Translucent" (`assets/bases/`) è un'icona vuota senza loghi; la sua calibrazione (glifo 66,9 %, centro 0,500/0,500, 26/26 campioni) è stata misurata con lo stesso algoritmo dell'app.

Banco di regressione: `cargo run --release --example regress -- OUT in*.png` rende ogni icona due volte con la pipeline dell'app, verifica che il risultato sia deterministico e stampa un hash per confrontare le versioni.

## Benchmark (i5-13500H, `cargo run --release --example bench`)

| Uscita | Thread | Velocità | Per icona |
|---|---|---|---|
| 512 px | 1 | 13,9 icone/s | 71,9 ms |
| 512 px | tutti | 124,8 icone/s | 8,0 ms |
| 192 px | tutti | 303,3 icone/s | 3,3 ms |

208 icone (26 di riferimento × 8): decodifica, isolamento, ridimensionamento, composizione, codifica PNG e scrittura.

Abbinamento (`cargo run --release --example bench_match -- 250 …`): 250 + 250 icone in 0,11 s, 0,02 s quando viene ripetuto (firme in cache); la 1.2.0 impiegava 1,41 s ogni volta.

## Icon Pack Builder

Su Android gli originali sono tutte le app con icona nel launcher, comprese quelle di sistema: le icone vengono messe in cache su disco e rigenerate solo quando un'app si aggiorna. Si possono aggiungere originali da cartella, ZIP o APK (`appfilter.xml` binario decodificato da `axml.rs`, tenuta la densità più alta).

Le icone nuove si generano con lo Studio o si importano. L'abbinamento (`matching.rs`) valuta package, nome dell'app, nome del file e somiglianza visiva (IoU della sagoma del glifo + istogramma delle tinte). È uno-a-uno e greedy, con indice per nome e package; le firme visive sono calcolate su una copia a 160 px e tenute in cache. Le corrispondenze per nome con disegno diverso sono "Da verificare", quelle deboli o solo visive "Dubbie".

Le correzioni manuali sono salvate in `state.json` (`packCorrections`); elenchi, icone modificate a mano e pack aperti in `pack_builder.json`.

Esportazione: cartella o ZIP (`res/drawable-nodpi`, `appfilter.xml`, `mapping.json`). Su Windows **Crea APK** riempie `assets/iconpack_template.zip` (sorgente in `iconpack_template/`, si ricostruisce con `python tool/make_template_zip.py`) ed esegue Gradle con Android SDK e JDK locali: il risultato è un icon pack installabile con il proprio visualizzatore di icone, firmato con la chiave di debug locale. Su Android **Condividi APK** crea e firma l'APK sul telefono e lo passa al foglio di condivisione.

### Sul telefono, con Shizuku (`DevicePack.kt`)

**Installa e applica.** Il pack è l'app separata `com.iconformatter.pack.device`. Viene costruito sul telefono a partire da `assets/iconpack_base.apk`, che `tool/make_base_apk.py` crea con 2000 slot drawable vuoti:
- gli slot ricevono i PNG;
- vengono scritti `appfilter.xml` e `drawable.xml` binari (writer AXML verificato con `aapt2 dump xmltree`), insieme a `mapping.json` e `pack.json`;
- `versionCode` / `versionName` vengono modificati nel manifest (1.0, 1.1, …);
- l'APK viene firmato con apksig (chiave nell'Android Keystore).

Shizuku (identità shell) esegue `pm install -r` e la sequenza di selezione di IconGen: apre `com.nothing.launcher.icon_pack_picker` dietro l'app, scrive `nothing_icon_pack` = `THEMED_ICONS_NOTHING` e dopo 500 ms il package del pack. Il valore precedente viene salvato per "Ripristina".

**Apri un pack.** Riapre il pack installato (dal suo APK) o un APK/ZIP creato su un altro telefono; la versione di un APK aperto viene ricordata, così la numerazione continua. La chiave di firma resta sul telefono che ha creato il pack: un pack firmato altrove non si può aggiornare, quindi dopo una conferma esplicita viene disinstallato via Shizuku e reinstallato, poi riselezionato.

Shizuku si avvia sul telefono stesso (Debug wireless, Android 11+). Senza Shizuku l'APK passa dall'installer di sistema e il pack si sceglie a mano.

**Verificato sull'emulatore (API 35):**
- Shizuku 13.6 avviato come shell, permesso concesso dalla finestra dell'app.
- Un `com.nothing.launcher` di prova (5.0) con l'activity del selettore.
- Risultati: installazione, aggiornamenti 1.1 → 1.2 → 1.3, il valore temporaneo visto in polling, selettore finale uguale al pack, controlli `aapt2` e `apksigner`; sostituzione dopo cambio di chiave (1.3 → 1.4, selezione ripristinata).

**Non verificato:** come il vero Nothing Launcher su Nothing OS 5.0 ridisegna le icone. Serve il telefono.

## Automazione Android

- Un job JobScheduler persistente (ogni 6 ore, batteria non scarica; sopravvive ai riavvii, soggetto a Doze) e un controllo immediato allo sblocco (`USER_PRESENT`) finché il processo è attivo.
- `PackageManager.getChangedPackages` evita ogni lavoro se nulla è cambiato. Solo le app del launcher cambiate vengono controllate.
- Le modifiche (installata, disinstallata, aggiornata, icona cambiata) sono elencate nel Pack Builder, con una notifica silenziosa. "Rielabora" elabora di nuovo solo quelle app.
- Permessi: `RECEIVE_BOOT_COMPLETED`, `POST_NOTIFICATIONS` (chiesto quando si attiva l'interruttore), `REQUEST_INSTALL_PACKAGES` (installazione senza Shizuku). Niente root, niente servizi in primo piano, niente `QUERY_ALL_PACKAGES`.

## Limiti noti

- **Aggiornamento del launcher**:
  - Con Shizuku, Icon Formatter installa e seleziona il pack come IconGen. L'identità shell può scrivere la chiave non pubblica `nothing_icon_pack`, cosa che le app con `targetSdk` ≥ 23 non possono fare.
  - Shizuku deve essere attivo quando si applica il pack, e dopo un riavvio va riavviato dall'app Shizuku.
  - Il ridisegno delle icone da parte del vero Nothing Launcher non è verificato senza il telefono.
- **Icon pack Android**:
  - La versione costruita sul telefono contiene fino a 2000 icone e ha un nome fisso ("Icon Formatter Pack"); nome e accento mostrati all'interno vengono da `pack.json`.
  - Senza root Android non permette a un'app di sostituire le icone delle altre app, e il supporto dipende dal launcher.
- **App installate**: sono visibili solo le app con un'activity nel launcher (regole di visibilità dei package da Android 11). Le app senza icona nella home e quelle del profilo di lavoro non compaiono; quelle senza icona leggibile vengono segnalate e saltate.
- **AI**: costi e limiti indicati sono orientativi e dipendono dal fornitore; fa fede il listino ufficiale.
- **Trasparenza dal vivo**: il parametro "Trasparenza simulata" abbassa l'alpha del PNG; non riproduce la sfocatura dal vivo del launcher.
- **Misure di fluidità e batteria**: sono state fatte sull'emulatore (rendering software), non sul Nothing Phone (2a) Plus.

## Licenza

AGPL-3.0-only (vedi `LICENSE`, testo ufficiale in inglese).

### Componenti di terze parti

| Componente | Licenza | Note |
|---|---|---|
| Nothing IconGen (© linuxct) | AGPL-3.0-only | `native/icon_core/src/lucent.rs` contiene codice derivato (render "Nothing Translucent"). |
| Cargokit (© Matej Knopp) | MIT o Apache-2.0 | Copiato in `rust_builder/cargokit/` come previsto da flutter_rust_bridge; licenza in `rust_builder/cargokit/LICENSE`. |
| Gradle Wrapper | Apache-2.0 | `iconpack_template/gradle/wrapper/`. |
| Pacchetti Dart (119) | BSD, MIT, Apache-2.0; `dbus` MPL-2.0 | Scaricati da pub.dev, non modificati. |
| Crate Rust (~210) | MIT, Apache-2.0, BSD, Zlib, Unlicense | Scaricati da crates.io, non modificati. |
| Modelli U²-Net-p e ISNet (rembg) | Apache-2.0 | **Non inclusi**: vengono scaricati su richiesta dalle release di rembg (MIT). |

I servizi online (OpenAI, Google Gemini, remove.bg) si usano con le chiavi API dell'utente, salvate nell'archivio sicuro del sistema.

### Marchi

Icon Formatter è un progetto indipendente e non è affiliato né approvato da Nothing Technology Limited. "Nothing", "Nothing OS", "Nothing Launcher" e "Phone (2a) Plus" sono marchi dei rispettivi proprietari, citati solo per indicare con quali prodotti l'app è compatibile. Lo stesso vale per i nomi e le icone delle app che l'utente elabora: l'app lavora sulle icone presenti sul suo dispositivo e non ne distribuisce nessuna.

### Sviluppato con Claude

Il codice di Icon Formatter è scritto in collaborazione con Claude (Anthropic) tramite Claude Code: i commit generati insieme riportano Claude come co-autore.

## Compilazione

```bash
cargo test --release --manifest-path native/icon_core/Cargo.toml
flutter test test
flutter test integration_test/ffi_test.dart -d windows
flutter build windows --release
flutter build apk --release
```
