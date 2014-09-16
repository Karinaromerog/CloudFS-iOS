//
//  BitcasaAPI.m
//  BitcasaSDK
//
//  Created by Olga on 8/21/14.
//  Copyright (c) 2014 Bitcasa. All rights reserved.
//

#import "BitcasaAPI.h"
#import "NSString+API.h"
#import "Session.h"
#import "Credentials.h"
#import "Item.h"
#import "Container.h"
#import "User.h"
#import "TransferManager.h"
#import "BCInputStream.h"
#import "Folder.h"
#import "File.h"

#import <AssetsLibrary/AssetsLibrary.h>
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonHMAC.h>

NSString* const kAPIEndpointToken = @"/oauth2/token";


NSString* const kAPIEndpointMetafolders = @"/metafolders";
NSString* const kAPIEndpointUser = @"/user";
NSString* const kAPIEndpointProfile = @"/profile/";
NSString* const kAPIEndpointAccount = @"/account";
NSString* const kAPIEndpointMsg = @"/msg/";
NSString* const kAPIEndpointSessions = @"/sessions/";
NSString* const kAPIEndpointCurrentSession = @"current/";
NSString* const kAPIEndpointThumbnail = @"/thumbnail/";
NSString* const kAPIEndpointShares = @"/shares/";
NSString* const kAPIEndpointEntrypoint = @"/filesystem/entrypoints/";
NSString* const kAPIEndpointTranscode = @"/transcode";
NSString* const kAPIEndpointVideo = @"/video";
NSString* const kAPIEndpointAudio = @"/audio";
NSString* const kAPIEndpointBatch = @"/batch";
NSString* const kAPIEndpointTrash = @"/trash";

NSString* const kCameraBackupEntrypointID = @"015199f04c044c5fa95fc69556cf723e";

NSString* const kHeaderContentType = @"Content-Type";
NSString* const kHeaderAuth = @"Authorization";
NSString* const kHeaderDate = @"Date";

NSString* const kHeaderContentTypeForm = @"application/x-www-form-urlencoded";
NSString* const kHeaderContentTypeJson = @"application/json";

NSString* const kHTTPMethodGET = @"GET";
NSString* const kHTTPMethodPOST = @"POST";
NSString* const kHTTPMethodDELETE = @"DELETE";

NSString* const kQueryParameterOperation = @"operation";
NSString* const kQueryParameterOperationMove = @"move";
NSString* const kQueryParameterOperationCopy = @"copy";
NSString* const kQueryParameterOperationCreate = @"create";

NSString* const kDeleteRequestParameterCommit = @"commit";
NSString* const kDeleteRequestParameterForce = @"force";

NSString* const kTrashRequestParameterRestore = @"restore";
NSString* const kTrashRequestParameterRescuePath = @"rescue-path";

NSString* const kRequestParameterTrue = @"true";
NSString* const kRequestParameterFalse = @"false";

NSString* const kBatchRequestJsonRequestsKey = @"requests";
NSString* const kBatchRequestJsonRelativeURLKey = @"relative_url";
NSString* const kBatchRequestJsonMethodKey = @"method";
NSString* const kBatchRequestJsonBody = @"body";

@interface BitcasaAPI ()
+ (NSString*)apiVersion;
+ (NSString*)authContentType;
+ (NSString*)contentType;
@end

@implementation NSURLRequest (Bitcasa)

