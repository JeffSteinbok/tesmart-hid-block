#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOUSBHost/IOUSBHost.h>
#include <signal.h>
#include <unistd.h>
#include <stdarg.h>
#include <os/log.h>

static volatile sig_atomic_t stopping = 0;
static void stopHandler(int signalNumber) { (void)signalNumber; stopping = 1; }
static void status(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void status(NSString *format, ...) {
    va_list args; va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_DEFAULT, "tesmart-hid-block: %{public}s", message.UTF8String);
    fprintf(stdout, "%s %s\n", [NSDate.date description].UTF8String, message.UTF8String);
    fflush(stdout);
}

// This is the KVM's composite HID controller, NOT the CH545 hub or receivers.
static BOOL allowed(NSDictionary *properties) {
    return [properties[@"idVendor"] unsignedIntValue] == 0x1a86 &&
           [properties[@"idProduct"] unsignedIntValue] == 0xe010 &&
           properties[@"bDeviceClass"] != nil &&
           [properties[@"bDeviceClass"] unsignedIntValue] == 0 &&
           [properties[@"USB Product Name"] isEqual:@"DKS202-M24"];
}

// Return an owned service only if exactly one matching VID/PID device exists
// and its model/class also pass the allowlist. Never choose arbitrarily.
static io_service_t findTarget(uint64_t *entryID, NSString **reason) {
    NSMutableDictionary *match = CFBridgingRelease(IOServiceMatching("IOUSBHostDevice"));
    match[@"idVendor"] = @0x1a86; match[@"idProduct"] = @0xe010;
    io_iterator_t iterator = IO_OBJECT_NULL;
    kern_return_t result = IOServiceGetMatchingServices(kIOMainPortDefault,
        (__bridge_retained CFDictionaryRef)match, &iterator);
    if (result != KERN_SUCCESS) {
        *reason = [NSString stringWithFormat:@"Enumeration error 0x%x", result]; return IO_OBJECT_NULL;
    }
    io_service_t candidate = IOIteratorNext(iterator);
    io_service_t extra = IOIteratorNext(iterator);
    IOObjectRelease(iterator);
    if (!candidate || extra) {
        if (candidate) IOObjectRelease(candidate);
        if (extra) IOObjectRelease(extra);
        *reason = extra ? @"Multiple TESmart controllers: refusing ambiguous capture" : @"Waiting for TESmart controller";
        return IO_OBJECT_NULL;
    }
    CFMutableDictionaryRef raw = NULL;
    result = IORegistryEntryCreateCFProperties(candidate, &raw, kCFAllocatorDefault, 0);
    NSDictionary *properties = CFBridgingRelease(raw);
    if (result != KERN_SUCCESS || !allowed(properties) ||
        IORegistryEntryGetRegistryEntryID(candidate, entryID) != KERN_SUCCESS) {
        IOObjectRelease(candidate); *reason = @"Device failed exact model/class allowlist"; return IO_OBJECT_NULL;
    }
    return candidate;
}

static int selfTest(void) {
    NSDictionary *good = @{@"idVendor":@0x1a86, @"idProduct":@0xe010,
        @"bDeviceClass":@0, @"USB Product Name":@"DKS202-M24"};
    if (!allowed(good) || allowed(nil)) return 1;
    NSDictionary *changes = @{@"idVendor":@0x45e, @"idProduct":@0x7a5,
        @"bDeviceClass":@9, @"USB Product Name":@"CH545"};
    for (NSString *key in changes) {
        NSMutableDictionary *bad = good.mutableCopy; bad[key] = changes[key];
        if (allowed(bad)) return 1;
        [bad removeObjectForKey:key]; if (allowed(bad)) return 1;
    }
    puts("PASS: exact controller accepted; wrong vendor/product/model, hubs, and missing properties rejected.");
    return 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        BOOL capture = NO; NSTimeInterval duration = 0;
        if (argc == 2 && strcmp(argv[1], "--self-test") == 0) return selfTest();
        if (argc == 2 && strcmp(argv[1], "--help") == 0) {
            puts("tesmart-hid-block [--dry-run | --capture [--duration SECONDS] | --self-test]\n"
                 "Default: dry run. Capture requires root; without --duration it runs until stopped."); return 0;
        }
        if (argc >= 2 && strcmp(argv[1], "--capture") == 0) {
            capture = YES;
            if (argc == 4 && strcmp(argv[2], "--duration") == 0) {
                char *end = NULL; duration = strtod(argv[3], &end);
                if (!end || *end || !isfinite(duration) || duration <= 0 || duration > 86400) return 2;
            } else if (argc != 2) return 2;
        } else if (argc != 1 && !(argc == 2 && strcmp(argv[1], "--dry-run") == 0)) return 2;
        if (capture && geteuid() != 0) { fprintf(stderr, "Capture requires root.\n"); return 1; }
        signal(SIGINT, stopHandler); signal(SIGTERM, stopHandler); signal(SIGHUP, stopHandler);
        IOUSBHostDevice *held = nil; uint64_t heldID = 0;
        NSString *lastStatus = nil;
        NSDate *deadline = duration > 0 ? [NSDate dateWithTimeIntervalSinceNow:duration] : nil;
        if (capture) status(@"Starting TESmart-only capture; %@", deadline ?: @"no time limit");
        while (!stopping && (!deadline || deadline.timeIntervalSinceNow > 0)) {
            @autoreleasepool {
                uint64_t entryID = 0; NSString *reason = nil;
                io_service_t target = findTarget(&entryID, &reason);
                if (!capture) {
                    if (target) {
                        status(@"DRY RUN: DKS202-M24 1a86:e010 registryID=0x%llx; no changes", entryID);
                        IOObjectRelease(target); return 0;
                    }
                    status(@"DRY RUN: %@; no changes", reason); return 1;
                }
                if (held && (!target || entryID != heldID)) {
                    [held destroy]; held = nil; heldID = 0;
                    status(@"Previous device removed/replaced or ambiguous; released capture");
                }
                if (target && !held) {
                    NSError *error = nil;
                    held = [[IOUSBHostDevice alloc] initWithIOService:target
                        options:IOUSBHostObjectInitOptionsDeviceCapture queue:nil error:&error interestHandler:nil];
                    if (held) {
                        heldID = entryID; status(@"CAPTURED DKS202-M24 registryID=0x%llx", heldID); lastStatus = nil;
                    } else reason = [NSString stringWithFormat:@"Capture failed: %@", error];
                }
                if (target) IOObjectRelease(target);
                if (!held && ![lastStatus isEqual:reason]) { status(@"%@; retrying every 2 seconds", reason); lastStatus = reason; }
                NSDate *next = [NSDate dateWithTimeIntervalSinceNow:2];
                while (!stopping && next.timeIntervalSinceNow > 0 && (!deadline || deadline.timeIntervalSinceNow > 0))
                    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
            }
        }
        if (held) { [held destroy]; status(@"RELEASED; normal driver matching restored"); }
        status(@"Stopped");
    }
    return 0;
}
