@import CommonCrypto;
@import MachO;

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "LCAppInfo.h"
#import "LCUtils.h"

uint32_t dyld_get_sdk_version(const struct mach_header* mh);

@implementation LCAppInfo
- (instancetype)initWithBundlePath:(NSString*)bundlePath {
    self = [super init];
    self.isShared = false;
	if(self) {
        _bundlePath = bundlePath;
        _infoPlist = [NSMutableDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"%@/Info.plist", bundlePath]];
        _info = [NSMutableDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"%@/LCAppInfo.plist", bundlePath]];
        if(!_info) {
            _info = [[NSMutableDictionary alloc] init];
        }
        if(!_infoPlist) {
            _infoPlist = [[NSMutableDictionary alloc] init];
        }
        
        // migrate old appInfo
        if(_infoPlist[@"LCPatchRevision"] && [_info count] == 0) {
            NSArray* lcAppInfoKeys = @[
                @"LCPatchRevision",
                @"LCOrignalBundleIdentifier",
                @"LCDataUUID",
                @"LCTweakFolder",
                @"LCJITLessSignID",
                @"LCSelectedLanguage",
                @"LCExpirationDate",
                @"LCTeamId",
                @"isJITNeeded",
                @"isLocked",
                @"isHidden",
                @"doUseLCBundleId",
                @"doSymlinkInbox",
                @"bypassAssertBarrierOnQueue",
                @"signer",
                @"LCOrientationLock",
                @"cachedColor",
                @"LCContainers",
                @"hideLiveContainer"
            ];
            for(NSString* key in lcAppInfoKeys) {
                _info[key] = _infoPlist[key];
                [_infoPlist removeObjectForKey:key];
            }
            [_infoPlist writeToFile:[NSString stringWithFormat:@"%@/Info.plist", bundlePath] atomically:YES];
            [self save];
        }
        
        // fix bundle id and execName if crash when signing
        if (_infoPlist[@"LCBundleIdentifier"]) {
            _infoPlist[@"CFBundleExecutable"] = _infoPlist[@"LCBundleExecutable"];
            _infoPlist[@"CFBundleIdentifier"] = _infoPlist[@"LCBundleIdentifier"];
            [_infoPlist removeObjectForKey:@"LCBundleExecutable"];
            [_infoPlist removeObjectForKey:@"LCBundleIdentifier"];
            [_infoPlist writeToFile:[NSString stringWithFormat:@"%@/Info.plist", bundlePath] atomically:YES];
        }

        _autoSaveDisabled = false;
    }
    return self;
}

- (void)setBundlePath:(NSString*)newBundlePath {
    _bundlePath = newBundlePath;
}

- (NSMutableArray*)urlSchemes {
    // find all url schemes
    NSMutableArray* urlSchemes = [[NSMutableArray alloc] init];
    int nowSchemeCount = 0;
    if (_infoPlist[@"CFBundleURLTypes"]) {
        NSMutableArray* urlTypes = _infoPlist[@"CFBundleURLTypes"];

        for(int i = 0; i < [urlTypes count]; ++i) {
            NSMutableDictionary* nowUrlType = [urlTypes objectAtIndex:i];
            if (!nowUrlType[@"CFBundleURLSchemes"]){
                continue;
            }
            NSMutableArray *schemes = nowUrlType[@"CFBundleURLSchemes"];
            for(int j = 0; j < [schemes count]; ++j) {
                [urlSchemes insertObject:[schemes objectAtIndex:j] atIndex:nowSchemeCount];
                ++nowSchemeCount;
            }
        }
    }
    
    return urlSchemes;
}

- (NSString*)displayName {
    if (_infoPlist[@"CFBundleDisplayName"]) {
        return _infoPlist[@"CFBundleDisplayName"];
    } else if (_infoPlist[@"CFBundleName"]) {
        return _infoPlist[@"CFBundleName"];
    } else if (_infoPlist[@"CFBundleExecutable"]) {
        return _infoPlist[@"CFBundleExecutable"];
    } else {
        return @"App Corrupted, Please Reinstall This App";
    }
}

- (NSString*)version {
    NSString* version = _infoPlist[@"CFBundleShortVersionString"];
    if (!version) {
        version = _infoPlist[@"CFBundleVersion"];
    }
    if(version) {
        return version;
    } else {
        return @"Unknown";
    }
}

