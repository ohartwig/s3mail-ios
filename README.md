# s3mail für iPhone und iPad

Native App zu [s3mail](../s3mail). Der Entwurf steht dort in
[`IOS.md`](../s3mail/-/blob/main/IOS.md); hier steht, was davon gebaut ist.

**Stand 2026-08-25: die Schritte 1 bis 4 sind gebaut.** Es gibt eine App: sie
richtet sich per QR-Code ein, zeigt Ordner und Postfach, öffnet Mail, schreibt
Entwürfe in den Bucket und verschickt über SES. Offen sind Push (Schritt 5) und
Verteilung (Schritt 6) — beide hängen am Mac-Runner und an Apple, nicht am Code.

## Was der Spike beantwortet hat

Die Frage, an der das ganze Vorhaben hing: **lässt sich der Go-Kern von s3mail
in eine iOS-App holen, statt ihn ein zweites Mal in Swift zu schreiben?**

Ja.

- `gomobile bind` erzeugt aus `core`, `mimeparse` und dem AWS-SDK ein
  XCFramework für Gerät und Simulator — 26 MB, 8,9 MB davon das arm64-Binary.
- **Das AWS-SDK übersetzt für iOS.** Das war das größte Risiko: ohne S3 keine
  App. 217 SDK-Symbole liegen im Binary.
- Die Brücke, die Swift sieht, ist schmal und lesbar:
  `MobileParseMessage(NSData*, NSError**) -> NSString*`.

Damit gilt, was `IOS.md` fordert: `mimeparse` existiert genau einmal. Der harte
Teil eines Mailclients — Outlook-Multiparts, `winmail.dat`, drei Zeichensätze in
einer Betreffzeile — wird nicht nachgebaut.

- **Es läuft auch.** Vier Tests im iOS-Simulator: Swift ruft Go, und ein
  Betreff aus drei Zeichensätzen kommt als „Grüße aus München und Zürich" an.
  Übersetzt ist nicht gelaufen — jetzt ist es beides.
- **Ein echter S3-Aufruf geht durch.** `ListObjectsV2` gegen ein echtes Postfach,
  aus dem Simulator, in 0,3 Sekunden. Das war das zweite Risiko: TLS, DNS, die
  App-Sandbox und die Zugangsdaten-Maschinerie des SDK müssen sich zusätzlich
  einig sein, und das beweist kein erfolgreicher Bau.
- **Falsche Zugangsdaten kommen als Fehler an**, nicht als leere Liste. Eine App,
  die bei fehlendem Zugriff ein leeres Postfach zeigt, schickt jemanden auf die
  Suche nach Mail, die längst da ist.

## Was der Spike nicht beantwortet hat

- **Kein Lauf auf echter Hardware.** Simulator ist nicht Telefon.
- **Keine Oberfläche.** `Sources/S3mailKit` ist die Naht, mehr nicht.
- **Kein Zugangsmodell.** Der Test bekommt Schlüssel über die Umgebung; wie eine
  App an ihre kommt — ein IAM-Benutzer je Gerät, Einrichtung per QR vom Rechner —
  steht in `IOS.md` und ist nicht gebaut.

## Schritt 2: das Zugangsmodell

Gebaut, mit einer Einschränkung.

Ein Telefon trägt **nicht** den Schlüssel des Rechners. Ein eigener IAM-Benutzer
je Gerät, dieselbe enge Policy — dann ist ein verlorenes Telefon ein Klick in
der IAM-Konsole und der Rechner läuft weiter. Der Assistent auf dem Rechner
schreibt die passende Policy aus und zeigt einen QR-Code; **der Code trägt
keinen Schlüssel**, der wird nach dem Anlegen des Benutzers von Hand eingesetzt.

Hier im Repo liegt die Telefon-Seite: `Setup` liest den Code und weist zurück,
was unvollständig ist — ein Prefix ohne Schrägstrich zum Beispiel, denn `mail`
fängt auch `mailbox-alt/` ein, und das Postfach enthielte still fremde Post.
`Keychain` legt das Ergebnis ab, mit `WhenUnlockedThisDeviceOnly`: nicht lesbar,
solange das Telefon gesperrt ist, und nie auf ein zweites Gerät zurückgespielt.

