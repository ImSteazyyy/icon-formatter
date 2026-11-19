# Piano dei media del README

Tutti i file vanno in `docs/media/`. Il README li richiama con percorsi relativi. Se un file manca, il README resta leggibile grazie al testo alternativo (`alt`).

## Regole per tutte le catture

- **Nessuna icona o logo di terze parti.** Non compaiono icone di app reali, né launcher, store, social, né il logo di Shizuku. Nelle schermate Shizuku mostra solo il testo di stato, con il logo ritagliato via.
- **Icone sintetiche.** Crea 8-10 icone demo semplici (forme geometriche, due colori) in `docs/media/samples/`, con nomi di fantasia tipo "Meteo Demo", "Note Demo", "Mappe Demo". Importale dalla cartella con "Immagini o icon pack". Non usare mai icone reali.
- **Nessun dato personale.** Niente nomi, email, account, chiave remove.bg, link Ko-fi personale. Niente percorsi con il nome utente (per esempio `C:\Users\...`): sfuocali o usa una cartella di esempio.
- **Telefono.** Emulatore Android con profilo pulito, solo le app demo installate, lingua italiana. Cattura a 1080x2400 e riduci a 360x800 (rapporto del telefono). Per una barra di stato pulita: `adb shell settings put global sysui_demo_allowed 1`, poi `adb shell am broadcast -a com.android.systemui.demo -e command enter` e `-e command clock -e hhmm 0941`, `-e command battery -e level 100 -e plugged false`, `-e command network -e wifi show -e level 4`.
- **PC.** Finestra di Icon Formatter ritagliata (nessun desktop, nessuna barra delle applicazioni con altre icone). Usa una risoluzione di 1280x800 e ritaglia a 960x600 dove indicato.
- **Peso.** GIF sotto 3 MB, PNG sotto 500 KB, hero sotto 800 KB.
- **GIF.** Registra con `adb shell screenrecord --size 1080x2400 /sdcard/cattura.mp4` (poi `adb pull`) o con scrcpy. Converti con:
  ```
  ffmpeg -i cattura.mp4 -vf "fps=12,scale=360:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer" out.gif
  ```
  Per le GIF su PC, registra la finestra ritagliata con ScreenToGif o con ffmpeg, poi applica lo stesso comando con `scale=960:-1`.

## File

### hero.png
- **Dove:** in cima al README, larghezza 800.
- **Formato:** PNG, 1600x600.
- **Cosa mostra:** a sinistra icone demo con sfondi e forme diverse; a destra le stesse icone nello stile uniforme, con una card del pack accanto.
- **Come:** due catture della finestra Studio su PC (prima di "Elabora tutte" e dopo), affiancate in un editor di immagini con uno sfondo neutro.

### studio-import.gif
- **Dove:** sezione Studio, larghezza 320.
- **Formato:** GIF, 360x800, circa 8 secondi.
- **Cosa mostra:** importazione di sei immagini demo e poi elaborazione.
- **Passi:** apri lo Studio vuoto → "Importa icone" → "Immagini o icon pack" → seleziona sei PNG demo dalla cartella `samples/` → "Aggiungi 6" → la griglia si riempie di miniature → "Elabora tutte" → l'elenco mostra lo stato "pronta".
- **Evita:** la voce "Usa le app del telefono" (mostrerebbe app reali).

### studio-corrections.png
- **Dove:** sezione Studio, larghezza 320.
- **Formato:** PNG, 360x800.
- **Cosa mostra:** anteprima di un'icona con la linea prima/dopo e il pannello di correzione aperto (centratura ottica, colore del simbolo).
- **Passi:** nello Studio tieni premuta un'icona demo → nel pannello regola "Centratura ottica" o "Colore del simbolo" → lascia la linea a metà schermo → scatta.

### studio-style.gif
- **Dove:** sezione Stili, larghezza 320.
- **Formato:** GIF, 360x800, circa 10 secondi.
- **Cosa mostra:** scelta dello stile Lucent e confronto prima/dopo.
- **Passi:** apri "Personalizza" → seleziona Lucent → sposta lo slider "Dimensione del simbolo" → cambia la forma del piatto in Squircle → "Elabora tutte" → trascina la linea bianca del confronto.

### pack-matching.gif
- **Dove:** sezione Pack, larghezza 480.
- **Formato:** GIF su PC, ritaglio 960x600, circa 8 secondi.
- **Cosa mostra:** l'elenco delle app del pack che si riempie e gli stati che cambiano (abbinata, incerta, icona mancante).
- **Passi:** apri il Pack con un pack demo caricato come originali (da file) → premi "Abbina" → mostra il conteggio "N app su M hanno la loro icona" → scorri l'elenco.

