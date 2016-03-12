/*
 Copyright (c) 2015, OpenEmu Team
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
     * Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
     * Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.
     * Neither the name of the OpenEmu Team nor the
       names of its contributors may be used to endorse or promote products
       derived from this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "OEDBRom.h"
#import "OEDBGame.h"
#import "OEDBSaveState.h"

#import "OELibraryDatabase.h"

#import "NSFileManager+OEHashingAdditions.h"

#import <OpenEmuSystem/OECUESheet.h>
#import <OpenEmuSystem/OECloneCD.h>

#import "OpenEmu-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OEDBRom

@dynamic URL;

// Data Model Properties
@dynamic location, favorite, crc32, md5, lastPlayed, fileSize, playCount, playTime, archiveFileIndex, header, serial, fileName, source;

// Data Model Relationships
@dynamic game, saveStates, tosec;

#pragma mark -

+ (nullable instancetype)romWithURL:(nullable NSURL *)url inContext:(NSManagedObjectContext *)context error:(NSError **)outError
{
    if(url == nil) return nil;

    OELibraryDatabase *library = context.userInfo[OELibraryDatabaseUserInfoKey];
    NSURL *romFolderURL = library.romsFolderURL;

    url = [url urlRelativeToURL:romFolderURL];

    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"location == %@", url.relativeString];
    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:[self entityName]];
    
    fetchRequest.fetchLimit = 1;
    fetchRequest.includesPendingChanges = YES;
    fetchRequest.predicate = predicate;
    
    return [context executeFetchRequest:fetchRequest error:outError].lastObject;
}

#pragma mark -

+ (nullable instancetype)romWithCRC32HashString:(nullable NSString *)crcHash inContext:(NSManagedObjectContext *)context error:(NSError **)outError
{
    if(crcHash == nil) return nil;
    
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"crc32 == %@", crcHash];
    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:[self entityName]];
    
    fetchRequest.fetchLimit = 1;
    fetchRequest.includesPendingChanges = YES;
    fetchRequest.predicate = predicate;
    
    return [context executeFetchRequest:fetchRequest error:outError].lastObject;
}

+ (nullable instancetype)romWithMD5HashString:(nullable NSString *)md5Hash inContext:(NSManagedObjectContext *)context error:(NSError **)outError
{
    if(md5Hash == nil) return nil;
    
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"md5 == %@", md5Hash.lowercaseString];
    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:[self entityName]];
    
    fetchRequest.fetchLimit = 1;
    fetchRequest.includesPendingChanges = YES;
    fetchRequest.predicate = predicate;
    
    return [context executeFetchRequest:fetchRequest error:outError].lastObject;
}

#pragma mark - Accessors

- (nullable NSURL *)URL
{
    NSURL *romFolderURL = self.libraryDatabase.romsFolderURL;
    return [NSURL URLWithString:self.location relativeToURL:romFolderURL];
}

- (void)setURL:(nullable NSURL *)url
{
    NSURL *romFolderURL = self.libraryDatabase.romsFolderURL;
    self.location = [url urlRelativeToURL:romFolderURL]. relativeString;
}

- (nullable NSURL *)sourceURL
{
    return [NSURL URLWithString:self.source];
}

- (void)setSourceURL:(nullable NSURL *)sourceURL
{
    self.source = sourceURL.absoluteString;
}

- (nullable NSString *)md5Hash
{
    NSString *hash = self.md5;
    if(hash == nil)
    {
        [self OE_calculateHashes];
        hash = self.md5HashIfAvailable;
    }
    return hash;
}

- (nullable NSString *)md5HashIfAvailable
{
    return self.md5;
}

- (nullable NSString *)crcHash
{
    NSString *hash = self.crc32;
    if(hash == nil)
    {
        [self OE_calculateHashes];
        hash = self.crcHashIfAvailable;
    }
    return hash;    
}

- (nullable NSString *)crcHashIfAvailable
{
    return self.crc32;
}

- (void)OE_calculateHashes
{
    NSError *error = nil;
    NSURL *url = self.URL;
    
    if(![url checkResourceIsReachableAndReturnError:&error])
    {
        // TODO: mark self as file missing
        DLog(@"%@", error);
        return;
    }
    
    NSString *md5Hash, *crc32Hash;
    if(![[NSFileManager defaultManager] hashFileAtURL:url md5:&md5Hash crc32:&crc32Hash error:&error])
    {
        DLog(@"%@", error);
        // TODO: mark self as file missing
        return;
    }
    
    self.crc32 = crc32Hash.lowercaseString;
    self.md5 = md5Hash.lowercaseString;
}

- (nullable NSArray <OEDBSaveState *> *)normalSaveStates
{
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"NOT (name beginswith[c] %@)", @"OESpecialState"];
    NSSet *set = self.saveStates;
    set = [set filteredSetUsingPredicate:predicate];
    
    return set.allObjects;
}

- (nullable NSArray <OEDBSaveState *> *)normalSaveStatesByTimestampAscending:(BOOL)ascFlag
{
    return [self.normalSaveStates sortedArrayUsingComparator:
            ^ NSComparisonResult (OEDBSaveState *obj1, OEDBSaveState *obj2)
            {
                NSDate *d1 = obj1.timestamp, *d2 = obj2.timestamp;
                
                return ascFlag ? [d2 compare:d1] : [d1 compare:d2];
            }];
}


- (NSInteger)saveStateCount
{
    return self.saveStates.count;
}

- (nullable OEDBSaveState *)autosaveState
{
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"name beginswith[c] %@", OESaveStateAutosaveName];

    return [self.saveStates filteredSetUsingPredicate:predicate].anyObject;
}

- (nullable NSArray *)quickSaveStates
{
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"name beginswith[c] %@", OESaveStateQuicksaveName];
    
    return [self.saveStates filteredSetUsingPredicate:predicate].allObjects;
}

- (nullable OEDBSaveState *)quickSaveStateInSlot:(NSInteger)num
{
    NSString *quickSaveName = [OEDBSaveState nameOfQuickSaveInSlot:num];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"name beginswith[c] %@", quickSaveName];
    
    return [self.saveStates filteredSetUsingPredicate:predicate].anyObject;
}

- (nullable OEDBSaveState *)saveStateWithName:(NSString *)string
{
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"name == %@", string];
    
    return [self.saveStates filteredSetUsingPredicate:predicate].anyObject;
}

- (void)removeMissingStates
{
    NSSet *set = self.saveStates.copy;
    [set makeObjectsPerformSelector:@selector(deleteAndRemoveFilesIfInvalid)];
    [self save];
}

- (void)incrementPlayCount
{
    NSInteger currentCount = self.playCount.integerValue;
    currentCount++;
    self.playCount = @(currentCount);
    self.game.playCount = @(self.game.playCount.integerValue + 1);
}

- (void)addTimeIntervalToPlayTime:(NSTimeInterval)timeInterval
{
    NSTimeInterval currentPlayTime = self.playTime.doubleValue;
    currentPlayTime += timeInterval;
    self.playTime = @(currentPlayTime);
}

// Core Data does not care about getter= overrides in modelled property declarations,
// so we provide our own -isFavorite
- (nullable NSNumber *)isFavorite
{
    // We cannot use -valueForKey:@"favorite" since vanilla KVC would end up
    // calling this very method, so we use -primitiveValueForKey: instead

    NSString *key = @"favorite";
    
    [self willAccessValueForKey:key];
    NSNumber *value = [self primitiveValueForKey:key];
    [self didAccessValueForKey:key];

    return value;
}

#pragma mark - File Handling

- (BOOL)consolidateFilesWithError:(NSError**)error
{
    NSURL *url = self.URL;
    OELibraryDatabase *library = self.libraryDatabase;
    NSURL *romsFolderURL = library.romsFolderURL;

    if([url checkResourceIsReachableAndReturnError:nil] && ![url isSubpathOfURL:romsFolderURL])
    {
        BOOL romFileLocked = NO;
        if([[[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:nil][NSFileImmutable] boolValue])
        {
            romFileLocked = YES;
            [[NSFileManager defaultManager] setAttributes:@{ NSFileImmutable: @(FALSE) } ofItemAtPath:url.path error:nil];
        }

        NSString *fullName  = url.lastPathComponent;
        NSString *extension = fullName.pathExtension;
        NSString *baseName  = fullName.stringByDeletingPathExtension;

        OEDBSystem  *system = self.game.system;

        NSURL *unsortedFolder = [library romsFolderURLForSystem:system];
        NSURL *romURL         = [unsortedFolder URLByAppendingPathComponent:fullName];
        romURL = [romURL uniqueURLUsingBlock:^NSURL *(NSInteger triesCount) {
            NSString *newName = [NSString stringWithFormat:@"%@ %ld.%@", baseName, triesCount, extension];
            return [unsortedFolder URLByAppendingPathComponent:newName];
        }];

        if([[NSFileManager defaultManager] copyItemAtURL:url toURL:romURL error:error])
        {
            self.URL = romURL;
            NSLog(@"New URL: %@", romURL);
        }
        else if(error != nil) return NO;

        if(romFileLocked)
            [[NSFileManager defaultManager] setAttributes:@{ NSFileImmutable: @(YES) } ofItemAtPath:url.path error:nil];
    }
    return YES;
}

- (BOOL)filesAvailable
{
    NSError *error = nil;
    BOOL    result = [self.URL checkResourceIsReachableAndReturnError:&error];
    return result;
}
#pragma mark - Mainpulating a rom

- (void)markAsPlayedNow
{
    self.lastPlayed = [NSDate date];
}

#pragma mark - Core Data utilities

- (void)deleteByMovingFile:(BOOL)moveToTrash keepSaveStates:(BOOL)statesFlag
{
    NSURL *url = [self URL];

    if(moveToTrash && [url isSubpathOfURL:self.libraryDatabase.romsFolderURL])
    {
        NSInteger count = 1;
        if([self archiveFileIndex])
        {
            NSPredicate *predicate = [NSPredicate predicateWithFormat:@"location == %@", [self location]];
            NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:[[self class] entityName]];
            [fetchRequest setPredicate:predicate];
            count = [self.managedObjectContext countForFetchRequest:fetchRequest error:nil];
        }

        if(count == 1)
        {
            NSString *path = url.path;
            NSURL *baseURL = [NSURL fileURLWithPath:path.stringByDeletingLastPathComponent isDirectory:YES];
            NSMutableArray *fileNames = @[ path.lastPathComponent ].mutableCopy;

            if([[path.pathExtension lowercaseString] isEqualToString:@"cue"])
            {
                OECUESheet *sheet = [[OECUESheet alloc] initWithPath:path];
                NSArray *additionalFileNames = sheet.referencedFileNames;
                [fileNames addObjectsFromArray:additionalFileNames];
            }
            else if([path.pathExtension.lowercaseString isEqualToString:@"ccd"])
            {
                OECloneCD *ccd = [[OECloneCD alloc] initWithURL:url];
                NSArray *additionalFileNames = ccd.referencedFileNames;
                [fileNames addObjectsFromArray:additionalFileNames];
            }

            for(int i=0; i < [fileNames count]; i++){
                NSString *fileName = fileNames[i];
                NSURL *url = [NSURL fileURLWithPath:fileName isDirectory:NO relativeToURL:baseURL];
                [fileNames replaceObjectAtIndex:i withObject:url];
            }

            [[NSWorkspace sharedWorkspace] recycleURLs:fileNames completionHandler:^(NSDictionary<NSURL *,NSURL *> * _Nonnull newURLs, NSError * _Nullable error) {}];
        } else DLog(@"Keeping file, other roms depent on it!");
    }

    if(!statesFlag)
    {
        // TODO: remove states
    }

    [self.managedObjectContext deleteObject:self];
}

+ (NSString *)entityName
{
    return @"ROM";
}

+ (NSEntityDescription *)entityDescriptionInContext:(NSManagedObjectContext *)context
{
    return [NSEntityDescription entityForName:[self entityName] inManagedObjectContext:context];
}

- (nullable NSMutableSet <OEDBSaveState *> *)mutableSaveStates
{
    return [self mutableSetValueForKey:@"saveStates"];
}

#pragma mark - Debug

- (void)dump
{
    [self dumpWithPrefix:@"---"];
}

- (void)dumpWithPrefix:(NSString *)prefix
{
//    NSString *subPrefix = [prefix stringByAppendingString:@"-----"];
    NSLog(@"%@ Beginning of ROM dump", prefix);

    NSLog(@"%@ ROM location is %@", prefix, self.location);
    NSLog(@"%@ favorite? %s", prefix, BOOL_STR(self.isFavorite));
    NSLog(@"%@ CRC32 is %@", prefix, self.crc32);
    NSLog(@"%@ MD5 is %@", prefix, self.md5);
    NSLog(@"%@ last played is %@", prefix, self.lastPlayed);
    NSLog(@"%@ file size is %@", prefix, self.fileSize);
    NSLog(@"%@ play count is %@", prefix, self.playCount);
    NSLog(@"%@ play time is %@", prefix, self.playTime);
    NSLog(@"%@ ROM is linked to a game? %s", prefix, (self.game ? "YES" : "NO"));

    NSLog(@"%@ Number of save states for this ROM is %ld", prefix, (unsigned long)self.saveStateCount);

    NSLog(@"%@ End of ROM dump\n\n", prefix);
}

@end

NS_ASSUME_NONNULL_END
