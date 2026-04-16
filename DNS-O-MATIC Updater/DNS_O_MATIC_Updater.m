//
//  DNS_O_MATIC_Updater.m
//  DNS-O-MATIC Updater
//
//  Created by Jörg Märtin on 14.04.26.
//

#import "DNS_O_MATIC_Updater.h"
#import <Security/Security.h>

// ── Konstanten ────────────────────────────────────────────────────────────────

static NSString * const kKeychainServer     = @"updates.dnsomatic.com";
static NSString * const kDefaultsSuite      = @"com.jorgemartin.dns-o-matic-updater";
static NSString * const kPrefUsername       = @"username";
static NSString * const kPrefInterval       = @"updateInterval";
static NSString * const kPrefLastIP         = @"lastIP";
static NSString * const kPrefLastUpdate     = @"lastUpdateDate";
static NSString * const kPrefLastResult     = @"lastResult";
static NSString * const kPrefHosts          = @"hosts";
static NSString * const kLaunchAgentLabel   = @"com.jorgemartin.dns-o-matic-updater";
static NSString * const kLaunchDaemonLabel  = @"com.jorgemartin.dns-o-matic-updater-daemon";
static NSInteger  const kDefaultInterval    = 300; // 5 Minuten

// ── Update-Skripte ────────────────────────────────────────────────────────────

static NSString * const kAgentScript =
    @"#!/bin/bash\n"
    @"PREFS=\"$HOME/Library/Preferences/com.jorgemartin.dns-o-matic-updater.plist\"\n"
    @"USERNAME=$(defaults read \"$PREFS\" username 2>/dev/null)\n"
    @"[ -z \"$USERNAME\" ] && exit 1\n"
    @"PASSWORD=$(security find-internet-password -a \"$USERNAME\" -s \"updates.dnsomatic.com\" -w 2>/dev/null)\n"
    @"[ -z \"$PASSWORD\" ] && exit 1\n"
    @"IP=$(curl -sf --max-time 10 \"https://api.ipify.org\")\n"
    @"[ -z \"$IP\" ] && exit 1\n"
    @"RESULT=$(curl -sf --max-time 30 \\\n"
    @"  -u \"$USERNAME:$PASSWORD\" \\\n"
    @"  -A \"DNS-O-MATIC-Updater-macOS/1.0\" \\\n"
    @"  \"https://updates.dnsomatic.com/nic/update?hostname=all.dnsomatic.com&myip=$IP&wildcard=NOCHG&mx=NOCHG&backmx=NOCHG\")\n"
    @"NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)\n"
    @"printf '%s ip=%s result=%s\\n' \"$NOW\" \"$IP\" \"$RESULT\" >> \"$HOME/Library/Logs/dns-o-matic-updater.log\"\n"
    @"defaults write \"$PREFS\" lastIP \"$IP\"\n"
    @"defaults write \"$PREFS\" lastUpdateDate \"$NOW\"\n"
    @"defaults write \"$PREFS\" lastResult \"$RESULT\"\n";

static NSString * const kDaemonScript =
    @"#!/bin/bash\n"
    @"CONFIG=\"/Library/Application Support/DNS-O-MATIC Updater/config.plist\"\n"
    @"[ -f \"$CONFIG\" ] || exit 1\n"
    @"USERNAME=$(defaults read \"$CONFIG\" username 2>/dev/null)\n"
    @"PASSWORD=$(defaults read \"$CONFIG\" password 2>/dev/null)\n"
    @"[ -z \"$USERNAME\" ] || [ -z \"$PASSWORD\" ] && exit 1\n"
    @"IP=$(curl -sf --max-time 10 \"https://api.ipify.org\")\n"
    @"[ -z \"$IP\" ] && exit 1\n"
    @"RESULT=$(curl -sf --max-time 30 \\\n"
    @"  -u \"$USERNAME:$PASSWORD\" \\\n"
    @"  -A \"DNS-O-MATIC-Updater-macOS/1.0\" \\\n"
    @"  \"https://updates.dnsomatic.com/nic/update?hostname=all.dnsomatic.com&myip=$IP&wildcard=NOCHG&mx=NOCHG&backmx=NOCHG\")\n"
    @"NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)\n"
    @"printf '%s ip=%s result=%s\\n' \"$NOW\" \"$IP\" \"$RESULT\" >> \"/Library/Logs/dns-o-matic-updater.log\"\n"
    @"STATE=\"/Library/Application Support/DNS-O-MATIC Updater/state.plist\"\n"
    @"defaults write \"$STATE\" lastIP \"$IP\"\n"
    @"defaults write \"$STATE\" lastUpdateDate \"$NOW\"\n"
    @"defaults write \"$STATE\" lastResult \"$RESULT\"\n"
    @"chmod 644 \"$STATE\"\n";

// ── Private Schnittstelle ─────────────────────────────────────────────────────

@interface DNS_O_MATIC_Updater ()

// Credentials
@property (strong) NSTextField        *usernameField;
@property (strong) NSSecureTextField  *passwordField;
@property (strong) NSTextField        *credStatusLabel;

// Status
@property (strong) NSTextField        *currentIPField;
@property (strong) NSTextField        *lastUpdateField;
@property (strong) NSTextField        *statusField;
@property (strong) NSTextField        *openDNSStatusField;
@property (strong) NSProgressIndicator *spinner;

// Hosts
@property (strong) NSTextField        *hostsField;
@property (strong) NSTableView        *hostsTable;
@property (strong) NSMutableArray     *hostsData;

// Automatisierung
@property (strong) NSButton           *launchAgentCheck;
@property (strong) NSButton           *launchDaemonCheck;
@property (strong) NSPopUpButton      *intervalPopUp;

// Persistenz
@property (strong) NSUserDefaults     *defaults;

@end

// ── Implementierung ───────────────────────────────────────────────────────────

