# Outland Patrol (Godot 4)

Farverigt co-op rumeventyr i retro 3D: Freelancer-flyvning set bagfra, handel mellem planeter og stationer, trade lanes, jump gates og sømløst atmosfæredyk. Op til 4 piloter i co-op.

Dette er første milepæl: demoen genskabt i Godot med co-op bygget ind fra starten.

## Kom i gang

1. Hent **Godot 4.4** (eller nyere 4.x) fra godotengine.org. Standardudgaven er nok; .NET-udgaven skal ikke bruges.
2. Åbn Godot, vælg **Import**, og peg på `project.godot` i denne mappe.
3. Tryk **F5** for at starte.

Første gang importerer Godot projektet. Det tager et par sekunder.

## Styring

| Tast | Funktion |
| --- | --- |
| Mus | Styr skibet (skibet drejer mod markøren) |
| Venstreklik / Space | Skyd med primære våben |
| Højreklik / Ctrl | Skyd med sekundære våben |
| 1–5 | Slå våben 1–5 til/fra |
| 6–9 | Aktivér gadget 1–4 (kappe, EMP-puls, skjoldbatteri …) |
| W / S | Mere / mindre fart |
| Shift | Afterburner |
| X | Cruise |
| A / D | Sidelæns |
| Q / E | Rul |
| R / T | Lås nærmeste fjende / næste mål |
| G / midterklik | Missil |
| B | Bombe |
| F | Flares |
| Z | Traktorstråle (hold) |
| C | Scan |
| H | Kald skib op |
| U | Rumskibsmanager (udstyr, Mk I–III, lager og last) |
| I | Lastrum |
| M | Kort |
| V | Cockpit |
| L | Land på planet / dock ved station (fart under 28) |
| Enter | Afgang fra menuen |
| F2 | Skift pixelstørrelse: Grov, Mellem, Fin, Fuld opløsning |
| F3 | Skift dithering: Retro, Blød, Fra |
| F6 | Gem |
| ESC | Menu (genstart, indstillinger, taster, testværktøjer) |

Alle taster kan ændres under ESC → Taster.

Gule ringe er en trade lane, den lilla ring er en jump gate til Frosta, og den pink lyssøjle markerer landingspladsen.

## Co-op

- **Vært:** tryk *HOST CO-OP*. Spillet lytter på UDP-port 7777.
- **Ven:** skriv værtens IP og tryk *JOIN VEN*.
- På samme netværk (LAN) bruges værtens lokale IP, fx `192.168.1.20`.
- Over internettet skal værten åbne/port-forwarde **UDP 7777** i routeren, og vennen bruger værtens offentlige IP.
- Til test på én maskine: start to instanser (i Godot: *Debug → Customize Run Instances → 2*), host i den ene og join `127.0.0.1` i den anden.

Værten er autoritativ over økonomien: priser, kredit og last ændres kun hos værten, og klienterne beder om handler via RPC. Hver spiller styrer sit eget skib og sender sin position ca. 20 gange i sekundet.

## Projektstruktur

```
project.godot
data/universe.json            Alle systemer, planeter, stationer, markeder, gates og rygter
shaders/palette_dither.gdshader   Pixel-look: begrænset palette + Bayer-dithering
shaders/nebula.gdshader       Tågebaggrund, der blandes mod himlen i atmosfæren
scenes/main.tscn              Hovedscene (bygges op i main.gd)
scripts/
  main.gd                     Pixel-pipeline (SubViewport i lav opløsning, F2/F3 justerer), verden, UI og forbindelser
  autoload/game.gd            Universdata, markeder, tegnebøger, handels-RPC'er (host-autoritativ)
  autoload/net.gd             Solo / host / join med ENet
  world/universe.gd           Bygger systemerne og svarer på: nærmeste planet, landing, lanes, gates
  world/planet_body.gd        Planet fra seed: icosphere + støj, biomer, atmosfære, skyer, by og lyssøjle
  world/station_body.gd       Station med roterende ring og dok
  world/sky_dome.gd           Tåge, stjerner og sol pr. system
  player/ship.gd              Flyvning, landing, trade lane, jump og netværkssynk
  player/ship_model.gd        Skibsmodellen
  player/chase_camera.gd      Kamera bag skibet
  ui/                         Tema, HUD, titelskærm og stations-/planetmenu
tests/                        Automatiske tests (se nedenfor)
```

## Nyt indhold uden kode

Det meste indhold ligger i `data/universe.json`:

