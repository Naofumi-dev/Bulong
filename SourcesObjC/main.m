#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>

typedef NS_ENUM(NSInteger, LocalTalkRunState) {
    LocalTalkRunStateIdle,
    LocalTalkRunStateRecording,
    LocalTalkRunStateTranscribing,
    LocalTalkRunStateFailed
};

typedef NS_ENUM(NSInteger, LocalTalkScreen) {
    LocalTalkScreenHome,
    LocalTalkScreenDictation,
    LocalTalkScreenHotkeys,
    LocalTalkScreenPreferences
};

static NSString * const LocalTalkWhisperPathKey = @"whisperPath";
static NSString * const LocalTalkModelNameKey = @"modelName";
static NSString * const LocalTalkTaskNameKey = @"taskName";
static NSString * const LocalTalkLanguageCodeKey = @"languageCode";
static NSString * const LocalTalkPasteResultKey = @"pasteResult";
static NSString * const LocalTalkCopyResultKey = @"copyResult";
static NSString * const LocalTalkShowMenuBarKey = @"showMenuBar";
static NSString * const LocalTalkShowDockKey = @"showDock";
static NSString * const LocalTalkInteractionSoundsKey = @"interactionSounds";
static NSString * const LocalTalkHUDLocationKey = @"hudLocation";
static NSString * const LocalTalkHUDUseCustomPositionKey = @"hudUseCustomPosition";
static NSString * const LocalTalkHUDCustomXKey = @"hudCustomX";
static NSString * const LocalTalkHUDCustomYKey = @"hudCustomY";
static NSString * const LocalTalkHistoryKey = @"transcriptionHistory";

static NSColor *LTColor(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha) {
    return [NSColor colorWithCalibratedRed:red / 255.0 green:green / 255.0 blue:blue / 255.0 alpha:alpha];
}

static NSColor *LTAccentColor(CGFloat alpha) {
    return LTColor(76, 198, 255, alpha);
}

static NSColor *LTAccentTextColor(CGFloat alpha) {
    return LTColor(178, 234, 255, alpha);
}

static NSString *LocalTalkSearchPath(void) {
    return @"/Library/Frameworks/Python.framework/Versions/3.14/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
}

static OSType LocalTalkFourCharCode(const char *code) {
    return ((UInt32)code[0] << 24) | ((UInt32)code[1] << 16) | ((UInt32)code[2] << 8) | (UInt32)code[3];
}

static NSString *LocalTalkDefaultWhisperPath(void) {
    NSArray<NSString *> *candidates = @[
        @"/Library/Frameworks/Python.framework/Versions/3.14/bin/whisper",
        @"/opt/homebrew/bin/whisper",
        @"/usr/local/bin/whisper"
    ];

    NSFileManager *fileManager = NSFileManager.defaultManager;
    for (NSString *candidate in candidates) {
        if ([fileManager isExecutableFileAtPath:candidate]) {
            return candidate;
        }
    }
    return @"whisper";
}

@interface LocalTalkHUDShellView : NSView
@property(nonatomic, assign) NSPoint dragStartMouseLocation;
@property(nonatomic, assign) NSPoint dragStartWindowOrigin;
@end

@implementation LocalTalkHUDShellView

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    return YES;
}

- (void)mouseDown:(NSEvent *)event {
    self.dragStartMouseLocation = NSEvent.mouseLocation;
    self.dragStartWindowOrigin = self.window.frame.origin;
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint currentLocation = NSEvent.mouseLocation;
    CGFloat deltaX = currentLocation.x - self.dragStartMouseLocation.x;
    CGFloat deltaY = currentLocation.y - self.dragStartMouseLocation.y;
    NSPoint nextOrigin = NSMakePoint(self.dragStartWindowOrigin.x + deltaX, self.dragStartWindowOrigin.y + deltaY);
    [self.window setFrameOrigin:nextOrigin];
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:LocalTalkHUDUseCustomPositionKey];
    [NSUserDefaults.standardUserDefaults setDouble:nextOrigin.x forKey:LocalTalkHUDCustomXKey];
    [NSUserDefaults.standardUserDefaults setDouble:nextOrigin.y forKey:LocalTalkHUDCustomYKey];
}

@end

@interface LocalTalkController : NSObject <NSApplicationDelegate, AVAudioRecorderDelegate, NSTextFieldDelegate>
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSMenu *statusMenu;
@property(nonatomic, strong) NSMenuItem *statusToggleItem;
@property(nonatomic, strong) NSMenuItem *statusTextItem;
@property(nonatomic, strong) NSMenuItem *statusPasteItem;
@property(nonatomic, strong) NSWindow *mainWindow;
@property(nonatomic, strong) NSView *rootView;
@property(nonatomic, strong) NSView *sidebarView;
@property(nonatomic, strong) NSView *contentView;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSButton *> *navButtons;
@property(nonatomic, strong) NSButton *primaryRecordButton;
@property(nonatomic, strong) NSTextField *statusTitleLabel;
@property(nonatomic, strong) NSTextField *statusDetailLabel;
@property(nonatomic, strong) NSImageView *statusGlyphView;
@property(nonatomic, strong) NSProgressIndicator *statusSpinner;
@property(nonatomic, strong) NSTextView *transcriptTextView;
@property(nonatomic, strong) NSTextView *activityTextView;
@property(nonatomic, strong) NSPopUpButton *modePopup;
@property(nonatomic, strong) NSPopUpButton *modelPopup;
@property(nonatomic, strong) NSPopUpButton *languagePopup;
@property(nonatomic, strong) NSTextField *whisperPathField;
@property(nonatomic, strong) NSButton *pasteCheckbox;
@property(nonatomic, strong) NSButton *clipboardCheckbox;
@property(nonatomic, strong) NSButton *menuBarCheckbox;
@property(nonatomic, strong) NSButton *dockCheckbox;
@property(nonatomic, strong) NSButton *soundCheckbox;
@property(nonatomic, strong) NSPopUpButton *hudLocationPopup;
@property(nonatomic, strong) NSPanel *hudPanel;
@property(nonatomic, strong) NSTextField *hudTitleLabel;
@property(nonatomic, strong) NSTextField *hudDetailLabel;
@property(nonatomic, strong) NSImageView *hudIconView;
@property(nonatomic, strong) NSTextField *hudModeLabel;
@property(nonatomic, strong) NSTextField *hudLanguageLabel;
@property(nonatomic, strong) NSImageView *hudDragHandleView;
@property(nonatomic, strong) NSMutableArray<CALayer *> *hudBars;
@property(nonatomic, strong) NSProgressIndicator *hudSpinner;
@property(nonatomic, assign) NSTimeInterval hudLastDetailTick;
@property(nonatomic, strong) NSTimer *recordingTimer;
@property(nonatomic, strong) NSDate *recordingStartDate;
@property(nonatomic, strong) AVAudioRecorder *recorder;
@property(nonatomic, strong) NSURL *recordingURL;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *history;
@property(nonatomic, copy) NSString *lastTranscript;
@property(nonatomic, copy) NSString *currentStatus;
@property(nonatomic, copy) NSString *targetAppName;
@property(nonatomic, assign) NSUInteger sessionTranscriptCount;
@property(nonatomic, assign) NSUInteger sessionWordCount;
@property(nonatomic, assign) NSTimeInterval sessionRecordedSeconds;
@property(nonatomic, assign) LocalTalkRunState runState;
@property(nonatomic, assign) LocalTalkScreen selectedScreen;
@property(nonatomic, assign) EventHotKeyRef hotKeyRef;
@property(nonatomic, assign) EventHandlerRef hotKeyHandlerRef;
- (NSImage *)brandImage;
- (void)toggleRecording:(id)sender;
@end

static OSStatus LocalTalkHotKeyHandler(EventHandlerCallRef nextHandler, EventRef event, void *userData) {
    LocalTalkController *controller = (__bridge LocalTalkController *)userData;
    [controller toggleRecording:nil];
    return noErr;
}

@implementation LocalTalkController

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    [self registerDefaultSettings];
    self.history = [[self loadHistory] mutableCopy];
    self.navButtons = [NSMutableDictionary dictionary];
    self.selectedScreen = LocalTalkScreenHome;
    [NSApp setApplicationIconImage:[self brandImage]];

    [self applyDockPreference];
    [self buildApplicationMenu];
    [self buildStatusMenuIfNeeded];
    [self buildMainWindow];
    [self buildHUD];
    [self registerHotKey];
    [self setStatus:@"Ready" detail:@"Press Control + Option + Space to dictate." state:LocalTalkRunStateIdle];
    [self showMainWindow:nil];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    [self showMainWindow:nil];
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self.recordingTimer invalidate];
    if (_hotKeyRef != NULL) {
        UnregisterEventHotKey(_hotKeyRef);
        _hotKeyRef = NULL;
    }
    if (_hotKeyHandlerRef != NULL) {
        RemoveEventHandler(_hotKeyHandlerRef);
        _hotKeyHandlerRef = NULL;
    }
}

- (void)registerDefaultSettings {
    [NSUserDefaults.standardUserDefaults registerDefaults:@{
        LocalTalkWhisperPathKey: LocalTalkDefaultWhisperPath(),
        LocalTalkModelNameKey: @"base.en",
        LocalTalkTaskNameKey: @"transcribe",
        LocalTalkLanguageCodeKey: @"en",
        LocalTalkPasteResultKey: @YES,
        LocalTalkCopyResultKey: @YES,
        LocalTalkShowMenuBarKey: @YES,
        LocalTalkShowDockKey: @YES,
        LocalTalkInteractionSoundsKey: @YES,
        LocalTalkHUDLocationKey: @"bottom",
        LocalTalkHUDUseCustomPositionKey: @NO,
        LocalTalkHUDCustomXKey: @0,
        LocalTalkHUDCustomYKey: @0
    }];
}