- (id)initWithMethod:(NSString*)httpMethod endpoint:(NSString*)endpoint queryParameters:(NSArray*)queryParams formParameters:(id)formParams
{
    Credentials* baseCredentials = [Credentials sharedInstance];
    NSMutableString* urlStr = [NSMutableString stringWithFormat:@"%@%@%@", baseCredentials.serverURL, [BitcasaAPI apiVersion], endpoint];
    
    if (queryParams)
        [urlStr appendFormat:@"?%@", [NSString parameterStringWithArray:queryParams]];
    
    NSURL* profileRequestURL = [NSURL URLWithString:urlStr];
    
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:profileRequestURL];
    
    [request setHTTPMethod:httpMethod];
    [request addValue:[NSString stringWithFormat:@"Bearer %@", baseCredentials.accessToken] forHTTPHeaderField:kHeaderAuth];
    
    NSData* formParamJsonData;
    NSString* contentTypeStr;
    if ([formParams isKindOfClass:[NSArray class]])
    {
        contentTypeStr = kHeaderContentTypeForm;
        NSString* formParameters = [NSString parameterStringWithArray:formParams];
        formParamJsonData = [formParameters dataUsingEncoding:NSUTF8StringEncoding];
    }
    else if ([formParams isKindOfClass:[NSDictionary class]])
    {
        contentTypeStr = kHeaderContentTypeJson;
        NSError* err;
        formParamJsonData = [NSJSONSerialization dataWithJSONObject:formParams options:0 error:&err];
        
        NSString* jsonStr = [[NSString alloc] initWithData:formParamJsonData encoding:NSUTF8StringEncoding];
        jsonStr = [jsonStr stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
        formParamJsonData = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];
    }
    [request setValue:contentTypeStr forHTTPHeaderField:kHeaderContentType];
    [request setHTTPBody:formParamJsonData];
    
    return request;
}

- (id)initWithMethod:(NSString*)httpMethod endpoint:(NSString *)endpoint
{
    return [self initWithMethod:httpMethod endpoint:endpoint queryParameters:nil formParameters:nil];
}

+ (id)requestForOperation:(NSString*)operation onItem:(Item*)item destinationItem:(Container*)destItem
{
    NSString* endpointPath = [item endpointPath];
    NSArray* queryParams = @[@{kQueryParameterOperation : operation}];
    
    NSString* toItemPath = destItem.url;
    NSDictionary* moveFormParams = @{@"to": toItemPath, @"name": item.name};
    
    NSURLRequest* request = [[NSURLRequest alloc] initWithMethod:kHTTPMethodPOST endpoint:endpointPath queryParameters:queryParams formParameters:moveFormParams];
    return request;
}

@end


@implementation BitcasaAPI

+ (NSString*)apiVersion
{
    return @"/v2";
}

+ (NSString*)authContentType
{
    return @"application/x-www-form-urlencoded; charset=\"utf-8\"";
}

+ (NSString*)contentType
{
    return @"application/x-www-form-urlencoded";
}

