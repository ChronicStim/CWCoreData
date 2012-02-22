//
//  NSPersistentStoreCoordinator+CWAdditions.m
//  CWCoreData
//  Created by Fredrik Olsson 
//
//  Copyright (c) 2011, Jayway AB All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright
//       notice, this list of conditions and the following disclaimer in the
//       documentation and/or other materials provided with the distribution.
//     * Neither the name of Jayway AB nor the names of its contributors may 
//       be used to endorse or promote products derived from this software 
//       without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
//  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
//  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
//  DISCLAIMED. IN NO EVENT SHALL JAYWAY AB BE LIABLE FOR ANY DIRECT, INDIRECT, 
//  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT 
//  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR 
//  PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF 
//  LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE 
//  OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF 
//  ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

#import "NSPersistentStoreCoordinator+CWCoreData.h"
#import "NSManagedObjectModel+CWCoreData.h"

#define DEFAULT_CACHE_FOLDER_NAME @"CPT_RptDatabase_Cache"

#define kPSCStoreFilenameDiary @"CPT_PrimaryDiary.sqlite"
#define kPSCStoreFilenameReports @"CPT_ReportData.sqlite"
#define kPSCConfigurationDiary @"DiaryModel"
#define kPSCConfigurationReports @"DiaryReportsModel"
#define kPrefLastVersionRunKey @"prefLastVersionRun"

@implementation NSPersistentStoreCoordinator (CWCoreData)

static NSPersistentStoreCoordinator* _persistentStoreCoordinator = nil;