- (NSArray<NSDictionary *> *)loadHistory {
    NSArray *items = [NSUserDefaults.standardUserDefaults arrayForKey:LocalTalkHistoryKey];
    return items ?: @[];
}

- (void)saveHistory {
    [NSUserDefaults.standardUserDefaults setObject:self.history forKey:LocalTalkHistoryKey];
}

- (void)applyDockPreference {
    BOOL showDock = [NSUserDefaults.standardUserDefaults boolForKey:LocalTalkShowDockKey];
    [NSApp setActivationPolicy:showDock ? NSApplicationActivationPolicyRegular : NSApplicationActivationPolicyAccessory];
}

- (void)buildApplicationMenu {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    [mainMenu addItem:appMenuItem];

    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"LocalTalk"];
    NSMenuItem *showItem = [[NSMenuItem alloc] initWithTitle:@"Show LocalTalk"
                                                      action:@selector(showMainWindow:)
                                               keyEquivalent:@"0"];
    showItem.target = self;
    [appMenu addItem:showItem];

    NSMenuItem *recordItem = [[NSMenuItem alloc] initWithTitle:@"Toggle Recording"
                                                        action:@selector(toggleRecording:)
                                                 keyEquivalent:@" "];
    recordItem.keyEquivalentModifierMask = NSEventModifierFlagControl | NSEventModifierFlagOption;
    recordItem.target = self;
    [appMenu addItem:recordItem];

    [appMenu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit LocalTalk"
                                                      action:@selector(terminate:)
                                               keyEquivalent:@"q"];
    quitItem.target = NSApp;
    [appMenu addItem:quitItem];
    appMenuItem.submenu = appMenu;
    NSApp.mainMenu = mainMenu;
}

- (void)buildStatusMenuIfNeeded {
    BOOL showMenuBar = [NSUserDefaults.standardUserDefaults boolForKey:LocalTalkShowMenuBarKey];
    if (!showMenuBar) {
        if (self.statusItem != nil) {
            [NSStatusBar.systemStatusBar removeStatusItem:self.statusItem];
            self.statusItem = nil;
        }
        return;
    }

    if (self.statusItem == nil) {
        self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
        self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"mic" accessibilityDescription:@"LocalTalk"];
        self.statusItem.button.image.template = YES;
    }

    self.statusMenu = [[NSMenu alloc] initWithTitle:@"LocalTalk"];
    NSMenuItem *showItem = [[NSMenuItem alloc] initWithTitle:@"Open LocalTalk"
                                                      action:@selector(showMainWindow:)
                                               keyEquivalent:@"0"];
    showItem.target = self;
    [self.statusMenu addItem:showItem];
    [self.statusMenu addItem:NSMenuItem.separatorItem];

    self.statusToggleItem = [[NSMenuItem alloc] initWithTitle:@"Start Recording"
                                                       action:@selector(toggleRecording:)
                                                keyEquivalent:@" "];
    self.statusToggleItem.keyEquivalentModifierMask = NSEventModifierFlagControl | NSEventModifierFlagOption;
    self.statusToggleItem.target = self;
    [self.statusMenu addItem:self.statusToggleItem];

    self.statusTextItem = [[NSMenuItem alloc] initWithTitle:@"Ready" action:nil keyEquivalent:@""];
    self.statusTextItem.enabled = NO;
    [self.statusMenu addItem:self.statusTextItem];
    [self.statusMenu addItem:NSMenuItem.separatorItem];

    self.statusPasteItem = [[NSMenuItem alloc] initWithTitle:@"Paste Result"
                                                      action:@selector(togglePasteResult:)
                                               keyEquivalent:@""];
    self.statusPasteItem.target = self;
    [self.statusMenu addItem:self.statusPasteItem];

    NSMenuItem *languageRoot = [[NSMenuItem alloc] initWithTitle:@"Dictation Language" action:nil keyEquivalent:@""];
    NSMenu *languageMenu = [[NSMenu alloc] initWithTitle:@"Dictation Language"];
    NSString *selectedLanguage = [NSUserDefaults.standardUserDefaults stringForKey:LocalTalkLanguageCodeKey] ?: @"en";
    NSArray<NSDictionary *> *languageItems = @[
        @{@"title": @"Auto Detect", @"value": @"auto"},
        @{@"title": @"English", @"value": @"en"},
        @{@"title": @"Filipino / Tagalog", @"value": @"tl"},
        @{@"title": @"Spanish", @"value": @"es"},
        @{@"title": @"Japanese", @"value": @"ja"},
        @{@"title": @"Korean", @"value": @"ko"}
    ];
    for (NSDictionary *language in languageItems) {
        NSString *title = language[@"title"];
        NSString *value = language[@"value"];
        NSMenuItem *languageItem = [[NSMenuItem alloc] initWithTitle:title action:@selector(selectLanguageMenuItem:) keyEquivalent:@""];
        languageItem.target = self;
        languageItem.representedObject = value;
        languageItem.state = [selectedLanguage isEqualToString:value] ? NSControlStateValueOn : NSControlStateValueOff;
        [languageMenu addItem:languageItem];
    }
    languageRoot.submenu = languageMenu;
    [self.statusMenu addItem:languageRoot];

    NSMenuItem *copyItem = [[NSMenuItem alloc] initWithTitle:@"Copy Last Transcript"
                                                      action:@selector(placeLastTranscriptOnClipboard:)
                                               keyEquivalent:@""];
    copyItem.target = self;
    [self.statusMenu addItem:copyItem];
    [self.statusMenu addItem:NSMenuItem.separatorItem];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit LocalTalk"
                                                      action:@selector(terminate:)
                                               keyEquivalent:@"q"];
    quitItem.target = NSApp;
    [self.statusMenu addItem:quitItem];
    self.statusItem.menu = self.statusMenu;
    [self refreshStatusMenu];
}

- (void)buildMainWindow {
    NSRect frame = NSMakeRect(0, 0, 1180, 720);
    self.mainWindow = [[NSWindow alloc] initWithContentRect:frame
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    self.mainWindow.title = @"LocalTalk";
    self.mainWindow.releasedWhenClosed = NO;
    self.mainWindow.minSize = frame.size;
    self.mainWindow.maxSize = frame.size;

    self.rootView = [[NSView alloc] initWithFrame:frame];
    self.rootView.wantsLayer = YES;
    self.rootView.layer.backgroundColor = LTColor(9, 10, 10, 1).CGColor;
    self.mainWindow.contentView = self.rootView;

    self.sidebarView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 184, 720)];
    self.sidebarView.wantsLayer = YES;
    self.sidebarView.layer.backgroundColor = LTColor(12, 13, 13, 1).CGColor;
    [self.rootView addSubview:self.sidebarView];

    self.contentView = [[NSView alloc] initWithFrame:NSMakeRect(184, 0, 996, 720)];
    self.contentView.wantsLayer = YES;
    self.contentView.layer.backgroundColor = LTColor(18, 19, 19, 1).CGColor;
    [self.rootView addSubview:self.contentView];

    [self buildSidebar];
    [self renderCurrentScreen];
}

- (void)buildSidebar {
    [self.sidebarView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];

    NSImageView *brandMark = [[NSImageView alloc] initWithFrame:NSMakeRect(22, 640, 32, 32)];
    brandMark.image = [self brandImage];
    brandMark.imageScaling = NSImageScaleProportionallyUpOrDown;
    brandMark.wantsLayer = YES;
    brandMark.layer.cornerRadius = 8;
    brandMark.layer.masksToBounds = YES;
    [self.sidebarView addSubview:brandMark];

    NSTextField *brand = [self label:@"LocalTalk"
                               frame:NSMakeRect(64, 654, 104, 24)
                                font:[NSFont boldSystemFontOfSize:22]
                               color:NSColor.whiteColor];
    [self.sidebarView addSubview:brand];

    NSTextField *tagline = [self label:@"Private input"
                                 frame:NSMakeRect(64, 634, 104, 18)
                                  font:[NSFont systemFontOfSize:12 weight:NSFontWeightMedium]
                                 color:LTColor(150, 154, 150, 1)];
    [self.sidebarView addSubview:tagline];

    [self addNavButton:@"Home" symbol:@"house.fill" screen:LocalTalkScreenHome y:562];
    [self addNavButton:@"Dictation" symbol:@"mic" screen:LocalTalkScreenDictation y:512];
    [self addNavButton:@"Hotkeys" symbol:@"command" screen:LocalTalkScreenHotkeys y:462];
    [self addNavButton:@"Preferences" symbol:@"slider.horizontal.3" screen:LocalTalkScreenPreferences y:412];

    NSButton *permissionButton = [self darkButton:@"Permissions"
                                            frame:NSMakeRect(16, 92, 152, 32)
                                           action:@selector(requestMicrophonePermission:)];
    [self.sidebarView addSubview:permissionButton];

    NSButton *accountButton = [self darkButton:NSUserName()
                                         frame:NSMakeRect(16, 34, 152, 34)
                                        action:@selector(showMainWindow:)];
    accountButton.enabled = NO;
    [self.sidebarView addSubview:accountButton];
    [self refreshNavSelection];
}

- (void)addNavButton:(NSString *)title symbol:(NSString *)symbol screen:(LocalTalkScreen)screen y:(CGFloat)y {
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(12, y, 160, 38)];
    button.title = [NSString stringWithFormat:@"  %@", title];
    button.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:title];
    button.imagePosition = NSImageLeft;
    button.alignment = NSTextAlignmentLeft;
    button.bezelStyle = NSBezelStyleRegularSquare;
    button.bordered = NO;
    button.wantsLayer = YES;
    button.layer.cornerRadius = 6;
    button.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    button.contentTintColor = LTColor(220, 224, 219, 1);
    button.target = self;
    button.action = @selector(selectScreen:);
    button.tag = screen;
    [self.sidebarView addSubview:button];
    self.navButtons[@(screen)] = button;
}

