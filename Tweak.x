// WatchMessages18: keeps Messages on watchOS 11.4+ when the paired iPhone runs iOS 18.3 or older.
//
// The watch reports Messages (com.apple.MobileSMS) as a system app with applicationMode 1: it is installable only while
// its companion app counts as "locally available" on the phone (-[ACXRemoteSystemAppList
// _onQueue_appIsInstallable:givenLocallyAvailableApps:]). appconduitd builds that set from
// -[ACXAvailableApplicationManager possibleCompanionDeletableSystemAppToWatchCounterpartsMap], which lists only the
// phone's deletable system apps (LSApplicationRecord systemPlaceholderEnumerator → counterpartIdentifiers). iOS 18.4
// made Messages deletable, so it is in that map there; on older iOS it is not, and the watch loses Messages.
// The fix adds com.apple.MobileSMS → {com.apple.MobileSMS} to the map. Its other condition,
// -[LSApplicationWorkspace applicationIsInstalled:@"com.apple.MobileSMS"], always holds.
// Verified on appconduitd 15.0 (19A346), 15.6.1 (19G82), 16.3.1 (20D67), 17.1.1 (21B91) and 18.4 (22E240): same map
// builder, same installability check.
//
// The watch picks the change up on the next reunion sync, which reads installableSystemAppToCompanionAppIdentifierMap.
// appconduitd runs one by itself when the watch appears or becomes reachable and when the Watch app opens (verified on
// 17.1.1); `killall -USR1 appconduitd` forces one.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <unistd.h>
#import "WM18Log.h"

static NSString *const WM18MessagesBundleID = @"com.apple.MobileSMS";

@interface ACXAvailableApplicationManager : NSObject
- (NSDictionary *)possibleCompanionDeletableSystemAppToWatchCounterpartsMap;
- (NSSet *)_bundleIDsOfLocallyAvailableSystemApps;
@end

@interface ACXRemoteApplication : NSObject
- (NSString *)bundleIdentifier;
- (NSUInteger)applicationMode;
- (BOOL)isDeletable;
@end

@interface ACXRemoteSystemAppList : NSObject
- (BOOL)_onQueue_appIsInstallable:(ACXRemoteApplication *)app givenLocallyAvailableApps:(NSSet *)locallyAvailableApps;
- (void)setAvailableSystemApps:(NSArray *)apps bundleIDsOfInstallableSystemAppsIgnoringCounterpartAvailability:(NSSet *)bundleIDs forRemoteOSBuildVersion:(NSString *)buildVersion;
- (NSDictionary *)installableSystemAppToCompanionAppIdentifierMap;
@end

@interface ACXCompanionSyncConnection : NSObject
- (void)performReunionSyncWithReason:(id)reason;
- (void)_onQueue_beginReunionSyncWithRetryCount:(NSUInteger)retryCount;
- (void)installSystemApplicationsWithBundleIDs:(id)bundleIDs withCompletion:(id)completion;
- (void)_onQueue_sendInstallOnGizmoMessageForSystemAppBundleIDs:(id)bundleIDs appsWithStoreMetadata:(NSDictionary *)metadata isUserInitiated:(BOOL)userInitiated exclusiveInstall:(BOOL)exclusive withCompletion:(id)completion;
@end

static BOOL WM18Contains(id collection, NSString *bundleID) {
	if ([collection isKindOfClass:[NSDictionary class]]) return ((NSDictionary *)collection)[bundleID] != nil;
	if ([collection respondsToSelector:@selector(containsObject:)]) return [collection containsObject:bundleID];
	return NO;
}

// These run several times per reunion sync with the same outcome: log a line only when its text differs from the last
// one logged under the same key.
static void WM18LogIfChanged(NSString *key, NSString *tag, NSString *text) {
	static NSMutableDictionary<NSString *, NSString *> *last;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ last = [NSMutableDictionary dictionary]; });
	@synchronized (last) {
		if ([last[key] isEqualToString:text]) return;
		last[key] = text;
	}
	WM18Log(tag, @"%@", text);
}

%hook ACXAvailableApplicationManager

- (NSDictionary *)possibleCompanionDeletableSystemAppToWatchCounterpartsMap {
	NSDictionary *map = %orig;
	if (map[WM18MessagesBundleID]) {
		WM18LogIfChanged(@"map", @"map", [NSString stringWithFormat:@"Messages already in deletable system app map (iOS 18.4+?): %@", map[WM18MessagesBundleID]]);
		return map;
	}
	NSMutableDictionary *patched = map ? [map mutableCopy] : [NSMutableDictionary dictionary];
	// Values are sets (the builder copies an NSMutableSet; _bundleIDsOfLocallyAvailableSystemApps passes them to -unionSet:).
	patched[WM18MessagesBundleID] = [NSSet setWithObject:WM18MessagesBundleID];
	WM18LogIfChanged(@"map", @"map", [NSString stringWithFormat:@"added %@ to deletable system app map (%lu original entries): %@", WM18MessagesBundleID, (unsigned long)map.count, [map.allKeys sortedArrayUsingSelector:@selector(compare:)]]);
	return [patched copy];
}

