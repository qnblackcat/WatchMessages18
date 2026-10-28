#import "WM18Log.h"
#include <roothide.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#define WM18LogMaxRecordChars 8000
#define WM18Chunk 800

// First directory the sandbox really lets us write to wins.
static NSArray<NSString *> *WM18LogDirectories(void) {
	return @[ jbroot(@"/var/mobile/Library/Caches/WatchMessages18"), jbroot(@"/var/mobile/Library/WatchMessages18/Logs"), jbroot(@"/var/tmp/WatchMessages18") ];
}

static NSString *WM18WritableDirectory(void) {
	static NSString *directory;
	static BOOL failed;
	if (directory || failed) return directory;
	for (NSString *candidate in WM18LogDirectories()) {
		if (![[NSFileManager defaultManager] createDirectoryAtPath:candidate withIntermediateDirectories:YES attributes:nil error:NULL]) continue;
		// access() can say yes where the sandbox still refuses open(): try a real file.
		NSString *probe = [candidate stringByAppendingPathComponent:@".probe"];
		int fd = open(probe.fileSystemRepresentation, O_WRONLY | O_CREAT, 0644);
		if (fd < 0) continue;
		close(fd);
		unlink(probe.fileSystemRepresentation);
		directory = candidate;
		NSLog(@"[WatchMessages18] [log] writing debug log to %@", directory);
		return directory;
	}
	failed = YES;
	NSLog(@"[WatchMessages18] [log] no writable log directory, debug log file disabled");
	return nil;
}

static void WM18LogFileAppend(NSString *tag, NSString *text) {
	static dispatch_queue_t queue;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ queue = dispatch_queue_create("com.qn.watchmessages18.log", DISPATCH_QUEUE_SERIAL); });
	static NSDateFormatter *formatter;
	static dispatch_once_t formatterOnce;
	dispatch_once(&formatterOnce, ^{
		formatter = [NSDateFormatter new];
		formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
	});
	NSString *time = [formatter stringFromDate:[NSDate date]];
	NSProcessInfo *info = [NSProcessInfo processInfo];
	if (text.length > WM18LogMaxRecordChars) text = [[text substringToIndex:WM18LogMaxRecordChars] stringByAppendingString:@"…"];
	NSString *record = [NSString stringWithFormat:@"%@ %@[%d] [%@] %@\n", time, info.processName, info.processIdentifier, tag, text];
	NSString *process = info.processName;
	dispatch_async(queue, ^{
		NSString *directory = WM18WritableDirectory();
		if (!directory) return;
		NSString *path = [directory stringByAppendingPathComponent:[process stringByAppendingString:@".log"]];
		struct stat st;
		if (stat(path.fileSystemRepresentation, &st) == 0 && st.st_size >= WM18LogFileMaxBytes)
			rename(path.fileSystemRepresentation, [path stringByAppendingString:@".1"].fileSystemRepresentation);
		int fd = open(path.fileSystemRepresentation, O_WRONLY | O_APPEND | O_CREAT, 0644);
		if (fd < 0) return;
		NSData *data = [record dataUsingEncoding:NSUTF8StringEncoding];
		write(fd, data.bytes, data.length);
		close(fd);
	});
}

void WM18LogWrite(NSString *tag, NSString *text) {
	// Split so unified logging does not truncate long lines.
	NSUInteger len = text.length, parts = MAX(1, (len + WM18Chunk - 1) / WM18Chunk);
	for (NSUInteger i = 0; i < parts; i++) {
		NSRange r = NSMakeRange(i * WM18Chunk, MIN(WM18Chunk, len - i * WM18Chunk));
		NSLog(@"[WatchMessages18] [%@] (%lu/%lu) %@", tag, (unsigned long)i + 1, (unsigned long)parts, len ? [text substringWithRange:r] : @"");
	}
	WM18LogFileAppend(tag, text);
}