- (void)refreshNavSelection {
    for (NSNumber *key in self.navButtons) {
        NSButton *button = self.navButtons[key];
        BOOL selected = key.integerValue == self.selectedScreen;
        button.layer.backgroundColor = selected ? LTColor(30, 31, 31, 1).CGColor : NSColor.clearColor.CGColor;
        button.contentTintColor = selected ? LTAccentColor(1) : LTColor(180, 184, 180, 1);
    }
}

- (void)selectScreen:(NSButton *)sender {
    self.selectedScreen = sender.tag;
    [self refreshNavSelection];
    [self renderCurrentScreen];
}

- (void)renderCurrentScreen {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    switch (self.selectedScreen) {
        case LocalTalkScreenHome:
            [self renderHome];
            break;
        case LocalTalkScreenDictation:
            [self renderDictationSettings];
            break;
        case LocalTalkScreenHotkeys:
            [self renderHotkeys];
            break;
        case LocalTalkScreenPreferences:
            [self renderPreferences];
            break;
    }
}

- (void)renderHome {
    [self addHeader:@"Home" subtitle:@"Dictate into any app with a local model and a global hotkey."];

    [self addMetricCardWithTitle:@"Session clips"
                           value:[NSString stringWithFormat:@"%lu", (unsigned long)self.sessionTranscriptCount]
                            note:@"Transcripts since launch"
                          symbol:@"waveform"
                           frame:NSMakeRect(40, 498, 292, 112)];
    [self addMetricCardWithTitle:@"Words captured"
                           value:[NSString stringWithFormat:@"%lu", (unsigned long)self.sessionWordCount]
                            note:@"Local count from transcripts"
                          symbol:@"text.word.spacing"
                           frame:NSMakeRect(352, 498, 292, 112)];
    [self addMetricCardWithTitle:@"Current model"
                           value:[NSUserDefaults.standardUserDefaults stringForKey:LocalTalkModelNameKey] ?: @"base.en"
                            note:@"Runs through local Whisper"
                          symbol:@"cpu"
                           frame:NSMakeRect(664, 498, 292, 112)];

    NSView *historyCard = [self card:NSMakeRect(40, 54, 916, 410)];
    [self.contentView addSubview:historyCard];
    NSTextField *title = [self label:@"Recent Transcriptions"
                               frame:NSMakeRect(26, 358, 260, 22)
                                font:[NSFont systemFontOfSize:14 weight:NSFontWeightBold]
                               color:LTColor(236, 238, 235, 1)];
    [historyCard addSubview:title];

    if (self.history.count == 0) {
        NSTextField *empty = [self label:@"Your transcripts will appear here after you record."
                                   frame:NSMakeRect(26, 310, 420, 22)
                                    font:[NSFont systemFontOfSize:14 weight:NSFontWeightRegular]
                                   color:LTColor(150, 154, 150, 1)];
        [historyCard addSubview:empty];
    } else {
        CGFloat y = 310;
        NSUInteger limit = MIN(self.history.count, 7);
        for (NSUInteger index = 0; index < limit; index += 1) {
            NSDictionary *item = self.history[index];
            [self addHistoryRow:item toView:historyCard y:y];
            y -= 48;
        }
    }
}

- (void)addMetricCardWithTitle:(NSString *)title value:(NSString *)value note:(NSString *)note symbol:(NSString *)symbol frame:(NSRect)frame {
    NSView *card = [self card:frame];
    [self.contentView addSubview:card];
    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSMakeRect(24, 70, 18, 18)];
    icon.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:title];
    icon.contentTintColor = LTAccentColor(1);
    [card addSubview:icon];
    [card addSubview:[self label:title frame:NSMakeRect(52, 68, 190, 20) font:[NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightSemibold] color:LTColor(170, 174, 170, 1)]];
    [card addSubview:[self label:value frame:NSMakeRect(24, 34, 244, 30) font:[NSFont systemFontOfSize:28 weight:NSFontWeightBold] color:NSColor.whiteColor]];
    [card addSubview:[self label:note frame:NSMakeRect(24, 16, 244, 18) font:[NSFont systemFontOfSize:12 weight:NSFontWeightMedium] color:LTColor(145, 149, 145, 1)]];
}

- (void)addHistoryRow:(NSDictionary *)item toView:(NSView *)parent y:(CGFloat)y {
    NSString *text = item[@"text"] ?: @"";
    NSString *app = item[@"app"] ?: @"Unknown app";
    NSDate *date = item[@"date"];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"HH:mm";

    NSTextField *snippet = [self label:[self shortened:text maxLength:76]
                                 frame:NSMakeRect(68, y + 14, 620, 20)
                                  font:[NSFont systemFontOfSize:13 weight:NSFontWeightMedium]
                                 color:LTColor(226, 228, 225, 1)];
    NSTextField *appLabel = [self label:app
                                  frame:NSMakeRect(68, y - 4, 260, 18)
                                   font:[NSFont systemFontOfSize:12 weight:NSFontWeightRegular]
                                  color:LTColor(145, 149, 145, 1)];
    NSTextField *time = [self label:[formatter stringFromDate:date ?: NSDate.date]
                              frame:NSMakeRect(812, y + 4, 60, 20)
                               font:[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular]
                              color:LTColor(145, 149, 145, 1)];
    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSMakeRect(26, y + 5, 26, 26)];
    icon.image = [NSImage imageWithSystemSymbolName:@"doc.text.fill" accessibilityDescription:@"Transcript"];
    icon.contentTintColor = LTAccentColor(1);
    [parent addSubview:icon];
    [parent addSubview:snippet];
    [parent addSubview:appLabel];
    [parent addSubview:time];
}

- (void)renderDictationSettings {
    [self addHeader:@"Dictation" subtitle:@"Choose how LocalTalk records, transcribes, and inserts text."];
    NSView *card = [self card:NSMakeRect(40, 76, 916, 534)];
    [self.contentView addSubview:card];

    [self addSettingsRowTo:card y:438 symbol:@"mic" title:@"Microphone" subtitle:@"Use the system default microphone for this MVP." control:[self compactButton:@"Check Permission" action:@selector(requestMicrophonePermission:)]];

    self.modePopup = [self popupWithAction:@selector(selectTaskFromPopup:)];
    [self addPopupItem:@"Transcribe" value:@"transcribe" toPopup:self.modePopup];
    [self addPopupItem:@"Translate to English" value:@"translate" toPopup:self.modePopup];
    [self addSettingsRowTo:card y:352 symbol:@"captions.bubble" title:@"Mode" subtitle:@"Transcribe speech or translate non-English speech to English." control:self.modePopup];

    self.modelPopup = [self popupWithAction:@selector(selectModelFromPopup:)];
    for (NSString *model in @[@"tiny.en", @"base.en", @"small.en", @"base", @"small", @"medium", @"turbo"]) {
        [self addPopupItem:model value:model toPopup:self.modelPopup];
    }
    [self addSettingsRowTo:card y:266 symbol:@"cpu" title:@"Model" subtitle:@"Smaller models are faster. Larger models are more accurate." control:self.modelPopup];

    self.languagePopup = [self popupWithAction:@selector(selectLanguageFromPopup:)];
    NSDictionary<NSString *, NSString *> *languages = @{
        @"Auto": @"auto",
        @"English": @"en",
        @"Filipino / Tagalog": @"tl",
        @"Spanish": @"es",
        @"Japanese": @"ja",
        @"Korean": @"ko",
        @"Chinese": @"zh",
        @"French": @"fr",
        @"German": @"de"
    };
    for (NSString *title in @[@"Auto", @"English", @"Filipino / Tagalog", @"Spanish", @"Japanese", @"Korean", @"Chinese", @"French", @"German"]) {
        [self addPopupItem:title value:languages[title] toPopup:self.languagePopup];
    }
    [self addSettingsRowTo:card y:180 symbol:@"translate" title:@"Language" subtitle:@"Filipino / Tagalog is available for local dictation." control:self.languagePopup];

    self.pasteCheckbox = [self switchButtonWithTitle:@"" action:@selector(pasteCheckboxChanged:)];
    [self addSettingsRowTo:card y:94 symbol:@"text.cursor" title:@"Paste after transcription" subtitle:@"Insert the transcript into the focused app when possible." control:self.pasteCheckbox];

    [self refreshWindowControls];
}

- (void)renderHotkeys {
    [self addHeader:@"Hotkeys" subtitle:@"Keep the MVP simple: one reliable global shortcut, then productize from there."];
    NSView *card = [self card:NSMakeRect(40, 76, 916, 534)];
    [self.contentView addSubview:card];

    [self addSettingsRowTo:card y:438 symbol:@"waveform" title:@"Dictation" subtitle:@"Press once to record. Press again to transcribe and paste." control:[self keycap:@"Control + Option + Space"]];
    [self addSettingsRowTo:card y:352 symbol:@"keyboard" title:@"Push to talk" subtitle:@"Recommended for v2 after the core paste flow feels solid." control:[self keycap:@"Planned"]];
    [self addSettingsRowTo:card y:266 symbol:@"gearshape" title:@"Settings" subtitle:@"Open the LocalTalk window from anywhere." control:[self keycap:@"Command + 0"]];
    [self addSettingsRowTo:card y:180 symbol:@"lock.shield" title:@"Accessibility" subtitle:@"Needed for automatic paste into Claude, Codex, Chrome, and other apps." control:[self compactButton:@"Request Access" action:@selector(requestAccessibilityPermission:)]];
}