@implementation DNS_O_MATIC_Updater

- (NSUserDefaults *)defaults {
    if (!_defaults) {
        _defaults = [[NSUserDefaults alloc] initWithSuiteName:kDefaultsSuite];
    }
    return _defaults;
}

#pragma mark - Lifecycle

- (void)mainViewDidLoad {
    [self buildUI];
    [self loadSavedSettings];
    [self updateAutomationCheckboxes];
    [self refreshCurrentIP];
    [self checkOpenDNSStatus];
}

- (void)willSelect {
    // Wird bei jedem Öffnen der Pane aufgerufen (nicht nur beim ersten Laden)
    [self loadDaemonState];
    [self refreshCurrentIP];
    [self checkOpenDNSStatus];
}

#pragma mark - UI-Aufbau

- (void)buildUI {
    NSView *root = self.mainView;
    root.wantsLayer = YES;

    // ── Abschnitt: Account ──────────────────────────────────────────────────
    NSBox *credBox = [self makeSectionBox:@"DNS-O-MATIC Account"];

    NSTextField *userLabel = [self makeRightLabel:@"Benutzername:"];
    NSTextField *passLabel = [self makeRightLabel:@"Passwort:"];

    self.usernameField = [self makeTextField];
    self.usernameField.placeholderString = @"DNS-O-MATIC Benutzername";

    self.passwordField = [[NSSecureTextField alloc] init];
    self.passwordField.translatesAutoresizingMaskIntoConstraints = NO;
    self.passwordField.placeholderString = @"Passwort";

    NSButton *saveBtn = [NSButton buttonWithTitle:@"Speichern"
                                           target:self
                                           action:@selector(saveCredentials:)];
    saveBtn.translatesAutoresizingMaskIntoConstraints = NO;

    self.credStatusLabel = [NSTextField labelWithString:@""];
    self.credStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.credStatusLabel.textColor = [NSColor systemGreenColor];

    [credBox.contentView addSubview:userLabel];
    [credBox.contentView addSubview:self.usernameField];
    [credBox.contentView addSubview:passLabel];
    [credBox.contentView addSubview:self.passwordField];
    [credBox.contentView addSubview:saveBtn];
    [credBox.contentView addSubview:self.credStatusLabel];

    NSDictionary *cv1 = @{@"ul": userLabel,   @"uf": self.usernameField,
                          @"pl": passLabel,   @"pf": self.passwordField,
                          @"save": saveBtn,   @"csl": self.credStatusLabel};
    NSView *cb = credBox.contentView;
    [cb addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:
        @"H:|-(8)-[ul(110)]-[uf(360)]"
        options:NSLayoutFormatAlignAllCenterY metrics:nil views:cv1]];
    [cb addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:
        @"H:|-(8)-[pl(110)]-[pf(360)]"
        options:NSLayoutFormatAlignAllCenterY metrics:nil views:cv1]];
    [cb addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:
        @"V:|-(10)-[ul]-(8)-[pl]-(12)-[save]-(12)-|"
        options:0 metrics:nil views:cv1]];
    [cb addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:
        @"H:|-(8)-[save]-(10)-[csl]"
        options:NSLayoutFormatAlignAllCenterY metrics:nil views:cv1]];

    // ── Abschnitt: Status ───────────────────────────────────────────────────
    NSBox *statusBox = [self makeSectionBox:@"Status"];

    NSTextField *ipLbl     = [self makeRightLabel:@"Aktuelle IP:"];
    NSTextField *lastLbl   = [self makeRightLabel:@"Letztes Update:"];
    NSTextField *resultLbl = [self makeRightLabel:@"Ergebnis:"];
    NSTextField *odLbl     = [self makeRightLabel:@"OpenDNS:"];

    self.currentIPField  = [self makeValueLabel];
    self.lastUpdateField = [self makeValueLabel];
    self.statusField     = [self makeValueLabel];
    self.openDNSStatusField = [self makeValueLabel];

    self.spinner = [[NSProgressIndicator alloc] init];
    self.spinner.style = NSProgressIndicatorStyleSpinning;
    self.spinner.controlSize = NSControlSizeSmall;
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.hidden = YES;

    NSButton *updateNowBtn = [NSButton buttonWithTitle:@"Jetzt aktualisieren"
                                                target:self
                                                action:@selector(updateNow:)];
    updateNowBtn.translatesAutoresizingMaskIntoConstraints = NO;

    [statusBox.contentView addSubview:ipLbl];
    [statusBox.contentView addSubview:self.currentIPField];
    [statusBox.contentView addSubview:lastLbl];
    [statusBox.contentView addSubview:self.lastUpdateField];
    [statusBox.contentView addSubview:resultLbl];
    [statusBox.contentView addSubview:self.statusField];
    [statusBox.contentView addSubview:odLbl];
    [statusBox.contentView addSubview:self.openDNSStatusField];
    [statusBox.contentView addSubview:self.spinner];
    [statusBox.contentView addSubview:updateNowBtn];

    NSDictionary *cv2 = @{@"il": ipLbl,        @"iv": self.currentIPField,
                          @"ll": lastLbl,      @"lv": self.lastUpdateField,
                          @"rl": resultLbl,    @"rv": self.statusField,
                          @"odl": odLbl,       @"odv": self.openDNSStatusField,
                          @"sp": self.spinner, @"upd": updateNowBtn};
    NSView *sb = statusBox.contentView;
    [sb addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:
        @"H:|-(8)-[il(110)]-[iv]-(8)-|"
        options:NSLayoutFormatAlignAllCenterY metrics:nil views:cv2]];
    [sb addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:
        @"H:|-(8)-[ll(110)]-[lv]-(8)-|"
        options:NSLayoutFormatAlignAllCenterY metrics:nil views:cv2]];
    [sb addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:
        @"H:|-(8)-[rl(110)]-[rv]-(8)-|"
        options:NSLayoutFormatAlignAllCenterY metrics:nil views:cv2]];
    [sb addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:
        @"H:|-(8)-[odl(110)]-[odv]-(8)-|"
        options:NSLayoutFormatAlignAllCenterY metrics:nil views:cv2]];
    [sb addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:
        @"H:|-(8)-[sp]-(6)-[upd]"
        options:NSLayoutFormatAlignAllCenterY metrics:nil views:cv2]];
    [sb addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:
        @"V:|-(10)-[il]-(8)-[ll]-(8)-[rl]-(8)-[odl]-(12)-[sp]-(12)-|"
        options:0 metrics:nil views:cv2]];

    // ── Abschnitt: Hosts ────────────────────────────────────────────────────
    NSBox *hostsBox = [self makeSectionBox:@"Hosts"];

    NSTextField *hostsLbl = [self makeRightLabel:@"Hosts:"];

    self.hostsField = [self makeTextField];
    self.hostsField.placeholderString = @"z.B. host1.duckdns.org, host2.duckdns.org";

    NSButton *resolveBtn = [NSButton buttonWithTitle:@"Auflösen"
                                              target:self
                                              action:@selector(resolveHosts:)];
    resolveBtn.translatesAutoresizingMaskIntoConstraints = NO;

    self.hostsTable = [[NSTableView alloc] init];
    self.hostsTable.translatesAutoresizingMaskIntoConstraints = NO;
    self.hostsTable.allowsColumnReordering = NO;
    self.hostsTable.allowsColumnSelection = NO;
    self.hostsTable.usesAlternatingRowBackgroundColors = YES;
    self.hostsTable.rowHeight = 18;
    self.hostsTable.dataSource = self;
    self.hostsTable.delegate = self;

    NSTableColumn *colHost = [[NSTableColumn alloc] initWithIdentifier:@"hostname"];
    colHost.title = @"Hostname";
    colHost.width = 220;
    colHost.minWidth = 120;
    colHost.editable = NO;

    NSTableColumn *colIP = [[NSTableColumn alloc] initWithIdentifier:@"ip"];
    colIP.title = @"Aufgelöste IP (extern)";
    colIP.width = 150;
    colIP.minWidth = 80;
    colIP.editable = NO;

    NSTableColumn *colStatus = [[NSTableColumn alloc] initWithIdentifier:@"status"];
    colStatus.title = @"Status";
    colStatus.width = 100;
    colStatus.minWidth = 60;
    colStatus.editable = NO;

    [self.hostsTable addTableColumn:colHost];
    [self.hostsTable addTableColumn:colIP];
    [self.hostsTable addTableColumn:colStatus];

    NSScrollView *hostsScroll = [[NSScrollView alloc] init];
    hostsScroll.translatesAutoresizingMaskIntoConstraints = NO;
    hostsScroll.documentView = self.hostsTable;
    hostsScroll.hasVerticalScroller = YES;
    hostsScroll.borderType = NSBezelBorder;
    [self.hostsTable sizeLastColumnToFit];

    [hostsBox.contentView addSubview:hostsLbl];
    [hostsBox.contentView addSubview:self.hostsField];
    [hostsBox.contentView addSubview:resolveBtn];
    [hostsBox.contentView addSubview:hostsScroll];

    NSDictionary *cv4 = @{@"hl": hostsLbl, @"hf": self.hostsField,
                          @"rb": resolveBtn, @"sv": hostsScroll};
    NSView *hb = hostsBox.contentView;
    [hb addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:
        @"H:|-(8)-[hl(110)]-[hf]-(8)-[rb]-(8)-|"
        options:NSLayoutFormatAlignAllCenterY metrics:nil views:cv4]];
    [hb addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:
        @"H:|-(8)-[sv]-(8)-|" options:0 metrics:nil views:cv4]];
    [hb addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:
        @"V:|-(10)-[hl]-(8)-[sv(95)]-(10)-|" options:0 metrics:nil views:cv4]];

    // ── Abschnitt: Automatische Updates ────────────────────────────────────
    NSBox *autoBox = [self makeSectionBox:@"Automatische Updates"];

    NSTextField *intervalLbl = [self makeRightLabel:@"Intervall:"];

    self.intervalPopUp = [[NSPopUpButton alloc] init];
    self.intervalPopUp.translatesAutoresizingMaskIntoConstraints = NO;
    NSArray *titles    = @[@"Alle 5 Minuten", @"Alle 10 Minuten",
                           @"Alle 30 Minuten", @"Jede Stunde", @"Alle 6 Stunden"];
    NSArray *intervals = @[@300, @600, @1800, @3600, @21600];
    for (NSUInteger i = 0; i < titles.count; i++) {
        [self.intervalPopUp addItemWithTitle:titles[i]];
        self.intervalPopUp.menu.itemArray[i].representedObject = intervals[i];
    }
    [self.intervalPopUp setTarget:self];
    [self.intervalPopUp setAction:@selector(intervalChanged:)];

    self.launchAgentCheck = [NSButton
        checkboxWithTitle:@"Bei Benutzer-Login starten (LaunchAgent)"
                   target:self
                   action:@selector(toggleLaunchAgent:)];
    self.launchAgentCheck.translatesAutoresizingMaskIntoConstraints = NO;

    self.launchDaemonCheck = [NSButton
        checkboxWithTitle:@"Beim Systemstart starten (LaunchDaemon, erfordert Admin)"
                   target:self
                   action:@selector(toggleLaunchDaemon:)];
    self.launchDaemonCheck.translatesAutoresizingMaskIntoConstraints = NO;

    [autoBox.contentView addSubview:intervalLbl];
    [autoBox.contentView addSubview:self.intervalPopUp];
    [autoBox.contentView addSubview:self.launchAgentCheck];
    [autoBox.contentView addSubview:self.launchDaemonCheck];

    NSDictionary *cv3 = @{@"intL": intervalLbl, @"pop": self.intervalPopUp,
                          @"ach": self.launchAgentCheck,
                          @"dch": self.launchDaemonCheck};
    NSView *ab = autoBox.contentView;
    [ab addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:
        @"H:|-(8)-[intL(110)]-[pop(220)]"
        options:NSLayoutFormatAlignAllCenterY metrics:nil views:cv3]];
    [ab addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:
        @"H:|-(8)-[ach]-(8)-|" options:0 metrics:nil views:cv3]];
    [ab addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:
        @"H:|-(8)-[dch]-(8)-|" options:0 metrics:nil views:cv3]];
    [ab addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:
        @"V:|-(10)-[intL]-(12)-[ach]-(6)-[dch]-(12)-|"
        options:0 metrics:nil views:cv3]];

    // ── Root-Layout ─────────────────────────────────────────────────────────
    credBox.translatesAutoresizingMaskIntoConstraints = NO;
    statusBox.translatesAutoresizingMaskIntoConstraints = NO;
    hostsBox.translatesAutoresizingMaskIntoConstraints = NO;
    autoBox.translatesAutoresizingMaskIntoConstraints = NO;

    [root addSubview:credBox];
    [root addSubview:statusBox];
    [root addSubview:hostsBox];
    [root addSubview:autoBox];

    NSDictionary *rv = @{@"cred": credBox, @"stat": statusBox,
                         @"hosts": hostsBox, @"auto": autoBox};
    [root addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:
        @"H:|-(16)-[cred]-(96)-|" options:0 metrics:nil views:rv]];
    [root addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:
        @"H:|-(16)-[stat]-(96)-|" options:0 metrics:nil views:rv]];
    [root addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:
        @"H:|-(16)-[hosts]-(96)-|" options:0 metrics:nil views:rv]];
    [root addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:
        @"H:|-(16)-[auto]-(96)-|" options:0 metrics:nil views:rv]];
    [root addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:
        @"V:|-(12)-[cred]-[stat]-[hosts]-[auto]-(12)-|"
        options:0 metrics:nil views:rv]];
}