**Der Schlüsselbund ist bewiesen — seit es die App gibt.** Vorher übersprangen
sich die Tests selbst: ein SwiftPM-Testbündel hat auf dem Simulator kein
Entitlement dafür (`-34018`), und ohne Host-App gibt es keinen Schlüsselbund zum
Reden. Ein übersprungener Test ist kein bestandener Test, und ein Schlüsselbund,
der still nichts speichert, ist das, was jemand im Zug bemerkt. Sie liegen
deshalb jetzt in `AppTests/`, in einem Bündel, das die App hostet.

## Schritt 3: Liste und Lesen

Gebaut, gegen das echte Postfach geprüft. Drei Entscheidungen mit Begründung im
Code:

- **Der Index liegt in Application Support, nicht in Caches.** iOS leert `Caches`,
  wann es will — meist ohne Netz.
- **Kein zweites Verschlüsseln.** Am Schreibtisch wird verschlüsselt, weil ein
  Heimatverzeichnis in Backups und synchronisierten Ordnern mitreist. Eine
  App-Sandbox tut das nicht: sie steht schon unter dem Dateischutz des Geräts,
  und ein zweiter Schlüssel wäre mehr Fläche als Schutz.
- **`allowDelete` bleibt aus.** Das Telefon zeigt und verschiebt; Löschen ist
  eine Entscheidung für den Schreibtisch.

**HTML-Mail wird noch nicht angezeigt.** Am Schreibtisch macht erst die Anordnung
aus `sandbox=""`-iframe, CSP und blockierten Bildern das Anzeigen fremden HTMLs
vertretbar. Die halbe Umsetzung wäre schlimmer als keine.

## Schritt 4: Schreiben und Senden

Entwürfe liegen als **richtige Nachrichten in `drafts/`**, nicht in einem
app-eigenen Speicher — deshalb sieht der Schreibtisch sie fünf Minuten später,
ohne dass die App irgendetwas abgleicht.

Die Reihenfolge beim Senden ist die aus `web/send.go`, bewusst übernommen und
nicht verbessert:

- **Erst den Versuch vermerken, dann senden.** Der Marker aus `store/sending.go`
  überlebt einen Prozess, der mittendrin stirbt. Auf dem Telefon ist das kein
  Randfall: iOS beendet Apps im Hintergrund ohne Vorwarnung.
- **Sobald SES angenommen hat, darf nichts mehr die Antwort zu einem Fehler
  machen.** Eine Kopie, die nicht in `sent/` ankam, ist eine Warnung. Als Fehler
  gemeldet liest sie sich als „nicht verschickt", und die Mail geht ein zweites
  Mal raus.

Beim Start fragt die App nach, was `RecoverSends` nicht selbst entscheiden kann.
Raten geht in beide Richtungen schief: „verschickt" verliert eine Mail, „nicht
verschickt" verschickt sie doppelt.

## Texte

Die App hat einen eigenen Katalog in `de`, `en`, `es`, und einen Test dafür wie
`i18n_test.go` im Kern: jede Sprache trägt jeden Schlüssel, die Platzhalter
stimmen überein.

**Die Brücke gibt Codes zurück, keine Sätze** (`send_not_permitted`). Ein
Go-Kern in einer App hat keine Sprache zu haben — welche gilt, entscheidet das
Telefon.

`core.Folder.Label` ist ebenfalls ein Katalogschlüssel und kein Wort: der
Ordnername ist ein S3-Prefix und darf nie übersetzt werden, sonst findet ein
Client in einer anderen Sprache die Mail nicht mehr, die ein Kollege abgelegt
hat. Ein selbst angelegter Ordner steht nicht im Katalog und kommt unverändert
zurück — dieser Rückfall ist die Absicht, nicht ein Versehen.

## Aufbau

    mobile/            Go: die Fassade, die Swift sieht. Eigenes Modul, weil
                       gomobile golang.org/x/mobile verlangt und s3mail nur
                       Standardbibliothek plus AWS-SDK und go-message nimmt.
    Sources/S3mailKit  Swift über der Brücke: Postfach, Ansichten, Katalog
    Tests/             XCTest gegen dieselben hässlichen Mails wie der Go-Korpus
    ios-app/           die App: Projektdatei, Quellen, Tests mit Host

