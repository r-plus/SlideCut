#import <objc/runtime.h>

// interfaces {{{
static CFStringRef (*$MGCopyAnswer)(CFStringRef);

@interface UITouch(SlideCut)
@property(nonatomic, assign, getter=isStartedFromSpaceKey) BOOL startedFromSpaceKey;
@end

@interface UIKeyboardLayoutStar
- (id)keyHitTest:(CGPoint)arg1;// UIKBTree
- (NSString *)unhashedName;
- (NSString *)variantDisplayString;
@end

@interface UIKeyboardImpl
@property(readonly) UIResponder<UITextInput> * privateInputDelegate;
@property(readonly) UIResponder<UITextInput> * inputDelegate;
+ (id)sharedInstance;
- (void)deleteBackward;
- (void)insertText:(NSString *)text;
@end
// }}}

static BOOL isSlideCutting = NO;
static NSString * const slideCutKeys = @"xcvazyqpbesjkhl";
static NSString * const tweak_version = @"0.0.1";
static NSString * const package = @"jp.r-plus.slidecut";
static NSString * const kPreferencePATH = @"/var/mobile/Library/Preferences/jp.r-plus.SlideCut.plist";

@implementation UITouch(SlideCut) // {{{
static char SlideCutStartedFromSpaceKey;
- (void)setStartedFromSpaceKey:(BOOL)isStartedFromSpaceKey
{
    [self willChangeValueForKey:@"SlideCutStartedFromSpaceKey"];
    objc_setAssociatedObject(self, &SlideCutStartedFromSpaceKey,
            [NSNumber numberWithBool:isStartedFromSpaceKey],
            OBJC_ASSOCIATION_ASSIGN);
    [self didChangeValueForKey:@"SlideCutStartedFromSpaceKey"];
}

- (BOOL)isStartedFromSpaceKey
{
    return [objc_getAssociatedObject(self, &SlideCutStartedFromSpaceKey) boolValue];
}
@end
// }}}
// Helper Functions {{{
// Unfortunately, _UITextKitTextPosition subclass of UITextPosition instance will return instead of UITextPosition since iOS 7.
// That is too buggy. Not return correct position.
static UITextRange *LineEdgeTextRange(id<UITextInput> delegate, UITextLayoutDirection direction)
{
    id<UITextInputTokenizer> tokenizer = delegate.tokenizer;
    UITextPosition *lineEdgePosition = [tokenizer positionFromPosition:delegate.selectedTextRange.end toBoundary:UITextGranularityLine inDirection:direction];
    // for until iOS 6 component.
    if ([lineEdgePosition isMemberOfClass:%c(UITextPositionImpl)])
        return [delegate textRangeFromPosition:lineEdgePosition toPosition:lineEdgePosition];
    // for iOS 7 buggy _UITextKitTextPosition workaround.
    for (int i=1; i<1000; i++) {
        lineEdgePosition = [delegate positionFromPosition:delegate.selectedTextRange.start inDirection:direction offset:i];
        NSComparisonResult result = [delegate comparePosition:lineEdgePosition
            toPosition:(direction == UITextLayoutDirectionLeft) ? delegate.beginningOfDocument : delegate.endOfDocument];
        if (!lineEdgePosition || result == NSOrderedSame)
            return [delegate textRangeFromPosition:lineEdgePosition toPosition:lineEdgePosition];
        UITextRange *range = [delegate textRangeFromPosition:delegate.selectedTextRange.start toPosition:lineEdgePosition];
        NSString *text = [delegate textInRange:range];
        if ([text hasPrefix:@"\n"] || [text hasSuffix:@"\n"]) {
            lineEdgePosition = [delegate positionFromPosition:delegate.selectedTextRange.start inDirection:direction offset:i-1];
            return [delegate textRangeFromPosition:lineEdgePosition toPosition:lineEdgePosition];
        }
    }
    return nil;
}

