#import <objc/runtime.h>

// interfaces {{{
@interface UIResponder(SlideCut)
- (void)scrollSelectionToVisible:(BOOL)scroll;
- (void)_define:(NSString *)text;
@end

@interface UIFieldEditor
+ (id)sharedFieldEditor;
- (void)revealSelection;
@end

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
- (id)delegateAsResponder;
- (void)deleteBackward;
- (void)insertText:(NSString *)text;
@end
// }}}

static BOOL isSlideCutting = NO;
static BOOL isDeleteCutting = NO;
static NSArray *slideCutKeys;

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

static UITextRange *WordSelectedTextRange(id<UITextInput> delegate, UITextStorageDirection direction)
{
    UITextRange *range = [delegate.tokenizer rangeEnclosingPosition:delegate.selectedTextRange.start
        withGranularity:UITextGranularityWord
        inDirection:direction];
    if (!range) {
        if (direction == UITextStorageDirectionBackward) {
            UITextPosition *p = [delegate.tokenizer positionFromPosition:delegate.selectedTextRange.start toBoundary:UITextGranularityWord inDirection:UITextStorageDirectionBackward];
            if (!p)
                p = [delegate.tokenizer positionFromPosition:delegate.selectedTextRange.start toBoundary:UITextGranularityLine inDirection:UITextLayoutDirectionUp];
            range = [delegate.tokenizer rangeEnclosingPosition:p withGranularity:UITextGranularityWord inDirection:UITextStorageDirectionBackward];
        } else {
            UITextPosition *p = [delegate.tokenizer positionFromPosition:delegate.selectedTextRange.start toBoundary:UITextGranularityWord inDirection:UITextStorageDirectionForward];
            if (!p)
                p = [delegate.tokenizer positionFromPosition:delegate.selectedTextRange.end toBoundary:UITextGranularityLine inDirection:UITextLayoutDirectionDown];
            range = [delegate.tokenizer rangeEnclosingPosition:p withGranularity:UITextGranularityWord inDirection:UITextStorageDirectionForward];
        }
    }
    return range;
}

static UITextRange *AutoDirectionWordSelectedTextRange(id<UITextInput> delegate)
{
    BOOL hasRightText = [delegate.tokenizer isPosition:delegate.selectedTextRange.start withinTextUnit:UITextGranularityWord inDirection:UITextLayoutDirectionRight];
    UITextStorageDirection direction = hasRightText ? UITextStorageDirectionForward : UITextStorageDirectionBackward;
    return WordSelectedTextRange(delegate, direction);
}

static UITextRange *WordMovedTextRange(id<UITextInput> delegate, UITextStorageDirection direction)
{
    UITextRange *range = WordSelectedTextRange(delegate, direction);
    if (direction == UITextStorageDirectionForward)
        return [delegate textRangeFromPosition:range.end toPosition:range.end];
    else
        return [delegate textRangeFromPosition:range.start toPosition:range.start];
}

static void RevealSelection(id<UITextInput> delegate)
{
    // reveal for UITextField.
    [[%c(UIFieldEditor) sharedFieldEditor] revealSelection];
    // reveal for UITextView, UITextContentView and UIWebDocumentView.
    if ([delegate respondsToSelector:@selector(scrollSelectionToVisible:)])
        [(UIResponder *)delegate scrollSelectionToVisible:YES];
}

