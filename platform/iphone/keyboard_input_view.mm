/**************************************************************************/
/*  keyboard_input_view.mm                                                */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#import "keyboard_input_view.h"

#include "core/os/keyboard.h"
#include "os_iphone.h"

@interface GodotKeyboardInputView () <UITextViewDelegate>

@property(nonatomic, copy) NSString *previousText;
@property(nonatomic, assign) NSRange previousSelectedRange;

@end

@implementation GodotKeyboardInputView

- (instancetype)initWithCoder:(NSCoder *)coder {
	self = [super initWithCoder:coder];

	if (self) {
		[self godot_commonInit];
	}

	return self;
}

- (instancetype)initWithFrame:(CGRect)frame textContainer:(NSTextContainer *)textContainer {
	self = [super initWithFrame:frame textContainer:textContainer];

	if (self) {
		[self godot_commonInit];
	}

	return self;
}

- (void)godot_commonInit {
	self.hidden = YES;
	self.delegate = self;
    self.autocapitalizationType = UITextAutocapitalizationTypeNone;
	self.autocorrectionType = UITextAutocorrectionTypeNo;
	self.spellCheckingType = UITextSpellCheckingTypeNo;
	self.smartQuotesType = UITextSmartQuotesTypeNo;
	self.smartDashesType = UITextSmartDashesTypeNo;
	self.smartInsertDeleteType = UITextSmartInsertDeleteTypeNo;

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(observeTextChange:)
												 name:UITextViewTextDidChangeNotification
											   object:self];
}

- (void)dealloc {
	self.delegate = nil;
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

// MARK: Keyboard

- (BOOL)canBecomeFirstResponder {
	return YES;
}

- (BOOL)becomeFirstResponderWithString:(NSString *)existingString multiline:(BOOL)flag cursorStart:(NSInteger)start cursorEnd:(NSInteger)end {
	self.text = existingString;
	self.previousText = existingString;

	NSInteger safeStartIndex = MAX(start, 0);

	NSRange textRange;

	// Either a simple cursor or a selection.
	if (end > 0) {
		textRange = NSMakeRange(safeStartIndex, end - start);
	} else {
		textRange = NSMakeRange(safeStartIndex, 0);
	}

	self.selectedRange = textRange;
	self.previousSelectedRange = textRange;

	return [self becomeFirstResponder];
}

- (BOOL)resignFirstResponder {
	self.text = nil;
	self.previousText = nil;
	return [super resignFirstResponder];
}

// MARK: OS Messages

- (void)deleteText:(NSInteger)charactersToDelete {
	for (int i = 0; i < charactersToDelete; i++) {
		OSIPhone::get_singleton()->key(KEY_BACKSPACE, true);
		OSIPhone::get_singleton()->key(KEY_BACKSPACE, false);
	}
}

- (void)enterText:(NSString *)substring {
	String characters;
	characters.parse_utf8([substring UTF8String]);

	for (int i = 0; i < characters.size(); i++) {
		int character = characters[i];

		switch (character) {
			case 10:
				character = KEY_ENTER;
				break;
			case 8198:
				character = KEY_SPACE;
				break;
			default:
				break;
		}

		OSIPhone::get_singleton()->key(character, true);
		OSIPhone::get_singleton()->key(character, false);
	}
}

- (NSString *)extractLastLine:(NSString *)text {
    // Ensure the text is not empty
    if (text.length == 0) {
        return @"";
    }

    // Remove the trailing newline if it exists
    if ([text hasSuffix:@"\n"]) {
        text = [text substringToIndex:text.length - 1];
    }

    // Find the range of the last newline character
    NSRange range = [text rangeOfString:@"\n" options:NSBackwardsSearch];

    if (range.location == NSNotFound) {
        // If no newline is found, return the entire text
        return text;
    } else {
        NSUInteger lineStart = range.location + 1;
        return [text substringFromIndex:lineStart];
    }
}
// MARK: Observer

- (void)observeTextChange:(NSNotification *)notification {
	if (notification.object != self) {
		return;
	}

	if (self.previousSelectedRange.length == 0) {
		// We are deleting all text before cursor if no range was selected.
		// This way any inserted or changed text will be updated.
		NSString *substringToDelete = [self.previousText substringToIndex:self.previousSelectedRange.location];
		[self deleteText:substringToDelete.length];
	} else {
		// If text was previously selected
		// we are sending only one `backspace`.
		// It will remove all text from text input.
		[self deleteText:1];
	}

	// Text changes added by the godot editor don't get synced back here,
	// so we handle indentation in the UITextField instead. Fixed in godot 4.
	int indent = 0;
	NSString *substringToEnter;

	if (self.selectedRange.length == 0) {
		// If previous cursor had a selection
		// we have to calculate an inserted text.
		if (self.previousSelectedRange.length != 0) {
			NSInteger rangeEnd = self.selectedRange.location + self.selectedRange.length;
			NSInteger rangeStart = MIN(self.previousSelectedRange.location, self.selectedRange.location);
			NSInteger rangeLength = MAX(0, rangeEnd - rangeStart);

			NSRange calculatedRange;

			if (rangeLength >= 0) {
				calculatedRange = NSMakeRange(rangeStart, rangeLength);
			} else {
				calculatedRange = NSMakeRange(rangeStart, 0);
			}

			substringToEnter = [self.text substringWithRange:calculatedRange];
		} else {
			substringToEnter = [self.text substringToIndex:self.selectedRange.location];
			NSCharacterSet *spaceCharacterSet = [NSCharacterSet characterSetWithCharactersInString:@" \n"];
            NSString *lastLine = [self extractLastLine:substringToEnter];
            NSString *stripped = [lastLine stringByTrimmingCharactersInSet:spaceCharacterSet];
			if (self.text.length > self.previousText.length && [substringToEnter hasSuffix:@"\n"]) {
				lastLine = [lastLine stringByAppendingString:@"\n"];
				indent = lastLine.length - stripped.length - 1;
				NSArray *keywords = @[@"var", @"let", @"const", @"type"];

				if ([keywords containsObject:stripped] || [stripped hasSuffix:@":"] || [stripped hasSuffix:@"="]) {
					indent += 2;
				}
            } else if (self.previousText.length - self.text.length == 1) {
                if (lastLine.length >= 1 && stripped.length == 0) {
                    indent = -1;
                }
            } else if ([substringToEnter hasSuffix:@"\t"]) {
				indent = -2;
			}
		}
	} else {
		substringToEnter = [self.text substringWithRange:self.selectedRange];
	}

	[self enterText:substringToEnter];

	self.previousText = self.text;
	self.previousSelectedRange = self.selectedRange;

	if (indent > 0) {
		[self insertText:[@"" stringByPaddingToLength:indent withString: @" " startingAtIndex:0]];
    } else if (indent == -1) {
		// backspace at the beginning of the line. Remove one additional space.
        [self deleteBackward];
    } else if (indent == -2) {
		// tab. Replace with two spaces.
		[self deleteBackward];
		[self insertText:@"  "];
	}
}

@end