+(NSPersistentStoreCoordinator*)defaultCoordinator;
{
    if (_persistentStoreCoordinator == nil) {
    
    	static NSString *storeFilename = kPSCStoreFilenameDiary;
        static NSString *storeFilenameReportData = kPSCStoreFilenameReports;
        
        NSArray *storeArray = [NSArray arrayWithObjects:storeFilename,storeFilenameReportData, nil];
        
        NSLog(@"Active database for newPSC = %@",storeFilename);
        NSLog(@"Active database for newPSC = %@",storeFilenameReportData);
        
        NSManagedObjectModel *mom = [NSManagedObjectModel defaultModel];
        if (!mom) {
            //NSAssert(NO, @"NSManagedObjectModel is nil");
            NSLog(@"%@: No model to generate a store from", [self class]);
            return nil;
        }
        
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *appDocumentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
        if ( ![fileManager fileExistsAtPath:appDocumentsDirectory isDirectory:NULL] ) {
            if (![fileManager createDirectoryAtPath:appDocumentsDirectory withIntermediateDirectories:NO attributes:nil error:nil]) {
                //NSAssert(NO, ([NSString stringWithFormat:@"Failed to create App Support directory %@", appDocumentsDirectory]));
                NSLog(@"Failed to create application directory: %@", appDocumentsDirectory);
                return nil;
            }
        }
        
        _persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:mom];
        
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *cacheDirectory = [paths objectAtIndex:0];
        NSString *cacheFolderPath = [cacheDirectory stringByAppendingPathComponent:DEFAULT_CACHE_FOLDER_NAME];
        
        BOOL isDirectory = NO;
        BOOL folderExists = [fileManager fileExistsAtPath:cacheFolderPath isDirectory:&isDirectory] && isDirectory;
        
        if (!folderExists)
        {
            NSError *error = nil;
            [fileManager createDirectoryAtPath:cacheFolderPath withIntermediateDirectories:YES attributes:nil error:&error];
            [error release];
        }
        
        for (NSString *filename in storeArray) {
            
            NSString *configuration;
            NSString *storePath;
            if ([filename isEqualToString:kPSCStoreFilenameDiary]) {
                configuration = kPSCConfigurationDiary;
                storePath = [appDocumentsDirectory stringByAppendingPathComponent: filename];
            } else if ([filename isEqualToString:kPSCStoreFilenameReports]) {
                configuration = kPSCConfigurationReports;
                storePath = [cacheFolderPath stringByAppendingPathComponent: filename];
            } else {
                configuration = nil;
                storePath = nil;
            }
            NSURL *storeUrl = [NSURL fileURLWithPath: storePath];
            
            // Check if a previously failed migration has left a *.new store in the filesystem. If it has, then remove it before the next migration.
            NSString *storePathNew = [storePath stringByAppendingPathExtension:@"new"];
            if ([fileManager fileExistsAtPath:storePathNew]) {
                NSError *errorNewRemoval = nil;
                if (![fileManager removeItemAtPath:storePathNew error:&errorNewRemoval]) {
                    NSLog(@"Removal of %@.new file was not successful",filename);
                }
            }
            
            // Need to see if the database files exist or not
            BOOL databaseFileExists = [fileManager fileExistsAtPath:storePath];
            if (databaseFileExists) {
                // If file exists, compatibility needs to be checked.
                NSString *sourceStoreType = NSSQLiteStoreType;
                NSError *errorCompatibility = nil;
                NSDictionary *sourceMetadata = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:sourceStoreType URL:storeUrl error:&errorCompatibility];
                
                if (sourceMetadata == nil) {
                    // deal with error
                    NSLog(@"Could not retrieve metadata from the store: %@ with Error: %@",storeFilename,[errorCompatibility userInfo]);
                }
                
                NSManagedObjectModel *destinationModel = [_persistentStoreCoordinator managedObjectModel];
                BOOL pscCompatibile = [destinationModel isConfiguration:configuration compatibleWithStoreMetadata:sourceMetadata];
                
                // If not compatible, then need to try to migrate using the workaround process.
                BOOL migrationWorkaroundHasBeenRun = NO;
                //BOOL migrationWorkaroundSucceeded = NO;
                if (!pscCompatibile) {
                    
                    while (!migrationWorkaroundHasBeenRun) {

                        NSString *dummyPSCString = @"dummyPSC";
                        
                        NSString *lastVersionRun;
                        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                        if ([defaults objectForKey:kPrefLastVersionRunKey]) {
                            lastVersionRun = [defaults objectForKey:kPrefLastVersionRunKey];
                        } else {
                            lastVersionRun = @"";
                        }

                        NSString *versionString;
                        NSString *ver = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
                        versionString = [NSString stringWithFormat:@"v%@",ver];

                        NSString *message = [NSString stringWithFormat:@"%@ to %@ migration for store: %@. Running workaround.",lastVersionRun,versionString,filename];
                        NSLog(@"Running migration workaround to try and bypass incompatibility. %@",message);

                        NSLog(@"Active database for %@ = %@",dummyPSCString,filename);
                        
                        NSString *configuration = nil;
                        NSString *storePath;
                        if ([filename isEqualToString:kPSCStoreFilenameDiary]) {
                            storePath = [appDocumentsDirectory stringByAppendingPathComponent: filename];
                        } else if ([filename isEqualToString:kPSCStoreFilenameReports]) {
                            storePath = [cacheFolderPath stringByAppendingPathComponent: filename];
                        } else {
                            configuration = nil;
                            storePath = nil;
                        }
                        
                        NSURL *storeUrl = [NSURL fileURLWithPath: storePath];
                        NSPersistentStoreCoordinator *dummyPSC = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:mom];
                        NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES],NSMigratePersistentStoresAutomaticallyOption,[NSNumber numberWithBool:YES],NSInferMappingModelAutomaticallyOption,nil];
                        NSError *error = nil;
                        if (![dummyPSC addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeUrl options:options error:&error]) {
                            NSLog(@"Core Data Error:%@ : %@",[error localizedDescription],[error userInfo]);
                           // migrationWorkaroundSucceeded = NO;
                            NSString *message = [NSString stringWithFormat:@"%@ to %@ migration for store: %@. Failed workaround.",lastVersionRun,versionString,filename];
                            NSLog(@"Failed to resolve migration issue. %@",message);
                        } else {
                            //migrationWorkaroundSucceeded = YES;
                            NSString *message = [NSString stringWithFormat:@"%@ to %@ migration for store: %@. Migration workaround succeeded.",lastVersionRun,versionString,filename];
                            NSLog(@"Migration issue resolved. %@",message);
                        }                        
                        [dummyPSC release], dummyPSC=nil;
                        migrationWorkaroundHasBeenRun = YES;
                    }                    
                }
            }
            
            // Proceed with store assignment
            NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES],NSMigratePersistentStoresAutomaticallyOption,[NSNumber numberWithBool:YES],NSInferMappingModelAutomaticallyOption,nil];
            NSError *error = nil;
            if (![_persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:configuration URL:storeUrl options:options error:&error]) {
                NSLog(@"Core Data Error:%@ : %@",[error localizedDescription],[error userInfo]);
                [_persistentStoreCoordinator release], _persistentStoreCoordinator = nil;
            }  
        }
        
        [NSPersistentStoreCoordinator setDefaultCoordinator:_persistentStoreCoordinator];

    }
    return _persistentStoreCoordinator;
}

+(void)setDefaultCoordinator:(NSPersistentStoreCoordinator*)coordinator;
{
	[_persistentStoreCoordinator autorelease];
    _persistentStoreCoordinator = [coordinator retain];
}
+(void)setDefaultStoreURL:(NSURL*)storeURL type:(NSString*)storeType;
{
	[_persistentStoreCoordinator autorelease];
    NSError* error = nil;
    _persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[NSManagedObjectModel defaultModel]];
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
                             [NSNumber numberWithBool:YES], NSMigratePersistentStoresAutomaticallyOption,
                             [NSNumber numberWithBool:YES], NSInferMappingModelAutomaticallyOption, nil];
    if (![_persistentStoreCoordinator addPersistentStoreWithType:storeType 
                                                   configuration:nil 
                                                             URL:storeURL 
                                                         options:options 
                                                           error:&error]) {
        [_persistentStoreCoordinator release];
        _persistentStoreCoordinator = nil;
    }
    if (_persistentStoreCoordinator == nil) {
    	[NSException raise:NSInternalInconsistencyException format:@"Could not setup default persistence store of type %@ at URL %@ (Error: %@)", storeType, [storeURL absoluteURL], [error localizedDescription]];
    } else {
        NSLog(@"Did create default NSPersistentStoreCoordinator of type %@ at %@", storeType, [[storeURL absoluteString] stringByAbbreviatingWithTildeInPath]);
    }
}


@end
