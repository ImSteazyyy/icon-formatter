# Pubblicare una release

Questa guida spiega come Icon Formatter viene compilato, firmato e pubblicato su GitHub. Le pipeline sono in `.github/workflows/`:

- `ci.yml` gira su ogni push e ogni pull request: `flutter analyze`, `flutter test`, `cargo test` su `native/icon_core` e il controllo delle traduzioni (`tool/l10n_gen.py --check`).
- `release.yml` gira quando pubblichi un tag `v*`: compila gli APK Android (split per ABI più universale) e lo zip Windows, li firma con la chiave di release e crea o aggiorna la release GitHub con gli asset e le note prese da `CHANGELOG.md`.

## Nomi degli asset

Per la versione `1.0.0` la release contiene:

- `IconFormatter-1.0.0-arm64-v8a.apk`
- `IconFormatter-1.0.0-armeabi-v7a.apk`
- `IconFormatter-1.0.0-x86_64.apk`
- `IconFormatter-1.0.0-universal.apk`
- `IconFormatter-1.0.0-windows-x64.zip`

## Come pubblicare una release

1. Aggiorna la versione in `icon_formatter/pubspec.yaml` (per esempio `version: 1.0.1+5`). Il numero dopo il `+` è il build number, non entra nel tag.
2. Aggiungi in cima a `CHANGELOG.md` una sezione `## 1.0.1 — AAAA-MM-GG`. Il testo della sezione diventa il corpo della release.
3. Fai commit e push su `main`, aspetta che CI sia verde.
4. Crea e pubblica il tag, con lo stesso numero della versione:

   ```
   git tag v1.0.1
   git push origin v1.0.1
   ```

5. Vai su **Actions**, apri il workflow **Release** e controlla che i tre job (android, windows, publish) finiscano verdi. Se il tag non corrisponde a `version:` in `pubspec.yaml`, il job fallisce subito con un messaggio chiaro: in quel caso elimina il tag remoto (`git push --delete origin v1.0.1`) e ricrealo dopo aver corretto la versione.
6. Apri la pagina **Releases**: trovi la release con i cinque file. Puoi ripubblicare lo stesso tag: gli asset con lo stesso nome vengono sostituiti.

## Secret da configurare (una volta sola)

In GitHub: repository **Settings › Secrets and variables › Actions › New repository secret**. Aggiungi quattro secret:

| Nome | Valore |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | il keystore codificato in base64 (vedi sotto) |
| `ANDROID_KEYSTORE_PASSWORD` | la password del keystore, da `KEYSTORE-INFO.txt` |
| `ANDROID_KEY_ALIAS` | `iconformatter` |
| `ANDROID_KEY_PASSWORD` | la password della chiave, da `KEYSTORE-INFO.txt` (è uguale a quella del keystore) |

Per il keystore in base64, in PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\.icon-formatter-keys\release.jks")) | Set-Clipboard
```

Poi incolla negli appunti nel campo `ANDROID_KEYSTORE_BASE64`. Non salvare mai questo valore in file del repository.

Se un secret manca, il job android si ferma con l'elenco di quelli mancanti. Nessun APK viene firmato con una chiave diversa da quella di release.

## Chiave di firma: da conservare

La chiave è in `$env:USERPROFILE\.icon-formatter-keys\release.jks`, con le password e l'impronta SHA-256 in `KEYSTORE-INFO.txt` nella stessa cartella. Sono fuori dal repository e non vanno committati.

Fai un backup di entrambi i file in un posto sicuro (per esempio una chiavetta o un gestore di password). Se li perdi, non puoi più pubblicare aggiornamenti che si installano sopra le versioni esistenti: gli utenti dovranno disinstallare e reinstallare l'app.

## Verificare la firma di un APK

Con il build-tools dell'SDK Android:

```
apksigner verify --print-certs IconFormatter-1.0.1-universal.apk
```

Il campo `SHA-256 digest` deve coincidere con l'impronta in `KEYSTORE-INFO.txt`.

## Nota per chi aggiorna dalla versione con la chiave di debug

Le build precedenti erano firmate con la chiave di debug. Questa è la prima con la chiave di release. Android rifiuta un aggiornamento firmato con una chiave diversa, quindi la prima installazione mostra "signatures do not match". Una volta sola bisogna disinstallare l'app e installare la nuova. Il pack di icone installato resta sul telefono. Da quel momento in poi gli aggiornamenti si installano normalmente sopra la versione precedente.

## Build locale

Senza `android/key.properties` la build di release locale usa la chiave di debug, così `flutter run --release` continua a funzionare. Con `key.properties` (già presente sul PC di sviluppo, ignorato da git) la build usa la chiave di release. Su CI la variabile `CI=true` rende obbligatoria la chiave: senza, la build fallisce invece di firmare con il debug.