#pragma mark - UI-Hilfsmethoden

- (NSBox *)makeSectionBox:(NSString *)title {
    NSBox *box = [[NSBox alloc] init];
    box.title = title;
    box.titlePosition = NSAtTop;
    return box;
}

- (NSTextField *)makeRightLabel:(NSString *)text {
    NSTextField *f = [NSTextField labelWithString:text];
    f.translatesAutoresizingMaskIntoConstraints = NO;
    f.alignment = NSTextAlignmentRight;
    return f;
}

- (NSTextField *)makeTextField {
    NSTextField *f = [[NSTextField alloc] init];
    f.translatesAutoresizingMaskIntoConstraints = NO;
    return f;
}

- (NSTextField *)makeValueLabel {
    NSTextField *f = [NSTextField labelWithString:@"—"];
    f.translatesAutoresizingMaskIntoConstraints = NO;
    return f;
}

#pragma mark - NSTableViewDataSource / Delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)self.hostsData.count;
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)tableColumn
                          row:(NSInteger)row {
    if (row >= (NSInteger)self.hostsData.count) return @"";
    NSDictionary *entry = self.hostsData[(NSUInteger)row];
    return entry[tableColumn.identifier] ?: @"";
}

- (void)tableView:(NSTableView *)tableView
  willDisplayCell:(id)cell
   forTableColumn:(NSTableColumn *)tableColumn
              row:(NSInteger)row {
    if (![cell respondsToSelector:@selector(setTextColor:)]) return;
    if (row >= (NSInteger)self.hostsData.count) return;

    NSDictionary *entry = self.hostsData[(NSUInteger)row];
    NSString *colID = tableColumn.identifier;
    NSColor *color = [NSColor labelColor]; // Standard

    if ([colID isEqualToString:@"ip"]) {
        NSString *ip = entry[@"ip"] ?: @"";
        if ([ip isEqualToString:@"Nicht erreichbar"]) {
            color = [NSColor systemRedColor];
        }
    } else if ([colID isEqualToString:@"status"]) {
        NSString *status = entry[@"status"] ?: @"";
        if ([status hasPrefix:@"✓"]) {
            color = [NSColor systemGreenColor];
        } else if ([status hasPrefix:@"⚠"]) {
            color = [NSColor systemOrangeColor];
        }
    }

    [cell setTextColor:color];
}

