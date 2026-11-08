# AC-Dimmer Test — Verdrahtung und Inbetriebnahme

Modul: RobotDyn-AC-Dimmer (BTA16-600B, CT3021-Treiber, PC817 als Nulldurchgangsgeber, 8 A RMS), 3-Klemmen-Netzteil, 4-Pin-Logikheader `VCC GND Z-C PSM`.
Board: AZ-Delivery ESP32 D1 Mini (ESP32-WROOM-32, 4 MB).
Last: erst Glühlampe, dann ebm-papst R2E190-RA (230 V~, 0,23–0,35 A, 52–80 W).

---

## 1. Logikseite

| ESP32 D1 Mini | Dimmer | Ader | Funktion |
|---|---|---|---|
| `3V3` | `VCC` | 1 | Logikversorgung, **zwingend 3,3 V** |
| `GND` | `GND` | 2 | gemeinsame Masse |
| `GPIO25` | `PSM` | 3 | Triac-Trigger, ESP → Dimmer |
| `GPIO27` | `Z-C` | 4 | Nulldurchgang, Dimmer → ESP |
| `GPIO26` | `Z-C` | 5 | Messabgriff, dieselbe Klemme |

Zusätzlich: **10 kΩ von der `PSM`-Ader nach `GND`**, direkt am ESP32.

Warum die Pins: `GPIO25`/`GPIO27` sind keine Strapping-Pins und keine Flash-Pins; `GPIO21`/`GPIO22` bleiben für I2C (DHT20/SGP40), `GPIO32/33/34/35/36/39` (ADC1) für spätere Sensoren.

**Warum die fünfte Ader:** der ZC-Ausgang ist open collector (Emitter auf Board-GND, Kollektor auf `Z-C`), es gibt keinen Pull-up auf der Platine — deshalb `INPUT_PULLUP` in der Konfiguration. Auf einem Pin kann nur ein ISRHandler sitzen, deshalb bekommt die Messung eine eigene Ader auf `GPIO26`. Ohne diese Ader bleibt `ZC Flankenrate` bei 0, alles andere funktioniert.

Signalform: PC817 hat eine LED, leitet also eine Halbwelle lang → der Ausgang ist ein **50-Hz-Rechteck**, dessen beide Flanken im Nulldurchgang liegen. `ac_dimmer` läuft deshalb mit `zero_cross_interrupt_type: ANY` (100 Interrupts/s). Mit `RISING` oder `FALLING` kämen nur 50 Ereignisse/s an, das Bauteil hielte 20 ms für die Halbwelle und würde nur eine Halbwelle ansteuern.

Nahtstellen nicht nach Zählung, sondern nach Aufdruck verbinden — Clone beschriften `VCC`/`3V3`, `PSM`/`PWM`/`DIM`, `ZC`/`ZERO-C`.

## 2. Netzseite

| Klemme | Adern |
|---|---|
| `IN` | Netz L, über Feinsicherung **T1A** |
| `N` | Netz N **und** Lüfter N (zwei Adern in eine Klemme) |
| `OUT` | Lüfter L |

- **Snubber**: 100 nF/600 V AC + 100 Ω (dein `MCR-P`-Kombibauteil) über `IN` und `OUT` — das sind die beiden Triac-Anschlüsse. Zwischen `IN` und `OUT` waren nur pF zu messen, auf der Platine sitzt also keiner. Kurze Adern, Schrumpfschlauch.
- **PE** des Lüfters direkt auf Netz-PE, nie über das Modul.
- Der `503K`-Filmkondensator auf der Platine liegt zwischen `IN` und `N` (Eingangsfilter), nicht über dem Triac.
- Gehäuse, Berührschutz, RCD 30 mA. Triac, Kühlkörper und Platinenrückseite sind spannungsführend, auch wenn der Lüfter steht.

Isolationstest vor dem ersten Einschalten (Modul stromlos, Lüfter ab): `IN`→`GND` und `N`→`GND` müssen offen sein. Ein Durchgang heißt, die ESP32-Masse liegt am Netz.

## 3. Konfiguration und Build

`secrets.yaml` ergänzen (Vorlage liegt bei): `wifi_ssid`, `wifi_password` — `api_key` ist bereits erzeugt.

Die ESPHome-Version steckt nicht in der YAML, sondern im uv-Projekt (`pyproject.toml`, festgeschrieben in `uv.lock`):

```powershell
uv sync                       # einmalig, legt .venv/ an
.\build.ps1 config ac-dimmer-test.yaml
.\build.ps1 run ac-dimmer-test.yaml     # erster Flash über USB
.\build.ps1 logs ac-dimmer-test.yaml    # Log über WLAN
```

`build.ps1` setzt drei Dinge nur für diesen Aufruf: `ESPHOME_ESP_IDF_PREFIX` auf `.esphome\idf` (Framework und Toolchain bleiben im Projekt, 2,5 GB, gitignored), `ESPHOME_IDF_DEFAULT_TARGETS=esp32` (sonst zieht ESPHome den 706-MB-RISC-V-Compiler mit, den ein ESP32 nie braucht) und löscht `MSYSTEM`.

**Aus PowerShell oder cmd, nicht aus Git Bash.** Git Bash setzt `MSYSTEM=MINGW64`, ESP-IDFs Installationsskript bricht darauf mit `MSys/Mingw is not supported` ab.

Der erste Build lädt das ESP-IDF-Framework von GitHub. Auf diesem Anschluss ist `github.com` nicht erreichbar (die IP-Range, die der DNS liefert, wird verworfen); dann `esp32: framework: source:` auf einen lokalen Mirror zeigen lassen — nach dem ersten Build liegt das Framework in `.esphome\idf` und der Override kann weg.