#pragma mark - access token
+ (NSString *)accessTokenWithEmail:(NSString *)email password:(NSString *)password
{
    Credentials* baseCredentials = [Credentials sharedInstance];
    
    // formatting the request string (to be signed)
    NSMutableString* requestString = [NSMutableString stringWithString:kHTTPMethodPOST];
    [requestString appendString:[NSString stringWithFormat:@"&%@%@", [BitcasaAPI apiVersion], kAPIEndpointToken]];
    
    NSArray* parameters = @[@{@"grant_type": @"password"}, @{@"password" : password}, @{@"username" : email}];
    [requestString appendString:[NSString stringWithFormat:@"&%@", [NSString parameterStringWithArray:parameters]]];
    [requestString appendString:[NSString stringWithFormat:@"&%@:%@", kHeaderContentType, [[BitcasaAPI authContentType] encode]]];
    
    NSDateFormatter* df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"EEE', 'd' 'MMM' 'yyyy' 'hh':'mm':'ss' 'z"];
    NSString* dateStr = [df stringFromDate:[NSDate date]];
    [requestString appendString:[NSString stringWithFormat:@"&%@:%@", kHeaderDate, [dateStr encode]]];
    
    // generating the signed request string
    NSData* secretData = [baseCredentials.appSecret dataUsingEncoding:NSUTF8StringEncoding];
    NSData* requestStrData = [requestString dataUsingEncoding:NSUTF8StringEncoding];
    
    NSMutableData* signedRequestData = [NSMutableData dataWithLength:CC_SHA1_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA1, secretData.bytes, secretData.length, requestStrData.bytes, requestStrData.length, signedRequestData.mutableBytes);
    NSString* signedRequestStr = [signedRequestData base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength];
    
    // creating the HTTP request
    NSURL* tokenReqURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@%@", baseCredentials.serverURL, [BitcasaAPI apiVersion], kAPIEndpointToken]];
    NSMutableURLRequest* tokenRequest = [NSMutableURLRequest requestWithURL:tokenReqURL];
    
    [tokenRequest setHTTPMethod:kHTTPMethodPOST];
    
    // setting HTTP request headers
    [tokenRequest addValue:[BitcasaAPI authContentType] forHTTPHeaderField:kHeaderContentType];
    [tokenRequest addValue:dateStr forHTTPHeaderField:kHeaderDate];
    NSString* authValue = [NSString stringWithFormat:@"BCS %@:%@", baseCredentials.appId,  signedRequestStr];
    [tokenRequest addValue:authValue forHTTPHeaderField:kHeaderAuth];
    
    // setting HTTP request parameters
    NSString* formParameters = [NSString parameterStringWithArray:parameters];
    [tokenRequest setHTTPBody:[formParameters dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSError* err;
    NSHTTPURLResponse *response;
    NSData *data = [NSURLConnection sendSynchronousRequest:tokenRequest returningResponse:&response error:&err];
    if ([response statusCode] != 200)
        return nil;
    
    if (data)
    {
        NSError *jsonError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (json[@"access_token"])
            return json[@"access_token"];
    }
    
    return nil;
}

#pragma mark - Get profile
+ (void)getProfileWithCompletion:(void(^)(NSDictionary* response))completion
{
    NSString *profileEndpoint = [NSString stringWithFormat:@"%@%@", kAPIEndpointUser, kAPIEndpointProfile];
    NSURLRequest* profileRequest = [[NSURLRequest alloc] initWithMethod:kHTTPMethodGET endpoint:profileEndpoint];
    
    [NSURLConnection sendAsynchronousRequest:profileRequest queue:[NSOperationQueue currentQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError)
     {
         NSInteger responseStatusCode = [((NSHTTPURLResponse*)response) statusCode];
         if (responseStatusCode == 200)
         {
             NSDictionary* responseDict;
             if (data)
             {
                 NSError* err;
                 responseDict = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:&err];
             }
             if (completion)
                 completion(responseDict[@"result"]);
             return;
         }
         else if (responseStatusCode == 401)
         {
             //[[BCTransferManager sharedManager] reauthenticate];
         }
         if (completion)
             completion(nil);
     }];
}

#pragma mark - List directory contents


+ (void)getContentsOfContainer:(Container*)container completion:(void (^)(NSArray* items))completion
{
    if (container == nil)
    {
        container = [[Container alloc] initRootContainer];
    }
    
    NSString* dirReqEndpoint = [container endpointPath];
    
    NSURLRequest* dirContentsRequest = [[NSURLRequest alloc] initWithMethod:kHTTPMethodGET endpoint:dirReqEndpoint];
    
    [NSURLConnection sendAsynchronousRequest:dirContentsRequest queue:[NSOperationQueue currentQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError)
     {
         NSArray* itemArray = [BitcasaAPI parseListAtContainter:container response:response data:data error:connectionError];
         completion(itemArray);
     }];
}

+ (void)getContentsOfTrashWithCompletion:(void (^)(NSArray* items))completion
{
    NSURLRequest* trashContentsRequest = [[NSURLRequest alloc] initWithMethod:kHTTPMethodGET endpoint:kAPIEndpointTrash];
    [NSURLConnection sendAsynchronousRequest:trashContentsRequest queue:[NSOperationQueue currentQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError)
    {
        NSArray* itemArray = [BitcasaAPI parseListAtContainter:nil response:response data:data error:connectionError];
        completion(itemArray);
    }];
}

#pragma mark - Restore item
+ (void)restoreItem:(Item*)itemToRestore to:(Container*)toItem completion:(void (^)(BOOL success))completion
{
    NSString* itemPath = [itemToRestore endpointPath];
    NSString* restoreEndpoint = [NSString stringWithFormat:@"%@%@", kAPIEndpointTrash, itemPath];
    
    NSDictionary* formParams = @{ kTrashRequestParameterRestore : @"rescue", kTrashRequestParameterRescuePath : toItem.url};
    NSURLRequest* restoreRequest = [[NSURLRequest alloc] initWithMethod:kHTTPMethodPOST endpoint:restoreEndpoint queryParameters:nil formParameters:formParams];
    [NSURLConnection sendAsynchronousRequest:restoreRequest queue:[NSOperationQueue currentQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError)
     {
         if ( ((NSHTTPURLResponse*)response).statusCode == 200 )
             completion(YES);
         else
         {
             [BitcasaAPI checkForAuthenticationFailure:response];
             completion(NO);
         }
     }];
}