#pragma mark - Einstellungen laden

- (void)loadSavedSettings {
    NSString *username = [self.defaults stringForKey:kPrefUsername];
    if (username.length > 0) {
        self.usernameField.stringValue = username;
        NSString *pw = [self keychainPasswordForUsername:username];
        if (pw) self.passwordField.stringValue = pw;
    }

    NSInteger interval = [self.defaults integerForKey:kPrefInterval];
    if (interval == 0) interval = kDefaultInterval;
    [self selectIntervalValue:interval];

    [self loadDaemonState];

    NSString *savedHosts = [self.defaults stringForKey:kPrefHosts];
    if (savedHosts.length > 0) {
        self.hostsField.stringValue = savedHosts;
        [self resolveAllHosts];
    }
}

- (void)loadDaemonState {
    NSISO8601DateFormatter *isoFmt = [[NSISO8601DateFormatter alloc] init];

    // ── NSUserDefaults (LaunchAgent oder manuelles Update) ────────────────
    NSString *defIP     = [self.defaults stringForKey:kPrefLastIP];
    NSString *defDateV  = [self.defaults stringForKey:kPrefLastUpdate];
    NSString *defResult = [self.defaults stringForKey:kPrefLastResult];
    // Datum immer als ISO normalisieren (ältere Builds speicherten lokalisiert)
    NSString *defISO = nil;
    if (defDateV) {
        if ([isoFmt dateFromString:defDateV]) {
            defISO = defDateV; // bereits ISO
        } else {
            NSDate *d = [self parsedFromLocalizedDate:defDateV];
            if (d) defISO = [isoFmt stringFromDate:d];
        }
    }

    // ── LaunchDaemon state.plist ──────────────────────────────────────────
    NSDictionary *daemonState = [NSDictionary dictionaryWithContentsOfFile:
        @"/Library/Application Support/DNS-O-MATIC Updater/state.plist"];
    NSString *daemonISO    = daemonState[@"lastUpdateDate"];
    NSString *daemonIP     = daemonState[@"lastIP"];
    NSString *daemonResult = daemonState[@"lastResult"];

    // ── Neuesten Wert bestimmen ───────────────────────────────────────────
    NSString *winnerISO, *winnerIP, *winnerResult;
    if (daemonISO && (!defISO || [daemonISO compare:defISO] == NSOrderedDescending)) {
        winnerISO    = daemonISO;
        winnerIP     = daemonIP;
        winnerResult = daemonResult;
    } else {
        winnerISO    = defISO;
        winnerIP     = defIP;
        winnerResult = defResult;
    }

    // ── ISO → lokalisiertes Datum ─────────────────────────────────────────
    NSString *displayDate = winnerISO;
    NSDate *winnerDate = [isoFmt dateFromString:winnerISO];
    if (winnerDate) {
        displayDate = [NSDateFormatter
            localizedStringFromDate:winnerDate
                          dateStyle:NSDateFormatterShortStyle
                          timeStyle:NSDateFormatterMediumStyle];
    }

    if (winnerIP)     self.currentIPField.stringValue  = winnerIP;
    if (displayDate)  self.lastUpdateField.stringValue = displayDate;
    if (winnerResult) self.statusField.stringValue     = winnerResult;
}