- (NSString*)bundleIdentifier {
    NSString* ans = nil;
    if([self doUseLCBundleId]) {
        ans = _info[@"LCOrignalBundleIdentifier"];
    } else {
        ans = _infoPlist[@"CFBundleIdentifier"];
    }
    if(ans) {
        return ans;
    } else {
        return @"Unknown";
    }
}

- (NSString*)dataUUID {
    return _info[@"LCDataUUID"];
}

- (NSString*)tweakFolder {
    return _info[@"LCTweakFolder"];
}

- (void)setDataUUID:(NSString *)uuid {
    _info[@"LCDataUUID"] = uuid;
    [self save];
}

- (void)setTweakFolder:(NSString *)tweakFolder {
    _info[@"LCTweakFolder"] = tweakFolder;
    [self save];
}

- (NSString*)selectedLanguage {
    return _info[@"LCSelectedLanguage"];
}

- (void)setSelectedLanguage:(NSString *)selectedLanguage {
    if([selectedLanguage isEqualToString: @""]) {
        _info[@"LCSelectedLanguage"] = nil;
    } else {
        _info[@"LCSelectedLanguage"] = selectedLanguage;
    }
    
    [self save];
}

- (NSString*)bundlePath {
    return _bundlePath;
}

- (NSMutableDictionary*)info {
    return _info;
}

- (UIImage*)icon {
    NSBundle* bundle = [[NSBundle alloc] initWithPath: _bundlePath];
    NSString* iconPath = nil;
    UIImage* icon = nil;

    if((iconPath = [_infoPlist valueForKeyPath:@"CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconFiles"][0]) &&
       (icon = [UIImage imageNamed:iconPath inBundle:bundle compatibleWithTraitCollection:nil])) {
        return icon;
    }
    
    if((iconPath = [_infoPlist valueForKeyPath:@"CFBundleIconFiles"][0]) &&
       (icon = [UIImage imageNamed:iconPath inBundle:bundle compatibleWithTraitCollection:nil])) {
        return icon;
    }
    
    if((iconPath = [_infoPlist valueForKeyPath:@"CFBundleIcons~ipad"][@"CFBundlePrimaryIcon"][@"CFBundleIconName"]) &&
       (icon = [UIImage imageNamed:iconPath inBundle:bundle compatibleWithTraitCollection:nil])) {
        return icon;
    }

    return [UIImage imageNamed:@"DefaultIcon"];

}

- (UIImage *)generateLiveContainerWrappedIcon {
    UIImage *icon = self.icon;
    if (![NSUserDefaults.standardUserDefaults boolForKey:@"LCFrameShortcutIcons"]) {
        return icon;
    }

    UIImage *lcIcon = [UIImage imageNamed:@"AppIcon60x60@2x"];
    CGFloat iconXY = (lcIcon.size.width - 40) / 2;
    UIGraphicsBeginImageContextWithOptions(lcIcon.size, NO, 0.0);
    [lcIcon drawInRect:CGRectMake(0, 0, lcIcon.size.width, lcIcon.size.height)];
    CGRect rect = CGRectMake(iconXY, iconXY, 40, 40);
    [[UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:7] addClip];
    [icon drawInRect:rect];
    UIImage *newIcon = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return newIcon;
}

- (NSDictionary *)generateWebClipConfigWithContainerId:(NSString*)containerId {
    NSString* appClipUrl;
    if(containerId) {
        appClipUrl = [NSString stringWithFormat:@"livecontainer://livecontainer-launch?bundle-name=%@&container-folder-name=%@", self.bundlePath.lastPathComponent, containerId];
    } else {
        appClipUrl = [NSString stringWithFormat:@"livecontainer://livecontainer-launch?bundle-name=%@", self.bundlePath.lastPathComponent];
    }
    
    NSDictionary *payload = @{
        @"FullScreen": @YES,
        @"Icon": UIImagePNGRepresentation(self.generateLiveContainerWrappedIcon),
        @"IgnoreManifestScope": @YES,
        @"IsRemovable": @YES,
        @"Label": self.displayName,
        @"PayloadDescription": [NSString stringWithFormat:@"Web Clip for launching %@ (%@) in LiveContainer", self.displayName, self.bundlePath.lastPathComponent],
        @"PayloadDisplayName": self.displayName,
        @"PayloadIdentifier": self.bundleIdentifier,
        @"PayloadType": @"com.apple.webClip.managed",
        @"PayloadUUID": NSUUID.UUID.UUIDString,
        @"PayloadVersion": @(1),
        @"Precomposed": @NO,
        @"toPayloadOrganization": @"LiveContainer",
        @"URL": appClipUrl
    };
    return @{
        @"ConsentText": @{
            @"default": [NSString stringWithFormat:@"This profile installs a web clip which opens %@ (%@) in LiveContainer", self.displayName, self.bundlePath.lastPathComponent]
        },
        @"PayloadContent": @[payload],
        @"PayloadDescription": payload[@"PayloadDescription"],
        @"PayloadDisplayName": self.displayName,
        @"PayloadIdentifier": self.bundleIdentifier,
        @"PayloadOrganization": @"LiveContainer",
        @"PayloadRemovalDisallowed": @(NO),
        @"PayloadType": @"Configuration",
        @"PayloadUUID": @"345097fb-d4f7-4a34-ab90-2e3f1ad62eed",
        @"PayloadVersion": @(1),
    };
}

