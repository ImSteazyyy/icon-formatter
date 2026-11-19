# Icon Formatter

Icon Formatter trasforma le icone delle app in uno stile uniforme e crea icon pack pronti da installare. Funziona su Android e su Windows.

## Cosa fa

- **Studio.** Importi immagini, una cartella, un icon pack (ZIP o APK) o le app del telefono. Lo Studio isola il simbolo di ogni icona e lo rimette su uno sfondo coerente: composizione originale, piatto traslucido "Lucent" o un preset tuo.
- **Pack.** Abbina le icone nuove alle app installate, ti mostra cosa manca o va controllato e crea l'icon pack. Su Android lo installa e lo applica nel launcher.
- **Le tue app** (Android). Mostra le app installate con l'icona che usa il launcher, e da lì le elabori in un tocco.
- **Pulizia pack.** Ripulisce un icon pack esistente mantenendo nomi, percorsi e `appfilter.xml`.
- **Calendario dinamico.** Da un icon pack prende solo le icone del calendario (un giorno per icona): nel pack generato il launcher mostra da solo il giorno di oggi.

## Requisiti

- **Consigliato: Nothing OS 5.0 (Android 16)**, per cui sono pensati lo stile Lucent e l'applicazione automatica. Minimo: Android 7.0. Per installare e applicare il pack senza PC serve [Shizuku](https://shizuku.rikka.app/) attivo (Debug wireless). Senza Shizuku il pack si installa con la conferma di sistema e si sceglie a mano dalle impostazioni del launcher.
- **Windows 10 o 11 a 64 bit.** Per creare l'APK del pack da Windows servono Android SDK e JDK.

## Aspetto

Due stili, in Impostazioni › Aspetto:

- **Stile Nothing** (predefinito): nero, card grigie, titoli serif e il rosso come colore di accento.
- **Vetro**: superfici in vetro con rifrazione, smerigliatura e luce sul bordo, regolabili in Impostazioni › Vetro.

In tutti e due gli stili l'indicatore della barra in basso si sposta tra le schede come una goccia.

## Come funziona

| Livello | Percorso | Ruolo |
|---|---|---|
| Motore Rust | `native/icon_core` | Isolamento del simbolo, piatti e forme, composizione, abbinamento delle icone, lettura e scrittura degli icon pack, elaborazione in parallelo annullabile. |
| Ponte | `rust/` | `flutter_rust_bridge` 2.13 tra Rust e Flutter. |
| Interfaccia | `lib/` | Flutter: barra in basso su Android, barra laterale su Windows. |
| Android | `android/app/src/main/kotlin/…` | App installate, accesso ai file (SAF), creazione, firma e installazione del pack sul telefono. |

### Isolamento del simbolo

È deterministico, senza modelli di machine learning. Lo sfondo viene riempito dai bordi, il "piatto" (sfondi arrotondati o semitrasparenti) viene riconosciuto e tolto, e i bordi anti-alias vengono separati senza aloni. I casi incerti sono segnalati per un controllo a mano.

Per gli sfondi difficili ci sono due alternative, in Impostazioni › Elaborazione:

- **AI locale**: un modello U²-Net-p facoltativo (4,6 MB, Apache-2.0), scaricato solo se lo chiedi ed eseguito offline sulla CPU.
- **remove.bg**: servizio online con la tua chiave API, salvata nell'archivio sicuro del sistema. Ogni immagine consuma un credito.

### Icon pack sul telefono

Il pack è un'app separata (`com.iconformatter.pack.device`). Viene costruito sul telefono partendo da un APK base con 2000 posti per le icone, firmato con una chiave che resta nell'Android Keystore e installato con Shizuku. La numerazione delle versioni si adegua da sola a quella che Android ricorda, anche dopo una disinstallazione che ha conservato i dati.

Le correzioni fatte a mano nel Pack restano salvate e vengono riapplicate a ogni rigenerazione.

### Aggiornamenti automatici (Android)

Un controllo periodico (ogni 6 ore e allo sblocco) trova le app installate, rimosse o con l'icona cambiata. Le elenca nel Pack con una notifica silenziosa, e "Rielabora" lavora solo su quelle. Niente root, niente servizi in primo piano, niente `QUERY_ALL_PACKAGES`.

## Limiti noti

- Su Android si vedono solo le app con un'icona nella home: le app senza icona e quelle del profilo di lavoro non compaiono.
- Il pack generato sul telefono contiene al massimo 2000 icone.
- Senza Shizuku Android non permette di installare il pack in silenzio né di selezionarlo nel launcher.
- L'effetto vetro completo (rifrazione, smerigliatura) richiede Android con Vulkan; su Windows il vetro usa la qualità Bilanciata.

## Compilazione

```bash
cargo test --release --manifest-path native/icon_core/Cargo.toml
flutter test test
flutter build apk --release
flutter build windows --release
```

## Licenza

AGPL-3.0-only (vedi `LICENSE`). Componenti e font di terze parti, con le loro licenze: [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

Icon Formatter è un progetto indipendente. I nomi dei produttori e dei launcher compatibili sono marchi dei rispettivi proprietari e sono citati solo per indicare la compatibilità. L'app lavora sulle icone presenti sul dispositivo dell'utente e non ne distribuisce nessuna.