- **Ny planet:** tilføj et objekt under `planets` med position, radius, seed, farver, biom og marked.
- **Nyt system:** tilføj et system med sin egen `origin` (fx 40 km fra de andre) og en gate i hver ende.
- **Nye varer:** tilføj under `goods` og brug dem i markederne.

## Tests

Kør fra projektmappen (erstat `godot` med stien til din Godot):

```
godot --headless --path . res://tests/smoke_test.tscn
```

Testen flyver hele loopet igennem: dock, handel, trade lane, landing, jump gate og opgradering.

Co-op-test med to processer:

```
godot --headless --path . res://tests/net_test.tscn -- host
godot --headless --path . res://tests/net_test.tscn -- client
```

Missioner og base (start i hangaren, nødkald, fiasko, patrulje, rang, moduler, tårne, gem/indlæs):

```
godot --headless --path . res://tests/mission_test.tscn
```

Lavtflyvning 8 m over Viridia (terræn, kollision og re-entry):

```
godot --headless --path . res://tests/low_flight_test.tscn
```

Skærmbilleder af nøglesituationer (kræver skærm):

```
godot --path . res://tests/screenshots.tscn
```

Billederne gemmes i Godots user-mappe under `screenshots/`.

## Concord Patrol

Outland Patrol foregår i the Reach, samme univers som Outland Frontier, men er et selvstændigt spil. Du er pilot i Concord Patrol og starter i hangaren på **Bastion Kepler**, Patrol-hovedkvarteret i Kepler Rand. Her ligger missionstavlen, og hertil bliver du bjærget, hvis du bliver skudt ned.

Missionerne tager 5–15 minutter:

- **Nødkald:** nå frem til et fragtskib under angreb, før tiden løber ud, skyd angriberne ned, og eskortér det til landing. Pas på bagholdet undervejs.
- **Patruljesweep:** flyv til tre navigationsbøjer, ryd bagholdet ved hver, og meld tilbage på basen.

Efter hver mission kommer en debriefing med løn, erfaring og rang (Kadet → Pilot → Løjtnant → Kaptajn → Kommandør). Højere rang åbner sværere missioner. I co-op deler hele gruppen missionen og belønningen, og antallet af pirater skalerer med antallet af piloter.

### Bastion Kepler

Basen vokser med gruppens fuldførte missioner. Se fanen *Bastion* i basens menu:

| Modul | Åbnes efter | Giver |
| --- | --- | --- |
| Hangar | Start | Start, bjærgning, missionstavle |
| Reparationsdok | Start | Reparation |
| Våbenlager | 2 missioner | Laser Mk II på basen |
| Skjoldgenerator | 4 missioner | Skjold Mk II på basen |
| Lastbugt | 6 missioner | Lastmoduler på basen |
| Forsvarstårne | 8 missioner | Tårne skyder pirater nær basen |
| Værft | 12 missioner | Nye skibe (kommer senere) |

Modulerne dukker op på basen i 3D, når de åbnes. Intet sker, mens I er væk: basen vokser kun af det, I flyver.

Spillet gemmer automatisk hos værten (`user://outland_patrol_save.json`) efter missioner og handler: piloter efter navn og basens fremskridt. Brug samme pilotnavn næste gang. Missioner, rang og moduler ligger i `data/missions.json` og `data/base.json`.

## Indhold

- **Flyvning og navigation:** musestyring set bagfra, afterburner, trade lane mellem Kepler Station og Viridia, jump gate til Frosta.
- **5 planeter i 2 systemer** med atmosfæredyk, re-entry-flammer, skyer, byer og detaljeret terræn med træer og sten tæt på jorden.
- **Handel:** 5 varer, priser der svinger med udbud, og NPC-fragtskibe der leverer og påvirker priserne.
- **Kamp:** laser, skjold der lader op, skrog, asteroider med malm og krystaller, pirater i bølger med dusør, nødsignaler når fragtskibe angribes, bjærgning når man bliver skudt ned.
- **Værksted:** reparation, Laser Mk II, Skjold Mk II og lastmoduler.
- **Menuer** med pixelscener for hver by og station.
- **Co-op for 4:** værten styrer økonomi, pirater, asteroider, fragtskibe og pickups; alle ser det samme.

## Næste skridt

- Startskærm med fraktion, profession og skibsvalg
- Hangar med flere skibe, harvesters og egen base
- Flere missionstyper: konvoj, planetforsvar, udpost, rekognoscering, dusør, gate-genaktivering
- Sektorkort med trussel og udvidelse
- AI-wingmen til solospil
- Flere våbentyper (missiler, flak) og forsvar (flares, dodge)
- Gem/indlæs på værten
- Lyd og musik