- (void)save {
    if(!_autoSaveDisabled) {
        [_info writeToFile:[NSString stringWithFormat:@"%@/LCAppInfo.plist", _bundlePath] atomically:YES];

        // Also save camera settings to guestAppInfo for hooks
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSMutableDictionary *guestAppInfo = [[defaults objectForKey:@"guestAppInfo"] mutableCopy] ?: [@{} mutableCopy];
        
        guestAppInfo[@"hideLiveContainer"] = @(self.hideLiveContainer);

        // Only save the 3 camera variables to guestAppInfo (keep it simple)
        guestAppInfo[@"spoofCamera"] = @(self.spoofCamera);
        guestAppInfo[@"spoofCameraVideoPath"] = self.spoofCameraVideoPath ?: @"";
        guestAppInfo[@"spoofCameraLoop"] = @(self.spoofCameraLoop);
        
        // save network variables to guestAppInfo
        guestAppInfo[@"spoofNetwork"] = @(self.spoofNetwork);
        guestAppInfo[@"proxyType"] = self.proxyType ?: @"HTTP";
        guestAppInfo[@"proxyHost"] = self.proxyHost ?: @"";
        guestAppInfo[@"proxyPort"] = @(self.proxyPort);
        guestAppInfo[@"proxyUsername"] = self.proxyUsername ?: @"";
        guestAppInfo[@"proxyPassword"] = self.proxyPassword ?: @"";
        guestAppInfo[@"spoofNetworkMode"] = self.spoofNetworkMode ?: @"standard";

        [defaults setObject:guestAppInfo forKey:@"guestAppInfo"];
        [defaults synchronize];
        
        // Trigger UserDefaults change notification for hooks
        [[NSNotificationCenter defaultCenter] postNotificationName:NSUserDefaultsDidChangeNotification object:nil];
    }
}