- (void)renderPreferences {
    [self addHeader:@"Preferences" subtitle:@"Tune the desktop behavior without sending your voice outside this Mac."];
    NSView *card = [self card:NSMakeRect(40, 46, 916, 564)];
    [self.contentView addSubview:card];

    self.menuBarCheckbox = [self switchButtonWithTitle:@"" action:@selector(menuBarCheckboxChanged:)];
    [self addSettingsRowTo:card y:466 symbol:@"menubar.rectangle" title:@"Show in Menu Bar" subtitle:@"Keep quick controls available near the clock." control:self.menuBarCheckbox];

    self.dockCheckbox = [self switchButtonWithTitle:@"" action:@selector(dockCheckboxChanged:)];
    [self addSettingsRowTo:card y:392 symbol:@"dock.rectangle" title:@"Show in Dock" subtitle:@"Keep LocalTalk visible in the Dock and app switcher." control:self.dockCheckbox];

    self.clipboardCheckbox = [self switchButtonWithTitle:@"" action:@selector(clipboardCheckboxChanged:)];
    [self addSettingsRowTo:card y:318 symbol:@"clipboard" title:@"Copy to Clipboard" subtitle:@"Also copy the transcript after dictation finishes." control:self.clipboardCheckbox];

    self.soundCheckbox = [self switchButtonWithTitle:@"" action:@selector(soundCheckboxChanged:)];
    [self addSettingsRowTo:card y:244 symbol:@"music.note" title:@"Interaction Sounds" subtitle:@"Play a subtle sound when recording starts and stops." control:self.soundCheckbox];

    self.hudLocationPopup = [self popupWithAction:@selector(selectHUDLocationFromPopup:)];
    [self addPopupItem:@"Bottom" value:@"bottom" toPopup:self.hudLocationPopup];
    [self addPopupItem:@"Center" value:@"center" toPopup:self.hudLocationPopup];
    [self addSettingsRowTo:card y:170 symbol:@"rectangle.inset.filled.and.person.filled" title:@"Dictation Bar Location" subtitle:@"Choose a default, or drag the floating bar to pin it." control:self.hudLocationPopup];

    NSView *pathControl = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 380, 34)];
    self.whisperPathField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 266, 34)];
    self.whisperPathField.delegate = self;
    self.whisperPathField.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightMedium];
    self.whisperPathField.textColor = LTColor(232, 234, 231, 1);
    self.whisperPathField.backgroundColor = LTColor(22, 23, 23, 1);
    self.whisperPathField.bezelStyle = NSTextFieldSquareBezel;
    [pathControl addSubview:self.whisperPathField];
    [pathControl addSubview:[self compactButton:@"Detect" action:@selector(detectWhisper:)]];
    pathControl.subviews.lastObject.frame = NSMakeRect(278, 0, 102, 34);
    [self addSettingsRowTo:card y:96 symbol:@"terminal" title:@"Whisper Executable" subtitle:@"Use a local whisper command or full executable path." control:pathControl];

    [self refreshWindowControls];
}

- (void)buildHUD {
    NSRect frame = NSMakeRect(0, 0, 360, 76);
    self.hudPanel = [[NSPanel alloc] initWithContentRect:frame
                                               styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];
    self.hudPanel.releasedWhenClosed = NO;
    self.hudPanel.level = NSStatusWindowLevel;
    self.hudPanel.opaque = NO;
    self.hudPanel.backgroundColor = NSColor.clearColor;
    self.hudPanel.hasShadow = YES;
    self.hudPanel.movableByWindowBackground = YES;
    self.hudPanel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;

    LocalTalkHUDShellView *shell = [[LocalTalkHUDShellView alloc] initWithFrame:frame];
    shell.wantsLayer = YES;
    shell.layer.cornerRadius = 19;
    shell.layer.backgroundColor = LTColor(13, 16, 20, 0.97).CGColor;
    shell.layer.borderColor = LTColor(46, 73, 91, 1).CGColor;
    shell.layer.borderWidth = 1;
    shell.layer.shadowColor = NSColor.blackColor.CGColor;
    shell.layer.shadowOpacity = 0.28;
    shell.layer.shadowRadius = 18;
    shell.layer.shadowOffset = NSMakeSize(0, 10);

    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = shell.bounds;
    gradient.cornerRadius = 19;
    gradient.startPoint = CGPointMake(0, 1);
    gradient.endPoint = CGPointMake(1, 0);
    gradient.colors = @[
        (__bridge id)LTColor(17, 22, 27, 0.98).CGColor,
        (__bridge id)LTColor(9, 11, 14, 0.98).CGColor,
        (__bridge id)LTColor(18, 34, 46, 0.96).CGColor
    ];
    [shell.layer insertSublayer:gradient atIndex:0];

    CALayer *shine = [CALayer layer];
    shine.frame = NSMakeRect(1, frame.size.height - 2, frame.size.width - 2, 1);
    shine.backgroundColor = LTColor(255, 255, 255, 0.14).CGColor;
    [shell.layer addSublayer:shine];
    self.hudPanel.contentView = shell;

    self.hudIconView = [[NSImageView alloc] initWithFrame:NSMakeRect(18, 21, 34, 34)];
    self.hudIconView.image = [self brandImage];
    self.hudIconView.imageScaling = NSImageScaleProportionallyUpOrDown;
    self.hudIconView.wantsLayer = YES;
    self.hudIconView.layer.cornerRadius = 8;
    self.hudIconView.layer.masksToBounds = YES;
    self.hudIconView.layer.borderColor = LTColor(255, 255, 255, 0.10).CGColor;
    self.hudIconView.layer.borderWidth = 1;
    [shell addSubview:self.hudIconView];

    self.hudTitleLabel = [self label:@"Listening" frame:NSMakeRect(68, 42, 150, 20) font:[NSFont systemFontOfSize:15 weight:NSFontWeightBold] color:NSColor.whiteColor];
    self.hudDetailLabel = [self label:@"LocalTalk is recording" frame:NSMakeRect(68, 23, 166, 17) font:[NSFont systemFontOfSize:11 weight:NSFontWeightMedium] color:LTColor(166, 178, 188, 1)];
    [shell addSubview:self.hudTitleLabel];
    [shell addSubview:self.hudDetailLabel];

    self.hudModeLabel = [self badgeLabel:@"LOCAL" frame:NSMakeRect(68, 7, 48, 17)];
    self.hudLanguageLabel = [self badgeLabel:@"EN" frame:NSMakeRect(122, 7, 42, 17)];
    [shell addSubview:self.hudModeLabel];
    [shell addSubview:self.hudLanguageLabel];

    self.hudBars = [NSMutableArray array];
    NSArray<NSNumber *> *scales = @[@0.30, @0.54, @0.82, @1.0, @0.74, @0.50, @0.30];
    CGFloat barX = 244;
    CGFloat baseY = 17;
    for (NSUInteger index = 0; index < scales.count; index += 1) {
        CALayer *bar = [CALayer layer];
        bar.bounds = CGRectMake(0, 0, 4, 42);
        bar.position = CGPointMake(barX + index * 8, baseY);
        bar.anchorPoint = CGPointMake(0.5, 0);
        bar.cornerRadius = 2;
        bar.masksToBounds = YES;
        bar.backgroundColor = (index >= 2 && index <= 4 ? LTAccentColor(1) : LTColor(93, 114, 128, 0.68)).CGColor;
        bar.transform = CATransform3DMakeScale(1, scales[index].doubleValue, 1);
        [shell.layer addSublayer:bar];
        [self.hudBars addObject:bar];
    }

    self.hudSpinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(304, 28, 20, 20)];
    self.hudSpinner.style = NSProgressIndicatorStyleSpinning;
    self.hudSpinner.controlSize = NSControlSizeSmall;
    self.hudSpinner.displayedWhenStopped = NO;
    [shell addSubview:self.hudSpinner];

    self.hudDragHandleView = [[NSImageView alloc] initWithFrame:NSMakeRect(334, 30, 14, 14)];
    self.hudDragHandleView.image = [NSImage imageWithSystemSymbolName:@"line.3.horizontal" accessibilityDescription:@"Drag"];
    self.hudDragHandleView.contentTintColor = LTColor(126, 144, 156, 1);
    [shell addSubview:self.hudDragHandleView];
}

- (void)positionHUD {
    NSScreen *screen = NSScreen.mainScreen ?: NSScreen.screens.firstObject;
    if (screen == nil) {
        return;
    }
    NSRect visible = screen.visibleFrame;
    NSRect frame = self.hudPanel.frame;
    BOOL useCustom = [NSUserDefaults.standardUserDefaults boolForKey:LocalTalkHUDUseCustomPositionKey];
    if (useCustom) {
        CGFloat customX = [NSUserDefaults.standardUserDefaults doubleForKey:LocalTalkHUDCustomXKey];
        CGFloat customY = [NSUserDefaults.standardUserDefaults doubleForKey:LocalTalkHUDCustomYKey];
        NSPoint centerPoint = NSMakePoint(customX + frame.size.width / 2.0, customY + frame.size.height / 2.0);
        if (NSPointInRect(centerPoint, visible)) {
            [self.hudPanel setFrameOrigin:NSMakePoint(customX, customY)];
            return;
        }
        [NSUserDefaults.standardUserDefaults setBool:NO forKey:LocalTalkHUDUseCustomPositionKey];
    }

    CGFloat x = NSMidX(visible) - frame.size.width / 2.0;
    CGFloat y;
    NSString *location = [NSUserDefaults.standardUserDefaults stringForKey:LocalTalkHUDLocationKey] ?: @"bottom";
    if ([location isEqualToString:@"center"]) {
        y = NSMidY(visible) - frame.size.height / 2.0;
    } else {
        y = visible.origin.y + 42;
    }
    [self.hudPanel setFrameOrigin:NSMakePoint(x, y)];
}

