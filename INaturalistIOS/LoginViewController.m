//
//  LoginViewController.m
//  iNaturalist
//
//  Created by Ken-ichi Ueda on 2/17/12.
//  Copyright (c) 2012 iNaturalist. All rights reserved.
//

#import "INaturalistAppDelegate.h"
#import "LoginViewController.h"
#import "DejalActivityView.h"
#import "INatWebController.h"
#import <FacebookSDK/FacebookSDK.h>
#import "GTLPlusConstants.h"
#import "GTMOAuth2Authentication.h"
#import "NXOAuth2.h"

static const NSInteger FacebookAssertionType = 1;
static const NSInteger GoogleAssertionType = 2;

@interface LoginViewController(){
    NSString    *ExternalAccessToken;
    NSString    *INatAccessToken;
    NSString    *AccountType;
    UIAlertView *av;
    BOOL        isLoginCompleted;
    NSInteger   lastAssertionType;
    BOOL        tryingGoogleReauth;
}

@end

@implementation LoginViewController
@synthesize usernameField, passwordField, delegate;



- (IBAction)cancel:(id)sender {
    [[self parentViewController] dismissViewControllerAnimated:YES completion:nil];
    if (self.delegate && [self.delegate respondsToSelector:@selector(loginViewControllerDidCancel:)]) {
        [self.delegate performSelector:@selector(loginViewControllerDidCancel:) withObject:self];
    }
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    // adujst the title font for Spanish
    NSString *currentLanguage = [[NSLocale preferredLanguages] objectAtIndex:0];
    if ([currentLanguage compare:@"es"] == NSOrderedSame){
        [self.navigationController.navigationBar setTitleTextAttributes:
         [NSDictionary dictionaryWithObject:[UIFont boldSystemFontOfSize:18] forKey:UITextAttributeFont]];
    }
    [self initGoogleLogin];
    [self initOAuth2Service];
    AccountType = kINatAuthService;
    av = nil;
    isLoginCompleted = NO;
}

- (void)viewDidUnload
{
    [self setUsernameField:nil];
    [self setPasswordField:nil];
    [self removeOAuth2Observers];
    [super viewDidUnload];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}


- (IBAction)signIn:(id)sender {
    //INaturalistAppDelegate *app = [[UIApplication sharedApplication] delegate];
    [DejalBezelActivityView activityViewForView:self.view withLabel:NSLocalizedString(@"Signing in...",nil)];
    AccountType = nil;
    AccountType = kINatAuthService;
    isLoginCompleted = NO;
    [[NXOAuth2AccountStore sharedStore] requestAccessToAccountWithType:AccountType
                                                              username:[usernameField text]
                                                              password:[passwordField text]];
}

#pragma mark - RKRequestDelegate methods
- (void)request:(RKRequest *)request didLoadResponse:(RKResponse *)response
{
    if (response.statusCode == 200 || response.statusCode == 304) {
        [DejalBezelActivityView removeView];
        NSString *jsonString = [[NSString alloc] initWithData:response.body
                                                     encoding:NSUTF8StringEncoding];
        NSError* error = nil;
        id<RKParser> parser = [[RKParserRegistry sharedRegistry] parserForMIMEType:@"application/json"];
        NSDictionary *parsedData = [parser objectFromString:jsonString error:&error];
        if (parsedData == nil && error) {
            // Parser error...
            [self failedLogin];
            return;
        }
        NSString *userName = [parsedData objectForKey:@"login"];
        
        [[NSUserDefaults standardUserDefaults] setValue:userName
                                                 forKey:INatUsernamePrefKey];
        [[NSUserDefaults standardUserDefaults] setValue:[passwordField text] 
                                                 forKey:INatPasswordPrefKey];
        [[NSUserDefaults standardUserDefaults] setValue:INatAccessToken
                                                 forKey:INatTokenPrefKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
        if (self.delegate && [self.delegate respondsToSelector:@selector(loginViewControllerDidLogIn:)]) {
            [self.delegate loginViewControllerDidLogIn:self];
        }
        [[self parentViewController] dismissViewControllerAnimated:YES completion:nil];
    } else {
        [self failedLogin];
    }
}

- (void)request:(RKRequest *)request didFailLoadWithError:(NSError *)error
{
    // KLUDGE!! RestKit doesn't seem to handle failed auth very well
    bool jsonParsingError = [error.domain isEqualToString:@"JKErrorDomain"] && error.code == -1;
    bool authFailure = [error.domain isEqualToString:@"NSURLErrorDomain"] && error.code == -1012;
    if (jsonParsingError || authFailure) {
        [self failedLogin];
    } else if (!av){
        av = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Whoops!",nil)
                                        message:[NSString stringWithFormat:NSLocalizedString(@"Looks like there was an unexpected error: %@", @"error message with the error") , error.localizedDescription]
                                       delegate:self 
                              cancelButtonTitle:NSLocalizedString(@"OK",nil)
                              otherButtonTitles:nil];
        [av show];
    }
    [DejalBezelActivityView removeView];
}