- (void)selectIntervalValue:(NSInteger)seconds {
    for (NSMenuItem *item in self.intervalPopUp.menu.itemArray) {
        if ([item.representedObject integerValue] == seconds) {
            [self.intervalPopUp selectItem:item];
            return;
        }
    }
    [self.intervalPopUp selectItemAtIndex:0];
}

- (NSInteger)selectedInterval {
    NSInteger v = [self.intervalPopUp.selectedItem.representedObject integerValue];
    return v > 0 ? v : kDefaultInterval;
}

#pragma mark - Actions

- (IBAction)saveCredentials:(id)sender {
    NSString *username = self.usernameField.stringValue;
    NSString *password = self.passwordField.stringValue;

    if (username.length == 0 || password.length == 0) {
        [self showAlert:@"Bitte Benutzernamen und Passwort eingeben."];
        return;
    }

    [self.defaults setObject:username forKey:kPrefUsername];
    [self.defaults synchronize];
    [self saveKeychainPassword:password forUsername:username];

    if ([self isLaunchDaemonInstalled]) {
        [self writeDaemonConfigForUsername:username password:password];
    }
    if ([self isLaunchAgentInstalled])  [self reinstallLaunchAgent];
    if ([self isLaunchDaemonInstalled]) [self reinstallLaunchDaemon];

    self.credStatusLabel.stringValue = @"Gespeichert.";
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        self.credStatusLabel.stringValue = @"";
    });
}

- (IBAction)updateNow:(id)sender {
    [self performUpdateFromPane];
}

- (IBAction)resolveHosts:(id)sender {
    [self.defaults setObject:self.hostsField.stringValue forKey:kPrefHosts];
    [self.defaults synchronize];
    [self resolveAllHosts];
}

- (IBAction)toggleLaunchAgent:(id)sender {
    if (self.launchAgentCheck.state == NSControlStateValueOn) {
        [self installLaunchAgent];
    } else {
        [self uninstallLaunchAgent];
    }
    [self updateAutomationCheckboxes];
}

- (IBAction)toggleLaunchDaemon:(id)sender {
    if (self.launchDaemonCheck.state == NSControlStateValueOn) {
        [self installLaunchDaemon];
    } else {
        [self uninstallLaunchDaemon];
    }
    [self updateAutomationCheckboxes];
}

- (IBAction)intervalChanged:(id)sender {
    NSInteger interval = [self selectedInterval];
    [self.defaults setInteger:interval forKey:kPrefInterval];
    [self.defaults synchronize];

    if ([self isLaunchAgentInstalled])  [self reinstallLaunchAgent];
    if ([self isLaunchDaemonInstalled]) [self reinstallLaunchDaemon];
}

#pragma mark - Host-Auflösung

- (void)resolveAllHosts {
    NSString *hostsStr = self.hostsField.stringValue;
    NSArray *parts = [hostsStr componentsSeparatedByString:@","];

    NSMutableArray *initial = [NSMutableArray array];
    for (NSString *h in parts) {
        NSString *t = [h stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (t.length > 0) {
            [initial addObject:[@{@"hostname": t,
                                  @"ip":       @"…",
                                  @"status":   @""} mutableCopy]];
        }
    }
    self.hostsData = initial;
    [self.hostsTable reloadData];

    NSString *currentIP = self.currentIPField.stringValue;

    for (NSMutableDictionary *entry in self.hostsData) {
        NSString *hostname = entry[@"hostname"];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSString *resolved = [self resolveHostnameExternally:hostname];
            NSString *ip, *status;
            if (!resolved) {
                ip     = @"Nicht erreichbar";
                status = @"⚠";
            } else {
                ip = resolved;
                BOOL matches = [resolved isEqualToString:currentIP]
                               && ![currentIP isEqualToString:@"—"]
                               && currentIP.length > 0;
                status = matches ? @"✓ aktuell" : @"⚠ veraltet";
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                for (NSMutableDictionary *e in self.hostsData) {
                    if ([e[@"hostname"] isEqualToString:hostname]) {
                        e[@"ip"]     = ip;
                        e[@"status"] = status;
                        break;
                    }
                }
                [self.hostsTable reloadData];
            });
        });
    }
}

