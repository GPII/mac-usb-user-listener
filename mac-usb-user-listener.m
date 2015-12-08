/*
 * GPII Mac OS X USB User Listener
 *
 * Copyright 2015 Raising the Floor
 *
 * Licensed under the New BSD license. You may not use this file except in
 * compliance with this License.
 *
 * The research leading to these results has received funding from the European Union's
 * Seventh Framework Programme (FP7/2007-2013)
 * under grant agreement no. 289016.
 *
 * You may obtain a copy of the License at
 * https://github.com/GPII/universal/blob/master/LICENSE.txt
 */

#include <Foundation/Foundation.h>
#include <DiskArbitration/DiskArbitration.h>

NSMutableDictionary *disks;
NSString *BSDName;
NSArray *volumeKindBlacklist;
DASessionRef session;
NSString *URL;

void performOnLogonChangeRequest (NSString *userToken) {
    NSString *url = [URL stringByReplacingOccurrencesOfString: @"token"
                     withString: userToken];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    [request setHTTPMethod: @"GET"];
    [request setURL:[NSURL URLWithString: url]];

    NSError *error = [[NSError alloc] init];
    NSHTTPURLResponse *responseCode = nil;

    NSData *oResponseData = [NSURLConnection sendSynchronousRequest: request
                             returningResponse: &responseCode error: &error];

    if ([responseCode statusCode] != 200) {
        NSLog(@"Error getting %@, HTTP status code %li", url,
              [responseCode statusCode]);
    } else { 
      NSString *response = [[NSString alloc] initWithData: oResponseData
                            encoding: NSUTF8StringEncoding];
      NSLog(@"The server has returned: %@", response);
    }
}

void volumePathDidChange (DADiskRef disk, CFArrayRef keys, void *context) {
    CFDictionaryRef dict = DADiskCopyDescription(disk);
    CFURLRef fspath = CFDictionaryGetValue(dict, kDADiskDescriptionVolumePathKey);
 
    char buf[MAXPATHLEN];
    if (CFURLGetFileSystemRepresentation(fspath, false, (UInt8 *) buf, sizeof(buf))) {
        NSString *mountPoint = [[NSString alloc] initWithUTF8String: buf ? buf : ""];
        NSString *path = [mountPoint stringByAppendingString: @"/.gpii-user-token.txt"];

        BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath: path];
        if (fileExists) {
            NSString *userToken = [NSString stringWithContentsOfFile: path
                                   encoding: NSUTF8StringEncoding error: nil];
            NSLog(@"User token is: %@", userToken);
            char *bsd_name = (char *) DADiskGetBSDName(disk);
            BSDName = [[NSString alloc] initWithUTF8String:bsd_name];
            disks[BSDName] = [userToken stringByTrimmingCharactersInSet:
                             [NSCharacterSet newlineCharacterSet]];
            NSLog(@"Disks: %@", disks);
            performOnLogonChangeRequest([userToken stringByTrimmingCharactersInSet:
                                        [NSCharacterSet newlineCharacterSet]]);
        } else {
            NSLog(@"Couldn't find a .gpii-user-token.txt file in %@", mountPoint);
        }

        DAUnregisterCallback(session, volumePathDidChange, NULL);
    } else {
        NSLog(@"Error when trying to obtain the mountpoint");
    }
    CFRelease(dict);
}

static void diskAppearedCallback (DADiskRef disk, void *context) {
    NSDictionary *diskDescription = (NSDictionary *) DADiskCopyDescription(disk);
    volumeKindBlacklist = @[@"autofs", @"hfs"];
    NSString *volumeKind = [diskDescription objectForKey: @"DAVolumeKind"];
    BOOL blacklisted = [volumeKindBlacklist containsObject: volumeKind];
    if (blacklisted) {
        NSLog(@"skipping %@!", volumeKind);
        return;
    }

    CFMutableArrayRef keys = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);
    CFArrayAppendValue(keys, kDADiskDescriptionWatchVolumePath);

    DARegisterDiskDescriptionChangedCallback(session, NULL, 
                                             kDADiskDescriptionWatchVolumePath,
                                             volumePathDidChange, NULL);

    CFRelease(diskDescription);
}


static void diskDisappearedCallback (DADiskRef disk, void *context) {
    CFDictionaryRef description = DADiskCopyDescription(disk);
    NSLog(@"Disk disappeared: %@", description);
    NSLog(@"BSDName = %s", DADiskGetBSDName(disk));
    char *bsd_name = (char *) DADiskGetBSDName(disk);
    BSDName = [[NSString alloc] initWithUTF8String: bsd_name];

    if (disks[BSDName]) {
        performOnLogonChangeRequest(disks[BSDName]);
        [disks removeObjectForKey: BSDName];
    }
    CFRelease(description);
}

int main (int argc, char **argv) {
    disks = [[NSMutableDictionary alloc] init];
    volumeKindBlacklist = @[@"autofs", @"hfs"];
    URL = @"http://localhost:8081/user/token/logonChange";

    session = DASessionCreate(kCFAllocatorDefault);
    DARegisterDiskAppearedCallback(session, kDADiskDescriptionMatchVolumeMountable,
                                   diskAppearedCallback, 0);
    DARegisterDiskDisappearedCallback(session, kDADiskDescriptionMatchVolumeMountable,
                                      diskDisappearedCallback, 0);
    DASessionScheduleWithRunLoop(session, CFRunLoopGetCurrent(),
                                 kCFRunLoopDefaultMode);

    CFRunLoopRun();

    return 0;
}