- (void)failedLogin
{
    [self failedLogin:nil];
}

- (void)failedLogin:(NSString *)msg
{
    //[[RKClient sharedClient] setUsername:nil];
    //[[RKClient sharedClient] setPassword:nil];
    if ([[GPPSignIn sharedInstance] hasAuthInKeychain]) [[GPPSignIn sharedInstance] disconnect];
    INaturalistAppDelegate *app = [[UIApplication sharedApplication] delegate];
    [RKClient.sharedClient setValue:nil forHTTPHeaderField:@"Authorization"];
    [app.photoObjectManager.client setValue:nil forHTTPHeaderField:@"Authorization"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:INatUsernamePrefKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:INatPasswordPrefKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:INatTokenPrefKey];

    [[NSUserDefaults standardUserDefaults] synchronize];
    if (self.delegate && [self.delegate respondsToSelector:@selector(loginViewControllerFailedToLogIn:)]) {
        [self.delegate loginViewControllerFailedToLogIn:self];
    }
    
    if (!av){
        if (!msg) {
            msg = NSLocalizedString(@"Username or password were invalid.", nil);
        }
        av = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Sign in failed",nil)
                                    message:msg
                                   delegate:self 
                          cancelButtonTitle:NSLocalizedString(@"OK",nil)
                          otherButtonTitles:nil];
        [av show];
    }
    isLoginCompleted = YES;
    [DejalBezelActivityView removeView];
}

#pragma mark UITextFieldDelegate methods
- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    if (textField == usernameField) {
        [passwordField becomeFirstResponder];
    } else if (textField == passwordField) {
        [self signIn:nil];
    }
    return YES;
}

#pragma mark UITableView delegate methods
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (![[[RKClient sharedClient] reachabilityObserver] isNetworkReachable]) {
        if (!av){
            av = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Internet connection required",nil)
                                                     message:NSLocalizedString(@"Try again next time you're connected to the Internet.", nil)
                                                    delegate:self
                                           cancelButtonTitle:NSLocalizedString(@"OK",nil)
                                           otherButtonTitles:nil];
            [av show];
        }
        return;
    }
    if (indexPath.section == 1) { //Facebook
        lastAssertionType = FacebookAssertionType;
        isLoginCompleted = NO;
        [DejalBezelActivityView activityViewForView:self.view withLabel:NSLocalizedString(@"Signing in...",nil)];
        [self openFacebookSession];
    }
    else if (indexPath.section == 2) {// Google+
        lastAssertionType = GoogleAssertionType;
        isLoginCompleted = NO;
        [DejalBezelActivityView activityViewForView:self.view withLabel:NSLocalizedString(@"Signing in...",nil)];
        [[GPPSignIn sharedInstance] authenticate];
    }
    else if (indexPath.section == 3) {
        lastAssertionType = 0;
        UINavigationController *nc = self.navigationController;
        INatWebController *webController = [[INatWebController alloc] init];
        NSURL *url = [NSURL URLWithString:
                      [NSString stringWithFormat:@"%@/users/new.mobile", INatWebBaseURL]];
        [webController openURL:url];
        webController.delegate = self;
        [nc pushViewController:webController animated:YES];
     }
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
}