// Externe DNS-Auflösung via Google DNS-over-HTTPS —
// umgeht lokalen DNS-Resolver und NAT-Loopback im Router.
// Verwendet curl als Subprocess, um Sandboxing des Host-Prozesses zu umgehen.
// Blockiert — nur aus einem Hintergrund-Thread aufrufen.
- (NSString *)resolveHostnameExternally:(NSString *)hostname {
    NSString *encoded = [hostname stringByAddingPercentEncodingWithAllowedCharacters:
                         [NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *urlStr = [NSString stringWithFormat:
        @"https://dns.google/resolve?name=%@&type=A", encoded];

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/curl"];
    task.arguments = @[@"-sf", @"--max-time", @"8", urlStr];

    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError  = [NSPipe pipe]; // unterdrücken

    NSError *launchErr = nil;
    [task launchAndReturnError:&launchErr];
    if (launchErr) return nil;

    [task waitUntilExit];

    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    if (!data || task.terminationStatus != 0) return nil;

    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if ([json[@"Status"] integerValue] != 0) return nil; // NXDOMAIN o.ä.

    for (NSDictionary *answer in json[@"Answer"]) {
        if ([answer[@"type"] integerValue] == 1) { // A-Record
            return answer[@"data"];
        }
    }
    return nil;
}

#pragma mark - Netzwerk: IP-Erkennung und DNS-Update

- (void)refreshCurrentIP {
    NSURL *url = [NSURL URLWithString:@"https://api.ipify.org"];
    [[[NSURLSession sharedSession] dataTaskWithURL:url
                                completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (!data) return;
        NSString *ip = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        ip = [ip stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (ip.length > 0) {
                self.currentIPField.stringValue = ip;
                if (self.hostsData.count > 0) [self resolveAllHosts];
            }
        });
    }] resume];
}

// Prüft ob OpenDNS als lokaler DNS-Resolver aktiv ist.
// welcome.opendns.com wird über den System-Resolver aufgelöst und per HTTP abgerufen.
// OpenDNS antwortet mit HTTP 200 + eigenem Inhalt; bei anderem DNS schlägt die Anfrage fehl.
- (void)checkOpenDNSStatus {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.openDNSStatusField.stringValue = @"…";
    });
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/curl"];
        // -sf: silent + fail on HTTP error; -L: follow redirects; max-time 8s
        // -o /dev/null: Körper verwerfen, nur Status-Code ausgeben
        task.arguments = @[@"-sf", @"--max-time", @"8", @"-L",
                           @"-o", @"/dev/null",
                           @"-w", @"%{http_code}",
                           @"http://welcome.opendns.com"];
        NSPipe *pipe = [NSPipe pipe];
        task.standardOutput = pipe;
        task.standardError  = [NSPipe pipe];

        NSError *err = nil;
        [task launchAndReturnError:&err];
        if (err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.openDNSStatusField.stringValue = @"⚠ Prüfung fehlgeschlagen";
                self.openDNSStatusField.textColor = [NSColor systemOrangeColor];
            });
            return;
        }
        [task waitUntilExit];

        NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
        NSString *httpCode = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        httpCode = [httpCode stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];

        // OpenDNS liefert HTTP 200 für welcome.opendns.com;
        // bei fremdem DNS schlägt curl fehl (exit ≠ 0) oder gibt anderen Code zurück.
        BOOL active = (task.terminationStatus == 0 && [httpCode isEqualToString:@"200"]);

        dispatch_async(dispatch_get_main_queue(), ^{
            if (active) {
                self.openDNSStatusField.stringValue = @"✓ aktiv";
                self.openDNSStatusField.textColor = [NSColor systemGreenColor];
            } else {
                self.openDNSStatusField.stringValue = @"✗ nicht aktiv";
                self.openDNSStatusField.textColor = [NSColor systemRedColor];
            }
        });
    });
}

- (void)performUpdateFromPane {
    NSString *username = self.usernameField.stringValue;
    NSString *password = self.passwordField.stringValue;

    if (username.length == 0 || password.length == 0) {
        [self showAlert:@"Bitte zuerst Credentials speichern."];
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        self.spinner.hidden = NO;
        [self.spinner startAnimation:nil];
        self.statusField.stringValue = @"IP wird ermittelt…";
    });

    NSURL *ipURL = [NSURL URLWithString:@"https://api.ipify.org"];
    [[[NSURLSession sharedSession] dataTaskWithURL:ipURL
                                completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        if (!d) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.statusField.stringValue = @"IP-Ermittlung fehlgeschlagen.";
                [self.spinner stopAnimation:nil];
                self.spinner.hidden = YES;
            });
            return;
        }
        NSString *ip = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        ip = [ip stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.currentIPField.stringValue = ip;
            self.statusField.stringValue = @"DNS-O-MATIC wird aktualisiert…";
        });

        [self updateDNSWithIP:ip username:username password:password];
    }] resume];
}