- (void)patchExecAndSignIfNeedWithCompletionHandler:(void(^)(bool success, NSString* errorInfo))completetionHandler progressHandler:(void(^)(NSProgress* progress))progressHandler forceSign:(BOOL)forceSign {
    
    // Set the signing in progress flag
    [NSUserDefaults.standardUserDefaults setObject:@(YES) forKey:@"SigningInProgress"];
    
    @try {
        NSString *appPath = self.bundlePath;
        NSString *infoPath = [NSString stringWithFormat:@"%@/Info.plist", appPath];
        NSMutableDictionary *info = _info;
        NSMutableDictionary *infoPlist = _infoPlist;
        
        if (!info) {
            completetionHandler(NO, @"Info.plist not found");
            return;
        }
        
        NSFileManager* fm = NSFileManager.defaultManager;
        NSString *execPath = [NSString stringWithFormat:@"%@/%@", appPath, _infoPlist[@"CFBundleExecutable"]];
        
        // Update patch
        int currentPatchRev = 7;
        bool needPatch = [info[@"LCPatchRevision"] intValue] < currentPatchRev;
        if (needPatch || forceSign) {
            // copy-delete-move to avoid EXC_BAD_ACCESS (SIGKILL - CODESIGNING)
            NSString *backupPath = [NSString stringWithFormat:@"%@/%@_LiveContainerPatchBackUp", appPath, _infoPlist[@"CFBundleExecutable"]];
            NSError *err;
            [fm copyItemAtPath:execPath toPath:backupPath error:&err];
            [fm removeItemAtPath:execPath error:&err];
            [fm moveItemAtPath:backupPath toPath:execPath error:&err];
        }
        
        if (needPatch) {
            __block bool has64bitSlice = NO;
            NSString *error = LCParseMachO(execPath.UTF8String, false, ^(const char *path, struct mach_header_64 *header, int fd, void* filePtr) {
                if(header->cputype == CPU_TYPE_ARM64) {
                    has64bitSlice |= YES;
                    int patchResult = LCPatchExecSlice(path, header, ![self dontInjectTweakLoader]);
                    if(patchResult & PATCH_EXEC_RESULT_NO_SPACE_FOR_TWEAKLOADER) {
                        info[@"LCTweakLoaderCantInject"] = @YES;
                        // info[@"dontInjectTweakLoader"] = @YES;
                    }
                }
            });
            self.is32bit = !has64bitSlice;
            LCPatchAppBundleFixupARM64eSlice([NSURL fileURLWithPath:appPath]);
            
            if (error) {
                completetionHandler(NO, error);
                return;
            }
            info[@"LCPatchRevision"] = @(currentPatchRev);
            forceSign = true;
            
            [self save];
        }

        if (!LCUtils.certificatePassword || self.is32bit || self.dontSign) {
            completetionHandler(YES, nil);
            return;
        }

        // check if iOS think this app's signature is valid, if so, we can skip any further signature check
        NSString* executablePath = [appPath stringByAppendingPathComponent:infoPlist[@"CFBundleExecutable"]];
        if(!forceSign) {
            bool signatureValid = checkCodeSignature(executablePath.UTF8String);
            
            if(signatureValid) {
                completetionHandler(YES, nil);
                return;
            }
        }
        
        if (!LCUtils.certificateData) {
            completetionHandler(NO, @"lc.signer.noCertificateFoundErr");
            return;
        }
        
        if(forceSign) {
            // remove ZSign cache since hash is changed after upgrading patch
            NSString* cachePath = [appPath stringByAppendingPathComponent:@"zsign_cache.json"];
            if([fm fileExistsAtPath:cachePath]) {
                NSError* err;
                [fm removeItemAtPath:cachePath error:&err];
            }
        }
        
        // Sign app if JIT-less is set up
        NSURL *appPathURL = [NSURL fileURLWithPath:appPath];
        // We need to temporarily fake bundle ID and main executable to sign properly
        NSString *tmpExecPath = [appPath stringByAppendingPathComponent:@"LiveContainer.tmp"];
        if (!info[@"LCBundleIdentifier"]) {
            // Don't let main executable get entitlements
            [fm copyItemAtPath:NSBundle.mainBundle.executablePath toPath:tmpExecPath error:nil];

            infoPlist[@"LCBundleExecutable"] = infoPlist[@"CFBundleExecutable"];
            infoPlist[@"LCBundleIdentifier"] = infoPlist[@"CFBundleIdentifier"];
            infoPlist[@"CFBundleExecutable"] = tmpExecPath.lastPathComponent;
            infoPlist[@"CFBundleIdentifier"] = NSBundle.mainBundle.bundleIdentifier;
            [infoPlist writeToFile:infoPath atomically:YES];
        }
        infoPlist[@"CFBundleExecutable"] = infoPlist[@"LCBundleExecutable"];
        infoPlist[@"CFBundleIdentifier"] = infoPlist[@"LCBundleIdentifier"];
        [infoPlist removeObjectForKey:@"LCBundleExecutable"];
        [infoPlist removeObjectForKey:@"LCBundleIdentifier"];
        
        void (^signCompletionHandler)(BOOL success, NSError *error) = ^(BOOL success, NSError *_Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                // Remove fake main executable
                [fm removeItemAtPath:tmpExecPath error:nil];
                
                // Save sign ID and restore bundle ID
                [self save];
                [infoPlist writeToFile:infoPath atomically:YES];
                
                if(!success) {
                    completetionHandler(NO, error.localizedDescription);
                } else {
                    bool signatureValid = checkCodeSignature(executablePath.UTF8String);
                    if(signatureValid) {
                        completetionHandler(YES, [error localizedDescription]);
                    } else {
                        completetionHandler(NO, @"lc.signer.latestCertificateInvalidErr");
                    }
                }
            });
        };
        
        // Get entitlements
        NSData* appProvData = [NSData dataWithContentsOfFile:[appPath stringByAppendingPathComponent:@"embedded.mobileprovision"]];
        NSDictionary* appEntitlements = [NSClassFromString(@"ZSigner") getEntitlementsWithProv:appProvData];

        NSURL *lcProfilePath = [NSBundle.mainBundle URLForResource:@"embedded" withExtension:@"mobileprovision"];
        NSData *lcProfileData = [NSData dataWithContentsOfURL:lcProfilePath];
        NSDictionary* lcEntitlements = [NSClassFromString(@"ZSigner") getEntitlementsWithProv:lcProfileData];

        NSMutableDictionary* mergedEntitlements = [lcEntitlements mutableCopy];
        if (appEntitlements) {
            [mergedEntitlements addEntriesFromDictionary:appEntitlements];
        }

        __block NSProgress *progress = [LCUtils signAppBundleWithZSign:appPathURL entitlements:mergedEntitlements completionHandler:signCompletionHandler];

        if (progress) {
            progressHandler(progress);
        }
        
    } @finally {
         // ✅ ONLY clear the flag here - this always runs regardless of how the method exits
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"SigningInProgress"];
        [NSUserDefaults.standardUserDefaults synchronize];
        NSLog(@"[LC] SigningInProgress flag cleared in @finally block");
    }
}

