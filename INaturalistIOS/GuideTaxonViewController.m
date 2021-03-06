//
//  GuideTaxonViewController.m
//  iNaturalist
//
//  Created by Ken-ichi Ueda on 9/16/13.
//  Copyright (c) 2013 iNaturalist. All rights reserved.
//

#import "GuideTaxonViewController.h"
#import "Observation.h"
#import "ObservationDetailViewController.h"
#import "RXMLElement+Helpers.h"
#import "PhotoSource.h"
#import "GuidePhotoViewController.h"
#import "GuideImageXML.h"

static const int WebViewTag = 1;

@implementation GuideTaxonViewController
@synthesize webView = _webView;
@synthesize localPosition = _localPosition;

- (void)viewWillAppear:(BOOL)animated
{
    // this is dumb, but the TTPhotoViewController forcibly sets the bar style, so we need to reset it
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    [super viewWillAppear:animated];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    if (!self.webView) {
        self.webView = (UIWebView *)[self.view viewWithTag:WebViewTag];
    }
    self.webView.delegate = self;
    if (self.guideTaxon.displayName) {
        self.title = self.guideTaxon.displayName;
    } else {
        self.title = self.guideTaxon.name;
    }
    NSString *xmlString = [self.guideTaxon.xml xmlString];
    BOOL local = [[NSFileManager defaultManager] fileExistsAtPath:[self.guideTaxon.guide.dirPath stringByAppendingPathComponent:@"files"]];
    if (xmlString && [xmlString rangeOfString:@"xsl"].location == NSNotFound) {
        NSString *xslPath;
        if (local) {
            xslPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"guide_taxon-local.xsl"];
        } else {
            xslPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"guide_taxon-remote.xsl"];
        }
        NSString *header = [NSString stringWithFormat:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<?xml-stylesheet type=\"text/xsl\" href=\"%@\"?>\n<INatGuide xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:dcterms=\"http://purl.org/dc/terms/\" xmlns:eol=\"http://www.eol.org/transfer/content/1.0\">", xslPath];
        xmlString = [[header stringByAppendingString:xmlString] stringByAppendingString:@"</INatGuide>"];
    }
    NSURL *baseURL = [NSURL fileURLWithPath:self.guideTaxon.guide.dirPath];
    [self.webView loadData:[xmlString dataUsingEncoding:NSUTF8StringEncoding]
                  MIMEType:@"text/xml"
          textEncodingName:@"utf-8"
                   baseURL:baseURL];
}

- (void)viewDidAppear:(BOOL)animated
{
    [self.navigationController setToolbarHidden:YES animated:animated];
}

- (void)viewDidUnload {
    [self setWebView:nil];
    [super viewDidUnload];
}
- (IBAction)clickedObserve:(id)sender {
    [self performSegueWithIdentifier:@"GuideTaxonObserveSegue" sender:sender];
}
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:@"GuideTaxonObserveSegue"]) {
        ObservationDetailViewController *vc = [segue destinationViewController];
        [vc setDelegate:self];
        Observation *o = [Observation object];
        o.localObservedOn = [NSDate date];
        if (self.guideTaxon.taxonID && self.guideTaxon.taxonID.length > 0) {
            vc.taxonID = self.guideTaxon.taxonID;
            o.speciesGuess = self.guideTaxon.displayName;
        }
        if (!o.speciesGuess || o.speciesGuess.length == 0) {
            o.speciesGuess = self.guideTaxon.name;
        }
        [vc setObservation:o];
    }
}

# pragma mark - UIWebViewDelegate
// http://engineering.tumblr.com/post/32329287335/javascript-native-bridge-for-ioss-uiwebview
- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    NSString *urlString = [[request URL] absoluteString];
    if ([urlString hasPrefix:@"js:"]) {
        NSString *jsonString = [[[urlString componentsSeparatedByString:@"js:"] lastObject]
                                stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
        
        NSError *error;
        id parameters = [NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONReadingMutableContainers
                                                          error:&error];
        if (error) {
            NSLog(@"error: %@", error);
        } else {
            // TODO: Logic based on parameters
        }
    } else if ([urlString hasPrefix:@"file:"] && [urlString rangeOfString:@"files/"].location != NSNotFound) {
        [self showAssetByURL:urlString];
    } else if ([urlString hasPrefix:@"http:"] || [urlString hasPrefix:@"https:"]) {
        if ([self.guideTaxon.xml atXPath:[NSString stringWithFormat:@"descendant::*[text()='%@']", urlString]]) {
            [self showAssetByURL:urlString];
        } else if (navigationType == UIWebViewNavigationTypeLinkClicked) {
            if (!linkActionSheet) {
                linkActionSheet = [[UIActionSheet alloc] initWithTitle:nil
                                                              delegate:self
                                                     cancelButtonTitle:NSLocalizedString(@"Cancel", nil)
                                                destructiveButtonTitle:nil
                                                     otherButtonTitles:NSLocalizedString(@"Open link in Safari", nil), nil];
            }
            lastURL = request.URL;
            [linkActionSheet showFromTabBar:self.tabBarController.tabBar];
        }
    } else if ([urlString hasPrefix:@"file:"]) {
        return YES;
    }
    return NO;
}

# pragma mark - UIActionSheetDelegate
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == 0 && lastURL) {
        [[UIApplication sharedApplication] openURL:lastURL];
    }
    lastURL = nil;
}

# pragma mark - GuideTaxonViewController
- (void)showAssetByURL:(NSString *)url
{
    NSString *name = [self.guideTaxon.xml atXPath:@"displayName"].text;
    if (!name) {
        name = [self.guideTaxon.xml atXPath:@"name"].text;
    }
    NSString *title = [NSString stringWithFormat:NSLocalizedString(@"Photos for %@", nil), name];
    PhotoSource *photoSource = [[PhotoSource alloc]
                                initWithPhotos:self.guideTaxon.guidePhotos
                                title:title];
    GuidePhotoViewController *vc = [[GuidePhotoViewController alloc] init];
    vc.photoSource = photoSource;
    vc.currentURL = url;
    [self.navigationController setToolbarHidden:YES];
    [self.navigationController pushViewController:vc animated:YES];
}

@end
