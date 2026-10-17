// Lumina's now-playing helper.
//
// macOS has no public API for another app's "now playing", and since macOS
// 15.4 the private MediaRemote framework only answers processes Apple
// entitles. The system's Perl is one, so Lumina runs /usr/bin/perl, which
// loads this library and calls lumina_media_run (see MediaController).
//
// It writes one JSON object per line to stdout whenever what's playing
// changes, and reads commands from stdin, one per line: play, pause,
// toggle, next, previous, seek <seconds>. It exits when stdin closes, so
// it never outlives Lumina.

#import <Foundation/Foundation.h>
#import <dlfcn.h>

typedef void (*MRGetInfo)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*MRGetPID)(dispatch_queue_t, void (^)(int));
typedef void (*MRGetIsPlaying)(dispatch_queue_t, void (^)(Boolean));
typedef void (*MRRegister)(dispatch_queue_t);
typedef Boolean (*MRSendCommand)(int, CFDictionaryRef);
typedef void (*MRSetElapsed)(double);

static MRGetInfo getInfo;
static MRGetPID getPID;
static MRGetIsPlaying getIsPlaying;
static MRSendCommand sendCommand;
static MRSetElapsed setElapsed;

static NSString *lastLine;
static NSData *lastArtwork;
static BOOL emitScheduled;

static void writeLine(NSDictionary *object) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (!json) return;
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static id jsonValue(id value) {
    if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]]) return value;
    if ([value isKindOfClass:[NSDate class]]) return @([(NSDate *)value timeIntervalSince1970]);
    return nil;
}

/// Reads what's playing and writes it, if anything changed.
static void emit(void) {
    emitScheduled = NO;
    getInfo(dispatch_get_main_queue(), ^(CFDictionaryRef infoRef) {
        NSDictionary *info = (__bridge NSDictionary *)infoRef;
        getPID(dispatch_get_main_queue(), ^(int pid) {
            getIsPlaying(dispatch_get_main_queue(), ^(Boolean isPlaying) {
                NSMutableDictionary *out = [NSMutableDictionary dictionary];
                NSDictionary *keys = @{
                    @"title": @"kMRMediaRemoteNowPlayingInfoTitle",
                    @"artist": @"kMRMediaRemoteNowPlayingInfoArtist",
                    @"album": @"kMRMediaRemoteNowPlayingInfoAlbum",
                    @"duration": @"kMRMediaRemoteNowPlayingInfoDuration",
                    @"elapsed": @"kMRMediaRemoteNowPlayingInfoElapsedTime",
                    @"timestamp": @"kMRMediaRemoteNowPlayingInfoTimestamp",
                    @"rate": @"kMRMediaRemoteNowPlayingInfoPlaybackRate",
                    @"contentID": @"kMRMediaRemoteNowPlayingInfoContentItemIdentifier",
                };
                for (NSString *name in keys) {
                    id value = jsonValue(info[keys[name]]);
                    if (value) out[name] = value;
                }
                out[@"pid"] = @(pid);
                out[@"playing"] = @(isPlaying);

                NSData *artwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                if (![artwork isKindOfClass:[NSData class]] || artwork.length == 0) artwork = nil;
                out[@"hasArtwork"] = @(artwork != nil);

                // Artwork only when it changes: it's the bulk of a message.
                NSData *line = [NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingSortedKeys error:nil];
                NSString *text = [[NSString alloc] initWithData:line encoding:NSUTF8StringEncoding];
                BOOL artworkChanged = !(artwork == lastArtwork || [artwork isEqualToData:lastArtwork]);
                if (!artworkChanged && [text isEqualToString:lastLine]) return;
                lastLine = text;
                if (artworkChanged) {
                    lastArtwork = artwork;
                    out[@"artwork"] = artwork ? [artwork base64EncodedStringWithOptions:0] : [NSNull null];
                }
                writeLine(out);
            });
        });
    });
}

/// Coalesces bursts of notifications into one read.
static void scheduleEmit(void) {
    if (emitScheduled) return;
    emitScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ emit(); });
}

