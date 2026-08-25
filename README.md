# s3mail für iPhone und iPad

Native App zu [s3mail](../s3mail). Der Entwurf steht dort in
[`IOS.md`](../s3mail/-/blob/main/IOS.md); hier steht, was davon gebaut ist.

**Stand 2026-08-25: der Spike aus Schritt 1, sonst nichts.** Es gibt keine App.

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

**Der Schlüsselbund ist unbewiesen.** Ein SwiftPM-Testbündel hat auf dem
Simulator kein Entitlement dafür (`-34018`), und ohne Host-App gibt es keinen
Schlüsselbund zum Reden. Die Tests überspringen deshalb — aber **nur** bei genau
diesem Fehlercode; jeder andere Status lässt sie weiter scheitern. Ein Skip, der
alle Schlüsselbund-Fehler schluckt, machte aus einem echten Defekt einen grünen
Lauf, und ein Schlüsselbund, der still nichts speichert, ist das, was jemand im
Zug bemerkt.

## Aufbau

    mobile/            Go: die Fassade, die Swift sieht. Eigenes Modul, weil
                       gomobile golang.org/x/mobile verlangt und s3mail nur
                       Standardbibliothek plus AWS-SDK und go-message nimmt.
    Sources/S3mailKit  Swift über der Brücke
    Tests/             XCTest gegen dieselben hässlichen Mails wie der Go-Korpus

Das Modul `mobile` zeigt über ein `replace` auf einen lokalen Auscheck des
Kerns. Sobald der Kern getaggt ist, wird daraus eine Version.

## Bauen

    make framework     baut das XCFramework
    make test          braucht eine Simulator-Laufzeit:
                       xcodebuild -downloadPlatform iOS

Eine Pipeline gibt es noch nicht: dafür braucht es einen Mac-Runner mit Tag
`mac`, und ausdrücklich **ohne** „run untagged jobs" — sonst nimmt er die
Linux-Jobs des ganzen Bestands an.
