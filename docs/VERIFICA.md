# Verifica della consegna

15 ottobre 2026 · macOS 27.0.1 · arm64 · Swift 6.4 · SDK macOS 27.0

Aggiornamento **1.0.1**: interfaccia in inglese, icona del timer fissa nella barra, pulsante **Start** compatto e cifre arrotondate. Ricompilazione Release, firma locale, metadati, integrità dello ZIP e typecheck verificati; ripetuti i 27 controlli dei servizi nativi. I risultati dei 90 controlli sotto riportati sono la verifica completa della prima versione; motore e pianificazione non sono cambiati in questo aggiornamento. Le anteprime vengono rigenerate dal pannello aggiornato.

**90 controlli superati, nessun errore:** 12 casi del motore, 27 controlli dei servizi nativi, 25 del modello e 26 nell’app avviata. Dettagli in `test-results.txt` e `integration-results.json`.

La verifica nell’app reale ha controllato l’icona nella barra dei menu e l’assenza dal Dock, apertura e chiusura del pannello, avvio, pausa, ripresa, reimpostazione, avvio manuale della fase successiva e alternanza automatica. Una scadenza reale di 60 secondi, con pannello chiuso, ha aperto il pannello e indicato correttamente la fine della fase. Gli avvisi ripetuti vengono esclusi anche al successivo sblocco della sessione.

La sospensione è simulata sul clock iniettato: il recupero di molti cicli produce un solo evento, mantenendo la cadenza. Il Mac non è stato sospeso fisicamente durante il lavoro. Un controllo indipendente del motore ha confrontato il recupero diretto con l’avanzamento sequenziale in 17.496 combinazioni ai confini delle scadenze, tutte coerenti.

Per l’audio sono state verificate le decisioni relative a suono disattivato, mute, volume zero e uscita assente, oltre a routing e configurazione del suono nativo. Nell’app il sistema ha accettato la riproduzione reale del suono (`nativeAudioOutcome: played`). L’ascolto umano non è automatizzato. I test non hanno modificato volume, mute o periferica di uscita.

L’apertura all’accesso è verificata con un servizio simulato, inclusi autorizzazione pendente, errori e annullamento. Non è stata modificata la configurazione personale di avvio del Mac.

Il modello programma solo la scadenza quando il pannello è chiuso; in pausa, a riposo e durante la sospensione non programma timer. Un campione dell’app in esecuzione durante l’attesa a pannello chiuso riportava RSS 37.200 KB e CPU 0,0%. È una misura istantanea, non un benchmark energetico.

La firma locale del bundle, l’architettura arm64, l’integrità dello ZIP e le dipendenze esclusivamente Apple sono verificate in `build-verification.txt`. Il progetto Xcode è stato validato nella struttura e tramite compilazione dei sorgenti in un unico modulo; l’ambiente dispone dei Command Line Tools, senza `xcodebuild`. Il bundle consegnato è compilato in Release con Swift Package Manager.
