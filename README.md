# Spraakwater

Menubar-app voor macOS: houd een sneltoets ingedrukt, praat, laat los en de tekst wordt op de cursorplek geplakt. Eigen alternatief voor Willow Voice.

## Hoe het werkt

1. Sneltoets ingedrukt houden neemt op (16 kHz mono). Een korte tik laat de opname doorlopen tot je nog een keer drukt.
2. De opname gaat naar OpenAI (`gpt-4o-transcribe`) of Groq (`whisper-large-v3`), standaard in het Nederlands.
3. Optioneel ruimt Claude (`claude-haiku-5-5`) de tekst op: vulwoorden eruit, leestekens, woordenlijst en eigen schrijfregels.
4. De tekst wordt geplakt met Cmd+V. Je klembord wordt daarna teruggezet.

Mislukt het opruimen, dan krijg je de ruwe transcriptie. De opname wordt verwijderd zodra de transcriptie binnen is. Mislukt de transcriptie zelf, dan blijft de opname bewaard (maximaal 7 dagen) en kun je hem vanuit het menu opnieuw proberen.

Verder:

- Esc annuleert een lopende opname.
- De sneltoets is vrij te kiezen, ook een losse toets zoals fn of de rechter Option (daarvoor vraagt macOS om Invoercontrole).
- De laatste 50 dictaten staan in het menu, alleen op deze Mac. Uitzetten wist ze meteen.
- Het opruimen past de toon aan op de app waarin je dicteert (mail, chat, code, notities). Alleen de naam van de app gaat mee.
- Je kiest zelf welke microfoon wordt gebruikt en of de app start bij inloggen.

## Bouwen en starten

    ./build.sh run        bouwen en starten
    ./build.sh install    bouwen en kopieren naar ~/Applications

Het script tekent de app met je Apple Development-certificaat. Zo blijven de rechten en de Keychain-toegang behouden na elke build.

## Eerste keer

1. Open Instellingen via het menubar-icoon en vul de sleutels in (OpenAI of Groq, voor het opruimen ook Anthropic). Ze staan in de Keychain.
2. Geef toegang tot de Microfoon bij de eerste opname.
3. Zet Spraakwater aan onder Systeeminstellingen > Privacy en beveiliging > Toegankelijkheid. Zonder dit kan de app niet plakken (de tekst staat dan wel op het klembord).

## Opbouw

- `AppController`: toestand en de flow opnemen, transcriberen, opruimen, plakken
- `HotkeyManager`: globale sneltoets met indrukken en loslaten (Carbon)
- `AudioRecorder`, `Transcriber`, `TextCleaner`, `TextInserter`: de losse stappen
- `Settings`: instellingen en validatie (sleutels in `Keychain`)