- (void)showHUDTitle:(NSString *)title detail:(NSString *)detail state:(LocalTalkRunState)state {
    self.hudTitleLabel.stringValue = title ?: @"LocalTalk";
    self.hudDetailLabel.stringValue = detail ?: @"";
    self.hudIconView.image = [self brandImage];
    self.hudModeLabel.stringValue = state == LocalTalkRunStateFailed ? @"CHECK" : @"LOCAL";
    self.hudLanguageLabel.stringValue = [self languageBadgeText];
    BOOL failed = state == LocalTalkRunStateFailed;
    NSColor *badgeColor = failed ? LTColor(255, 118, 112, 1) : LTAccentTextColor(1);
    NSColor *badgeFill = failed ? LTColor(255, 118, 112, 0.10) : LTAccentColor(0.11);
    NSColor *badgeBorder = failed ? LTColor(255, 118, 112, 0.28) : LTAccentColor(0.25);
    self.hudModeLabel.textColor = badgeColor;
    self.hudLanguageLabel.textColor = LTAccentTextColor(1);
    self.hudModeLabel.layer.backgroundColor = badgeFill.CGColor;
    self.hudModeLabel.layer.borderColor = badgeBorder.CGColor;
    self.hudLanguageLabel.layer.backgroundColor = LTAccentColor(0.09).CGColor;
    self.hudLanguageLabel.layer.borderColor = LTAccentColor(0.22).CGColor;
    [self updateHUDBarsForState:state level:0.45];
    if (state == LocalTalkRunStateTranscribing) {
        [self.hudSpinner startAnimation:nil];
    } else {
        [self.hudSpinner stopAnimation:nil];
    }
    [self positionHUD];
    BOOL shouldAnimateIn = !self.hudPanel.visible || self.hudPanel.alphaValue < 0.99;
    NSRect targetFrame = self.hudPanel.frame;
    if (shouldAnimateIn) {
        self.hudPanel.alphaValue = 0;
        [self.hudPanel setFrame:NSOffsetRect(targetFrame, 0, -8) display:NO];
        [self.hudPanel orderFrontRegardless];
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.16;
            context.allowsImplicitAnimation = YES;
            context.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.16 :1.0 :0.30 :1.0];
            self.hudPanel.animator.alphaValue = 1;
            [self.hudPanel.animator setFrame:targetFrame display:YES];
        } completionHandler:nil];
    } else {
        self.hudPanel.alphaValue = 1;
        [self.hudPanel orderFrontRegardless];
    }
}

- (void)hideHUDAfterDelay:(NSTimeInterval)delay {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.runState != LocalTalkRunStateRecording && self.runState != LocalTalkRunStateTranscribing) {
            [self hideHUDAnimated];
        }
    });
}

- (void)hideHUDAnimated {
    if (!self.hudPanel.visible) {
        return;
    }
    NSRect startFrame = self.hudPanel.frame;
    NSRect endFrame = NSOffsetRect(startFrame, 0, -7);
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.14;
        context.allowsImplicitAnimation = YES;
        context.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.32 :0.0 :0.67 :0.0];
        self.hudPanel.animator.alphaValue = 0;
        [self.hudPanel.animator setFrame:endFrame display:YES];
    } completionHandler:^{
        if (self.runState == LocalTalkRunStateRecording || self.runState == LocalTalkRunStateTranscribing) {
            self.hudPanel.alphaValue = 1;
            return;
        }
        [self.hudPanel orderOut:nil];
        self.hudPanel.alphaValue = 1;
        [self.hudPanel setFrame:startFrame display:NO];
    }];
}

- (BOOL)isRecordingCaptureActive {
    return self.recorder.recording || self.recordingTimer != nil;
}

- (BOOL)deferSettingsActionWhileRecording:(NSString *)actionName {
    if (![self isRecordingCaptureActive]) {
        return NO;
    }
    [self setStatus:@"Listening" detail:[NSString stringWithFormat:@"Stop recording before %@.", actionName] state:LocalTalkRunStateRecording];
    [self showHUDTitle:@"Listening" detail:@"Stop recording before changing settings" state:LocalTalkRunStateRecording];
    return YES;
}

- (void)showMainWindow:(id)sender {
    if (!self.mainWindow.visible) {
        [self.mainWindow center];
    }
    [NSApp activateIgnoringOtherApps:YES];
    [self.mainWindow makeKeyAndOrderFront:nil];
}

- (void)registerHotKey {
    EventHotKeyID hotKeyID;
    hotKeyID.signature = LocalTalkFourCharCode("LTLK");
    hotKeyID.id = 1;
    EventTypeSpec eventType = { kEventClassKeyboard, kEventHotKeyPressed };
    OSStatus installStatus = InstallApplicationEventHandler(&LocalTalkHotKeyHandler, 1, &eventType, (__bridge void *)self, &_hotKeyHandlerRef);
    OSStatus registerStatus = RegisterEventHotKey(kVK_Space, controlKey | optionKey, hotKeyID, GetApplicationEventTarget(), 0, &_hotKeyRef);
    if (installStatus != noErr || registerStatus != noErr) {
        [self appendActivity:@"Global hotkey registration failed"];
    }
}

- (void)toggleRecording:(id)sender {
    if (self.runState == LocalTalkRunStateTranscribing) {
        [self setStatus:@"Still transcribing" detail:@"Wait for the local model to finish." state:LocalTalkRunStateTranscribing];
        return;
    }
    if (self.runState == LocalTalkRunStateRecording) {
        [self stopRecordingAndTranscribe];
        return;
    }
    [self requestMicrophonePermissionThenStart];
}

- (void)requestMicrophonePermissionThenStart {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    if (status == AVAuthorizationStatusAuthorized) {
        [self startRecording];
        return;
    }
    if (status == AVAuthorizationStatusDenied || status == AVAuthorizationStatusRestricted) {
        [self setStatus:@"Microphone blocked" detail:@"Enable microphone access in System Settings." state:LocalTalkRunStateFailed];
        [self showHUDTitle:@"Microphone blocked" detail:@"Enable access in System Settings" state:LocalTalkRunStateFailed];
        [self hideHUDAfterDelay:2.0];
        return;
    }

    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (granted) {
                [self startRecording];
            } else {
                [self setStatus:@"Microphone denied" detail:@"LocalTalk cannot record without microphone access." state:LocalTalkRunStateFailed];
            }
        });
    }];
}

- (void)startRecording {
    if (self.recorder.recording) {
        return;
    }

    NSURL *directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"LocalTalk/Recordings"] isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *fileName = [NSString stringWithFormat:@"localtalk-%lld.wav", (long long)(NSDate.date.timeIntervalSince1970 * 1000)];
    self.recordingURL = [directory URLByAppendingPathComponent:fileName];

    NSDictionary *settings = @{
        AVFormatIDKey: @(kAudioFormatLinearPCM),
        AVSampleRateKey: @16000.0,
        AVNumberOfChannelsKey: @1,
        AVLinearPCMBitDepthKey: @16,
        AVLinearPCMIsFloatKey: @NO,
        AVLinearPCMIsBigEndianKey: @NO
    };

    NSError *error = nil;
    self.recorder = [[AVAudioRecorder alloc] initWithURL:self.recordingURL settings:settings error:&error];
    self.recorder.delegate = self;
    self.recorder.meteringEnabled = YES;
    if (error != nil || ![self.recorder prepareToRecord] || ![self.recorder record]) {
        [self setStatus:@"Recording failed" detail:error.localizedDescription ?: @"Could not start the microphone." state:LocalTalkRunStateFailed];
        [self showHUDTitle:@"Recording failed" detail:@"Could not start the microphone" state:LocalTalkRunStateFailed];
        [self hideHUDAfterDelay:2.0];
        return;
    }

    self.targetAppName = NSWorkspace.sharedWorkspace.frontmostApplication.localizedName ?: @"Focused app";
    self.recordingStartDate = NSDate.date;
    if ([NSUserDefaults.standardUserDefaults boolForKey:LocalTalkInteractionSoundsKey]) {
        NSBeep();
    }
    [self setStatus:@"Listening" detail:@"Press Control + Option + Space again to stop." state:LocalTalkRunStateRecording];
    [self showHUDTitle:@"Listening" detail:[NSString stringWithFormat:@"Dictating into %@", self.targetAppName] state:LocalTalkRunStateRecording];
    self.hudLastDetailTick = -1;
    self.recordingTimer = [NSTimer scheduledTimerWithTimeInterval:0.12 target:self selector:@selector(updateRecordingTimer:) userInfo:nil repeats:YES];
}

- (void)updateRecordingTimer:(NSTimer *)timer {
    NSTimeInterval elapsed = fabs(self.recordingStartDate.timeIntervalSinceNow);
    NSTimeInterval detailTick = floor(elapsed * 2.0) / 2.0;
    if (self.hudLastDetailTick < 0 || fabs(detailTick - self.hudLastDetailTick) > 0.01) {
        self.hudDetailLabel.stringValue = [NSString stringWithFormat:@"%.1fs - %@", detailTick, self.targetAppName ?: @"Focused app"];
        self.hudLastDetailTick = detailTick;
    }
    [self.recorder updateMeters];
    CGFloat averagePower = [self.recorder averagePowerForChannel:0];
    CGFloat normalizedLevel = MAX(0.12, MIN(1.0, (averagePower + 58.0) / 58.0));
    [self updateHUDBarsForState:LocalTalkRunStateRecording level:normalizedLevel];
}

