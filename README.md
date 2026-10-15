# Pomodoro

App nativa per la barra dei menu di macOS, in Swift, SwiftUI e AppKit. Versione 1.0.1 (build 2), con interfaccia in inglese. Progettata per Apple Silicon e verificata su macOS 27.0.1. Nessuna dipendenza esterna, servizio remoto o connessione di rete.

## Installazione

Se scarichi il progetto da GitHub, compila prima l’app con `./scripts/build.sh` dalla cartella del progetto (vedi [Compilazione](#compilazione) per i requisiti). La cartella `dist/` viene generata localmente e non è inclusa nel repository.

1. Apri `dist/Pomodoro-macOS-arm64.zip`.
2. Trascina **Pomodoro.app** in **Applicazioni**.
3. Aprila con un doppio clic: compare l’icona del timer nella barra dei menu. Cliccala per aprire il pannello.

L’app inclusa è firmata localmente, senza notarizzazione Apple. È pronta per l’uso sul Mac su cui è stata compilata. Se viene trasferita tramite Internet a un altro Mac, macOS può richiedere **Impostazioni di Sistema › Privacy e sicurezza › Apri comunque**.

## Uso

- **Focus** parte da 25 minuti, **Relax** da 5. I controlli sotto i nomi regolano separatamente le durate, da 1 a 180 minuti.
- Scegli la fase a timer fermo, poi premi **Start**. **Pause**, **Resume** e **Reset** agiscono sull’unico timer attivo. Il pulsante di avvio ha una larghezza compatta e mostra solo **Start**. I numeri usano la variante arrotondata del carattere di sistema. Barra spaziatrice: avvio/pausa/ripresa; ⌘R: reimposta; Esc: chiudi il pannello.
- Le modifiche alle durate valgono dal prossimo avvio della fase; per applicarle subito, reimposta il timer. Il tempo già in corso o in pausa viene conservato.
- Con **Start next phase automatically** attivo, le fasi si alternano ciclicamente. Se disattivo, dopo la scadenza compare **Start** per avviare la fase successiva. L’interruttore non avvia da solo una fase già terminata.
- Alla scadenza si apre il pannello con il nome del periodo terminato. In modalità automatica mostra anche la fase già in corso. Chiudere il pannello lascia proseguire il conteggio.
- **Sound when timer ends** abilita un breve avviso nativo. Segue l’uscita audio predefinita, il volume e il mute del sistema, senza modificare le impostazioni. Il suono non viene riprodotto con uscita muta o volume zero.
- Nel menu **•••** trovi **Open at Login** e **Quit** (⌘Q). Attiva l’apertura all’accesso dopo aver spostato l’app in Applicazioni; se macOS richiede l’autorizzazione, il menu permette di aprire le Impostazioni.

Durate e preferenze sono salvate sul Mac tramite `UserDefaults`. **Open at Login** usa lo stato effettivo di `SMAppService`, gestito da macOS. Uscire dall’app interrompe la sessione corrente; al nuovo avvio il timer è pronto per Focus. Non vengono salvate sessioni di lavoro o statistiche.

## Conteggio e consumi

Il motore usa scadenze su `ContinuousClock`, che continua durante la sospensione ed è indipendente dall’ora civile del Mac ([documentazione Apple](https://developer.apple.com/documentation/swift/clock/continuous)).

A pannello chiuso è programmato un solo timer non ripetuto per la scadenza. Solo mentre il pannello è aperto e il timer è in esecuzione vengono aggiornati i secondi visibili. In pausa, a riposo e durante la sospensione non ci sono timer programmati. Nella barra dei menu resta sempre la stessa icona del timer, in tutte le fasi e gli stati. Non vengono usati assertion energetici per impedire la sospensione, notifiche remote o servizi in background separati.

Al risveglio lo stato viene ricalcolato. In modalità automatica l’app recupera le fasi trascorse mantenendo la cadenza originale e segnala una sola volta l’ultimo periodo concluso e il numero di periodi trascorsi. Non riproduce una sequenza di avvisi arretrati. Un pannello già chiuso dall’utente non viene riaperto a ogni sblocco per lo stesso evento.

## Compilazione

Requisiti: Mac Apple Silicon, macOS 14 o successivo, Swift 6 e Command Line Tools Apple. Verificato con Swift 6.4 e SDK macOS 27.0. Non serve scaricare pacchetti.

```sh
./scripts/build.sh
```

Produce `dist/Pomodoro.app` e l’archivio ZIP dell’app in configurazione Release per arm64. `./scripts/build.sh --debug` produce una build Debug. Per una firma di distribuzione puoi fornire `CODE_SIGN_IDENTITY` con un’identità presente nel Portachiavi; la notarizzazione non è automatizzata.

Con Xcode 16 o successivo puoi aprire `Pomodoro.xcodeproj` e scegliere lo schema **Pomodoro**. Il progetto usa gruppi sincronizzati con la cartella `Sources`. In alternativa apri `Package.swift`. Per ottenere il bundle pronto con `LSUIElement` e risorse usa il progetto Xcode o lo script, anziché eseguire il solo binario SwiftPM.

## Verifiche

```sh
./scripts/test.sh
open -n dist/Pomodoro.app --args --self-test "$PWD/docs/integration-results.json"
./scripts/preview.sh
```

Il secondo comando esegue una verifica nell’app reale, dura circa 65 secondi e chiude la sua istanza al termine. Usa preferenze isolate e non modifica l’apertura all’accesso. Controlla anche una scadenza reale di 60 secondi a pannello chiuso e può riprodurre un singolo suono di prova se l’uscita del Mac è udibile. Scrive il resoconto JSON in `docs/`.

Lo script `preview.sh` riutilizza il pannello reale per generare anteprime in chiaro, in scuro e a timer concluso, catturando esclusivamente la finestra del proprio processo con un framework Apple. Non richiede accesso allo schermo delle altre applicazioni. Questo strumento è separato dall’app consegnata.

Con l’SDK macOS 27, alcune acquisizioni ScreenCaptureKit possono omettere il testo del pulsante nativo; il confronto con il rendering `NSView` dello stesso pannello mostra correttamente **Start**. È un limite delle anteprime acquisite, non una modifica al pulsante dell’app.

I test automatici del motore, del modello e dei servizi nativi si eseguono anche con i soli Command Line Tools. La suite XCTest del motore è disponibile con Xcode completo; nell’ambiente usato per la consegna manca XCTest, quindi lo script esegue gli stessi casi tramite un runner Swift locale.

I resoconti della consegna si trovano in `docs/test-results.txt`, `docs/integration-results.json` e `docs/build-verification.txt`. La sospensione viene simulata in modo deterministico sul clock del modello, senza sospendere fisicamente il Mac. I test audio verificano mute, volume zero, routing e richiesta nativa di riproduzione; la conferma uditiva richiede un ascoltatore. L’apertura all’accesso viene provata con un servizio simulato per evitare di cambiare le impostazioni personali del Mac.

## Struttura

- `Sources/PomodoroCore/`: motore indipendente dalla UI, con recupero dei cicli in tempo costante.
- `Sources/Pomodoro/`: pannello SwiftUI, ciclo di vita AppKit, pianificazione, audio e apertura all’accesso.
- `Tests/`: verifiche deterministiche senza dipendenze esterne.
- `Resources/`: metadati del bundle e icona originale disegnata con AppKit.
- `scripts/`: compilazione, firma locale, test e rigenerazione dell’icona.

L’audio usa [`NSSound`](https://developer.apple.com/documentation/appkit/nssound) sull’uscita normale del Mac, con gain dello stream a 1 e senza scritture CoreAudio. Non usa l’eventuale uscita separata configurata per gli effetti sonori. L’avvio all’accesso usa [`SMAppService.mainApp`](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp).