- (void)updateDNSWithIP:(NSString *)ip username:(NSString *)username password:(NSString *)password {
    NSString *urlStr = [NSString stringWithFormat:
        @"https://updates.dnsomatic.com/nic/update"
        @"?hostname=all.dnsomatic.com&myip=%@&wildcard=NOCHG&mx=NOCHG&backmx=NOCHG", ip];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];

    NSString *creds = [NSString stringWithFormat:@"%@:%@", username, password];
    NSString *b64   = [[creds dataUsingEncoding:NSUTF8StringEncoding]
                        base64EncodedStringWithOptions:0];
    [req setValue:[@"Basic " stringByAppendingString:b64] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"DNS-O-MATIC-Updater-macOS/1.0" forHTTPHeaderField:@"User-Agent"];

    [[[NSURLSession sharedSession] dataTaskWithRequest:req
                                    completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        NSString *result = d
            ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]
            : (e.localizedDescription ?: @"Unbekannter Fehler");
        result = [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        NSISO8601DateFormatter *isoFmt = [[NSISO8601DateFormatter alloc] init];
        NSString *nowISO = [isoFmt stringFromDate:[NSDate date]];
        NSString *nowDisplay = [NSDateFormatter
            localizedStringFromDate:[NSDate date]
            dateStyle:NSDateFormatterShortStyle
            timeStyle:NSDateFormatterMediumStyle];

        [self.defaults setObject:ip      forKey:kPrefLastIP];
        [self.defaults setObject:nowISO  forKey:kPrefLastUpdate];
        [self.defaults setObject:result  forKey:kPrefLastResult];
        [self.defaults synchronize];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.lastUpdateField.stringValue = nowDisplay;
            self.statusField.stringValue     = result;
            [self.spinner stopAnimation:nil];
            self.spinner.hidden = YES;

            [self checkOpenDNSStatus];
            if (self.hostsData.count > 0) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    [self resolveAllHosts];
                });
            }
        });
    }] resume];
}

#pragma mark - Keychain

- (NSString *)keychainPasswordForUsername:(NSString *)username {
    if (username.length == 0) return nil;

    const char *server  = kKeychainServer.UTF8String;
    const char *account = username.UTF8String;
    UInt32 pwLen = 0; void *pwData = NULL;

    OSStatus status = SecKeychainFindInternetPassword(
        NULL,
        (UInt32)strlen(server),  server,
        0, NULL,
        (UInt32)strlen(account), account,
        0, NULL, 0,
        kSecProtocolTypeHTTPS,
        kSecAuthenticationTypeDefault,
        &pwLen, &pwData, NULL);

    if (status == errSecSuccess && pwData) {
        NSString *pw = [[NSString alloc] initWithBytes:pwData length:pwLen
                                              encoding:NSUTF8StringEncoding];
        SecKeychainItemFreeContent(NULL, pwData);
        return pw;
    }
    return nil;
}

- (void)saveKeychainPassword:(NSString *)password forUsername:(NSString *)username {
    const char *server  = kKeychainServer.UTF8String;
    const char *account = username.UTF8String;
    const char *pw      = password.UTF8String;

    SecKeychainItemRef item = NULL;
    OSStatus found = SecKeychainFindInternetPassword(
        NULL,
        (UInt32)strlen(server),  server,
        0, NULL,
        (UInt32)strlen(account), account,
        0, NULL, 0,
        kSecProtocolTypeHTTPS,
        kSecAuthenticationTypeDefault,
        0, NULL, &item);

    if (found == errSecSuccess && item) {
        SecKeychainItemModifyAttributesAndData(item, NULL, (UInt32)strlen(pw), pw);
        CFRelease(item);
    } else {
        SecKeychainAddInternetPassword(
            NULL,
            (UInt32)strlen(server),  server,
            0, NULL,
            (UInt32)strlen(account), account,
            0, NULL, 0,
            kSecProtocolTypeHTTPS,
            kSecAuthenticationTypeDefault,
            (UInt32)strlen(pw), pw, NULL);
    }
}

#pragma mark - LaunchAgent

- (NSString *)launchAgentPlistPath {
    return [NSString stringWithFormat:@"%@/Library/LaunchAgents/%@.plist",
            NSHomeDirectory(), kLaunchAgentLabel];
}

- (NSString *)agentSupportDir {
    return [NSString stringWithFormat:@"%@/Library/Application Support/DNS-O-MATIC Updater",
            NSHomeDirectory()];
}

- (NSString *)agentScriptPath {
    return [[self agentSupportDir] stringByAppendingPathComponent:@"update-agent.sh"];
}

- (BOOL)isLaunchAgentInstalled {
    return [[NSFileManager defaultManager] fileExistsAtPath:[self launchAgentPlistPath]];
}

- (void)installLaunchAgent {
    NSString *username = [self.defaults stringForKey:kPrefUsername];
    if (username.length == 0) {
        [self showAlert:@"Bitte zuerst Credentials speichern."];
        return;
    }

    NSError *err = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:[self agentSupportDir]
  withIntermediateDirectories:YES attributes:nil error:&err];

    [kAgentScript writeToFile:[self agentScriptPath]
                   atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if (err) { [self showAlert:err.localizedDescription]; return; }

    [fm setAttributes:@{NSFilePosixPermissions: @(0755)}
          ofItemAtPath:[self agentScriptPath] error:nil];

    NSDictionary *plist = @{
        @"Label":            kLaunchAgentLabel,
        @"ProgramArguments": @[@"/bin/bash", [self agentScriptPath]],
        @"StartInterval":    @([self selectedInterval]),
        @"RunAtLoad":        @YES
    };
    [plist writeToFile:[self launchAgentPlistPath] atomically:YES];

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/launchctl"];
    task.arguments = @[@"load", [self launchAgentPlistPath]];
    [task launchAndReturnError:nil];
}

- (void)uninstallLaunchAgent {
    if (![self isLaunchAgentInstalled]) return;

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/launchctl"];
    task.arguments = @[@"unload", [self launchAgentPlistPath]];
    [task launchAndReturnError:nil];
    [task waitUntilExit];

    [[NSFileManager defaultManager] removeItemAtPath:[self launchAgentPlistPath] error:nil];
}

- (void)reinstallLaunchAgent {
    [self uninstallLaunchAgent];
    [self installLaunchAgent];
}

#pragma mark - LaunchDaemon

- (NSString *)launchDaemonPlistPath {
    return [NSString stringWithFormat:@"/Library/LaunchDaemons/%@.plist", kLaunchDaemonLabel];
}

- (NSString *)daemonSupportDir {
    return @"/Library/Application Support/DNS-O-MATIC Updater";
}