- (void)stopRecordingAndTranscribe {
    NSTimeInterval elapsed = fabs(self.recordingStartDate.timeIntervalSinceNow);
    self.sessionRecordedSeconds += elapsed;
    [self.recordingTimer invalidate];
    self.recordingTimer = nil;
    [self.recorder stop];
    self.recorder = nil;
    if ([NSUserDefaults.standardUserDefaults boolForKey:LocalTalkInteractionSoundsKey]) {
        NSBeep();
    }

    NSURL *audioURL = self.recordingURL;
    [self setStatus:@"Transcribing" detail:@"Running the local Whisper command." state:LocalTalkRunStateTranscribing];
    [self showHUDTitle:@"Transcribing" detail:@"Local model is working" state:LocalTalkRunStateTranscribing];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        NSString *text = [self transcribeAudioAtURL:audioURL error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (text.length == 0 || error != nil) {
                [self setStatus:@"Transcription failed" detail:error.localizedDescription ?: @"Whisper returned no text." state:LocalTalkRunStateFailed];
                [self showHUDTitle:@"Transcription failed" detail:@"Check Whisper executable and model" state:LocalTalkRunStateFailed];
                [self hideHUDAfterDelay:2.5];
            } else {
                [self finishTranscription:text];
            }
        });
    });
}

- (NSString *)transcribeAudioAtURL:(NSURL *)audioURL error:(NSError **)error {
    NSString *configuredPath = [NSUserDefaults.standardUserDefaults stringForKey:LocalTalkWhisperPathKey];
    if (configuredPath.length == 0) {
        configuredPath = LocalTalkDefaultWhisperPath();
    }
    NSString *model = [NSUserDefaults.standardUserDefaults stringForKey:LocalTalkModelNameKey] ?: @"base.en";
    NSString *taskName = [NSUserDefaults.standardUserDefaults stringForKey:LocalTalkTaskNameKey] ?: @"transcribe";
    NSString *language = [NSUserDefaults.standardUserDefaults stringForKey:LocalTalkLanguageCodeKey] ?: @"en";
    NSURL *outputDirectory = audioURL.URLByDeletingLastPathComponent;
    NSString *baseName = [audioURL.lastPathComponent stringByDeletingPathExtension];
    NSURL *txtURL = [outputDirectory URLByAppendingPathComponent:[baseName stringByAppendingPathExtension:@"txt"]];

    NSMutableArray<NSString *> *arguments = [NSMutableArray arrayWithArray:@[
        audioURL.path,
        @"--model", model,
        @"--task", taskName,
        @"--output_format", @"txt",
        @"--output_dir", outputDirectory.path
    ]];
    if (![language isEqualToString:@"auto"]) {
        [arguments addObjectsFromArray:@[@"--language", language]];
    }

    NSTask *task = [[NSTask alloc] init];
    if ([configuredPath containsString:@"/"]) {
        task.launchPath = configuredPath;
    } else {
        task.launchPath = @"/usr/bin/env";
        [arguments insertObject:configuredPath atIndex:0];
    }
    task.arguments = arguments;
    task.environment = @{ @"PATH": LocalTalkSearchPath() };

    NSPipe *stdoutPipe = [NSPipe pipe];
    NSPipe *stderrPipe = [NSPipe pipe];
    task.standardOutput = stdoutPipe;
    task.standardError = stderrPipe;

    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"LocalTalk" code:1 userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Failed to launch Whisper"}];
        }
        return @"";
    }

    NSData *stdoutData = [stdoutPipe.fileHandleForReading readDataToEndOfFile];
    NSData *stderrData = [stderrPipe.fileHandleForReading readDataToEndOfFile];
    NSString *stdoutText = [[NSString alloc] initWithData:stdoutData encoding:NSUTF8StringEncoding] ?: @"";
    NSString *stderrText = [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding] ?: @"";

    if (task.terminationStatus != 0) {
        if (error != NULL) {
            NSString *message = stderrText.length > 0 ? stderrText : @"Whisper exited with an error.";
            *error = [NSError errorWithDomain:@"LocalTalk" code:task.terminationStatus userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return @"";
    }

    NSString *fileText = [NSString stringWithContentsOfURL:txtURL encoding:NSUTF8StringEncoding error:nil];
    NSString *rawText = fileText.length > 0 ? fileText : stdoutText;
    return [rawText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (void)finishTranscription:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        [self setStatus:@"No speech detected" detail:@"Try again with a little more volume." state:LocalTalkRunStateFailed];
        return;
    }

    self.lastTranscript = trimmed;
    NSUInteger words = [self wordCount:trimmed];
    self.sessionTranscriptCount += 1;
    self.sessionWordCount += words;

    NSMutableDictionary *item = [@{
        @"text": trimmed,
        @"app": self.targetAppName ?: @"Focused app",
        @"date": NSDate.date,
        @"model": [NSUserDefaults.standardUserDefaults stringForKey:LocalTalkModelNameKey] ?: @"base.en"
    } mutableCopy];
    [self.history insertObject:item atIndex:0];
    while (self.history.count > 50) {
        [self.history removeLastObject];
    }
    [self saveHistory];

    BOOL shouldCopy = [NSUserDefaults.standardUserDefaults boolForKey:LocalTalkCopyResultKey];
    BOOL shouldPaste = [NSUserDefaults.standardUserDefaults boolForKey:LocalTalkPasteResultKey];
    if (shouldCopy || shouldPaste) {
        [self placeTextOnClipboard:trimmed];
    }
    if (shouldPaste) {
        [self pasteTextIntoFocusedApp:trimmed];
    }

    NSString *detail = shouldPaste ? @"Pasted into the focused app." : @"Transcript copied locally.";
    [self setStatus:@"Transcript ready" detail:detail state:LocalTalkRunStateIdle];
    [self showHUDTitle:@"Transcript ready" detail:[NSString stringWithFormat:@"%lu words", (unsigned long)words] state:LocalTalkRunStateIdle];
    [self hideHUDAfterDelay:1.4];
    [self renderCurrentScreen];
}

- (void)pasteTextIntoFocusedApp:(NSString *)text {
    AXUIElementRef systemWide = AXUIElementCreateSystemWide();
    CFTypeRef focused = NULL;
    AXError focusError = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute, &focused);
    if (focusError == kAXErrorSuccess && focused != NULL) {
        AXError setError = AXUIElementSetAttributeValue((AXUIElementRef)focused, kAXSelectedTextAttribute, (__bridge CFTypeRef)text);
        CFRelease(focused);
        CFRelease(systemWide);
        if (setError == kAXErrorSuccess) {
            return;
        }
    } else {
        CFRelease(systemWide);
    }

    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateCombinedSessionState);
    CGEventRef keyDown = CGEventCreateKeyboardEvent(source, kVK_ANSI_V, true);
    CGEventRef keyUp = CGEventCreateKeyboardEvent(source, kVK_ANSI_V, false);
    CGEventSetFlags(keyDown, kCGEventFlagMaskCommand);
    CGEventSetFlags(keyUp, kCGEventFlagMaskCommand);
    CGEventPost(kCGHIDEventTap, keyDown);
    CGEventPost(kCGHIDEventTap, keyUp);
    CFRelease(keyDown);
    CFRelease(keyUp);
    CFRelease(source);
}

- (void)placeTextOnClipboard:(NSString *)text {
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard setString:text forType:NSPasteboardTypeString];
}

- (void)placeLastTranscriptOnClipboard:(id)sender {
    if (self.lastTranscript.length == 0) {
        [self setStatus:@"No transcript yet" detail:@"Record once before copying." state:LocalTalkRunStateIdle];
        return;
    }
    [self placeTextOnClipboard:self.lastTranscript];
    [self setStatus:@"Copied" detail:@"Last transcript copied to the clipboard." state:LocalTalkRunStateIdle];
}

- (void)requestMicrophonePermission:(id)sender {
    if ([self deferSettingsActionWhileRecording:@"requesting microphone access"]) {
        return;
    }
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setStatus:granted ? @"Microphone allowed" : @"Microphone denied"
                     detail:granted ? @"LocalTalk can record on this Mac." : @"Enable access in System Settings."
                      state:granted ? LocalTalkRunStateIdle : LocalTalkRunStateFailed];
        });
    }];
}

- (void)requestAccessibilityPermission:(id)sender {
    if ([self deferSettingsActionWhileRecording:@"requesting Accessibility access"]) {
        return;
    }
    NSDictionary *options = @{ (__bridge id)kAXTrustedCheckOptionPrompt: @YES };
    BOOL trusted = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
    [self setStatus:trusted ? @"Accessibility allowed" : @"Accessibility requested"
             detail:trusted ? @"Automatic paste is ready." : @"Approve LocalTalk in System Settings."
              state:trusted ? LocalTalkRunStateIdle : LocalTalkRunStateFailed];
}

- (void)detectWhisper:(id)sender {
    if ([self deferSettingsActionWhileRecording:@"detecting Whisper"]) {
        return;
    }
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/env";
    task.arguments = @[@"which", @"whisper"];
    task.environment = @{ @"PATH": LocalTalkSearchPath() };
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        [self setStatus:@"Whisper not found" detail:@"Install openai-whisper or enter the executable path." state:LocalTalkRunStateFailed];
        return;
    }
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    NSString *path = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (task.terminationStatus == 0 && path.length > 0) {
        [NSUserDefaults.standardUserDefaults setObject:path forKey:LocalTalkWhisperPathKey];
        self.whisperPathField.stringValue = path;
        [self setStatus:@"Whisper detected" detail:path state:LocalTalkRunStateIdle];
    } else {
        [self setStatus:@"Whisper not found" detail:@"Enter the executable path in Preferences." state:LocalTalkRunStateFailed];
    }
}