Die Projektdatei ist klein, weil Xcode 16 **synchronisierte Ordner** kann: das
Ziel nennt `ios-app/Sources`, und jede Datei darin ist im Bau, ohne einen
Eintrag von sich.
Die Alternative wäre `xcodegen` gewesen — eine YAML-Datei plus ein Werkzeug, das
der Mac-Runner auch installieren müsste. Dieselbe Überlegung wie bei
`tools/zip.go` im Kern: keine Abhängigkeit für das, was auf einen Bildschirm
passt.

Sie liegt in einem Unterverzeichnis und nicht neben `Package.swift`: mit einer
`.xcodeproj` im Wurzelverzeichnis meint `xcodebuild` dort immer das Projekt, und
die Tests des Pakets wären unerreichbar, ohne dass es jemandem gesagt würde.

Das Modul `mobile` zeigt über ein `replace` auf einen lokalen Auscheck des
Kerns. Sobald der Kern getaggt ist, wird daraus eine Version.

## Bauen

    make framework     baut das XCFramework
    make test          Paket-Tests, braucht eine Simulator-Laufzeit:
                       xcodebuild -downloadPlatform iOS
    make app           baut die App
    make app-test      die Tests, die eine Host-App brauchen

Die Tests gegen ein echtes Postfach laufen nur mit Zugangsdaten in der Umgebung,
und `xcodebuild` reicht **ausschließlich** Variablen mit dem Präfix
`TEST_RUNNER_` an das Testbündel weiter. Ohne das Präfix überspringen sie sich
still, während die Zusammenfassung „passed" meldet:

    TEST_RUNNER_S3MAIL_KEY=… TEST_RUNNER_S3MAIL_SECRET=… \
    TEST_RUNNER_S3MAIL_REGION=eu-north-1 \
    TEST_RUNNER_S3MAIL_BUCKET=… TEST_RUNNER_S3MAIL_PREFIX="mail/ole/" \
    make test

## Pipeline

Sie zerfällt in zwei Hälften, und die Trennung ist der Punkt:

- **Die Go-Seite der Brücke braucht keinen Mac.** Formatierung, `vet` und ein
  Bau laufen auf dem gewöhnlichen Linux-Runner. Dort entstehen die Fehler, für
  die man sonst zwanzig Minuten auf einen Mac wartet: eine Signatur, die sich
  geändert hat, ein Feld, das die Fassade nicht mehr kennt.
- **Alles mit Xcode braucht einen Mac.** Diese Jobs tragen `tags: [mac]` und
  laufen nur, wenn die Projektvariable `MAC_RUNNER = yes` gesetzt ist. Ohne
  Runner blieben sie hängen, und jede Pipeline stünde auf „stuck" — eine rote
  Ampel, die nichts über den Code aussagt.

Der Runner braucht Tag `mac` und ausdrücklich **kein** „run untagged jobs" —
sonst nimmt er die Linux-Jobs des ganzen Bestands an und ist damit beschäftigt,
während niemand eine App baut.

Für iOS baut die CI **nicht** auf Linux: `GOOS=ios` verlangt CGO und damit eine
clang-Toolchain mit iOS-SDK. Der Linux-Job baut deshalb für Linux — was er
prüft, ist die Brücke, nicht das Ziel.

## Der Kern als Modul mit Version

`mobile/go.mod` verlangt `git.ole-hartwig.eu/development/s3mail/s3mail/go` in
einer festen Version — das `/go` am Ende, weil die `go.mod` des Kerns unter
`go/` steht und Go ein Untermodul nach seinem Verzeichnis benennt. Die
Versionen heißen dort `go/v1.5.0`, neben `v1.5.0`.

Der Kern ist nicht öffentlich. Lokal braucht Go darum zweierlei:

    export GOPRIVATE=git.ole-hartwig.eu
    # ~/.netrc, Rechte 0600:
    machine git.ole-hartwig.eu login <benutzer> password <token mit read_repository>

Ohne Anmeldung antwortet GitLab auf Gos Modulanfrage nicht mit einem Fehler,
sondern mit der Gruppe als Modul — und `go` klont dann etwas, das kein
Repository ist. Die Pipeline meldet sich mit dem Job-Token an.

Eine neue Kern-Version kommt wie jede andere Abhängigkeit: als Merge Request
von pinup, mit `go mod tidy` im Gepäck. Wer lokal gegen einen ungetaggten
Stand des Kerns arbeiten will, nimmt dafür eine `go.work` — nicht ein
`replace` in `mobile/go.mod`, das würde jeden mitnehmen.