#pragma mark - Move item(s)
+ (void)moveItem:(Item*)itemToMove to:(Container*)dest withSuccessIndex:(NSInteger)successIndex completion:(void (^)(Item* movedItem, NSInteger index))completion
{
    NSURLRequest* moveRequest = [NSURLRequest requestForOperation:kQueryParameterOperationMove onItem:itemToMove destinationItem:dest];
    
    [NSURLConnection sendAsynchronousRequest:moveRequest queue:[NSOperationQueue currentQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError)
     {
         if ( ((NSHTTPURLResponse*)response).statusCode == 200 )
         {
             id newItem;
             NSDictionary* responseMeta = [BitcasaAPI metaDictFromResponseData:data];
             if ([itemToMove isKindOfClass:[Container class]])
                 newItem = [[Container alloc] initWithDictionary:responseMeta andParentContainer:dest];
             else
                 newItem = [[File alloc] initWithDictionary:responseMeta andParentContainer:dest];
             
             completion(newItem, successIndex);
         }
         else
         {
             [BitcasaAPI checkForAuthenticationFailure:response];
             completion(NO, successIndex);
         }
     }];
}

+ (void)moveItem:(Item *)itemToMove to:(Container*)toItem completion:(void (^)(Item* movedItem))completion
{
    [BitcasaAPI moveItem:itemToMove to:toItem withSuccessIndex:-1 completion:^(Item* movedItem, NSInteger index)
    {
        completion(movedItem);
    }];
}

+ (void)moveItems:(NSArray*)itemsToMove to:(Container*)toItem completion:(void (^)(NSArray* success))completion
{
    __block NSInteger indexOfSuccessArray = 0;
    __block NSMutableArray* successArray = [NSMutableArray arrayWithObjects:nil count:[itemsToMove count]];
    for (Item* item in itemsToMove)
    {
        [BitcasaAPI moveItem:item to:toItem withSuccessIndex:indexOfSuccessArray completion:^(Item* movedItem, NSInteger index)
        {
             [successArray setObject:movedItem atIndexedSubscript:index];
        }];
        indexOfSuccessArray++;
    }
    
    completion(successArray);
}

#pragma mark - Delete item(s)
+ (void)deleteItem:(Item*)itemToDelete withSuccessIndex:(NSInteger)successIndex completion:(void (^)(BOOL success, NSInteger successArrayIndex))completion
{
    NSString* deleteEndpoint = [itemToDelete endpointPath];
    NSMutableArray* deleteQueryParams = [@[@{kDeleteRequestParameterCommit:kRequestParameterFalse}] mutableCopy];
    if ([itemToDelete isKindOfClass:[Container class]])
        [deleteQueryParams addObject:@{kDeleteRequestParameterForce:kRequestParameterTrue}];
    
    NSURLRequest* deleteRequest = [[NSURLRequest alloc] initWithMethod:kHTTPMethodDELETE endpoint:deleteEndpoint queryParameters:deleteQueryParams formParameters:nil];
    
    [NSURLConnection sendAsynchronousRequest:deleteRequest queue:[NSOperationQueue currentQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError)
     {
         if ( ((NSHTTPURLResponse*)response).statusCode == 200 )
             completion(YES, successIndex);
         else
         {
             [BitcasaAPI checkForAuthenticationFailure:response];
             completion(NO, successIndex);
         }
     }];
}

+ (void)deleteItem:(Item*)itemToDelete completion:(void (^)(BOOL success))completion
{
    [BitcasaAPI deleteItem:itemToDelete withSuccessIndex:-1 completion:^(BOOL success, NSInteger successArrayIndex)
    {
        completion(success);
    }];
}