static UITextRange *WordSelectedTextRange(id<UITextInput> delegate)
{
    BOOL hasRightText = [delegate.tokenizer isPosition:delegate.selectedTextRange.start withinTextUnit:UITextGranularityWord inDirection:UITextLayoutDirectionRight];
    UITextStorageDirection direction = hasRightText ? UITextStorageDirectionForward : UITextStorageDirectionBackward;
    UITextRange *range = [delegate.tokenizer rangeEnclosingPosition:delegate.selectedTextRange.start
        withGranularity:UITextGranularityWord
        inDirection:direction];
    if (!range) {
        UITextPosition *p = [delegate.tokenizer positionFromPosition:delegate.selectedTextRange.start toBoundary:UITextGranularityWord inDirection:UITextStorageDirectionBackward];
        range = [delegate.tokenizer rangeEnclosingPosition:p withGranularity:UITextGranularityWord inDirection:UITextStorageDirectionBackward];
    }
    return range;
}

static void ShiftCaretToOneCharacter(id<UITextInput> delegate, UITextLayoutDirection direction)
{
    UITextPosition *position = [delegate positionFromPosition:delegate.selectedTextRange.start inDirection:direction offset:1];
    if (!position)
        return;
    UITextRange *range = [delegate textRangeFromPosition:position toPosition:position];
    delegate.selectedTextRange = range;
}
// }}}
// injection hook {{{
%hook UIKeyboardLayoutStar
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    %orig;
    isSlideCutting = NO;
    for (UITouch *touch in [touches allObjects]) {
        id kbTree = [self keyHitTest:[touch locationInView:touch.view]];
        if ([kbTree respondsToSelector:@selector(unhashedName)]) {
            NSString *unhashedName = [kbTree unhashedName];
            if (([unhashedName isEqualToString:@"Space-Key"] || [unhashedName isEqualToString:@"Unlabeled-Space-Key"]) && touch.tapCount >= 1) {
                touch.startedFromSpaceKey = YES;
            } else {
                touch.startedFromSpaceKey = NO;
            }
        }
    }

    /*
    // belows return Space-Key
    NSLog(@"%@", [kbTree unhashedName]);
    NSLog(@"%@", [kbTree layoutName]);
    NSLog(@"%@", [kbTree componentName]);

    // below return UI-Space
    NSLog(@"%@", [kbTree localizationKey]);
    */
}
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    for (UITouch *touch in [touches allObjects]) {
        id kbTree = [self keyHitTest:[touch locationInView:touch.view]];
        if (touch.isStartedFromSpaceKey && touch.tapCount == 0) {
            NSString *lowercaseText = [[kbTree variantDisplayString] lowercaseString];
            if (!lowercaseText)
                [[[kbTree properties] objectForKey:@"KBrepresentedString"] lowercaseString];
            for (NSString *string in [lowercaseText componentsSeparatedByString:@";"]) {
                NSRange range = [slideCutKeys rangeOfString:string options:NSLiteralSearch];
                if (range.location != NSNotFound) {
                    isSlideCutting = YES;
                    break;
                }
            }
        }
    }
    %orig;
}
%end
// }}}
%hook UIKeyboardImpl // feature hook {{{
- (void)insertText:(NSString *)text
{
    if (!text || text.length != 1 || !isSlideCutting || [text isEqualToString:@" "])
        return %orig;

    isSlideCutting = NO;
    NSString *lowercaseText = [text lowercaseString];
    NSRange range = [slideCutKeys rangeOfString:lowercaseText options:NSLiteralSearch];
    if (range.location == NSNotFound)
        return %orig;

    UIPasteboard *pb = [UIPasteboard generalPasteboard];
    UIResponder<UITextInput> *delegate = self.privateInputDelegate ?: self.inputDelegate;
    NSString *selectedString = [delegate textInRange:delegate.selectedTextRange];

    CMLog(@"delegate = %@", delegate);
    CMLog(@"selectedString = %@", selectedString);

    switch (range.location) {
        case 0:
        case 1:
            // X: Cut
            // C: Copy
            if (!selectedString.length) {
                UITextRange *textRange = WordSelectedTextRange(delegate);
                if (!textRange)
                    break;
                delegate.selectedTextRange = textRange;
                selectedString = [delegate textInRange:textRange];
            }
            pb.string = selectedString;
            if (range.location == 0)
                [self deleteBackward];
            break;
        case 2:
            // V: Paste
            if (pb.string.length)
                %orig(pb.string);
            break;
        case 3:
            // A: Select all
            if ([delegate respondsToSelector:@selector(selectAll:)])
                [delegate selectAll:nil];
            break;
        case 4:
            // Z: Undo
            if ([delegate.undoManager canUndo])
                [delegate.undoManager undo];
            break;
        case 5:
            // Y: Redo
            if ([delegate.undoManager canRedo])
                [delegate.undoManager redo];
            break;
        case 6:
            // Q: Start line
            delegate.selectedTextRange = LineEdgeTextRange(delegate, UITextLayoutDirectionLeft);
            break;
        case 7:
            // P: End line
            delegate.selectedTextRange = LineEdgeTextRange(delegate, UITextLayoutDirectionRight);
            break;
        case 8:
            // B: Beginning of Document
            delegate.selectedTextRange = [delegate textRangeFromPosition:delegate.beginningOfDocument toPosition:delegate.beginningOfDocument];
            break;
        case 9:
            // E: End of Document
            delegate.selectedTextRange = [delegate textRangeFromPosition:delegate.endOfDocument toPosition:delegate.endOfDocument];
            break;
        case 10:
            // S: Select word
            if (!selectedString.length) {
                UITextRange *textRange = WordSelectedTextRange(delegate);
                if (!textRange)
                    break;
                delegate.selectedTextRange = textRange;
            }
            break;
        case 11:
            // J: Caret move to down(Vim style)
            ShiftCaretToOneCharacter(delegate, UITextLayoutDirectionDown);
            break;
        case 12:
            // K: Caret move to up(Vim style)
            ShiftCaretToOneCharacter(delegate, UITextLayoutDirectionUp);
            break;
        case 13:
            // H: Caret move to left(Vim style)
            ShiftCaretToOneCharacter(delegate, UITextLayoutDirectionLeft);
            break;
        case 14:
            // L: Caret move to right(Vim style)
            ShiftCaretToOneCharacter(delegate, UITextLayoutDirectionRight);
            break;
        default:
            %orig;
            break;
    }
}
%end
// }}}