- (bool)isJITNeeded {
    if(_info[@"isJITNeeded"] != nil) {
        return [_info[@"isJITNeeded"] boolValue];
    } else {
        return NO;
    }
}
- (void)setIsJITNeeded:(bool)isJITNeeded {
    _info[@"isJITNeeded"] = [NSNumber numberWithBool:isJITNeeded];
    [self save];
    
}

- (bool)isLocked {
    if(_info[@"isLocked"] != nil) {
        return [_info[@"isLocked"] boolValue];
    } else {
        return NO;
    }
}
- (void)setIsLocked:(bool)isLocked {
    _info[@"isLocked"] = [NSNumber numberWithBool:isLocked];
    [self save];
    
}

- (bool)isHidden {
    if(_info[@"isHidden"] != nil) {
        return [_info[@"isHidden"] boolValue];
    } else {
        return NO;
    }
}
- (void)setIsHidden:(bool)isHidden {
    _info[@"isHidden"] = [NSNumber numberWithBool:isHidden];
    [self save];
    
}

- (bool)doSymlinkInbox {
    if(_info[@"doSymlinkInbox"] != nil) {
        return [_info[@"doSymlinkInbox"] boolValue];
    } else {
        return NO;
    }
}
- (void)setDoSymlinkInbox:(bool)doSymlinkInbox {
    _info[@"doSymlinkInbox"] = [NSNumber numberWithBool:doSymlinkInbox];
    [self save];
    
}

- (bool)hideLiveContainer {
    if(_info[@"hideLiveContainer"] != nil) {
        return [_info[@"hideLiveContainer"] boolValue];
    } else {
        return YES; // default to YES
    }
}
- (void)setHideLiveContainer:(bool)hideLiveContainer {
    _info[@"hideLiveContainer"] = [NSNumber numberWithBool:hideLiveContainer];
    [self save];
}

- (bool)dontInjectTweakLoader {
    if(_info[@"dontInjectTweakLoader"] != nil) {
        return [_info[@"dontInjectTweakLoader"] boolValue];
    } else {
        return NO;
    }
}
- (void)setDontInjectTweakLoader:(bool)dontInjectTweakLoader {
    if([_info[@"dontInjectTweakLoader"] boolValue] == dontInjectTweakLoader) {
        return;
    }
    
    _info[@"dontInjectTweakLoader"] = [NSNumber numberWithBool:dontInjectTweakLoader];
    // we have to update patch to achieve this
    _info[@"LCPatchRevision"] = @(-1);
    [self save];
}

- (bool)dontLoadTweakLoader {
    if(_info[@"dontLoadTweakLoader"] != nil) {
        return [_info[@"dontLoadTweakLoader"] boolValue];
    } else {
        return NO;
    }
}
- (void)setDontLoadTweakLoader:(bool)dontLoadTweakLoader {
    _info[@"dontLoadTweakLoader"] = [NSNumber numberWithBool:dontLoadTweakLoader];
    [self save];
}

- (bool)doUseLCBundleId {
    if(_info[@"doUseLCBundleId"] != nil) {
        return [_info[@"doUseLCBundleId"] boolValue];
    } else {
        return NO;
    }
}
- (void)setDoUseLCBundleId:(bool)doUseLCBundleId {
    _info[@"doUseLCBundleId"] = [NSNumber numberWithBool:doUseLCBundleId];
    NSString *infoPath = [NSString stringWithFormat:@"%@/Info.plist", self.bundlePath];
    if(doUseLCBundleId) {
        _info[@"LCOrignalBundleIdentifier"] = _infoPlist[@"CFBundleIdentifier"];
        _infoPlist[@"CFBundleIdentifier"] = NSBundle.mainBundle.bundleIdentifier;
    } else if (_info[@"LCOrignalBundleIdentifier"]) {
        _infoPlist[@"CFBundleIdentifier"] = _info[@"LCOrignalBundleIdentifier"];
        [_info removeObjectForKey:@"LCOrignalBundleIdentifier"];
    }
    [_infoPlist writeToFile:infoPath atomically:YES];
    [self save];
}

