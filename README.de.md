<p align="center">
  <img src="docs/images/icon.png" width="160" height="160" alt="SnakeStick-App-Icon: eine Schlangenfrau, die einen roten Apfel hinhält">
</p>

<h1 align="center">SnakeStick</h1>

<p align="center">
  <b>Erstelle auf deinem Mac einen startfähigen USB-Stick zur Installation von Windows 10 / 11.</b><br>
  ISO auswählen, Stick auswählen, Start drücken. Kein Terminal, kein Boot Camp, kein Aufteilen von <code>install.wim</code>.
</p>

<p align="center">
  <a href="https://github.com/team-unstablers/SnakeStick/releases/latest"><img alt="Neueste Version herunterladen" src="https://img.shields.io/badge/Download-Latest%20release-B3122E?style=for-the-badge&logo=github&logoColor=white"></a>
  <img alt="macOS 26.6 oder neuer" src="https://img.shields.io/badge/macOS-26.6%2B-0E0B10?style=for-the-badge&logo=apple&logoColor=white">
  <img alt="Windows 10 und 11" src="https://img.shields.io/badge/Windows-10%20%7C%2011-0E0B10?style=for-the-badge">
  <a href="COPYING"><img alt="Lizenz: GPL-3.0" src="https://img.shields.io/badge/License-GPL--3.0-0E0B10?style=for-the-badge"></a>
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.ko.md">한국어</a> · <a href="README.ja.md">日本語</a> · <a href="README.zh-Hans.md">简体中文</a> · <a href="README.zh-Hant.md">繁體中文</a> · <b>Deutsch</b> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a>
</p>

<p align="center">
  <img src="docs/images/screenshot.png" width="592" alt="SnakeStick kopiert eine Windows-11-ISO auf einen USB-Stick, Schritt 6 von 8">
</p>

---

## ✨ Warum SnakeStick

- 🪟 **Nur die App.** Wähle eine ISO von Windows 10 oder 11 aus (oder zieh sie auf das Fenster), wähle einen USB-Stick
  aus und klicke auf **Schreiben starten**.
