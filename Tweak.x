@interface UIKeyboardLayoutStar
- (id)keyHitTest:(CGPoint)arg1;// UIKBTree
- (NSString *)unhashedName;
@end

@interface UIKeyboardImpl
@property(readonly) UIResponder<UITextInput> * privateInputDelegate;
@property(readonly) UIResponder<UITextInput> * inputDelegate;
- (void)deleteBackward;
@end

static BOOL isSlideCutting = NO;

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

%hook UIKeyboardLayoutStar
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    %orig;
    UITouch *touch = [touches anyObject];
    id kbTree = [self keyHitTest:[touch locationInView:touch.view]];
    if ([kbTree respondsToSelector:@selector(unhashedName)])
        isSlideCutting = ([[kbTree unhashedName] isEqualToString:@"Space-Key"]) ? YES : NO;

    /*
    // belows return Space-Key
    NSLog(@"%@", [kbTree unhashedName]);
    NSLog(@"%@", [kbTree layoutName]);
    NSLog(@"%@", [kbTree componentName]);

    // below return UI-Space
    NSLog(@"%@", [kbTree localizationKey]);
    */
}
%end

%hook UIKeyboardImpl
- (void)insertText:(NSString *)text
{
    static NSString * const slideCutKeys = @"xcvazqphes";
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
            // Q: Start line
            delegate.selectedTextRange = LineEdgeTextRange(delegate, UITextLayoutDirectionLeft);
            break;
        case 6:
            // P: End line
            delegate.selectedTextRange = LineEdgeTextRange(delegate, UITextLayoutDirectionRight);
            break;
        case 7:
            // H: Home
            delegate.selectedTextRange = [delegate textRangeFromPosition:delegate.beginningOfDocument toPosition:delegate.beginningOfDocument];
            break;
        case 8:
            // E: End
            delegate.selectedTextRange = [delegate textRangeFromPosition:delegate.endOfDocument toPosition:delegate.endOfDocument];
            break;
        case 9:
            // S: Select word
            if (!selectedString.length) {
                UITextRange *textRange = WordSelectedTextRange(delegate);
                if (!textRange)
                    break;
                delegate.selectedTextRange = textRange;
            }
            break;
        default:
            %orig;
            break;
    }
}
%end