+ (void)deleteItems:(NSArray *)items completion:(void (^)(NSArray* results))completion
{
    __block NSInteger indexOfSuccessArray = 0;
    __block NSMutableArray* successArray = [NSMutableArray arrayWithObjects:nil count:[items count]];

    for (Item* item in items)
    {
        [BitcasaAPI deleteItem:item withSuccessIndex:indexOfSuccessArray completion:^(BOOL success, NSInteger successArrayIndex)
        {
            [successArray setObject:@(success) atIndexedSubscript:successArrayIndex];
        }];
        indexOfSuccessArray++;
    }
    
    completion(successArray);
}

#pragma mark - Copy item(s)
+ (void)copyItem:(Item*)itemToCopy to:(Container*)destItem withSuccessIndex:(NSInteger)successIndex completion:(void (^)(Item* newItem, NSInteger successIndex))completion
{
    NSURLRequest* moveRequest = [NSURLRequest requestForOperation:kQueryParameterOperationCopy onItem:itemToCopy destinationItem:destItem];
    
    [NSURLConnection sendAsynchronousRequest:moveRequest queue:[NSOperationQueue currentQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError)
     {
         if ( ((NSHTTPURLResponse*)response).statusCode == 200 )
         {
             NSDictionary* metaDict = [BitcasaAPI metaDictFromResponseData:data];
             Item* newItem = [[Item alloc] initWithDictionary:metaDict andParentContainer:destItem];
             completion(newItem, successIndex);
         }
         else
         {
             [BitcasaAPI checkForAuthenticationFailure:response];
             completion(nil, successIndex);
         }
     }];
}

+ (void)copyItem:(Item*)itemToCopy to:(Container*)destItem completion:(void (^)(Item* newItem))completion
{
    [BitcasaAPI copyItem:itemToCopy to:destItem withSuccessIndex:-1 completion:^(Item* newItem, NSInteger successIndex)
    {
        completion(newItem);
    }];
}

+ (void)copyItems:(NSArray*)items to:(Container*)toItem completion:(void (^)(NSArray* success))completion
{
    __block NSInteger indexOfSuccessArray = 0;
    __block NSMutableArray* successArray = [NSMutableArray arrayWithObjects:nil count:[items count]];
    
    for (id item in items)
    {
        [BitcasaAPI copyItem:item to:toItem withSuccessIndex:indexOfSuccessArray completion:^(Item* newItem, NSInteger successIndex)
        {
            [successArray setObject:newItem atIndexedSubscript:successIndex];
        }];
        
        indexOfSuccessArray++;
    }
    
    completion(successArray);
}

#pragma mark - Create new directory
+ (void)createFolderInContainer:(Container*)container withName:(NSString*)name completion:(void (^)(NSDictionary* newFolderDict))completion
{
    NSString* createFolderEndpoint = [container endpointPath];
    NSArray* createFolderQueryParams = @[@{kQueryParameterOperation : kQueryParameterOperationCreate}];
    NSMutableArray* createFolderFormParams = [NSMutableArray arrayWithObjects:@{@"name": name}, @{@"exists":@"rename"}, nil];
    
    NSURLRequest* createFolderRequest = [[NSURLRequest alloc] initWithMethod:kHTTPMethodPOST endpoint:createFolderEndpoint queryParameters:createFolderQueryParams formParameters:createFolderFormParams];
    
    [NSURLConnection sendAsynchronousRequest:createFolderRequest queue:[NSOperationQueue currentQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError)
     {
         if ( ((NSHTTPURLResponse*)response).statusCode == 200 )
         {
             if (data)
             {
                 NSArray* itemDicts = [BitcasaAPI itemDictsFromResponseData:data];
                 completion([itemDicts firstObject]);
             }
         }
         else
         {
             [BitcasaAPI checkForAuthenticationFailure:response];
             completion(nil);
         }
     }];
}

#pragma mark - Downloads
+ (void)downloadItem:(Item*)item delegate:(id <TransferDelegate>)delegate
{
    NSURLRequest* downloadFileRequest = [[NSURLRequest alloc] initWithMethod:kHTTPMethodGET endpoint:[item endpointPath]];
    
    TransferManager* transferManager = [TransferManager sharedManager];
    transferManager.delegate = delegate;
    NSURLSessionDownloadTask *task = [transferManager.backgroundSession downloadTaskWithRequest:downloadFileRequest];
    task.taskDescription = item.url;
    [task resume];
}