- (LCOrientationLock)orientationLock {
    return (LCOrientationLock) [((NSNumber*) _info[@"LCOrientationLock"]) intValue];

}
- (void)setOrientationLock:(LCOrientationLock)orientationLock {
    _info[@"LCOrientationLock"] = [NSNumber numberWithInt:(int) orientationLock];
    [self save];
    
}

- (UIColor*)cachedColor {
    if(_info[@"cachedColor"] != nil) {
        NSData *colorData = _info[@"cachedColor"];
        NSError* error;
        UIColor *color = [NSKeyedUnarchiver unarchivedObjectOfClass:UIColor.class fromData:colorData error:&error];
        if (!error) {
            return color;
        } else {
            NSLog(@"[LC] failed to get color %@", error);
            return nil;
        }
    } else {
        return nil;
    }
}

- (void)setCachedColor:(UIColor*) color {
    if(color == nil) {
        _info[@"cachedColor"] = nil;
    } else {
        NSError* error;
        NSData *colorData = [NSKeyedArchiver archivedDataWithRootObject:color requiringSecureCoding:YES error:&error];
        [_info setObject:colorData forKey:@"cachedColor"];
        if(error) {
            NSLog(@"[LC] failed to set color %@", error);
        }

    }
    [self save];
}

- (NSArray<NSDictionary*>* )containerInfo {
    return _info[@"LCContainers"];
}

- (void)setContainerInfo:(NSArray<NSDictionary *> *)containerInfo {
    _info[@"LCContainers"] = containerInfo;
    [self save];
}

- (bool)is32bit {
    if(_info[@"is32bit"] != nil) {
        return [_info[@"is32bit"] boolValue];
    } else {
        return NO;
    }
}
- (void)setIs32bit:(bool)is32bit {
    _info[@"is32bit"] = [NSNumber numberWithBool:is32bit];
    [self save];
    
}

- (bool)dontSign {
    if(_info[@"dontSign"] != nil) {
        return [_info[@"dontSign"] boolValue];
    } else {
        return NO;
    }
}
- (void)setDontSign:(bool)dontSign {
    _info[@"dontSign"] = [NSNumber numberWithBool:dontSign];
    [self save];
    
}

- (bool)spoofSDKVersion {
    if(!_info[@"spoofSDKVersion"]) {
        return false;
    } else {
        return [_info[@"spoofSDKVersion"] unsignedIntValue] != 0;
    }
}

- (void)setSpoofSDKVersion:(bool)doSpoof {
    if(!doSpoof) {
        _info[@"spoofSDKVersion"] = 0;
    } else {
        NSString *execPath = [NSString stringWithFormat:@"%@/%@", _bundlePath, _infoPlist[@"CFBundleExecutable"]];
        __block uint32_t sdkVersion = 0;
        LCParseMachO(execPath.UTF8String, true, ^(const char *path, struct mach_header_64 *header, int fd, void *filePtr) {
            sdkVersion = dyld_get_sdk_version((const struct mach_header *)header);
        });
        NSLog(@"[LC] sdkversion = %8x", sdkVersion);
        _info[@"spoofSDKVersion"] = [NSNumber numberWithUnsignedInt:sdkVersion];
    }
    [self save];
}

// MARK: GPS Addon Section
- (bool)spoofGPS {
    if(_info[@"spoofGPS"] != nil) {
        return [_info[@"spoofGPS"] boolValue];
    } else {
        return NO;
    }
}
- (void)setSpoofGPS:(bool)spoofGPS {
    _info[@"spoofGPS"] = [NSNumber numberWithBool:spoofGPS];
    [self save];
}

- (CLLocationDegrees)spoofLatitude {
    if(_info[@"spoofLatitude"] != nil) {
        return [_info[@"spoofLatitude"] doubleValue];
    } else {
        return 37.7749;
    }
}
- (void)setSpoofLatitude:(CLLocationDegrees)spoofLatitude {
    _info[@"spoofLatitude"] = [NSNumber numberWithDouble:spoofLatitude];
    [self save];
}

