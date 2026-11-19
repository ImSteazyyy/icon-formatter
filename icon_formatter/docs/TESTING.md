# Test

Tre livelli: test unitari, test di integrazione (flussi dell'app) e stress test a 5000 icone.
Comandi da eseguire nella cartella `icon_formatter` del progetto, con Flutter in `/d/dev/flutter/bin/flutter`.

## Test unitari

```
flutter test test
```

Controllano la logica pura (modelli, pack, l10n, calendario, ecc.).

## Test di integrazione (flussi)

File: `integration_test/app_flow_test.dart` (helper in `integration_test/e2e_support.dart`).

```
export MSYS_NO_PATHCONV=1
flutter test integration_test/app_flow_test.dart -d emulator-5554
```

Su Windows desktop: `-d windows` (la scheda Apps esiste solo su Android).

Cosa copre:

- a: le schede Studio, Pack e Impostazioni si aprono senza eccezioni e la barra e' visibile.
- b: Impostazioni > Aspetto: Nothing e Vetro, tema scuro e chiaro, poi ritorno allo stato iniziale.
- c: Studio: importa 13 icone sintetiche (disegnate dal test, nessuna grafica di terzi), "Elabora tutte",
  controllo che ogni icona abbia un risultato senza errori e che l'output esista, poi "Manda al Pack".
- d: "Manda al Pack" arriva davvero al Pack builder (controllo sui dati del builder, non sul testo
  a schermo, perche' la scheda Pack mostra le app del catalogo); "Abbina" non genera eccezioni.
- e: Impostazioni > Sistema: si vedono le righe della cache.

La lingua e' forzata all'italiano e l'onboarding e il tour sono saltati.
La scheda Apps apre la richiesta di permesso Shizuku, quindi non viene aperta a meno di
`--dart-define=E2E_APPS=true`.

Errori Flutter tollerati: `e2e_support.dart`, costante `allowedFlutterErrors`. Oggi contiene un solo
errore di debug (ListTile senza Material, in `AutoSyncCard`, `lib/screens/pack_builder_screen.dart:3116`).
Ogni occorrenza viene stampata con `E2E_ALLOWED` e la catena dei creatori del widget. Quando il
problema viene corretto in `lib/`, togliere la voce dalla lista.

Ogni test riparte dall'app appena avviata; i messaggi di errore indicano il passo che fallisce.

## Stress test: 5000 icone

File: `integration_test/stress_5000_test.dart`. Il test genera le immagini da solo, nella cache
dell'app (`.../cache/IconFormatterCache/stress_in`), con colori e codici a 16 bit distinti per
ogni icona, cosi' la cache dei ritagli non puo' riutilizzarli. Non serve nessun file sul
dispositivo. La generazione non entra nei tempi misurati (ma e' riportata nella prima riga).

```
flutter test integration_test/stress_5000_test.dart -d emulator-5554 \
  --dart-define=STRESS=true \
  --dart-define=STRESS_N=5000 \
  --dart-define=STRESS_BUDGET_MB=1536
```

Per la prova rapida usare `--dart-define=STRESS_N=500`. Senza `STRESS=true` il test viene saltato,
cosi' il comando di integrazione normale non lo esegue.

Il test importa la cartella dallo Studio, preme "Elabora tutte" e ogni 100 icone registra:
tempo trascorso, tempo per 100 icone, RSS del processo (MB), frame totali, frame "janky"
(piu' di 16,7 ms tra costruzione e raster), frame peggiore ed errori.

### Cosa significano i budget

- `STRESS_BUDGET_MB` (default 1536): picco di RSS del processo oltre il quale il test fallisce.
  E' una soglia scelta, non una misura del telefono. Sull'emulatore x86_64, che ha poca RAM,
  un superamento va letto come un dato da confrontare con le versioni precedenti.
- Frame "janky": percentuale di frame oltre 16,7 ms durante l'elaborazione. Non fa fallire il
  test: e' un indicatore per confrontare le versioni.
- Il test fallisce anche se un'icona termina con errore, se non si importano tutte le icone o se
  l'app si chiude (crash).

### Dove sono i risultati

- File: `<cache dell'app>/IconFormatterCache/stress_results.txt`. Su Android e' in
  `/data/user/0/com.iconformatter.icon_formatter/cache/IconFormatterCache/`, leggibile con
  `adb shell run-as com.iconformatter.icon_formatter cat ...` (app debug).
- Stampati in console con il prefisso `E2E_STRESS`.

Il file si aggiorna a ogni blocco di 100 icone, quindi resta leggibile anche se l'app si chiude a meta'.

## Immagini di test

Le immagini generate non vanno nel repository e non vengono copiate sul dispositivo: vivono solo
nella cache dell'app durante il test. Non mettere screenshot dell'emulatore nel repository.
