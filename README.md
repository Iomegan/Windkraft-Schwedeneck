# Windkraft Schwedeneck

Eine iOS/iPadOS-App zur groben Visualisierung geplanter Windkraftanlagen in Schwedeneck aus realen Blickwinkeln.

Die App nutzt Standortdaten, Kompass, ARKit-Kameraausrichtung und eine 2D-Projektion der Anlagen, um Turm, Gondel und Rotor im Kamerabild zu platzieren. Optional kann eine einfache Himmel-Maske das Overlay dort ausblenden, wo Gebäude, Bäume oder Gelände den freien Himmel verdecken.

## Hinweis

Diese App ist ein Projekt der Unabhaengigen Buergergemeinschaft Schwedeneck. Sie soll helfen, die geplanten Windkraftanlagen aus realen Blickwinkeln besser einzuordnen und die Diskussion transparenter zu machen.

Wir haben die bekannten Standorte, Hoehen und technischen Daten sorgfaeltig umgesetzt. Trotzdem bleibt die Darstellung eine Naeherung: GPS, Kompass, AR-Tracking, Gelaende, Verdeckung, Licht und Planungsdaten koennen von der Realitaet abweichen. Eine Haftung fuer die Richtigkeit wird nicht uebernommen.

Aktuell wird nach unserem Stand die groesstmoegliche Anzahl und Hoehe der Anlagen gezeigt. Das kann sich im weiteren Verfahren noch nach unten aendern.

Weitere Informationen:

- Website: <https://www.ubs-schwedeneck.de>
- FAQ zur Windkraft in Schwedeneck: <https://www.ubs-schwedeneck.de/windkraft-faq>
- Open Source: [Iomegan/Windkraft-Schwedeneck](https://github.com/Iomegan/Windkraft-Schwedeneck)

## Funktionen

- AR-Kamerabild mit georeferenzierter 2D-Anlagenprojektion
- Darstellung von sechs Anlagenstandorten in Schwedeneck
- Kartenansicht mit WEA-Markern und aktueller Position
- Vereinfachte und Experten-Ansicht
- Optionale Himmel-Maske fuer grobe Verdeckung durch Vordergrund
- Rotordrehung und vereinfachte Rotor-Seitenansicht je nach Windrichtung aus WeatherKit, mit saisonaler Schaetzung als Fallback
- Anpassung der Overlay-Helligkeit an das von ARKit geschaetzte Umgebungslicht
- Manuelle Ausrichtung im Expertenmodus

## Anlagen im Prototyp

- WEA 1: 54.458512 N, 10.084441 O, 39 m ueber NN
- WEA 2: 54.459011 N, 10.089719 O, 38 m ueber NN
- WEA 3: 54.459759 N, 10.096843 O, 37 m ueber NN
- WEA 4: 54.463399 N, 10.095556 O, 30 m ueber NN
- WEA 5: 54.466391 N, 10.098903 O, 34 m ueber NN
- WEA 6: 54.469698 N, 10.102905 O, 34 m ueber NN

Fuer alle Anlagen sind im aktuellen Prototyp 230 m Gesamthoehe und 175 m Rotordurchmesser angenommen. In der aktuellen Version wird nach aktuellem Stand die groesste Anzahl und Hoehe von Anlagen dargestellt. Das kann sich noch nach unten aendern, da das Verfahren noch am Anfang steht.

## Entwicklung

Das Projekt ist ein natives iOS-Projekt mit Swift, SwiftUI, ARKit und RealityKit.

Fuer aktuelle Winddaten nutzt die App WeatherKit. Dafuer muss die WeatherKit-Capability fuer die App-ID im Apple Developer Account aktiviert sein; wenn keine Wetterdaten abgerufen werden koennen, verwendet die App automatisch die saisonale Schaetzung.

Zum Bauen in Xcode:

1. `Windkraft Schwedeneck/Windkraft Schwedeneck.xcodeproj` oeffnen.
2. Scheme `Windkraft Schwedeneck` auswaehlen.
3. Auf einem echten iPhone oder iPad mit Kamera, Standortdiensten und ARKit testen.

Ein Simulator eignet sich nur eingeschraenkt, da Kamera, Standort, Kompass und AR-Tracking fuer die Kernfunktion gebraucht werden.

## Lizenz

Dieses Projekt steht unter der MIT-Lizenz. Siehe [LICENSE.md](LICENSE.md).