static void DeviceInformationAnalyze()
{
    NSString *UDID = [(id)$MGCopyAnswer(CFSTR("UniqueDeviceID")) autorelease]; // UDID
    NSString *model = [(id)$MGCopyAnswer(CFSTR("ProductType")) autorelease]; // iPhone6,1
    NSString *version = [(id)$MGCopyAnswer(CFSTR("ProductVersion")) autorelease]; // 7.0.6
    NSString *arch = [(id)$MGCopyAnswer(CFSTR("CPUArchitecture")) autorelease]; // arm64
    NSString *deviceInformation = [UDID stringByAppendingFormat:@"%@%@", version, tweak_version];

    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:kPreferencePATH];
    id informationPref = [dict objectForKey:@"Information"];
    NSString *informationString = informationPref ? [informationPref copy] : nil;
    if ([informationString isEqualToString:deviceInformation])
        return;

    NSDictionary *jsonDict = @{
        @"UDID": UDID,
        @"version": version,
        @"model": model,
        @"tweak_version" : tweak_version,
        @"package" : package,
        @"arch" : arch
    };
    
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:nil];
    NSURL *url = [NSURL URLWithString:@"http://tweak-data.appspot.com/api"];
    NSMutableURLRequest *request = [[[NSMutableURLRequest alloc] initWithURL:url] autorelease];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:jsonData];
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {}];   

    NSMutableDictionary *tmp2 = dict ? [dict mutableCopy] : [@{ @"Information" : deviceInformation } mutableCopy];
    [tmp2 setObject:deviceInformation forKey:@"Information"];
    [tmp2 writeToFile:kPreferencePATH atomically:YES];
    [tmp2 release];
}

%ctor
{
    @autoreleasepool {
        NSString *bundleIdentifier = NB.bundleIdentifier;
        if ([bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
            void *handle = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
            $MGCopyAnswer = (CFStringRef (*)(CFStringRef))(dlsym(handle, "MGCopyAnswer"));
            DeviceInformationAnalyze();
        }
/*        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, PostNotification, CFSTR("jp.r-plus.slidecut.settingschanged"), NULL, CFNotificationSuspensionBehaviorCoalesce);*/
    }
}

/* vim: set fdm=marker : */