- (CLLocationDegrees)spoofLongitude {
    if(_info[@"spoofLongitude"] != nil) {
        return [_info[@"spoofLongitude"] doubleValue];
    } else {
        return -122.4194;
    }
}
- (void)setSpoofLongitude:(CLLocationDegrees)spoofLongitude {
    _info[@"spoofLongitude"] = [NSNumber numberWithDouble:spoofLongitude];
    [self save];
}

- (CLLocationDistance)spoofAltitude {
    if(_info[@"spoofAltitude"] != nil) {
        return [_info[@"spoofAltitude"] doubleValue];
    } else {
        return 0.0;
    }
}
- (void)setSpoofAltitude:(CLLocationDistance)spoofAltitude {
    _info[@"spoofAltitude"] = [NSNumber numberWithDouble:spoofAltitude];
    [self save];
}

- (NSString*)spoofLocationName {
    NSString* locationName = _info[@"spoofLocationName"];
    if (locationName && [locationName isKindOfClass:[NSString class]]) {
        return locationName;
    } else {
        return @"";
    }
}

- (void)setSpoofLocationName:(NSString*)spoofLocationName {
    if (spoofLocationName && [spoofLocationName length] > 0) {
        _info[@"spoofLocationName"] = spoofLocationName;
    } else {
        _info[@"spoofLocationName"] = @"";
    }
    [self save];
}

// MARK: Camera Addon Section
- (bool)spoofCamera {
    if(_info[@"spoofCamera"] != nil) {
        return [_info[@"spoofCamera"] boolValue];
    } else {
        return NO;
    }
}
- (void)setSpoofCamera:(bool)spoofCamera {
    _info[@"spoofCamera"] = [NSNumber numberWithBool:spoofCamera];
    [self save];
}

- (NSString*)spoofCameraType {
    NSString* cameraType = _info[@"spoofCameraType"];
    if (cameraType && [cameraType isKindOfClass:[NSString class]]) {
        return cameraType;
    } else {
        return @"image";
    }
}
- (void)setSpoofCameraType:(NSString*)spoofCameraType {
    if (spoofCameraType && [spoofCameraType length] > 0) {
        _info[@"spoofCameraType"] = spoofCameraType;
    } else {
        _info[@"spoofCameraType"] = @"video";
    }
    [self save];
}

- (NSString*)spoofCameraImagePath {
    NSString* imagePath = _info[@"spoofCameraImagePath"];
    if (imagePath && [imagePath isKindOfClass:[NSString class]]) {
        return imagePath;
    } else {
        return @"";
    }
}
- (void)setSpoofCameraImagePath:(NSString*)spoofCameraImagePath {
    if (spoofCameraImagePath && [spoofCameraImagePath length] > 0) {
        _info[@"spoofCameraImagePath"] = spoofCameraImagePath;
    } else {
        _info[@"spoofCameraImagePath"] = @"";
    }
    [self save];
}

- (NSString*)spoofCameraVideoPath {
    NSString* videoPath = _info[@"spoofCameraVideoPath"];
    if (videoPath && [videoPath isKindOfClass:[NSString class]]) {
        return videoPath;
    } else {
        return @"";
    }
}
- (void)setSpoofCameraVideoPath:(NSString*)spoofCameraVideoPath {
    if (spoofCameraVideoPath && [spoofCameraVideoPath length] > 0) {
        _info[@"spoofCameraVideoPath"] = spoofCameraVideoPath;
    } else {
        _info[@"spoofCameraVideoPath"] = @"";
    }
    [self save];
}

- (bool)spoofCameraLoop {
    if(_info[@"spoofCameraLoop"] != nil) {
        return [_info[@"spoofCameraLoop"] boolValue];
    } else {
        return YES; // Default to looping
    }
}
- (void)setSpoofCameraLoop:(bool)spoofCameraLoop {
    _info[@"spoofCameraLoop"] = [NSNumber numberWithBool:spoofCameraLoop];
    [self save];
}

// Mode 
- (NSString*)spoofCameraMode {
    NSString* cameraMode = _info[@"spoofCameraMode"];
    if (cameraMode && [cameraMode isKindOfClass:[NSString class]]) {
        return cameraMode;
    } else {
        return @"standard"; // Default mode
    }
}

- (void)setSpoofCameraMode:(NSString*)spoofCameraMode {
    _info[@"spoofCameraMode"] = spoofCameraMode ?: @"standard";
    [self save];
}

// MARK: Camera Transform Section