static void ShiftCaretToOneCharacter(id<UITextInput> delegate, UITextLayoutDirection direction)
{
    UITextPosition *position = [delegate positionFromPosition:delegate.selectedTextRange.start inDirection:direction offset:1];
    if (!position)
        return;
    UITextRange *range = [delegate textRangeFromPosition:position toPosition:position];
    delegate.selectedTextRange = range;
    RevealSelection(delegate);
}
// }}}
static BOOL SlideCutFunction(NSString *text)// {{{
{
    // return YES if function is fire.
    NSString *lowercaseText = [text lowercaseString];
    NSUInteger functionIndex = [slideCutKeys indexOfObject:lowercaseText];
    if (functionIndex == NSNotFound)
        return NO;

    UIKeyboardImpl *keyboardImpl = [%c(UIKeyboardImpl) sharedInstance];
    UIPasteboard *pb = [UIPasteboard generalPasteboard];
    UIResponder<UITextInput> *delegate = [keyboardImpl delegateAsResponder];
/*    self.privateInputDelegate ?: self.inputDelegate;*/
    NSString *selectedString = [delegate textInRange:delegate.selectedTextRange];

    CMLog(@"delegate = %@", delegate);
    CMLog(@"selectedString = %@", selectedString);

    switch (functionIndex) {
        case 0:
        case 1:
            // X: Cut
            // C: Copy
            if (!selectedString.length) {
                UITextRange *textRange = AutoDirectionWordSelectedTextRange(delegate);
                if (!textRange)
                    break;
                delegate.selectedTextRange = textRange;
                selectedString = [delegate textInRange:textRange];
            }
            pb.string = selectedString;
            if (functionIndex == 0)
                [keyboardImpl deleteBackward];
            break;
        case 2:
            // V: Paste
            if (pb.string.length)
                [keyboardImpl insertText:pb.string];
            break;
        case 3:
            // A: Select all
            if ([delegate respondsToSelector:@selector(selectAll:)])
                [delegate selectAll:nil];
            else if ([delegate respondsToSelector:@selector(selectAll)])
                [delegate performSelector:@selector(selectAll)];
            break;
        case 4:
            // Z: Undo
            if ([delegate respondsToSelector:@selector(undoManager)] && [delegate.undoManager canUndo])
                [delegate.undoManager undo];
            break;
        case 5:
            // Y: Redo
            if ([delegate respondsToSelector:@selector(undoManager)] && [delegate.undoManager canRedo])
                [delegate.undoManager redo];
            break;
        case 6:
            // Q: Start line
            delegate.selectedTextRange = LineEdgeTextRange(delegate, UITextLayoutDirectionLeft);
            RevealSelection(delegate);
            break;
        case 7:
            // P: End line
            delegate.selectedTextRange = LineEdgeTextRange(delegate, UITextLayoutDirectionRight);
            RevealSelection(delegate);
            break;
        case 8:
            // B: Beginning of Document
            delegate.selectedTextRange = [delegate textRangeFromPosition:delegate.beginningOfDocument toPosition:delegate.beginningOfDocument];
            RevealSelection(delegate);
            break;
        case 9:
            // E: End of Document
            delegate.selectedTextRange = [delegate textRangeFromPosition:delegate.endOfDocument toPosition:delegate.endOfDocument];
            RevealSelection(delegate);
            break;
        case 10:
            // S: Select word
            if (!selectedString.length) {
                UITextRange *textRange = AutoDirectionWordSelectedTextRange(delegate);
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
        case 15:
            // D: Define
            if (!selectedString.length) {
                UITextRange *textRange = AutoDirectionWordSelectedTextRange(delegate);
                if (!textRange)
                    break;
                delegate.selectedTextRange = textRange;
                selectedString = [delegate textInRange:textRange];
            }
            if ([delegate respondsToSelector:@selector(_define:)])
                [delegate _define:selectedString];
            break;
        case 16:
            // delete: Delete backward word
            if (!selectedString.length) {
                UITextRange *textRange = AutoDirectionWordSelectedTextRange(delegate);
                if (!textRange)
                    break;
                delegate.selectedTextRange = textRange;
            }
            isDeleteCutting = YES;
            [keyboardImpl deleteBackward];
            break;
        case 17:
            // N: Previous word position.
            if (!selectedString.length) {
                UITextRange *textRange = WordMovedTextRange(delegate, UITextStorageDirectionBackward);
                if (!textRange)
                    break;
                delegate.selectedTextRange = textRange;
                RevealSelection(delegate);
            }
            break;
        case 18:
            // M: Next word position.
            if (!selectedString.length) {
                UITextRange *textRange = WordMovedTextRange(delegate, UITextStorageDirectionForward);
                if (!textRange)
                    break;
                delegate.selectedTextRange = textRange;
                RevealSelection(delegate);
            }
            break;
        default:
            return NO;
    }
    return YES;
}
// }}}
// injection hook {{{
%hook UIKeyboardLayoutStar
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    %orig;
    isSlideCutting = NO;
    isDeleteCutting = NO;
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
    NSString *hitedString = nil;
    for (UITouch *touch in [touches allObjects]) {
        id kbTree = [self keyHitTest:[touch locationInView:touch.view]];
        if (touch.isStartedFromSpaceKey) {
            NSString *lowercaseText = [[kbTree variantDisplayString] lowercaseString];
            NSString *KBrepresentedString = [[[kbTree properties] objectForKey:@"KBrepresentedString"] lowercaseString];
            for (NSString *string in [[NSString stringWithFormat:@"%@;%@", lowercaseText, KBrepresentedString] componentsSeparatedByString:@";"]) {
                if (!string)
                    continue;
                NSUInteger functionIndex = [slideCutKeys indexOfObject:string];
                if (functionIndex != NSNotFound) {
                    hitedString = string;
                    isSlideCutting = YES;
                    break;
                }
            }
        }
    }
    if ([hitedString isEqualToString:@"delete"]) {
        SlideCutFunction(hitedString);
        return %orig;
    }
    if (!isSlideCutting || UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone)
        return %orig;
    SlideCutFunction(hitedString);
    %orig;
}
%end
// }}}
// feature hook {{{
%hook UIKeyboardImpl
%group iPhone
- (void)insertText:(NSString *)text
{
    if (text.length == 1 && isSlideCutting && isDeleteCutting) {
        isSlideCutting = NO;
        isDeleteCutting = NO;
        return;
    }
    if (!text || text.length != 1 || !isSlideCutting || [text isEqualToString:@" "])
        return %orig;

    isSlideCutting = NO;
    if (!SlideCutFunction(text))
        %orig;
}
%end
%group iPad
- (void)insertText:(NSString *)text
{
    if ([text isEqualToString:@" "] && isSlideCutting) {
        isSlideCutting = NO;
        return;
    }
    %orig;
}
%end
%end
// }}}
// ctor {{{
%ctor
{
    @autoreleasepool {
        slideCutKeys = [@[@"x", @"c", @"v", @"a", @"z", @"y", @"q", @"p", @"b", @"e", @"s", @"j", @"k", @"h", @"l", @"d", @"delete", @"n", @"m"] retain];
        %init;
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone)
            %init(iPhone);
        else
            %init(iPad);
/*        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, PostNotification, CFSTR("jp.r-plus.slidecut.settingschanged"), NULL, CFNotificationSuspensionBehaviorCoalesce);*/
    }
}
// }}}
/* vim: set fdm=marker : */
