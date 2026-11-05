# Pianoskola – krav och designbeslut

## Bakgrund
En app som lär en 11-åring spela piano. Pianot har MIDI över **Bluetooth** och **USB**.

## Krav från beställaren
1. Appen ska ansluta till pianot via MIDI (USB och Bluetooth).
2. Man ska kunna **importera nya låtar** genom att klistra in noter / MIDI.
   - Format: **MIDI-filer (.mid)** och **ABC-notation**.
3. Stöd för **en hand** (höger eller vänster) och **två händer**.
4. Läge där man **spelar med** låten i tempo.
5. Läge där appen **väntar** tills man trycker på rätt tangent(er).
6. Plattform: **iPad**, och sedan även **iPhone**.
7. Native iOS-app i **Swift** (valt framför webbapp, eftersom Safari saknar Web MIDI).

## Funktionella krav (så som de är implementerade)

### Anslutning
- CoreMIDI: ansluter automatiskt till alla MIDI-källor (USB, Bluetooth, nätverk) och följer in-/urkoppling.
- Bluetooth-MIDI paras inifrån appen (Apples `CABTMIDICentralViewController`).
- Appens toner (komp, Lyssna-läget) kan skickas till pianot via MIDI ut, eller spelas i enheten
  (inbyggd synt). Val: Automatiskt / Pianot / iPaden / Båda.
- Eko-skydd: toner som appen själv skickat ignoreras om pianot skickar tillbaka dem (80 ms).
- Skärmklaviatur för test utan piano.

### Import av låtar
- Klistra in ABC-text (även flera låtar med `X:` på en gång), MIDI som base64 eller hex.
- Välj fil (.mid / .abc / .txt) via Filer.
- ABC-stöd: huvudfält X T M L Q K V, tonarter och kyrkotonarter, förtecken (gäller takten ut),
  oktaver, notlängder, pauser, ackord, bindebågar, punkterad rytm, trioler, repriser med
  1:a/2:a slut, flera stämmor, `clef=bass`. Text, ackordsymboler, ornament och förslag ignoreras.
- MIDI-stöd: typ 0 och 1, running status, tempoändringar, taktart, spårnamn, flera kanaler per
  spår delas upp; trumkanalen (10) ignoreras.
- Handfördelning per spår/stämma: Höger, Vänster, Dela (vid valbar ton, standard mitt-C),
  Komp (appen spelar), Tyst. Automatisk gissning från spårnamn, basklav och tonhöjd.
  Kan ändras i efterhand.

### Övning
- **Vänta på mig**: låten stannar vid varje ton/ackord tills alla rätt tangenter tryckts.
  Tillåter tryck upp till 0,35 s för tidigt. Fel tangent markeras rött och räknas, men låten väntar.
  Första tangenttrycket startar låten.
- **Spela med**: låten går i tempo med en takts inräkning; träff inom tidsmarginal
  (standard ±180 ms, justerbar), annars miss.
- **Lyssna**: appen spelar hela låten och visar tangenterna.
- Välj hand: höger, vänster eller båda. Appen kan spela den andra handen ("Komp").
- Tempo 25–150 %, metronom, A–B-loop vid taktstreck, positionsreglage. Spola genom att dra i stapeln eller i noterna, även under spel.
- Fallande noter (blå = höger hand, orange = vänster hand, grå = komp), taktnummer, notnamn.
- Klaviatur lyser där man ska spela; grönt = rätt, rött = fel.
- Notsystem: låten visas som riktiga noter (G- och F-klav, tonart, taktart, notvärden, pauser, förtecken,
  balkar, bindebågar och trioler) som rullar förbi en spelmarkör, i samma färger som de fallande noterna.
  Notnamn står vid noterna och kan slås av. Nedtryckta tangenter visas direkt i systemet: grönt = rätt, rött = fel.
  Dra i sidled för att spola. Välj mellan noter och fallande, bara noter eller bara fallande. På liggande iPhone
  får inte båda plats, och då visas fallande noter om man inte valt bara noter.
- Poäng: rätt, missade, fel, svit i rad; 1–3 stjärnor (≥40 / 70 / 90 % träffsäkerhet).
  Bästa resultat och antal spelningar sparas per låt.

### Övrigt
- Svenska notnamn (C D E F G A **H**, B = Bb) eller engelska.
- Inbyggda låtar: C-durskala, Blinka lilla stjärna, Mary Had a Little Lamb, Glädjens sång,
  Jingle Bells, Für Elise (början) – flera med två händer.
- Låtar sparas lokalt (JSON i appens dokumentmapp). Inget konto, ingen nätverkstrafik.

## Plattformskrav
- iOS 17+, iPad och iPhone, stående och liggande.
- iPhone: kompakt kontrollrad med menyer; klaviaturen anpassar omfånget efter bredden
  (vita tangenter minst ~16 pt) och centreras på låtens toner; tips om att vrida telefonen.
- Byggs som Swift Playgrounds-apppaket (`PianoApp.swiftpm`): körs i Swift Playgrounds på iPad
  utan Mac, eller i Xcode. iPhone kräver Mac (Xcode eller TestFlight).

## Arkitektur
- `Sources/App/Core/` – plattformsoberoende logik (bara Foundation): tolkar, handfördelning,
  övningsmotor (`PracticeEngine`, injicerad klocka) och klaviaturomfång. Testas med `swift test` på Linux/macOS.
- `MIDI/`, `Audio/`, `Store/`, `Views/` – iOS-specifikt (CoreMIDI, AVAudioEngine, SwiftUI).
- CI: GitHub Actions kör kärnans tester.

## Kända begränsningar / möjliga förbättringar
- iOS-koden är inte kompilerad i utvecklingsmiljön (saknar Apples SDK) – första bygget kan kräva små rättelser.
- Skärmklaviaturen tar en tangent i taget (inga ackord på skärmen).
- Notbilden härleds ur tonerna, eftersom låtarna lagras utan notbild: tonarten gissas, rytmen avrundas till
  sextondelar och trioler, och varje system visas enstämmigt. Upptakt känns inte igen, så takterna kan ligga förskjutna.
- Fingersättning visas inte.
- Ljudet i enheten är en enkel synt; en riktig pianoljudbank (SF2) vore bättre.
- "Öppna i Pianoskola" från andra appar stöds inte; filer väljs inifrån appen.
