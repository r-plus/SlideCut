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
static NSString *slideCutKeys = @"xcvaz";

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
    if (!text || text.length != 1 || !isSlideCutting || [text isEqualToString:@" "])
        return %orig;

    isSlideCutting = NO;
    NSString *lowercaseText = [text lowercaseString];
    NSRange range = [slideCutKeys rangeOfString:lowercaseText options:NSLiteralSearch];
    if (range.location == NSNotFound)
        return %orig;

    UIPasteboard *pb = [UIPasteboard generalPasteboard];
    UIResponder<UITextInput> *delegate = self.privateInputDelegate ?: self.inputDelegate;
    UITextRange *selectedTextRange = [delegate selectedTextRange];
    NSString *selectedString = [delegate textInRange:selectedTextRange];

    CMLog(@"delegate = %@", delegate);
    CMLog(@"selectedTextRange = %@", selectedTextRange);
    CMLog(@"selectedString = %@", selectedString);

    switch (range.location) {
        case 0:
            // X: Cut
            if (selectedString.length) {
                pb.string = selectedString;
                [self deleteBackward];
            }
            break;
        case 1:
            // C: Copy
            if (selectedString.length)
                pb.string = selectedString;
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
        default:
            %orig;
            break;
    }
}
%end