static void handleCommand(NSString *line) {
    NSArray<NSString *> *parts = [line componentsSeparatedByString:@" "];
    NSString *command = parts.firstObject;
    // MRMediaRemoteCommand: play 0, pause 1, togglePlayPause 2, nextTrack 4, previousTrack 5.
    if ([command isEqualToString:@"play"]) sendCommand(0, NULL);
    else if ([command isEqualToString:@"pause"]) sendCommand(1, NULL);
    else if ([command isEqualToString:@"toggle"]) sendCommand(2, NULL);
    else if ([command isEqualToString:@"next"]) sendCommand(4, NULL);
    else if ([command isEqualToString:@"previous"]) sendCommand(5, NULL);
    else if ([command isEqualToString:@"seek"] && parts.count > 1 && setElapsed) setElapsed(parts[1].doubleValue);
    else if ([command isEqualToString:@"refresh"]) { lastLine = nil; lastArtwork = nil; }
    scheduleEmit();
}

static void readCommands(void) {
    static NSMutableData *buffer;
    buffer = [NSMutableData data];
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(source, ^{
        char chunk[1024];
        ssize_t count = read(STDIN_FILENO, chunk, sizeof chunk);
        if (count <= 0) exit(0);
        [buffer appendBytes:chunk length:count];
        while (true) {
            NSRange newline = [buffer rangeOfData:[NSData dataWithBytes:"\n" length:1] options:0 range:NSMakeRange(0, buffer.length)];
            if (newline.location == NSNotFound) break;
            NSData *lineData = [buffer subdataWithRange:NSMakeRange(0, newline.location)];
            [buffer replaceBytesInRange:NSMakeRange(0, newline.location + 1) withBytes:NULL length:0];
            NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
            if (line.length) handleCommand(line);
        }
    });
    dispatch_resume(source);
    // Kept alive for the life of the process.
    static dispatch_source_t keep;
    keep = source;
}

static void observe(void *framework, const char *symbol) {
    CFStringRef *name = (CFStringRef *)dlsym(framework, symbol);
    if (!name) return;
    [[NSNotificationCenter defaultCenter] addObserverForName:(__bridge NSString *)*name object:nil queue:nil
                                                  usingBlock:^(NSNotification *note) { scheduleEmit(); }];
}

/// Called by Perl as an XSUB; never returns.
__attribute__((visibility("default")))
void lumina_media_run(void *interpreter, void *cv) {
    void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    getInfo = mr ? (MRGetInfo)dlsym(mr, "MRMediaRemoteGetNowPlayingInfo") : NULL;
    getPID = mr ? (MRGetPID)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationPID") : NULL;
    getIsPlaying = mr ? (MRGetIsPlaying)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") : NULL;
    sendCommand = mr ? (MRSendCommand)dlsym(mr, "MRMediaRemoteSendCommand") : NULL;
    setElapsed = mr ? (MRSetElapsed)dlsym(mr, "MRMediaRemoteSetElapsedTime") : NULL;
    MRRegister registerForNotifications = mr ? (MRRegister)dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications") : NULL;

    if (!getInfo || !getPID || !getIsPlaying || !sendCommand || !registerForNotifications) {
        writeLine(@{@"error": @"MediaRemote is unavailable"});
        exit(1);
    }

    registerForNotifications(dispatch_get_main_queue());
    observe(mr, "kMRMediaRemoteNowPlayingInfoDidChangeNotification");
    observe(mr, "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification");
    observe(mr, "kMRMediaRemoteNowPlayingApplicationDidChangeNotification");
    observe(mr, "kMRMediaRemoteNowPlayingApplicationClientStateDidChange");
    readCommands();

    // Some apps don't announce every change; look again now and then.
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), 3 * NSEC_PER_SEC, NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{ scheduleEmit(); });
    dispatch_resume(timer);
    static dispatch_source_t keepTimer;
    keepTimer = timer;

    CFRunLoopRun();
    exit(0);
}
