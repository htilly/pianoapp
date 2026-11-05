# 🎹 Pianoskola

En iPad-app som lär barn spela piano. Appen ansluts till ett digitalpiano via
**MIDI över USB eller Bluetooth**, visar noterna som faller ner mot en klaviatur,
och lyssnar på vad som spelas.

## Funktioner

- **Tre lägen**
  - **Vänta på mig** – låten stannar vid varje ton/ackord tills rätt tangenter trycks. Perfekt för att lära sig en ny låt.
  - **Spela med** – låten går i jämn takt (med inräkning) och appen räknar träffar, missar och fel.
  - **Lyssna** – appen spelar låten (på pianot eller i iPaden) och visar tangenterna.
- **En eller två händer** – öva höger, vänster eller båda. Appen kan spela den andra handen ("Komp").
- **Tempo** 25–150 %, **metronom**, och **loop** av ett svårt ställe (tryck *Loopa* vid början och *Sätt slut* vid slutet).
- **Stjärnor**, träffsäkerhet och "x i rad" – bästa resultatet sparas per låt.
- **Importera låtar**
  - Klistra in **ABC-notation** (även flera låtar på en gång).
  - Välj en **MIDI-fil** (.mid) från Filer-appen, eller klistra in MIDI som base64/hex.
  - Välj vilken hand varje spår/stämma ska spelas med, eller dela ett spår vid mitt-C.
- Svenska notnamn (C D E F G A **H**) eller engelska.
- Skärmklaviatur, så det går att testa utan piano.
- Inbyggda övningslåtar: C-durskala, Blinka lilla stjärna, Mary Had a Little Lamb, Glädjens sång, Jingle Bells och början av Für Elise.

## Installera på iPaden (ingen Mac behövs)

1. Installera **Swift Playgrounds** (gratis) från App Store på iPaden.
2. Ladda ner det här repot (GitHub → *Code* → *Download ZIP*) och packa upp det i Filer-appen.
3. Öppna mappen **`PianoApp.swiftpm`** i Swift Playgrounds.
4. Tryck på ▶︎ *Kör*. Vill du ha appen som en egen ikon på hemskärmen: välj *Installera på enheten*
   / "Lägg till på hemskärmen" (kräver att du loggar in med ditt Apple-ID i Swift Playgrounds).

Med Mac: öppna `PianoApp.swiftpm` i Xcode 15+ och kör på iPaden.

## Ansluta pianot

**USB (enklast, ingen fördröjning):** koppla pianots USB-port (*USB to Host*) till iPaden med en USB-kabel.
iPad med USB-C: vanlig USB-A→USB-C eller USB-B→USB-C-kabel. Äldre iPad med Lightning:
Apples *Lightning-till-USB 3-kameraadapter*. Pianot dyker upp automatiskt.

**Bluetooth:** slå på Bluetooth-MIDI på pianot och tryck på **⚙︎ → Anslut Bluetooth-piano** i appen.
Parkoppla *inte* pianot under iPadens vanliga Bluetooth-inställningar – MIDI-anslutningen görs inifrån appen.

Under *Inställningar → Ljud* väljer du om appens toner (komp och Lyssna-läget) ska spelas på pianot eller i iPaden.

## Skriva egna låtar i ABC

```
X:1
T:Glädjens sång
M:4/4          % taktart
L:1/4          % grundlängd: fjärdedel
Q:1/4=100      % tempo
K:C            % tonart
V:1 name="Höger hand"
V:2 name="Vänster hand" clef=bass
[V:1] E E F G | G F E D | C C D E | E3/2 D/2 D2 |
[V:2] C,4     | G,,4    | C,4     | C,2 G,,2   |
```

- `C D E F G A B` = mitt-C och uppåt, `c d e …` en oktav högre, `C,` en oktav lägre, `c'` två oktaver högre
- `^F` kors, `_B` b, `=F` återställt (gäller resten av takten)
- `C2` dubbel längd, `C/2` eller `C/` halv, `C3/2` punkterad; `z` = paus
- `[CEG]` ackord, `C-C` bindebåge, `C>D` punkterad rytm, `(3CDE` triol
- `|:` … `:|` repris, `[1` … `:|[2` första och andra slut

Gratis låtar finns t.ex. på [abcnotation.com](https://abcnotation.com). Man kan också be en AI-assistent
"skriv *låtnamn* i ABC-notation för piano med två stämmor, V:1 höger hand och V:2 vänster hand med clef=bass".

## Projektstruktur

```
PianoApp.swiftpm/
  Package.swift                 Swift Playgrounds-app (iOS 17+). På Linux byggs bara kärnan.
  Sources/App/
    Core/                       Plattformsoberoende logik – testas med `swift test`
      Song.swift                Datamodell, tempokarta
      MIDIFileParser.swift      Standard MIDI File typ 0/1
      ABCParser.swift           ABC-notation
      HandAssigner.swift        Höger/vänster hand per spår eller delningspunkt
      SongImporter.swift        Känner igen ABC / base64-MIDI / hex-MIDI / filer
      PracticeEngine.swift      Lägena Vänta, Spela med och Lyssna, poäng, loop, metronom
      ExampleSongs.swift        Inbyggda låtar
    MIDI/                       CoreMIDI (USB/Bluetooth) och Bluetooth-parkoppling
    Audio/                      Inbyggd pianosynt och metronomklick
    Store/                      Sparade låtar och inställningar
    Views/                      SwiftUI-vyer
  Tests/PianoCoreTests/         Enhetstester för kärnan
```

## Utveckling

Kärnan går att testa på Linux eller macOS:

```sh
cd PianoApp.swiftpm
swift test
```