Web-Oberfläche: `http://ac-dimmer-test.local` (Fallback-AP `ac-dimmer-test fallback`, IP 192.168.4.1).

Bedienelemente — zwei davon sind unabhängig voneinander:

| Entity | Rolle | Wirkung |
|---|---|---|
| `Leistung` (0–100 %) | **wie viel** | Sollwert; wird nur angelegt, wenn `Dimmer ein` an ist. 0 = aus |
| `Dimmer ein` | **ob** | legt den gespeicherten Sollwert auf den Triac oder auf 0. Startet nach jedem Reboot aus |
| `Lüftermodus (min 40 %)` | **Grenze** | kappt jeden Sollwert zwischen 1 % und 39 % auf 40 %. 0 bleibt 0 |

`Leistung` sagt *wie viel*, `Dimmer ein` sagt *ob*. Getrennt, damit du einen Wert vorwählen kannst, ohne dass der Triac zündet, und damit nach einem Reboot nichts von selbst anläuft.

`Lüftermodus` ist **kein Betriebsmodus**, sondern ein Schutz für den R2E190: unterhalb von etwa 40 % hat der Motor zu wenig Drehmoment, läuft unsicher an und erwärmt sich durch die Oberwellen stärker. Für die Glühlampe bleibt er aus (voller Bereich 0–100 % zugänglich), für den Lüftertest wird er eingeschaltet.

Beispiel: `Lüftermodus` an, `Dimmer ein` an, `Leistung` auf 20 → das Feld springt auf 40, am Triac liegen 40 % an, im Log steht `level=40%`. Sollwert und angelegter Wert sind immer identisch.

Ist `Dimmer ein` aus, merkt sich `Leistung` den Wert nur vor und loggt `Sollwert NN% vorgemerkt (Dimmer aus)`.

## 4. Was im Log steht

Alle 5 s eine Zeile:

```
[dimmer-test] ein=1 level=40% zc=50.0Hz delay=5.64ms leitwinkel=79deg uptime=124s rssi=-58dBm
```

| Feld | Bedeutung |
|---|---|
| `zc` | gemessene Flankenrate am ZC-Ausgang. **~50 Hz** = Rechteck, eine Flanke pro Netzperiode (richtig). ~100 Hz = schmale Vollwellenpulse. **0 Hz** = kein ZC-Signal |
| `delay` | Zündverzögerung nach dem Nulldurchgang, aus dem Sollwert nachgerechnet (acos-Kennlinie wie im Bauteil) |
| `leitwinkel` | Durchlasswinkel in Grad, gleiche Rechnung |
| `uptime`, `rssi` | Laufzeit und WLAN-Pegel für den Langzeittest |

Zusätzlich beim Boot (Log-Level VERBOSE): `AcDimmer: ... Estimated Frequency: 50.000Hz`. 25 Hz = es kommen nur 50 Interrupts/s an, dann stimmt der Interrupt-Typ nicht.

`delay` und `leitwinkel` sind gerechnet, nicht gemessen — es gibt keine Strommessung auf dem Board. Sie dienen dem Vergleich „verhält sich die Lampe wie die Zahl sagt".

## 5. Phase 1 — Glühlampe

1. Flashen, WLAN prüfen, Log öffnen. `zc` muss ~50 Hz zeigen. Zeigt es 0: Ader auf `GPIO26`/`Z-C` und Pull-up prüfen.
2. `Dimmer ein` einschalten, dann 10 / 25 / 50 / 75 / 100 % durchfahren.
3. Erwartung: 100 % = volle Helligkeit ohne Flackern; die Helligkeit steigt monoton; bei 50 % etwa halbe Leistung.
4. **Fehlerbild 50-Hz-Flackern, max. ~50 % Helligkeit** → es wird nur eine Halbwelle angesteuert; dann `zero_cross_interrupt_type` auf `RISING` bzw. `FALLING` umstellen und erneut prüfen.
5. Kleinsten Wert notieren, bei dem die Lampe eben zündet (typisch 3–8 %). Das ist die untere Grenze des Triacs, nicht des Lüfters.

Erst wenn 4 sauber durchläuft, geht es weiter.

## 6. Phase 2 — Lüfter

1. Netz trennen, Lampe ab, Lüfter nach Abschnitt 2 anklemmen, PE nicht vergessen.
2. `Lüftermodus (min 40 %)` einschalten.
3. **Min-Test**: 40 % → 45 % → 50 % … und notieren, ab welchem Wert der Motor sicher anläuft und durchläuft. Bleibt er stehen oder brummt er: Wert anheben.
4. **Max-Test**: 100 %. Der Triac ist dann dauerhaft leitend (kein Phasenanschnitt).
5. **Langzeittest**: 60 min bei mittlerer Stufe. Beobachten:
   - `zc` konstant ~50 Hz (Einbrüche oder Springen = Fehlzündungen durch die Motorinduktivität)
   - `rssi` stabil, `uptime` monoton
   - Motorgehäuse handwarm; heiß oder Thermokontakt (TOP) löst aus → Min-Wert anheben
   - Snubber nach 30 min anfassen (1/2-W-Widerstand läuft an der Grenze)
6. Abbruchkriterien: unregelmäßige Drehzahl, Brummen, Geruch, `zc` schwankt → Netz trennen.

## 7. Was die Konfiguration nicht kann

- Keine Strom-/Leistungsmessung: „Leistung 40 %" ist ein Sollwert, keine gemessene Wattzahl.
- Kein Min-/Max-Automatiktest; die Stufen werden von Hand durchgefahren.
- Phasenanschnitt bleibt für den R2E190 die unsaubere Lösung (Oberwellen, Zusatzwärme im Motor). Der Test liefert die Zahlen, ab denen er stabil läuft — mehr nicht.