#pragma mark - Uploads
+ (void)uploadFile:(NSString*)sourcePath to:(Folder*)destContainer delegate:(id <TransferDelegate>)transferDelegate
{
    NSData *tempData = [NSData dataWithContentsOfFile:sourcePath];
    NSInputStream *inputStream = [[NSInputStream alloc] initWithData:tempData];
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:sourcePath error:nil];
    NSUInteger dataLength = 0;
    if (attributes)
        dataLength = [attributes[NSFileSize] unsignedIntegerValue];
    
    [BitcasaAPI uploadStream:inputStream withFileName:[sourcePath lastPathComponent] toContainer:(Container*)destContainer withDelegate:transferDelegate];
}

+ (void)uploadStream:(NSInputStream *)stream withFileName:(NSString*)fileName toContainer:(Container*)destContainer withDelegate:(id <TransferDelegate>)delegate
{
    NSString* destPath = [NSString stringWithFormat:@"%@%@", kAPIEndpointFileAction, destContainer.url];
    NSString* name = fileName;
    
    NSURL* uploadFileURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@%@", [Credentials sharedInstance].serverURL, [BitcasaAPI apiVersion], destPath]];
    NSMutableURLRequest* uploadFileRequest = [NSMutableURLRequest requestWithURL:uploadFileURL];
    [uploadFileRequest setHTTPMethod:kHTTPMethodPOST];
    [uploadFileRequest setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", kBCMultipartFormDataBoundary] forHTTPHeaderField:kHeaderContentType];
    [uploadFileRequest addValue:[NSString stringWithFormat:@"Bearer %@", [Credentials sharedInstance].accessToken] forHTTPHeaderField:kHeaderAuth];
    
    BCInputStream *formStream = [BCInputStream BCInputStreamWithFilename:name inputStream:stream];
    
    [uploadFileRequest setHTTPBodyStream:formStream];
    
    TransferManager* transferMngr = [TransferManager sharedManager];
    transferMngr.delegate = delegate;
    NSURLConnection* connection = [[NSURLConnection alloc] initWithRequest:uploadFileRequest delegate:transferMngr startImmediately:NO];
    [connection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    [connection start];
}

#pragma mark - utilities
+ (void)checkForAuthenticationFailure:(NSURLResponse*)response
{
    if (((NSHTTPURLResponse*)response).statusCode == 401)
    {
        Session* currentSession = [Session sharedSession];
        [currentSession.delegate sessionDidReceiveAuthorizationFailure:currentSession userId:currentSession.user.email];
    }
}

+ (NSArray*)parseListAtContainter:(Container*)parent response:(NSURLResponse *)response data:(NSData *)data error:(NSError *)connectionError
{
    if ( ((NSHTTPURLResponse*)response).statusCode == 200 )
    {
        if (data)
        {
            NSArray* itemsDictArray = [BitcasaAPI itemDictsFromResponseData:data];
            NSMutableArray* itemArray = [NSMutableArray array];
            for (NSDictionary* itemDict in itemsDictArray)
            {
                id item;
                if ([itemDict[@"type"] isEqualToString:@"folder"])
                    item = [[Folder alloc] initWithDictionary:itemDict andParentContainer:parent];
                else
                    item = [[File alloc] initWithDictionary:itemDict andParentContainer:parent];

                [itemArray addObject:item];
            }
            return itemArray;
        }
    }
    else
        [BitcasaAPI checkForAuthenticationFailure:response];
    
    return nil;
};

+ (NSDictionary*)resultDictFromResponseData:(NSData*)data
{
    NSError* err;
    NSDictionary* responseDict = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:&err];
    NSDictionary* resultDict = responseDict[@"result"];
    return resultDict;
}

+ (NSArray*)itemDictsFromResponseData:(NSData*)data
{
    NSDictionary* resultDict = [BitcasaAPI resultDictFromResponseData:data];
    NSArray* itemsDictArray = resultDict[@"items"];
    return itemsDictArray;
}

+ (NSDictionary*)metaDictFromResponseData:(NSData*)data
{
    NSDictionary* resultDict = [BitcasaAPI resultDictFromResponseData:data];
    NSDictionary* meta = resultDict[@"meta"];
    return meta;
}
@end