- (void)togglePasteResult:(id)sender {
    BOOL current = [NSUserDefaults.standardUserDefaults boolForKey:LocalTalkPasteResultKey];
    [NSUserDefaults.standardUserDefaults setBool:!current forKey:LocalTalkPasteResultKey];
    [self refreshStatusMenu];
    [self refreshWindowControls];
}

- (void)pasteCheckboxChanged:(NSButton *)sender {
    [NSUserDefaults.standardUserDefaults setBool:(sender.state == NSControlStateValueOn) forKey:LocalTalkPasteResultKey];
    [self refreshStatusMenu];
}

- (void)clipboardCheckboxChanged:(NSButton *)sender {
    [NSUserDefaults.standardUserDefaults setBool:(sender.state == NSControlStateValueOn) forKey:LocalTalkCopyResultKey];
}

- (void)menuBarCheckboxChanged:(NSButton *)sender {
    [NSUserDefaults.standardUserDefaults setBool:(sender.state == NSControlStateValueOn) forKey:LocalTalkShowMenuBarKey];
    [self buildStatusMenuIfNeeded];
}

- (void)dockCheckboxChanged:(NSButton *)sender {
    [NSUserDefaults.standardUserDefaults setBool:(sender.state == NSControlStateValueOn) forKey:LocalTalkShowDockKey];
    [self applyDockPreference];
}

- (void)soundCheckboxChanged:(NSButton *)sender {
    [NSUserDefaults.standardUserDefaults setBool:(sender.state == NSControlStateValueOn) forKey:LocalTalkInteractionSoundsKey];
}

- (void)selectTaskFromPopup:(NSPopUpButton *)sender {
    NSString *value = sender.selectedItem.representedObject ?: @"transcribe";
    [NSUserDefaults.standardUserDefaults setObject:value forKey:LocalTalkTaskNameKey];
}

- (void)selectModelFromPopup:(NSPopUpButton *)sender {
    NSString *value = sender.selectedItem.representedObject ?: @"base.en";
    [NSUserDefaults.standardUserDefaults setObject:value forKey:LocalTalkModelNameKey];
    [self renderCurrentScreen];
}

- (void)selectLanguageFromPopup:(NSPopUpButton *)sender {
    NSString *value = sender.selectedItem.representedObject ?: @"en";
    [NSUserDefaults.standardUserDefaults setObject:value forKey:LocalTalkLanguageCodeKey];
    [self buildStatusMenuIfNeeded];
}

- (void)selectLanguageMenuItem:(NSMenuItem *)sender {
    NSString *value = sender.representedObject ?: @"en";
    [NSUserDefaults.standardUserDefaults setObject:value forKey:LocalTalkLanguageCodeKey];
    [self buildStatusMenuIfNeeded];
    [self refreshWindowControls];
    if (self.selectedScreen == LocalTalkScreenDictation) {
        [self renderCurrentScreen];
    }
}

- (void)selectHUDLocationFromPopup:(NSPopUpButton *)sender {
    NSString *value = sender.selectedItem.representedObject ?: @"bottom";
    [NSUserDefaults.standardUserDefaults setObject:value forKey:LocalTalkHUDLocationKey];
    [NSUserDefaults.standardUserDefaults setBool:NO forKey:LocalTalkHUDUseCustomPositionKey];
    [self positionHUD];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    if (notification.object == self.whisperPathField) {
        [NSUserDefaults.standardUserDefaults setObject:self.whisperPathField.stringValue ?: @"" forKey:LocalTalkWhisperPathKey];
    }
}

- (void)setStatus:(NSString *)status detail:(NSString *)detail state:(LocalTalkRunState)state {
    LocalTalkRunState effectiveState = state;
    if ([self isRecordingCaptureActive] && state != LocalTalkRunStateRecording && state != LocalTalkRunStateTranscribing) {
        effectiveState = LocalTalkRunStateRecording;
    }

    self.runState = effectiveState;
    self.currentStatus = status ?: @"Ready";
    [self appendActivity:detail.length > 0 ? [NSString stringWithFormat:@"%@ - %@", self.currentStatus, detail] : self.currentStatus];
    if (self.statusTitleLabel != nil) {
        self.statusTitleLabel.stringValue = self.currentStatus;
    }
    if (self.statusDetailLabel != nil) {
        self.statusDetailLabel.stringValue = detail ?: @"";
    }
    if (self.primaryRecordButton != nil) {
        NSString *buttonTitle = effectiveState == LocalTalkRunStateRecording ? @"Stop and Transcribe" : @"Start Recording";
        self.primaryRecordButton.attributedTitle = [[NSAttributedString alloc] initWithString:buttonTitle attributes:@{
            NSForegroundColorAttributeName: NSColor.blackColor,
            NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightBold]
        }];
    }
    if (self.statusSpinner != nil) {
        effectiveState == LocalTalkRunStateTranscribing ? [self.statusSpinner startAnimation:nil] : [self.statusSpinner stopAnimation:nil];
    }
    [self refreshStatusMenu];
    if (effectiveState != LocalTalkRunStateRecording && effectiveState != LocalTalkRunStateTranscribing && self.hudPanel.visible) {
        [self hideHUDAfterDelay:1.2];
    }
}

- (void)refreshStatusMenu {
    if (self.statusTextItem != nil) {
        self.statusTextItem.title = self.currentStatus ?: @"Ready";
    }
    if (self.statusToggleItem != nil) {
        self.statusToggleItem.title = self.runState == LocalTalkRunStateRecording ? @"Stop and Transcribe" : @"Start Recording";
    }
    if (self.statusPasteItem != nil) {
        self.statusPasteItem.state = [NSUserDefaults.standardUserDefaults boolForKey:LocalTalkPasteResultKey] ? NSControlStateValueOn : NSControlStateValueOff;
    }
    if (self.statusItem != nil) {
        NSString *symbol = @"mic";
        if (self.runState == LocalTalkRunStateRecording) {
            symbol = @"mic.circle.fill";
        } else if (self.runState == LocalTalkRunStateTranscribing) {
            symbol = @"waveform";
        } else if (self.runState == LocalTalkRunStateFailed) {
            symbol = @"exclamationmark.circle";
        }
        self.statusItem.button.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:@"LocalTalk"];
        self.statusItem.button.image.template = YES;
    }
}

- (void)refreshWindowControls {
    NSString *taskName = [NSUserDefaults.standardUserDefaults stringForKey:LocalTalkTaskNameKey] ?: @"transcribe";
    NSString *model = [NSUserDefaults.standardUserDefaults stringForKey:LocalTalkModelNameKey] ?: @"base.en";
    NSString *language = [NSUserDefaults.standardUserDefaults stringForKey:LocalTalkLanguageCodeKey] ?: @"en";
    NSString *hudLocation = [NSUserDefaults.standardUserDefaults stringForKey:LocalTalkHUDLocationKey] ?: @"bottom";
    [self selectPopup:self.modePopup representedObject:taskName];
    [self selectPopup:self.modelPopup representedObject:model];
    [self selectPopup:self.languagePopup representedObject:language];
    [self selectPopup:self.hudLocationPopup representedObject:hudLocation];
    self.pasteCheckbox.state = [NSUserDefaults.standardUserDefaults boolForKey:LocalTalkPasteResultKey] ? NSControlStateValueOn : NSControlStateValueOff;
    self.clipboardCheckbox.state = [NSUserDefaults.standardUserDefaults boolForKey:LocalTalkCopyResultKey] ? NSControlStateValueOn : NSControlStateValueOff;
    self.menuBarCheckbox.state = [NSUserDefaults.standardUserDefaults boolForKey:LocalTalkShowMenuBarKey] ? NSControlStateValueOn : NSControlStateValueOff;
    self.dockCheckbox.state = [NSUserDefaults.standardUserDefaults boolForKey:LocalTalkShowDockKey] ? NSControlStateValueOn : NSControlStateValueOff;
    self.soundCheckbox.state = [NSUserDefaults.standardUserDefaults boolForKey:LocalTalkInteractionSoundsKey] ? NSControlStateValueOn : NSControlStateValueOff;
    self.whisperPathField.stringValue = [NSUserDefaults.standardUserDefaults stringForKey:LocalTalkWhisperPathKey] ?: @"";
}

- (void)selectPopup:(NSPopUpButton *)popup representedObject:(NSString *)value {
    if (popup == nil || value == nil) {
        return;
    }
    for (NSMenuItem *item in popup.itemArray) {
        if ([item.representedObject isEqual:value]) {
            [popup selectItem:item];
            return;
        }
    }
}

- (NSImage *)brandImage {
    static NSImage *cachedImage = nil;
    if (cachedImage != nil) {
        return cachedImage;
    }
    NSString *imagePath = [NSBundle.mainBundle pathForResource:@"LocalTalkLogo" ofType:@"png"];
    if (imagePath.length > 0) {
        cachedImage = [[NSImage alloc] initWithContentsOfFile:imagePath];
    }
    if (cachedImage == nil) {
        cachedImage = [NSImage imageWithSystemSymbolName:@"waveform.circle.fill" accessibilityDescription:@"LocalTalk"];
    }
    return cachedImage;
}

- (NSString *)languageBadgeText {
    NSString *language = [NSUserDefaults.standardUserDefaults stringForKey:LocalTalkLanguageCodeKey] ?: @"en";
    if ([language isEqualToString:@"tl"]) {
        return @"FIL";
    }
    if ([language isEqualToString:@"auto"]) {
        return @"AUTO";
    }
    if ([language isEqualToString:@"zh"]) {
        return @"ZH";
    }
    return language.uppercaseString;
}