- 📦 **Große Installationsdateien sind kein Problem.** Aktuelle Windows-ISOs enthalten eine `install.wim`, die größer als
  4 GB ist – zu groß für einen FAT32-Stick. SnakeStick legt Windows auf eine NTFS-Partition und fügt eine kleine
  Boot-Partition mit dem [UEFI:NTFS](https://github.com/pbatard/uefi-ntfs)-Loader hinzu – dasselbe Layout, das auch
  [Rufus](https://rufus.ie) verwendet. Nichts wird aufgeteilt.
- 🔐 **Funktioniert mit Secure Boot.** Der mitgelieferte Bootloader ist von Microsoft signiert. Für PCs, die das
  Microsoft-Zertifikat von 2011 widerrufen haben, kann SnakeStick die mit Windows UEFI CA 2023 signierten Bootloader aus
  ISOs von Windows 11 25H2 oder neuer verwenden.
- ✅ **Prüft die eigene Arbeit.** Nach dem Schreiben liest SnakeStick den gesamten Stick zurück und vergleicht ihn Datei
  für Datei mit der ISO.
- 🛡️ **Hält sich von den Laufwerken deines Macs fern.** Nur externe Laufwerke und Wechselmedien werden aufgelistet.
  Interne Laufwerke und das Startvolume tauchen nie auf, das Ziel wird direkt vor dem Schreiben noch einmal geprüft, und
  gelöscht wird erst, wenn du es bestätigst.
- 🧹 **Keine Mac-Überbleibsel.** Die Windows-Partition wird beschrieben, ohne je gemountet zu werden. Deshalb landen keine
  `.DS_Store`-, `._`- oder `.fseventsd`-Dateien auf dem Stick.
- 🍎 **Eine native Mac-App.** In Swift und SwiftUI geschrieben und auf Englisch, Koreanisch, Japanisch, Chinesisch
  (vereinfacht und traditionell), Deutsch, Französisch, Spanisch, Portugiesisch (Brasilien) und Russisch verfügbar.
  Kostenlos und Open Source unter der GPLv3.

## 📥 Download

Lade die neueste Version im Tab **[Releases](https://github.com/team-unstablers/SnakeStick/releases/latest)** herunter
und bewege **SnakeStick** dann in deinen Ordner **Programme**. Die App ist signiert und von Apple notariell beglaubigt.

## 🧰 Was du brauchst

| | |
|---|---|
| **Mac** | macOS Tahoe 26.6 oder neuer und ein Administratorpasswort |
| **Windows-ISO** | Eine Installations-ISO von Windows 10 oder 11, zum Beispiel von Microsofts Downloadseite für [Windows 11](https://www.microsoft.com/de-de/software-download/windows11) oder [Windows 10](https://www.microsoft.com/de-de/software-download/windows10) |
| **USB-Stick** | Groß genug für die ISO; zu kleine Sticks sind ausgegraut. Für aktuelle Windows-11-ISOs sind 16 GB eine sichere Größe. |
| **Ziel-PC** | Ein PC, der im UEFI-Modus startet. Das Starten über Legacy-BIOS (CSM) wird nicht unterstützt. |

> [!CAUTION]
> Beim Schreiben wird **alles gelöscht**, was sich auf dem ausgewählten USB-Stick befindet. Sichere vorher alles, was du
> behalten möchtest.

## 🔑 Erster Start: zwei einmalige Berechtigungen

SnakeStick beschreibt den Stick über ein kleines Hilfsprogramm, das mit Administratorrechten im Hintergrund läuft, damit
die App selbst nie als root laufen muss. macOS bittet dich einmalig, dieses Hilfsprogramm zu genehmigen:

1. **Erlaube das Hilfsprogramm.** Wenn du zum ersten Mal auf **Schreiben starten** klickst, bittet dich macOS, das
   Hilfsprogramm von SnakeStick zu erlauben. Aktiviere **SnakeStick** unter **Systemeinstellungen › Allgemein ›
   Anmeldeobjekte & Erweiterungen** und versuche es dann erneut.
2. **Erteile den Festplattenvollzugriff.** Solange die App keinen Festplattenvollzugriff hat, sperrt macOS Hilfsprogramme
   im Hintergrund von Wechselmedien und von Ordnern wie **Downloads** aus. Füge **SnakeStick** unter
   **Systemeinstellungen › Datenschutz & Sicherheit › Festplattenvollzugriff** hinzu. SnakeStick weist dich darauf hin,
   wenn der Zugriff fehlt, und bietet eine Taste, die die richtige Seite öffnet.

Danach fragt SnakeStick bei jedem Schreibvorgang einmal nach deinem Administratorpasswort.

## 🚀 Einen Stick erstellen

1. **Wähle die ISO aus.** Klicke unter **Quell-ISO** auf **Auswählen …** oder zieh die ISO auf das Fenster. SnakeStick
   zeigt die Windows-Version, die Architektur und die Größe an.
2. **Wähle den Stick aus.** Schließe ihn an und wähle ihn unter **Ziellaufwerk** aus.
3. **Prüfe die Optionen.**
   - **Volumename**: der Name des Sticks. Standardmäßig wird der Name der ISO übernommen.
   - **Nach dem Schreiben überprüfen**: standardmäßig aktiviert. Das dauert ein paar Minuten länger, lohnt sich aber.
   - **Mit Windows UEFI CA 2023 signierte Bootloader verwenden**: nur für PCs nötig, die das Secure-Boot-Zertifikat von
     Microsoft aus dem Jahr 2011 widerrufen haben, und nur mit ISOs von Windows 11 25H2 oder neuer verfügbar. Wenn du
     unsicher bist, lass die Option deaktiviert.
4. Klicke auf **Schreiben starten**, bestätige mit **Löschen und schreiben** und gib dein Administratorpasswort ein.
5. **Warte.** Der Fortschrittsbalken zeigt den aktuellen Schritt (insgesamt 8) und die verbleibende Zeit. Auf dem
   USB-3-Stick, mit dem wir getestet haben, dauerte eine 8,7 GB große Windows-11-ISO einschließlich Überprüfung etwa
   16 Minuten.
6. Klicke auf **Auswerfen**, sobald SnakeStick meldet, dass der Vorgang abgeschlossen ist.

Mit **Stoppen** kannst du jederzeit abbrechen. Der Stick ist danach nicht startfähig, und ein erneuter Schreibvorgang
beginnt wieder ganz von vorn.

## 💻 Den PC vom Stick starten

1. Schließe den Stick an den PC an und schalte den PC ein, während du die Taste für das Bootmenü drückst. Meist ist das
   **F12**, **F11**, **F8** oder **Esc**; sieh im Handbuch deines PCs nach.
2. Wähle den **UEFI**-Eintrag für den USB-Stick aus.
3. Das Windows-Setup startet.

Falls der PC bei aktiviertem Secure Boot nicht vom Stick starten will, suche in seinen Firmware-Einstellungen nach einer
Option wie **„Allow Microsoft 3rd Party UEFI CA“** und aktiviere sie. Manche PCs, insbesondere Secured-core PCs, werden
mit deaktivierter Option ausgeliefert, und der UEFI:NTFS-Bootloader benötigt sie. Du kannst Secure Boot auch für die
Dauer der Installation deaktivieren; schalte es danach wieder ein.

## ❓ Häufige Fragen

<details>
<summary><b>Warum braucht SnakeStick Festplattenvollzugriff?</b></summary>
<br>

Der Teil von SnakeStick, der den Stick beschreibt, ist ein Hilfsprogramm im Hintergrund (ein launchd-Daemon). macOS
erlaubt solchen Hilfsprogrammen nicht, Wechselmedien zu öffnen oder eine ISO in Ordnern wie „Downloads“ zu lesen,
solange die App, zu der sie gehören, keinen Festplattenvollzugriff hat – und eine engere Berechtigung, die ein
Hilfsprogramm anfordern könnte, gibt es nicht. Du erteilst den Zugriff der SnakeStick-App, und er gilt damit auch für das
Hilfsprogramm in der App.

</details>

<details>
<summary><b>Warum den Stick nicht einfach als FAT32 formatieren, wie es der Boot Camp-Assistent getan hat?</b></summary>
<br>

FAT32 kann keine Dateien mit 4 GB oder mehr speichern, und `sources/install.wim` ist in aktuellen Windows-ISOs meist
größer. Üblicherweise wird die Datei deshalb aufgeteilt. SnakeStick lässt sie stattdessen in einem Stück auf einer
NTFS-Partition, und eine winzige FAT-Partition daneben enthält den UEFI:NTFS-Loader, der der Firmware des PCs beibringt,
NTFS zu lesen.

</details>

<details>
<summary><b>Kann SnakeStick die TPM- oder Secure-Boot-Anforderungen von Windows 11 umgehen?</b></summary>
<br>

Nein. SnakeStick kopiert die ISO unverändert. Es umgeht keine Hardwareanforderungen, fügt keine Antwortdateien für
unbeaufsichtigte Installationen hinzu und bindet keine Treiber ein.

</details>

<details>
<summary><b>Was passiert, wenn ich den Stick abziehe oder mittendrin stoppe?</b></summary>
<br>

SnakeStick räumt hinter sich auf, und der Stick ist danach nicht startfähig. Beschreibe ihn erneut, dann ist alles
wieder in Ordnung. Die Laufwerke deines Macs werden nie angetastet.

</details>

<details>
<summary><b>Kann ich statt eines Sticks ein Disk-Image erstellen?</b></summary>
<br>

Nicht mit der App. SnakeStick schreibt nur auf USB-Sticks.

</details>

> [!NOTE]
> SnakeStick ist noch jung. Damit erstellte Sticks haben auf einem x64-PC mit aktiviertem Secure Boot erfolgreich das
> Windows-Setup gestartet, eine vollständige Windows-Installation von einem solchen Stick wurde aber noch nicht getestet.
> Wenn etwas schiefgeht, [eröffne bitte ein Issue](https://github.com/team-unstablers/SnakeStick/issues) und hänge das
> Protokoll an (**Protokoll anzeigen …** in der App).

## 🙏 Aufgebaut auf

SnakeStick gäbe es ohne diese freie Software nicht. Vielen Dank!

- [ntfs-3g](https://github.com/tuxera/ntfs-3g): erstellt und beschreibt die NTFS-Partition
- [UEFI:NTFS](https://github.com/pbatard/uefi-ntfs): der Bootloader, mit dem UEFI-Firmware Windows von NTFS starten kann
- [wimlib](https://github.com/ebiggers/wimlib): liest das Windows-Boot-Image
- [Rufus](https://github.com/pbatard/rufus): der Quellcode wurde als Referenz verwendet

SnakeStick wurde von einem LLM-basierten Coding-Agenten unter menschlicher Aufsicht geschrieben.

## 🐍 Über das Icon

Die Schlange aus dem Garten Eden, die deinem Mac einen Apfel hinhält. Der Apfel ist noch ganz: Niemand hat bisher
hineingebissen.

## 🛠️ Für Entwickler

Wie SnakeStick funktioniert, wie du es aus dem Quellcode baust und wie du die Tests ausführst: siehe
[docs/DESIGN.md](docs/DESIGN.md).

## 📄 Lizenz

SnakeStick ist freie Software unter der [GNU General Public License v3.0 oder neuer](COPYING). Es wird ohne jegliche
Gewährleistung bereitgestellt. Die mitgelieferten Komponenten behalten ihre eigenen Lizenzen; siehe
[docs/DESIGN.md](docs/DESIGN.md#license).