#pragma mark UIAlertViewDelegate methods
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    av = nil;
    if (buttonIndex == 0) return;
    NSURL *url = [NSURL URLWithString:
                  [NSString stringWithFormat:@"%@/users/new.mobile", INatWebBaseURL]];
    [[UIApplication sharedApplication] openURL:url];
}

#pragma mark - TTWebControllerDelegate
- (BOOL)webController:(TTWebController *)controller 
              webView:(UIWebView *)webView 
shouldStartLoadWithRequest:(NSURLRequest *)request 
       navigationType:(UIWebViewNavigationType)navigationType
{
    if ([request.URL.path isEqualToString:@"/users"] || [request.URL.path hasPrefix:@"/users/new"]) {
        return YES;
    }
    [self.navigationController popViewControllerAnimated:YES];
    if (av) [av dismissWithClickedButtonIndex:0 animated:YES];
    av = nil;
    av = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Welcome to iNaturalist!", nil)
                                                 message:NSLocalizedString(@"Now that you've signed up you can sign in with the username and password you just created.  Don't forget to check for your confirmation email as well.", nil)
                                                delegate:self 
                                       cancelButtonTitle:NSLocalizedString(@"OK", nil)
                                       otherButtonTitles:nil];
    [av show];
    return NO;
}

#pragma mark - Facebook calls

- (void)sessionStateChanged:(FBSession *)session
                      state:(FBSessionState) state
                      error:(NSError *)error
{
    switch (state) {
        case FBSessionStateOpen:
//            NSLog(@"session.accessTokenData.accessToken %@", session.accessTokenData.accessToken);
            ExternalAccessToken = [session.accessTokenData.accessToken copy];
            AccountType = nil;
            AccountType = kINatAuthServiceExtToken;
            [[NXOAuth2AccountStore sharedStore]
             requestAccessToAccountWithType:AccountType
             assertionType:[NSURL URLWithString:@"http://facebook.com"]
             assertion:ExternalAccessToken];
            break;
        case FBSessionStateClosed:
//            NSLog(@"session FBSessionStateClosed");
        case FBSessionStateClosedLoginFailed:
//            NSLog(@"session FBSessionStateClosedLoginFailed");
            // Once the user has logged in, we want them to
            // be looking at the root view.
            [FBSession.activeSession closeAndClearTokenInformation];
            ExternalAccessToken = nil;
            break;
        default:
            break;
    }
    
    if (error) {
        if (error.code == 2) {
            [self failedLogin:NSLocalizedString(@"Either you didn't grant access to your Facebook account, or the request timed out. Try again if you want to sign in using your Facebook account, and make sure to grant access.", nil)];
        } else {
            [self failedLogin:error.localizedDescription];
        }
    }
}

- (void)openFacebookSession
{
    NSArray *permissions = [NSArray arrayWithObjects:@"email", @"offline_access", @"user_photos", @"friends_photos", @"user_groups", nil];
    FBSession *session = [[FBSession alloc] initWithAppID:nil
                                              permissions:permissions
                                          urlSchemeSuffix:@"inat"
                                       tokenCacheStrategy:nil];
    [FBSession setActiveSession:session];
    [session openWithBehavior:FBSessionLoginBehaviorUseSystemAccountIfPresent
            completionHandler:
     ^(FBSession *session, FBSessionState state, NSError *error) {
         [self sessionStateChanged:session state:state error:error];
     }];
}

#pragma mark - Google methods

-(void) initGoogleLogin{
    // Google+ init
    GPPSignIn   *googleSignIn = [GPPSignIn sharedInstance];
    googleSignIn.clientID = GoogleClientId;
    googleSignIn.scopes = [NSArray arrayWithObjects:
                           kGTLAuthScopePlusLogin, // defined in GTLPlusConstants.h
                           kGTLAuthScopePlusMe,
                           @"https://www.googleapis.com/auth/userinfo.email", nil];
    googleSignIn.delegate = self;
    [googleSignIn trySilentAuthentication];
}