- (NSTextField *)badgeLabel:(NSString *)text frame:(NSRect)frame {
    NSTextField *badge = [self label:text frame:frame font:[NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightBold] color:LTAccentTextColor(1)];
    badge.alignment = NSTextAlignmentCenter;
    badge.wantsLayer = YES;
    badge.layer.cornerRadius = frame.size.height / 2.0;
    badge.layer.backgroundColor = LTAccentColor(0.10).CGColor;
    badge.layer.borderColor = LTAccentColor(0.22).CGColor;
    badge.layer.borderWidth = 1;
    return badge;
}

- (void)updateHUDBarsForState:(LocalTalkRunState)state level:(CGFloat)level {
    if (self.hudBars.count == 0) {
        return;
    }
    NSArray<NSNumber *> *factors = @[@0.28, @0.52, @0.82, @1.0, @0.72, @0.46, @0.26];
    CGFloat effectiveLevel = MAX(0.16, MIN(1.0, level));
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.16];
    [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithControlPoints:0.16 :1.0 :0.30 :1.0]];
    for (NSUInteger index = 0; index < self.hudBars.count; index += 1) {
        CALayer *bar = self.hudBars[index];
        CGFloat scale = 0.18 + (0.82 * MIN(1.0, effectiveLevel * factors[index].doubleValue + 0.12));
        if (state == LocalTalkRunStateIdle) {
            scale = 0.22 + (0.52 * factors[index].doubleValue);
        } else if (state == LocalTalkRunStateTranscribing) {
            scale = 0.28 + (0.64 * factors[(index + 2) % factors.count].doubleValue);
        } else if (state == LocalTalkRunStateFailed) {
            scale = 0.24 + (0.34 * factors[index].doubleValue);
        }

        BOOL accent = (index >= 2 && index <= 4);
        NSColor *color = accent ? LTAccentColor(1) : LTColor(93, 114, 128, 0.70);
        if (state == LocalTalkRunStateFailed) {
            color = accent ? LTColor(255, 110, 100, 1) : LTColor(138, 92, 88, 0.72);
        } else if (state == LocalTalkRunStateIdle) {
            color = accent ? LTAccentColor(0.78) : LTColor(84, 102, 114, 0.52);
        }
        bar.transform = CATransform3DMakeScale(1, scale, 1);
        bar.backgroundColor = color.CGColor;
    }
    [CATransaction commit];
}

- (void)addHeader:(NSString *)title subtitle:(NSString *)subtitle {
    NSTextField *titleLabel = [self label:title frame:NSMakeRect(40, 642, 360, 36) font:[NSFont systemFontOfSize:28 weight:NSFontWeightBold] color:NSColor.whiteColor];
    NSTextField *subtitleLabel = [self label:subtitle frame:NSMakeRect(40, 610, 520, 22) font:[NSFont systemFontOfSize:14 weight:NSFontWeightMedium] color:LTColor(155, 159, 155, 1)];
    [self.contentView addSubview:titleLabel];
    [self.contentView addSubview:subtitleLabel];

    NSImageView *glyph = [[NSImageView alloc] initWithFrame:NSMakeRect(608, 634, 24, 24)];
    glyph.image = [NSImage imageWithSystemSymbolName:@"mic.circle.fill" accessibilityDescription:@"Status"];
    glyph.contentTintColor = LTAccentColor(1);
    self.statusGlyphView = glyph;
    [self.contentView addSubview:glyph];

    self.statusTitleLabel = [self label:self.currentStatus ?: @"Ready" frame:NSMakeRect(642, 644, 146, 18) font:[NSFont systemFontOfSize:13 weight:NSFontWeightBold] color:LTColor(238, 240, 237, 1)];
    self.statusDetailLabel = [self label:@"Control + Option + Space" frame:NSMakeRect(642, 622, 188, 18) font:[NSFont systemFontOfSize:11 weight:NSFontWeightMedium] color:LTColor(145, 149, 145, 1)];
    [self.contentView addSubview:self.statusTitleLabel];
    [self.contentView addSubview:self.statusDetailLabel];

    self.statusSpinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(808, 633, 20, 20)];
    self.statusSpinner.style = NSProgressIndicatorStyleSpinning;
    self.statusSpinner.controlSize = NSControlSizeSmall;
    self.statusSpinner.displayedWhenStopped = NO;
    [self.contentView addSubview:self.statusSpinner];

    self.primaryRecordButton = [self accentButton:(self.runState == LocalTalkRunStateRecording ? @"Stop and Transcribe" : @"Start Recording")
                                            frame:NSMakeRect(842, 624, 114, 34)
                                           action:@selector(toggleRecording:)];
    [self.contentView addSubview:self.primaryRecordButton];
}

- (NSView *)card:(NSRect)frame {
    NSView *card = [[NSView alloc] initWithFrame:frame];
    card.wantsLayer = YES;
    card.layer.cornerRadius = 8;
    card.layer.backgroundColor = LTColor(24, 25, 25, 1).CGColor;
    card.layer.borderColor = LTColor(42, 44, 42, 1).CGColor;
    card.layer.borderWidth = 1;
    return card;
}

- (NSTextField *)label:(NSString *)text frame:(NSRect)frame font:(NSFont *)font color:(NSColor *)color {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.stringValue = text ?: @"";
    label.font = font;
    label.textColor = color;
    label.drawsBackground = NO;
    label.bezeled = NO;
    label.editable = NO;
    label.selectable = NO;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

- (NSButton *)accentButton:(NSString *)title frame:(NSRect)frame action:(SEL)action {
    NSButton *button = [self darkButton:title frame:frame action:action];
    button.layer.backgroundColor = LTAccentColor(1).CGColor;
    button.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{
        NSForegroundColorAttributeName: LTColor(3, 17, 25, 1),
        NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightBold]
    }];
    return button;
}

- (NSButton *)darkButton:(NSString *)title frame:(NSRect)frame action:(SEL)action {
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.bordered = NO;
    button.bezelStyle = NSBezelStyleRegularSquare;
    button.wantsLayer = YES;
    button.layer.cornerRadius = 6;
    button.layer.backgroundColor = LTColor(52, 54, 52, 1).CGColor;
    button.target = self;
    button.action = action;
    button.attributedTitle = [[NSAttributedString alloc] initWithString:title ?: @"" attributes:@{
        NSForegroundColorAttributeName: LTColor(238, 240, 237, 1),
        NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightBold]
    }];
    return button;
}

- (NSButton *)compactButton:(NSString *)title action:(SEL)action {
    return [self darkButton:title frame:NSMakeRect(0, 0, 142, 34) action:action];
}

- (NSButton *)keycap:(NSString *)title {
    NSButton *button = [self darkButton:title frame:NSMakeRect(0, 0, 174, 34) action:nil];
    button.enabled = NO;
    return button;
}

- (NSButton *)switchButtonWithTitle:(NSString *)title action:(SEL)action {
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 66, 28)];
    button.buttonType = NSButtonTypeSwitch;
    button.title = title ?: @"";
    button.target = self;
    button.action = action;
    return button;
}

- (NSPopUpButton *)popupWithAction:(SEL)action {
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 238, 34) pullsDown:NO];
    popup.target = self;
    popup.action = action;
    popup.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    return popup;
}

- (void)addPopupItem:(NSString *)title value:(NSString *)value toPopup:(NSPopUpButton *)popup {
    [popup addItemWithTitle:title];
    popup.lastItem.representedObject = value;
}

- (void)addSettingsRowTo:(NSView *)parent y:(CGFloat)y symbol:(NSString *)symbol title:(NSString *)title subtitle:(NSString *)subtitle control:(NSView *)control {
    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSMakeRect(34, y + 18, 26, 26)];
    icon.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:title];
    icon.contentTintColor = LTColor(226, 229, 225, 1);
    [parent addSubview:icon];

    [parent addSubview:[self label:title frame:NSMakeRect(86, y + 33, 330, 22) font:[NSFont systemFontOfSize:16 weight:NSFontWeightSemibold] color:LTColor(238, 240, 237, 1)]];
    [parent addSubview:[self label:subtitle frame:NSMakeRect(86, y + 11, 430, 20) font:[NSFont systemFontOfSize:13 weight:NSFontWeightRegular] color:LTColor(150, 154, 150, 1)]];

    NSRect controlFrame = control.frame;
    controlFrame.origin.x = parent.bounds.size.width - controlFrame.size.width - 40;
    controlFrame.origin.y = y + 20;
    control.frame = controlFrame;
    [parent addSubview:control];

    NSBox *line = [[NSBox alloc] initWithFrame:NSMakeRect(86, y - 8, parent.bounds.size.width - 126, 1)];
    line.boxType = NSBoxSeparator;
    [parent addSubview:line];
}

- (NSString *)shortened:(NSString *)text maxLength:(NSUInteger)maxLength {
    if (text.length <= maxLength) {
        return text;
    }
    return [[text substringToIndex:maxLength - 3] stringByAppendingString:@"..."];
}

- (NSUInteger)wordCount:(NSString *)text {
    __block NSUInteger count = 0;
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length)
                             options:NSStringEnumerationByWords
                          usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
        count += 1;
    }];
    return count;
}

- (void)appendActivity:(NSString *)message {
    if (message.length == 0) {
        return;
    }
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"HH:mm:ss";
    NSString *line = [NSString stringWithFormat:@"%@  %@\n", [formatter stringFromDate:NSDate.date], message];
    if (self.activityTextView != nil) {
        NSString *existing = self.activityTextView.string ?: @"";
        self.activityTextView.string = [existing stringByAppendingString:line];
        [self.activityTextView scrollRangeToVisible:NSMakeRange(self.activityTextView.string.length, 0)];
    }
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        LocalTalkController *delegate = [[LocalTalkController alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