- (NSString*)spoofCameraTransformOrientation {
    NSString* orientation = _info[@"spoofCameraTransformOrientation"];
    if (orientation && [orientation isKindOfClass:[NSString class]]) {
        return orientation;
    } else {
        return @"none";
    }
}
- (void)setSpoofCameraTransformOrientation:(NSString*)spoofCameraTransformOrientation {
    _info[@"spoofCameraTransformOrientation"] = spoofCameraTransformOrientation ?: @"none";
    [self save];
}

- (NSString*)spoofCameraTransformScale {
    NSString* scale = _info[@"spoofCameraTransformScale"];
    if (scale && [scale isKindOfClass:[NSString class]]) {
        return scale;
    } else {
        return @"fit";
    }
}
- (void)setSpoofCameraTransformScale:(NSString*)spoofCameraTransformScale {
    _info[@"spoofCameraTransformScale"] = spoofCameraTransformScale ?: @"fit";
    [self save];
}

- (NSString*)spoofCameraTransformFlip {
    NSString* flip = _info[@"spoofCameraTransformFlip"];
    if (flip && [flip isKindOfClass:[NSString class]]) {
        return flip;
    } else {
        return @"none";
    }
}
- (void)setSpoofCameraTransformFlip:(NSString*)spoofCameraTransformFlip {
    _info[@"spoofCameraTransformFlip"] = spoofCameraTransformFlip ?: @"none";
    [self save];
}

// MARK: Network Addon Section
- (bool)spoofNetwork {
    if(_info[@"spoofNetwork"] != nil) {
        return [_info[@"spoofNetwork"] boolValue];
    } else {
        return NO;
    }
}
- (void)setSpoofNetwork:(bool)spoofNetwork {
    _info[@"spoofNetwork"] = [NSNumber numberWithBool:spoofNetwork];
    [self save];
}

- (NSString*)proxyType {
    NSString* type = _info[@"proxyType"];
    if (type && [type isKindOfClass:[NSString class]]) {
        return type;
    } else {
        return @"HTTP"; // Default type
    }
}
- (void)setProxyType:(NSString*)proxyType {
    _info[@"proxyType"] = proxyType ?: @"HTTP";
    [self save];
}

- (NSString*)proxyHost {
    NSString* host = _info[@"proxyHost"];
    if (host && [host isKindOfClass:[NSString class]]) {
        return host;
    } else {
        return @"";
    }
}
- (void)setProxyHost:(NSString*)proxyHost {
    _info[@"proxyHost"] = proxyHost ?: @"";
    [self save];
}

- (int32_t)proxyPort {
    if(_info[@"proxyPort"] != nil) {
        return [_info[@"proxyPort"] intValue];
    } else {
        return 8080; // Default port
    }
}
- (void)setProxyPort:(int32_t)proxyPort {
    _info[@"proxyPort"] = [NSNumber numberWithInt:proxyPort];
    [self save];
}

- (NSString*)proxyUsername {
    NSString* username = _info[@"proxyUsername"];
    if (username && [username isKindOfClass:[NSString class]]) {
        return username;
    } else {
        return @"";
    }
}
- (void)setProxyUsername:(NSString*)proxyUsername {
    _info[@"proxyUsername"] = proxyUsername ?: @"";
    [self save];
}

- (NSString*)proxyPassword {
    NSString* password = _info[@"proxyPassword"];
    if (password && [password isKindOfClass:[NSString class]]) {
        return password;
    } else {
        return @"";
    }
}
- (void)setProxyPassword:(NSString*)proxyPassword {
    _info[@"proxyPassword"] = proxyPassword ?: @"";
    [self save];
}

- (NSString*)spoofNetworkMode {
    NSString* mode = _info[@"spoofNetworkMode"];
    if (mode && [mode isKindOfClass:[NSString class]]) {
        return mode;
    } else {
        return @"standard"; // Default mode
    }
}
- (void)setSpoofNetworkMode:(NSString*)spoofNetworkMode {
    _info[@"spoofNetworkMode"] = spoofNetworkMode ?: @"standard";
    [self save];
}

// MARK: UI Addon Section
- (NSDate*)lastLaunched {
    return _info[@"lastLaunched"];
}

- (void)setLastLaunched:(NSDate*)lastLaunched {
    _info[@"lastLaunched"] = lastLaunched;
    [self save];
}

- (NSDate*)installationDate {
    return _info[@"installationDate"];
}

- (void)setInstallationDate:(NSDate*)installationDate {
    _info[@"installationDate"] = installationDate;
    [self save];
}

@end
