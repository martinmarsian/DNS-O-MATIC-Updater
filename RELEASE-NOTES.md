# DNS-O-MATIC Updater — Release Notes

## Version 1.0.1 (Build 2)

### Fehlerbehebungen und Verbesserungen

- **LaunchDaemon-Status synchronisiert**: Letztes Update, IP und Ergebnis werden nun auch dann korrekt angezeigt, wenn der LaunchDaemon das Update durchgeführt hat (nicht nur bei manuellem Update). Der Daemon schreibt seinen Status in `/Library/Application Support/DNS-O-MATIC Updater/state.plist`, die Pane liest beim Öffnen den neuesten Wert.
- **Pane aktualisiert sich bei jedem Öffnen**: IP-Adresse, Host-Auflösungen und OpenDNS-Status werden jetzt bei jedem Öffnen der Pane automatisch neu abgerufen — nicht nur beim ersten Laden.
- **Optische Verbesserungen**: Abstände aller Bereiche zur rechten Fensterkante vereinheitlicht; Icon mit korrektem Innenabstand für konsistente Darstellung in den Systemeinstellungen.
- **Farbige Statusanzeige in der Hosts-Tabelle**: IP- und Statusspalte werden nun farbig hervorgehoben (grün = aktuell, orange = veraltet, rot = nicht erreichbar).
- **Notarisierung**: Release-Skript robuster gegen Fehlerausgabe von `notarytool`; Stapling des Notarisierungstickets vor ZIP-Erstellung.

---

## Version 1.0

Erste öffentliche Version des DNS-O-MATIC Updater als macOS System Preferences Preference Pane.

---

### Funktionen

#### DNS-O-MATIC Account
- Eingabe von Benutzername und Passwort für den DNS-O-MATIC-Dienst
- Sichere Speicherung der Zugangsdaten im macOS Keychain (Server: `updates.dnsomatic.com`)
- Visuelle Bestätigung nach erfolgreichem Speichern

#### Status
- Automatische Erkennung der aktuellen öffentlichen IP-Adresse über `api.ipify.org`
- Anzeige von Datum und Uhrzeit des letzten DNS-Updates
- Anzeige des Ergebnisses der letzten DNS-O-MATIC-Anfrage
- **OpenDNS-Status**: Prüft beim Öffnen der Pane automatisch, ob OpenDNS als lokaler DNS-Resolver aktiv ist (`welcome.opendns.com`), mit farbiger Rückmeldung (grün = aktiv, rot = nicht aktiv)
- Schaltfläche „Jetzt aktualisieren" für manuellen DNS-Update

#### Hosts
- Manuelle Eingabe beliebig vieler Hostnamen (kommagetrennt), z. B. `host1.duckdns.org, host2.duckdns.org`
- Externe DNS-Auflösung über Google DNS-over-HTTPS (`dns.google`) — umgeht NAT-Loopback und den lokalen DNS-Resolver
- Tabellenansicht mit Hostname, aufgelöster IP und Status:
  - **✓ aktuell** (grün) — aufgelöste IP stimmt mit aktueller öffentlicher IP überein
  - **⚠ veraltet** (orange) — IP weicht ab, DNS-Update empfohlen
  - **Nicht erreichbar** (rot) — Hostname konnte nicht aufgelöst werden
- Hostnamen werden beim Öffnen der Pane automatisch aufgelöst

#### Automatische Updates
- **LaunchAgent** (kein Admin erforderlich): Startet den DNS-Updater nach Benutzer-Login automatisch im Hintergrund. Liest das Passwort sicher aus dem Benutzer-Keychain.
- **LaunchDaemon** (Admin erforderlich): Startet den DNS-Updater beim Systemstart, unabhängig vom angemeldeten Benutzer. Zugangsdaten werden in einer root-geschützten Konfigurationsdatei gespeichert.
- Konfigurierbares Update-Intervall: 5 Minuten, 10 Minuten, 30 Minuten, 1 Stunde oder 6 Stunden

---

### Systemvoraussetzungen

- macOS 13.5 (Ventura) oder neuer
- Universal Binary (Apple Silicon und Intel)

---

### Hinweise

- DNS-O-MATIC aktualisiert alle konfigurierten Dienste gleichzeitig (`all.dnsomatic.com`)
- Die Hostnamen im Bereich „Hosts" dienen ausschließlich der Überwachung — sie werden auf der DNS-O-MATIC-Website konfiguriert
- Log-Dateien des Hintergrunddienstes:
  - LaunchAgent: `~/Library/Logs/dns-o-matic-updater.log`
  - LaunchDaemon: `/Library/Logs/dns-o-matic-updater.log`