- (NSString *)daemonScriptPath {
    return [[self daemonSupportDir] stringByAppendingPathComponent:@"update-daemon.sh"];
}

- (NSString *)daemonConfigPath {
    return [[self daemonSupportDir] stringByAppendingPathComponent:@"config.plist"];
}

- (BOOL)isLaunchDaemonInstalled {
    return [[NSFileManager defaultManager] fileExistsAtPath:[self launchDaemonPlistPath]];
}

- (void)writeDaemonConfigForUsername:(NSString *)username password:(NSString *)password {
    NSString *tmpDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"dns-o-matic-install"];
    [[NSFileManager defaultManager] createDirectoryAtPath:tmpDir
                              withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *tmpConfig = [tmpDir stringByAppendingPathComponent:@"config.plist"];
    [@{@"username": username, @"password": password} writeToFile:tmpConfig atomically:YES];

    NSString *destDir  = [self daemonSupportDir];
    NSString *destConf = [self daemonConfigPath];

    NSString *cmds = [NSString stringWithFormat:
        @"mkdir -p '%@' && cp '%@' '%@' && chmod 600 '%@' && chown root '%@'",
        [destDir stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"],
        [tmpConfig stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"],
        [destConf  stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"],
        [destConf  stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"],
        [destConf  stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];;

    NSString *as = [NSString stringWithFormat:
        @"do shell script \"%@\" with administrator privileges",
        [cmds stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
    [[[NSAppleScript alloc] initWithSource:as] executeAndReturnError:nil];
}

- (void)installLaunchDaemon {
    NSString *username = [self.defaults stringForKey:kPrefUsername];
    NSString *password = [self keychainPasswordForUsername:username];

    if (username.length == 0 || password.length == 0) {
        [self showAlert:@"Bitte zuerst Credentials speichern."];
        return;
    }

    NSString *tmpDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"dns-o-matic-install"];
    [[NSFileManager defaultManager] createDirectoryAtPath:tmpDir
                              withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *tmpScript = [tmpDir stringByAppendingPathComponent:@"update-daemon.sh"];
    [kDaemonScript writeToFile:tmpScript atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSString *tmpConfig = [tmpDir stringByAppendingPathComponent:@"config.plist"];
    [@{@"username": username, @"password": password} writeToFile:tmpConfig atomically:YES];

    NSString *tmpPlist = [tmpDir stringByAppendingPathComponent:@"daemon.plist"];
    [@{@"Label":            kLaunchDaemonLabel,
       @"ProgramArguments": @[@"/bin/bash", [self daemonScriptPath]],
       @"StartInterval":    @([self selectedInterval]),
       @"RunAtLoad":        @YES} writeToFile:tmpPlist atomically:YES];

    NSString *destDir    = [self daemonSupportDir];
    NSString *destScript = [self daemonScriptPath];
    NSString *destConf   = [self daemonConfigPath];
    NSString *destPlist  = [self launchDaemonPlistPath];

    #define SQ(s) [(s) stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]

    NSString *cmds = [NSString stringWithFormat:
        @"mkdir -p '%@' && "
        @"cp '%@' '%@' && chmod 755 '%@' && "
        @"cp '%@' '%@' && chmod 600 '%@' && chown root '%@' && "
        @"cp '%@' '%@' && launchctl load '%@'",
        SQ(destDir),
        SQ(tmpScript), SQ(destScript), SQ(destScript),
        SQ(tmpConfig),  SQ(destConf),  SQ(destConf),  SQ(destConf),
        SQ(tmpPlist),   SQ(destPlist), SQ(destPlist)];

    NSString *appleScript = [NSString stringWithFormat:
        @"do shell script \"%@\" with administrator privileges",
        [cmds stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];

    NSAppleScript *as = [[NSAppleScript alloc] initWithSource:appleScript];
    NSDictionary *errInfo = nil;
    [as executeAndReturnError:&errInfo];
    if (errInfo) {
        [self showAlert:[NSString stringWithFormat:@"Installation fehlgeschlagen:\n%@",
            errInfo[NSAppleScriptErrorMessage]]];
    }
}

- (void)uninstallLaunchDaemon {
    #define SQ(s) [(s) stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]
    NSString *p = [self launchDaemonPlistPath];
    NSString *d = [self daemonSupportDir];
    NSString *cmds = [NSString stringWithFormat:
        @"launchctl unload '%@' ; rm -f '%@' ; rm -rf '%@'",
        SQ(p), SQ(p), SQ(d)];
    NSString *as = [NSString stringWithFormat:
        @"do shell script \"%@\" with administrator privileges",
        [cmds stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
    [[[NSAppleScript alloc] initWithSource:as] executeAndReturnError:nil];
}

- (void)reinstallLaunchDaemon {
    [self uninstallLaunchDaemon];
    [self installLaunchDaemon];
}

#pragma mark - Hilfsmethoden

// Wandelt ein lokalisiertes Datum zurück in ISO 8601 für den Vergleich.
// Gibt den Original-String zurück wenn Parsing fehlschlägt.
// Parst ein lokalisiertes Datum (ShortDate + MediumTime) zurück in NSDate.
// Wird nur für Rückwärtskompatibilität mit alten Werten in NSUserDefaults benötigt.
- (NSDate *)parsedFromLocalizedDate:(NSString *)localDate {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateStyle = NSDateFormatterShortStyle;
    fmt.timeStyle = NSDateFormatterMediumStyle;
    return [fmt dateFromString:localDate];
}

- (void)updateAutomationCheckboxes {
    self.launchAgentCheck.state  = [self isLaunchAgentInstalled]
        ? NSControlStateValueOn : NSControlStateValueOff;
    self.launchDaemonCheck.state = [self isLaunchDaemonInstalled]
        ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)showAlert:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText     = @"DNS-O-MATIC Updater";
        alert.informativeText = msg;
        [alert runModal];
    });
}

@end
