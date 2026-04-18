# DNS-O-MATIC Updater

A macOS System Settings Preference Pane that keeps your [DNS-O-MATIC](https://www.dnsomatic.com) records up to date automatically — with LaunchAgent and LaunchDaemon support, host monitoring, and OpenDNS status detection.

> **[English](#english) · [Deutsch](#deutsch)**

---

## English

### What is DNS-O-MATIC?

[DNS-O-MATIC](https://www.dnsomatic.com) is a free service by OpenDNS that lets you update multiple dynamic DNS providers simultaneously whenever your public IP address changes. DNS-O-MATIC Updater automates this process on macOS.

### Requirements

- macOS 13.5 (Ventura) or later
- Universal Binary — runs natively on Apple Silicon and Intel

### Installation

1. Download the latest release from the [Releases](https://github.com/martinmarsian/DNS-O-MATIC-Updater/releases) page.
2. Unzip the downloaded archive.
3. Double-click `DNS-O-MATIC Updater.prefPane`.
4. macOS will ask whether to install for the current user or all users — choose as appropriate.
5. The pane opens automatically in System Settings under the third-party section.

### Features

#### Account
- Enter your DNS-O-MATIC username and password.
- Credentials are stored securely in the macOS Keychain (server: `updates.dnsomatic.com`).
- A green confirmation message appears after saving.

#### Status
- **Public IP**: Detects your current public IP address via `api.ipify.org`.
- **Last update**: Shows the date and time of the most recent DNS update (manual or automatic).
- **Last result**: Shows the response returned by DNS-O-MATIC.
- **OpenDNS status**: Checks whether OpenDNS is active as your DNS resolver (green = active, red = not active).
- **Update Now** button for triggering a manual update at any time.

#### Hosts
Enter one or more hostnames (comma-separated) to monitor — for example:

```
host1.duckdns.org, host2.duckdns.org
```

The table shows three columns:

| Column | Meaning |
|--------|---------|
| Hostname | The DNS hostname configured in DNS-O-MATIC |
| IP | The IP currently in DNS for that hostname |
| Status | ✓ current (green) · ⚠ outdated (orange) · unreachable (red) |

Hostnames are resolved using Google DNS-over-HTTPS (`dns.google`) — this bypasses NAT-loopback issues and works even when the local DNS resolver returns stale results.

> **Note**: The hostnames here are for monitoring only. They are configured on the DNS-O-MATIC website, not in this pane.

#### Automatic Updates

| Mode | Privileges | Trigger |
|------|-----------|---------|
| **LaunchAgent** | No admin required | Runs after user login |
| **LaunchDaemon** | Admin required | Runs at system boot, independent of logged-in user |

**Update intervals**: 5 minutes · 10 minutes · 30 minutes · 1 hour · 6 hours

Click **Install** to activate the chosen mode. The LaunchDaemon installation prompts for your administrator password via a system dialog.

To switch modes, uninstall the current one first, then install the other.

### Log Files

| Source | Log location |
|--------|-------------|
| LaunchAgent | `~/Library/Logs/dns-o-matic-updater.log` |
| LaunchDaemon | `/Library/Logs/dns-o-matic-updater.log` |

You can open these files with Console.app or any text editor.

### Notes

- DNS-O-MATIC updates all configured services at once via `all.dnsomatic.com`.
- The date and time format follows your macOS Region setting (System Settings → General → Language & Region).
- If you want to add a language other than English or German, add a `xx.lproj/Localizable.strings` file to the project.

### License

MIT — see [LICENSE](LICENSE) for details.

---

## Deutsch

### Was ist DNS-O-MATIC?

[DNS-O-MATIC](https://www.dnsomatic.com) ist ein kostenloser Dienst von OpenDNS, der es ermöglicht, mehrere Dynamic-DNS-Anbieter gleichzeitig zu aktualisieren, wenn sich die öffentliche IP-Adresse ändert. DNS-O-MATIC Updater automatisiert diesen Vorgang auf macOS.

### Systemvoraussetzungen

- macOS 13.5 (Ventura) oder neuer
- Universal Binary — läuft nativ auf Apple Silicon und Intel

### Installation

1. Lade die neueste Version von der [Releases](https://github.com/martinmarsian/DNS-O-MATIC-Updater/releases)-Seite herunter.
2. Entpacke das heruntergeladene Archiv.
3. Doppelklicke auf `DNS-O-MATIC Updater.prefPane`.
4. macOS fragt, ob die Installation für den aktuellen Benutzer oder alle Benutzer gelten soll — wähle entsprechend.
5. Die Preference Pane öffnet sich automatisch in den Systemeinstellungen im Bereich der Drittanbieter.

### Funktionen

#### Account
- Gib deinen DNS-O-MATIC-Benutzernamen und dein Passwort ein.
- Die Zugangsdaten werden sicher im macOS Keychain gespeichert (Server: `updates.dnsomatic.com`).
- Nach dem Speichern erscheint eine grüne Bestätigungsmeldung.

#### Status
- **Öffentliche IP**: Erkennt deine aktuelle öffentliche IP-Adresse über `api.ipify.org`.
- **Letztes Update**: Zeigt Datum und Uhrzeit des zuletzt durchgeführten DNS-Updates (manuell oder automatisch).
- **Letztes Ergebnis**: Zeigt die Antwort von DNS-O-MATIC.
- **OpenDNS-Status**: Prüft, ob OpenDNS als DNS-Resolver aktiv ist (grün = aktiv, rot = nicht aktiv).
- Schaltfläche **Jetzt aktualisieren** für einen manuellen Update-Aufruf.

#### Hosts
Gib einen oder mehrere Hostnamen (kommagetrennt) zur Überwachung ein — z. B.:

```
host1.duckdns.org, host2.duckdns.org
```

Die Tabelle zeigt drei Spalten:

| Spalte | Bedeutung |
|--------|----------|
| Hostname | Der bei DNS-O-MATIC konfigurierte DNS-Name |
| IP | Die aktuell im DNS eingetragene IP des Hostnamens |
| Status | ✓ aktuell (grün) · ⚠ veraltet (orange) · nicht erreichbar (rot) |

Hostnamen werden über Google DNS-over-HTTPS (`dns.google`) aufgelöst — das umgeht NAT-Loopback-Probleme und funktioniert auch dann, wenn der lokale DNS-Resolver veraltete Werte zurückliefert.

> **Hinweis**: Die Hostnamen dienen ausschließlich der Überwachung. Sie werden auf der DNS-O-MATIC-Website konfiguriert, nicht in dieser Pane.

#### Automatische Updates

| Modus | Rechte | Auslöser |
|-------|--------|---------|
| **LaunchAgent** | Kein Admin erforderlich | Startet nach Benutzer-Login |
| **LaunchDaemon** | Admin erforderlich | Startet beim Systemstart, unabhängig vom angemeldeten Benutzer |

**Update-Intervalle**: 5 Minuten · 10 Minuten · 30 Minuten · 1 Stunde · 6 Stunden

Klicke auf **Installieren**, um den gewählten Modus zu aktivieren. Die Installation des LaunchDaemons fordert per Systemdialog das Administratorpasswort an.

Um den Modus zu wechseln, deinstalliere zunächst den aktiven Modus und installiere dann den anderen.

### Log-Dateien

| Quelle | Speicherort |
|--------|------------|
| LaunchAgent | `~/Library/Logs/dns-o-matic-updater.log` |
| LaunchDaemon | `/Library/Logs/dns-o-matic-updater.log` |

Diese Dateien können mit der Console.app oder einem Texteditor geöffnet werden.

### Hinweise

- DNS-O-MATIC aktualisiert alle konfigurierten Dienste gleichzeitig über `all.dnsomatic.com`.
- Das Datums- und Uhrzeitformat richtet sich nach der in macOS eingestellten Region (Systemeinstellungen → Allgemein → Sprache & Region).
- Weitere Sprachen können durch Hinzufügen einer `xx.lproj/Localizable.strings`-Datei zum Projekt ergänzt werden.

### Lizenz

MIT — siehe [LICENSE](LICENSE) für Details.