- (NSSet *)_bundleIDsOfLocallyAvailableSystemApps {
	NSSet *bundleIDs = %orig;
	WM18LogIfChanged(@"available", @"available", [NSString stringWithFormat:@"locally available system apps: Messages %@ (%lu apps)", WM18Contains(bundleIDs, WM18MessagesBundleID) ? @"YES" : @"NO", (unsigned long)bundleIDs.count]);
	return bundleIDs;
}

%end

%hook ACXRemoteSystemAppList

- (void)setAvailableSystemApps:(NSArray *)apps bundleIDsOfInstallableSystemAppsIgnoringCounterpartAvailability:(NSSet *)bundleIDs forRemoteOSBuildVersion:(NSString *)buildVersion {
	ACXRemoteApplication *messages = nil;
	for (id app in apps) {
		if ([app respondsToSelector:@selector(bundleIdentifier)] && [[app bundleIdentifier] isEqualToString:WM18MessagesBundleID]) {
			messages = app;
			break;
		}
	}
	NSString *details = @"not in the watch's list";
	if (messages) {
		NSUInteger mode = [messages respondsToSelector:@selector(applicationMode)] ? [messages applicationMode] : NSNotFound;
		BOOL deletable = [messages respondsToSelector:@selector(isDeletable)] && [messages isDeletable];
		details = [NSString stringWithFormat:@"applicationMode %lu, isDeletable %d", (unsigned long)mode, deletable];
	}
	WM18Log(@"watch", @"watch OS build %@ sent %lu system apps; Messages: %@; in installable-ignoring-counterpart set: %@", buildVersion, (unsigned long)apps.count, details, WM18Contains(bundleIDs, WM18MessagesBundleID) ? @"YES" : @"NO");
	%orig;
}

- (BOOL)_onQueue_appIsInstallable:(ACXRemoteApplication *)app givenLocallyAvailableApps:(NSSet *)locallyAvailableApps {
	BOOL installable = %orig;
	if ([app respondsToSelector:@selector(bundleIdentifier)] && [[app bundleIdentifier] isEqualToString:WM18MessagesBundleID]) {
		NSUInteger mode = [app respondsToSelector:@selector(applicationMode)] ? [app applicationMode] : NSNotFound;
		WM18LogIfChanged(@"appIsInstallable", @"installable", [NSString stringWithFormat:@"Messages installable: %@ (applicationMode %lu, locally available %@)", installable ? @"YES" : @"NO", (unsigned long)mode, WM18Contains(locallyAvailableApps, WM18MessagesBundleID) ? @"YES" : @"NO"]);
	}
	return installable;
}

- (NSDictionary *)installableSystemAppToCompanionAppIdentifierMap {
	NSDictionary *map = %orig;
	WM18LogIfChanged(@"installableMap", @"installable", [NSString stringWithFormat:@"installable system app map: Messages %@ (%lu apps)", map[WM18MessagesBundleID] ? [NSString stringWithFormat:@"→ %@", map[WM18MessagesBundleID]] : @"missing", (unsigned long)map.count]);
	return map;
}

%end

%hook ACXCompanionSyncConnection

- (void)performReunionSyncWithReason:(id)reason {
	WM18Log(@"reunion", @"performReunionSyncWithReason: %@", reason);
	%orig;
}

- (void)_onQueue_beginReunionSyncWithRetryCount:(NSUInteger)retryCount {
	// Every sync is already logged by performReunionSyncWithReason:; only retries are news.
	if (retryCount) WM18Log(@"reunion", @"retrying reunion sync, retry count %lu", (unsigned long)retryCount);
	%orig;
}

- (void)installSystemApplicationsWithBundleIDs:(id)bundleIDs withCompletion:(id)completion {
	WM18Log(@"install", @"installSystemApplicationsWithBundleIDs: %@", bundleIDs);
	%orig;
}

- (void)_onQueue_sendInstallOnGizmoMessageForSystemAppBundleIDs:(id)bundleIDs appsWithStoreMetadata:(NSDictionary *)metadata isUserInitiated:(BOOL)userInitiated exclusiveInstall:(BOOL)exclusive withCompletion:(id)completion {
	WM18Log(@"install", @"sending install-on-watch for system apps %@ (store apps %@, user initiated %d, exclusive %d)", bundleIDs, metadata.allKeys, userInitiated, exclusive);
	%orig;
}

%end

%ctor {
	NSOperatingSystemVersion os = [[NSProcessInfo processInfo] operatingSystemVersion];
	WM18Log(@"init", @"loaded in %@[%d], iOS %ld.%ld.%ld; classes: manager %d, system app list %d, sync connection %d",
		[[NSProcessInfo processInfo] processName], getpid(), (long)os.majorVersion, (long)os.minorVersion, (long)os.patchVersion,
		objc_getClass("ACXAvailableApplicationManager") != nil, objc_getClass("ACXRemoteSystemAppList") != nil, objc_getClass("ACXCompanionSyncConnection") != nil);
	%init;
}