- (void)finishedWithAuth: (GTMOAuth2Authentication *)auth
                   error: (NSError *) error
{
    
//    NSLog(@"Google Received error %@ and auth object %@ [auth accessToken] %@ ",error, auth, [auth accessToken]);
    if (error || (!auth.accessToken && tryingGoogleReauth)) {
        NSString *msg = error.localizedDescription;
        if (!msg) {
            msg = NSLocalizedString(@"Google sign in failed", nil);
        }
        [self failedLogin:msg];
        tryingGoogleReauth = NO;
    } else if (!auth.accessToken && !tryingGoogleReauth) {
        tryingGoogleReauth = YES;
        [[GPPSignIn sharedInstance] signOut];
        [self initGoogleLogin];
    } else {
        ExternalAccessToken = [[auth accessToken] copy];
        AccountType = nil;
        AccountType = kINatAuthServiceExtToken;
        [[NXOAuth2AccountStore sharedStore]
         requestAccessToAccountWithType:AccountType
         assertionType:[NSURL URLWithString:@"http://google.com"]
         assertion:ExternalAccessToken];
        tryingGoogleReauth = NO;
    }
}


#pragma mark - OAuth2 methods

-(void) initOAuth2Service{
    [[NSNotificationCenter defaultCenter] addObserverForName:NXOAuth2AccountStoreAccountsDidChangeNotification
                                                      object:[NXOAuth2AccountStore sharedStore]
                                                       queue:nil
                                                  usingBlock:^(NSNotification *aNotification){
                                                      if (!isLoginCompleted) {
                                                          [self finishWithAuth2Login];
                                                      }
                                                  }];
    [[NSNotificationCenter defaultCenter] addObserverForName:NXOAuth2AccountStoreDidFailToRequestAccessNotification
                                                      object:[NXOAuth2AccountStore sharedStore]
                                                       queue:nil
                                                  usingBlock:^(NSNotification *aNotification){
                                                      // Do something with the error
                                                      if (!isLoginCompleted) {
                                                          if (lastAssertionType != 0) {
                                                              [self failedLogin:NSLocalizedString(@"Authentication credentials were invalid. This can happen if you recently disconnected your acount from the 3rd party provider (e.g. Facebook). Please try again in a few minutes.", nil)];
                                                          } else {
                                                              [self failedLogin];
                                                          }
                                                      }
                                                  }];
}


-(void) finishWithAuth2Login{
    [DejalBezelActivityView removeView];
    NXOAuth2AccountStore *sharedStore = [NXOAuth2AccountStore sharedStore];
    BOOL loginSuccessed = NO;
    for (NXOAuth2Account *account in [sharedStore accountsWithAccountType:AccountType]) {
        NSString *accessT = [[account accessToken] accessToken];
        if (accessT && [accessT length]>0){
            INatAccessToken = nil;
            INatAccessToken = [NSString stringWithFormat:@"Bearer %@", accessT ];
            loginSuccessed = YES;
        }
        //NSLog(@"account %@  INatAccessToken %@",account, INatAccessToken);
    }
    if (loginSuccessed){
        isLoginCompleted = YES;
        [[NSUserDefaults standardUserDefaults]
         setValue:INatAccessToken
         forKey:INatTokenPrefKey];
        INaturalistAppDelegate *app = [[UIApplication sharedApplication] delegate];
        [RKClient.sharedClient setValue:INatAccessToken forHTTPHeaderField:@"Authorization"];
        [RKClient.sharedClient setAuthenticationType: RKRequestAuthenticationTypeNone];
        [app.photoObjectManager.client setValue:INatAccessToken forHTTPHeaderField:@"Authorization"];
        [app.photoObjectManager.client setAuthenticationType: RKRequestAuthenticationTypeNone];
        [self removeOAuth2Observers];
        [[RKClient sharedClient] get:@"/users/edit.json" delegate:self];
    }
    else [self failedLogin];
}

-(void) removeOAuth2Observers{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NXOAuth2AccountStoreAccountsDidChangeNotification object:[NXOAuth2AccountStore sharedStore]];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NXOAuth2AccountStoreDidFailToRequestAccessNotification object:[NXOAuth2AccountStore sharedStore]];
}

@end