### pack-details.png
- **Dove:** sezione Pack, larghezza 480.
- **Formato:** PNG su PC, ritaglio 960x600.
- **Cosa mostra:** i dettagli di un abbinamento incerto, con prima/dopo e il motivo ("stesso nome" o "somiglianza visiva").
- **Passi:** tocca un abbinamento incerto → apri "Dettagli" → scatta con il riquadro prima/dopo visibile.

### pack-preview-home.png
- **Dove:** sezione Pack, larghezza 480.
- **Formato:** PNG su PC, ritaglio 960x600.
- **Cosa mostra:** l'anteprima della schermata home con le icone demo, in chiaro e in scuro affiancati.
- **Passi:** apri "Anteprima home" → scatta con "Chiaro" e poi con "Scuro", affiancandole in un solo PNG.

### android-apply.gif
- **Dove:** sezione Android, larghezza 320.
- **Formato:** GIF, 360x800, circa 10 secondi.
- **Cosa mostra:** la sezione "Applica nel launcher" che installa e seleziona il pack.
- **Passi:** nel Pack apri "Applica nel launcher" → "Installa e applica" → lascia vedere i passi di avanzamento ("Creo il pack…", "Installo il pack…", "Seleziono il pack nel launcher…") → esito "Pack applicato: N icone".
- **Note:** usa un emulatore con Shizuku attivo solo se puoi ritagliarne il logo. Altrimenti inquadra solo la scheda di Icon Formatter con lo stato in testo. La finestra di conferma del sistema può restare, perché mostra solo l'icona di Icon Formatter.

### calendar.gif
- **Dove:** sezione Android, larghezza 320.
- **Formato:** GIF, 360x800, circa 8 secondi.
- **Cosa mostra:** il giorno del calendario che si aggiorna.
- **Passi:** nel Pack apri la sezione "Giorno del calendario" → imposta l'ora "Aggiorna il giorno alle" → premi "Aggiorna giorno" → compare "Giorno aggiornato su N icone" → mostra l'anteprima home con l'icona del calendario demo che cambia da un giorno all'altro.
- **Note:** nessuna schermata del launcher reale: usa solo l'anteprima dell'app.

### pack-app.png
- **Dove:** sezione Android, larghezza 320.
- **Formato:** PNG, 360x800.
- **Cosa mostra:** la schermata dell'app del pack con la barra di ricerca, i filtri (Tutte, Installate, Mancanti) e il pulsante di ordinamento.
- **Passi:** installa il pack demo sull'emulatore → apri la sua app → scatta con il filtro "Tutte" attivo.
- **Note:** nomi delle app demo di fantasia.

### themes-nothing-glass.png
- **Dove:** sezione Aspetto, larghezza 640.
- **Formato:** PNG, 720x800 (due catture da 360x800 affiancate, con un piccolo spazio tra le due).
- **Cosa mostra:** Impostazioni › Aspetto con lo stile Nothing a sinistra e lo stile Vetro a destra, entrambi in modalità scura.
- **Passi:** apri Impostazioni › Aspetto → scegli Nothing → scatta → scegli Vetro → scatta → affianca.

### onboarding.gif
- **Dove:** sezione Aspetto, larghezza 320.
- **Formato:** GIF, 360x800, circa 12 secondi.
- **Cosa mostra:** il primo avvio: scelta della lingua, aggiornamento automatico, Shizuku come voce facoltativa, poi le pagine del tour.
- **Passi:** disinstalla l'app (o cancella i dati) → primo avvio → "Benvenuto" → lingua → "Aggiornamento automatico" → "Shizuku (facoltativo)" (solo testo) → "Inizia" → pagine del tour: benvenuto, stile (Nero o Vetro), permessi con stato "Non concesso", "Tutto pronto".
- **Note:** nessuna pagina di store di Shizuku.

### settings.png
- **Dove:** sezione Aspetto, larghezza 320.
- **Formato:** PNG, 360x800.
- **Cosa mostra:** la griglia di Impostazioni con le sue categorie (Aspetto, Vetro, Elaborazione, Icone base, Pack, Esportazione, Sistema, Info).
- **Passi:** apri Impostazioni, scorri in alto, scatta. Non mostrare la scheda Ko-fi.

## Controlli prima di pubblicare

- Ogni file ha il nome esatto indicato sopra e sta in `docs/media/`.
- Nessuna icona di terze parti, né logo, né nome di app reale (controlla anche le barre di stato e i menu).
- Nessun dato personale, né percorsi con il nome utente.
- Pesi nei limiti; le GIF si riproducono in loop senza scatti.
