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

## Was der Spike nicht beantwortet hat

- **Kein Lauf auf einem Gerät.** Übersetzt ist nicht gelaufen.
- **Kein AWS-Aufruf.** Dass das SDK übersetzt, heißt nicht, dass ein
  `ListObjectsV2` vom Telefon aus durchgeht.
- **Keine Oberfläche.** `Sources/S3mailKit` ist die Naht, mehr nicht.

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
