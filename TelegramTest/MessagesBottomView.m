//
//  MessagesBottomView.m
//  Messenger for Telegram
//
//  Created by Dmitry Kondratyev on 3/7/14.
//  Copyright (c) 2014 keepcoder. All rights reserved.
//

#import "MessagesBottomView.h"
#import "MessagesViewController.h"
#import "NSString+Extended.h"
#import "FileUtils.h"
#import "Telegram.h"
#import "MessageInputGrowingTextView.h"
#import <Quartz/Quartz.h>
#import "Rebel/Rebel.h"
#import "EmojiViewController.h"
#import "MapPanel.h"
#import "TGTimer.h"

#import "POPLayerExtras.h"

#import "TMAudioRecorder.h"
#import "TGSendTypingManager.h"

#import "NSString+FindURLs.h"
#import "TGAttachImageElement.h"
#import "TGMentionPopup.h"
#import "MessageReplyContainer.h"
#import "TGForwardContainer.h"
#import "TGHashtagPopup.h"
#import "TGWebpageAttach.h"
#import "TGImageAttachmentsController.h"


@interface MessagesBottomView()<TGImageAttachmentsControllerDelegate>

@property (nonatomic, strong) TMView *actionsView;
@property (nonatomic, strong) TMView *normalView;
@property (nonatomic, strong) TMView *secretInfoView;



@property (nonatomic, strong) BTRButton *attachButton;
@property (nonatomic, strong) BTRButton *smileButton;
@property (nonatomic, strong) TMButton *sendButton;


@property (nonatomic, strong) TGTimer *recordTimer;
@property (nonatomic) int recordTime;
@property (nonatomic, strong) BTRButton *recordAudioButton;
@property (nonatomic, strong) TMCircleLayer *recordCircleLayer;
@property (nonatomic, strong) TMTextLayer *recordDurationLayer;
@property (nonatomic, strong) TMTextLayer *recordHelpLayer;

@property (nonatomic, strong) TMTextButton *deleteButton;
@property (nonatomic, strong) TMTextButton *messagesSelectedCount;
@property (nonatomic, strong) TMTextButton *forwardButton;

@property (nonatomic, strong) TMTextField *encryptedStateTextField;

@property (nonatomic,strong) NSMenu *attachMenu;
@property (nonatomic, strong) TMMenuPopover *menuPopover;

@property (nonatomic,strong) NSMutableArray *attachments;

@property (nonatomic,strong) NSMutableArray *attachmentsIgnore;

@property (nonatomic,strong) MessageReplyContainer *replyContainer;


@property (nonatomic,strong) TGForwardContainer *fwdContainer;

@property (nonatomic,strong) TGWebpageAttach *webpageAttach;

@property (nonatomic,strong,readonly) TGImageAttachmentsController *imageAttachmentsController;

@end

@implementation MessagesBottomView

- (id)initWithFrame:(NSRect)frameRect {
    
    self = [super initWithFrame:frameRect];
    if(self) {
        [self setWantsLayer:YES];
        
        self.layer.backgroundColor = NSColorFromRGB(0xfafafa).CGColor;
        
        self.attachments = [[NSMutableArray alloc] init];
        
        self.attachmentsIgnore = [[NSMutableArray alloc] init];

                
        [self setState:MessagesBottomViewNormalState animated:NO];
        

        [[EmojiViewController instance] loadView];
        
        [Notification addObserver:self selector:@selector(didChangeBlockedUser:) name:USER_BLOCK];
    }
    return self;
}

- (void)addSubview:(NSView *)aView {
    [super addSubview:aView];
    [aView setHidden:YES];
}

- (void)didChangeBlockedUser:(NSNotification *)notification {
    if(self.dialog && self.dialog.type == DialogTypeUser) {
        [self setState:self.stateBottom animated:YES];
    }
}

-(void)didChangeAttachmentsCount:(int)futureCount {
    
    if(futureCount == 0 && _imageAttachmentsController.isShown) {
        [_imageAttachmentsController hide:YES deleteItems:NO];
        [self updateBottomHeight:YES];
    } else if(futureCount > 0 && !_imageAttachmentsController.isShown) {
        [_imageAttachmentsController show:_dialog animated:YES];
        [self updateBottomHeight:YES];
    }
    
    [self  TMGrowingTextViewTextDidChange:nil];
}

-(void)addAttachment:(TGImageAttachment *)attachment {
    
    [_imageAttachmentsController addItems:@[attachment] animated:YES];
    
    
    [self updateBottomHeight:YES];
    
}


-(NSUInteger)attachmentsCount {
    return _imageAttachmentsController.attachments.count;
}

-(void)closeAttachments {
    [_imageAttachmentsController hide:YES deleteItems:YES];
    
    [self updateBottomHeight:YES];
}

- (void)dealloc {
    [Notification removeObserver:self];
}

- (void)setDialog:(TL_conversation *)dialog {
    self->_dialog = dialog;

    [self stopRecord:nil];
    
    if(self.dialog.type == DialogTypeSecretChat) {
        weakify();
        ;
        
        __block NSUInteger dialogHash = self.dialog.cacheHash;
        __block EncryptedParams *params = self.dialog.encryptedChat.encryptedParams;
        __block stateHandler handler = ^(EncryptedState state) {
            if(dialogHash != strongSelf.dialog.cacheHash)
                return;
            
            [self setState:MessagesBottomViewNormalState animated:NO];
        };
        
        [params setStateHandler:handler];
        handler(params.state);
        
        [self setForwardEnabled:NO];
    } else if(self.dialog.type == DialogTypeBroadcast) {
        [self setForwardEnabled:NO];
    } else {
         [self setForwardEnabled:YES];
    }
    
    [self checkReplayMessage:YES animated:NO];
    
    [self checkFwdMessages:YES animated:NO];
    
    
    
    
    [_imageAttachmentsController show:_dialog animated:NO];
    
    [self TMGrowingTextViewHeightChanged:self.inputMessageTextField height:NSHeight(self.inputMessageTextField.containerView.frame) cleared:NO];

    
    

}

- (TMView *)actionsView {
    if(self->_actionsView)
        return self->_actionsView;
    
    weakify();
    
    self->_actionsView = [[TMView alloc] initWithFrame:NSMakeRect(0, 0, self.bounds.size.width, self.bounds.size.height - 1)];
    [self.actionsView setWantsLayer:YES];
    [self.actionsView setAutoresizesSubviews:YES];
    [self.actionsView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    
    
        self.actionsView.backgroundColor = [NSColor whiteColor];
    
    self.deleteButton = [TMTextButton standartButtonWithTitle:NSLocalizedString(@"Messages.Selected.Delete", nil) standartImage:image_MessageActionDeleteActive() disabledImage:image_MessageActionDelete()];
    
    [self.deleteButton setAutoresizingMask:NSViewMaxXMargin ];
    [self.deleteButton setTapBlock:^{
        [strongSelf.messagesViewController deleteSelectedMessages];
    }];
    self.deleteButton.disableColor = NSColorFromRGB(0xa1a1a1);
    [self.actionsView addSubview:self.deleteButton];
    
    
    self.messagesSelectedCount = [TMTextButton standartUserProfileNavigationButtonWithTitle:@""];
    self.messagesSelectedCount.textColor = DARK_BLACK;
    self.messagesSelectedCount.font = [NSFont fontWithName:@"HelveticaNeue" size:14];
    [self.messagesSelectedCount setAutoresizingMask:NSViewMinXMargin | NSViewMaxXMargin];
    [self.actionsView addSubview:self.messagesSelectedCount];
    
    self.forwardButton = [TMTextButton standartButtonWithTitle:NSLocalizedString(@"Messages.Selected.Forward", nil) standartImage:image_MessageActionForwardActive() disabledImage:image_MessageActionForward()];
    
    [self.forwardButton setAutoresizingMask:NSViewMinXMargin];
    self.forwardButton.disableColor = NSColorFromRGB(0xa1a1a1);

    [self.forwardButton setTapBlock:^{
//        strongify();
    
        
        [[Telegram rightViewController] showForwardMessagesModalView:strongSelf.messagesViewController.conversation messagesCount:strongSelf.messagesViewController.selectedMessages.count];
    }];
     
     [self.actionsView setDrawBlock:^{
        [strongSelf.forwardButton setFrameOrigin:NSMakePoint(strongSelf.bounds.size.width - strongSelf.forwardButton.bounds.size.width - 22, roundf((strongSelf.bounds.size.height - strongSelf.deleteButton.bounds.size.height) / 2))];
        [strongSelf.deleteButton setFrameOrigin:NSMakePoint(30, roundf((strongSelf.bounds.size.height - strongSelf.deleteButton.bounds.size.height) / 2) )];
        [strongSelf.messagesSelectedCount setCenterByView:strongSelf.actionsView];
    }];
     

    
    [self.actionsView addSubview:self.forwardButton];
    
    return self.actionsView;
}

- (void)setForwardEnabled:(BOOL)forwardEnabled {
    self->_forwardEnabled = forwardEnabled;
    [self.forwardButton setDisable:!forwardEnabled];
}

-(void)updateReplayMessage:(BOOL)updateHeight animated:(BOOL)animated {
    [self checkReplayMessage:updateHeight animated:animated];
}

-(void)updateFwdMessage:(BOOL)updateHeight animated:(BOOL)animated {
    [self checkFwdMessages:updateHeight animated:animated];
}

- (void)setSectedMessagesCount:(NSUInteger)count {
    if(count == 0) {
        [self.messagesSelectedCount setHidden:YES];
        [self.forwardButton setDisable:YES];
        [self.deleteButton setDisable:YES];
        return;
    } else {
        if(self.forwardEnabled)
            [self.forwardButton setDisable:NO];
        [self.deleteButton setDisable:NO];
    }
    
    [self.messagesSelectedCount setHidden:NO];
    
    [self.messagesSelectedCount setStringValue:[NSString stringWithFormat:NSLocalizedString(count == 1 ? @"Edit.selectMessage" : @"Edit.selectMessages", nil), count]];
    [self.messagesSelectedCount sizeToFit];
    [self.messagesSelectedCount setFrameOrigin:NSMakePoint(roundf((self.bounds.size.width - self.messagesSelectedCount.bounds.size.width) /2), roundf((self.bounds.size.height - self.messagesSelectedCount.bounds.size.height)/2))];
}

- (TMView *)blockSecretView {
    TMView *bottomView = [[TMView alloc] initWithFrame:NSMakeRect(0, 0, self.bounds.size.width, self.bounds.size.height - 1)];
    [bottomView setAutoresizingMask:NSViewWidthSizable];
//    [bottomView setBackgroundColor:NSColorFromRGB(0xfafafa)];
    
    TMTextField *secretBlockTextField = [[TMTextField alloc] initWithFrame:NSMakeRect(0, -15, bottomView.frame.size.width, bottomView.frame.size.height)];
    
    [secretBlockTextField setStringValue:@"...."];
    [secretBlockTextField setBackgroundColor:NSColorFromRGB(0xfafafa)];
    [secretBlockTextField setTextColor:NSColorFromRGB(0x010101)];
    [bottomView addSubview:secretBlockTextField];
    [secretBlockTextField setEditable:NO];
    [secretBlockTextField setEnabled:NO];
    [secretBlockTextField setSelectable:NO];
    [secretBlockTextField setBordered:NO];
    [secretBlockTextField setAlignment:NSCenterTextAlignment];
    [secretBlockTextField setAutoresizingMask:NSViewWidthSizable];
    //[bottomView setBackgroundColor:NSColorFromRGB(0xfafafa)];
    return bottomView;
}

- (TMView *)normalView {
    if(self->_normalView)
        return self->_normalView;
    
    self->_normalView = [[TMView alloc] initWithFrame:NSMakeRect(0, 0, self.bounds.size.width, self.bounds.size.height - 1)];
    [self.normalView setWantsLayer:YES];
    
    
  //  [self.normalView setBackgroundColor:NSColorFromRGB(0xfafafa)];
    [self.normalView setAutoresizesSubviews:YES];
    [self.normalView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
//    [self.normalView setBorder:TMViewBorderTop];
//    [self.normalView setBorderColor:GRAY_BORDER_COLOR];
    
    
    self.inputMessageTextField = [[MessageInputGrowingTextView alloc] initWithFrame:NSMakeRect(0, 0, 0, 0)];
    [self.inputMessageTextField setEditable:YES];
    [self.inputMessageTextField setRichText:NO];
 //   [self.inputMessageTextField.scrollView setFrameSize:NSMakeSize(100-30,100-10)];

    
    self.attachButton = [[BTRButton alloc] initWithFrame:NSMakeRect(16, 11, image_BottomAttach().size.width, image_BottomAttach().size.height)];
    
    [self.attachButton setFrameOrigin:NSMakePoint(21, roundf((self.bounds.size.height - self.attachButton.bounds.size.height) / 2) - 3)];
    
    [self.attachButton setBackgroundImage:image_BottomAttach() forControlState:BTRControlStateNormal];
    [self.attachButton setBackgroundImage:image_AttachHighlighted() forControlState:BTRControlStateSelected];
    [self.attachButton setBackgroundImage:image_AttachHighlighted() forControlState:BTRControlStateSelected | BTRControlStateHover];
    [self.attachButton setBackgroundImage:image_AttachHighlighted() forControlState:BTRControlStateHighlighted];
    [self.attachButton addTarget:self action:@selector(attachButtonPressed) forControlEvents:BTRControlEventMouseEntered];

    
    [self.normalView addSubview:self.attachButton];
    
    self.sendButton = [[TMButton alloc] initWithFrame:NSZeroRect];
    [self.sendButton setAutoresizesSubviews:YES];
    [self.sendButton setAutoresizingMask:NSViewMinXMargin];
    [self.sendButton setTarget:self selector:@selector(sendButtonAction)];
    [self.sendButton setText:NSLocalizedString(@"Message.Send", nil)];
    [self.sendButton setTextFont:[NSFont fontWithName:@"HelveticaNeue-Medium" size:14]];
    NSSize size = [self.sendButton sizeOfText];
    [self.sendButton setFrameSize:size];
    [self.sendButton setFrameOrigin:NSMakePoint(self.bounds.size.width - size.width - 17, 19)];
    [self.normalView addSubview:self.sendButton];
    
    self.recordAudioButton = [[BTRButton alloc] initWithFrame:NSZeroRect];
    [self.recordAudioButton setAutoresizingMask:NSViewMinXMargin];
    [self.recordAudioButton setBackgroundImage:image_VoiceMic() forControlState:BTRControlStateNormal];
    [self.recordAudioButton setBackgroundImage:image_VoiceMicHighlighted2() forControlState:BTRControlStateHover];
    [self.recordAudioButton setBackgroundImage:image_VoiceMicHighlighted() forControlState:BTRControlStateHighlighted];
    [self.recordAudioButton setBackgroundImage:image_VoiceMicHighlighted() forControlState:BTRControlStateSelected];
    [self.recordAudioButton setBackgroundImage:image_VoiceMicHighlighted() forControlState:BTRControlStateSelected | BTRControlStateHover];
    [self.recordAudioButton setFrameSize:image_VoiceMicHighlighted().size];
    [self.recordAudioButton setFrameOrigin:NSMakePoint(self.bounds.size.width - self.recordAudioButton.bounds.size.width - 26, roundf((self.bounds.size.height - self.recordAudioButton.bounds.size.height) / 2.f) - 2)];
    [self.recordAudioButton addTarget:self action:@selector(startRecord:) forControlEvents:BTRControlEventMouseDownInside];
    [self.recordAudioButton addTarget:self action:@selector(stopRecordInside:) forControlEvents:BTRControlEventMouseUpInside];
    [self.recordAudioButton addTarget:self action:@selector(stopRecordOutside:) forControlEvents:BTRControlEventMouseUpOutside];
    
    [self addTarget:self action:@selector(recordAudioMouseEntered:) forControlEvents:BTRControlEventMouseEntered];
    [self addTarget:self action:@selector(recordAudioMouseExited:) forControlEvents:BTRControlEventMouseExited];
    
    

    [self.normalView addSubview:self.recordAudioButton];
    
    self.recordCircleLayer = [TMCircleLayer layer];
    self.recordCircleLayer.contentsScale = self.normalView.layer.contentsScale;
    [self.recordCircleLayer setFillColor:NSColorFromRGB(0xf36f75)];
    [self.recordCircleLayer setRadius:17];
    [self.recordCircleLayer setFrameOrigin:CGPointMake(28, roundf((self.bounds.size.height - self.recordCircleLayer.bounds.size.height) / 2))];
    [self.recordCircleLayer setNeedsDisplay];
    [self.normalView.layer addSublayer:self.recordCircleLayer];
    
    self.recordDurationLayer = [TMTextLayer layer];
    [self.recordDurationLayer disableActions];
    self.recordDurationLayer.contentsScale = self.normalView.layer.contentsScale;
    [self.recordDurationLayer setTextColor:[NSColor blackColor]];
    [self.recordDurationLayer setTextFont:[NSFont fontWithName:@"HelveticaNeue" size:14]];
    [self.recordDurationLayer setString:@"00:34"];
    [self.recordDurationLayer sizeToFit];
    [self.recordDurationLayer setFrameOrigin:CGPointMake(52, roundf( (self.bounds.size.height - self.recordDurationLayer.bounds.size.height) / 2.f) - 1)];
    [self.normalView.layer addSublayer:self.recordDurationLayer];
    
    self.recordHelpLayer = [TMTextLayer layer];
    [self.recordHelpLayer disableActions];
    self.recordHelpLayer.contentsScale = self.normalView.layer.contentsScale;
    [self.recordHelpLayer setTextFont:[NSFont fontWithName:@"HelveticaNeue" size:14]];
    [self.normalView.layer addSublayer:self.recordHelpLayer];


    

    
 //   self.attachMenu = theMenu;

    
    int offsetX = self.attachButton.frame.origin.x + self.attachButton.frame.size.width + 21;
    
    self.inputMessageTextField.containerView.autoresizesSubviews = YES;
    self.inputMessageTextField.containerView.autoresizingMask = NSViewWidthSizable;
    
    self.inputMessageTextField.containerView.frame = NSMakeRect(offsetX, 11, self.bounds.size.width - offsetX - self.sendButton.frame.size.width - 33, 30);
    self.inputMessageTextField.growingDelegate = self;
    [self.inputMessageTextField textDidChange:nil];
    
    [self.normalView addSubview:self.inputMessageTextField.containerView];
    
    
    
    self.smileButton = [[BTRButton alloc] initWithFrame:NSMakeRect(self.inputMessageTextField.containerView.frame.size.width - 30, 7, image_smile().size.width, image_smile().size.height)];
    [self.smileButton setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [self.smileButton.layer disableActions];
    [self.smileButton setBackgroundImage:image_smile() forControlState:BTRControlStateNormal];
    [self.smileButton setBackgroundImage:image_smileHover() forControlState:BTRControlStateHover];
    [self.smileButton setBackgroundImage:image_smileActive() forControlState:BTRControlStateHighlighted];
    [self.smileButton setBackgroundImage:image_smileActive() forControlState:BTRControlStateSelected | BTRControlStateHover];
    [self.smileButton setBackgroundImage:image_smileActive() forControlState:BTRControlStateSelected];
  //  [self.smileButton setCursor:[NSCursor pointingHandCursor] forControlState:BTRControlStateNormal];
    
    
    [self.smileButton addTarget:self action:@selector(smileButtonClick:) forControlEvents:BTRControlEventMouseEntered];
    
    [self.inputMessageTextField.containerView addSubview:self.smileButton];
    
    //self.normalView.backgroundColor = NSColorFromRGB(0x000000)
    
    _imageAttachmentsController = [[TGImageAttachmentsController alloc] initWithFrame:NSMakeRect(self.attachButton.frame.origin.x + self.attachButton.frame.size.width + 11, NSHeight(self.inputMessageTextField.containerView.frame) + NSMinX(self.inputMessageTextField.frame) + 20, NSWidth(self.inputMessageTextField.containerView.frame), 70)];
        
    _imageAttachmentsController.delegate = self;
        
    [self.normalView addSubview:_imageAttachmentsController];

    
    return self.normalView;
}

-(NSMenu *)attachMenu {
    NSMenu *theMenu = [[NSMenu alloc] init];
    
    NSMenuItem *attachPhotoOrVideoItem = [NSMenuItem menuItemWithTitle:NSLocalizedString(@"Attach.PictureOrVideo", nil) withBlock:^(id sender) {
        [FileUtils showPanelWithTypes:mediaTypes() completionHandler:^(NSArray *paths) {
            
            BOOL isMultiple = [paths filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self.pathExtension.lowercaseString IN (%@)",imageTypes()]].count > 1;
            
            [paths enumerateObjectsUsingBlock:^(NSString *obj, NSUInteger idx, BOOL *stop) {
                
                NSString *extenstion = [[obj pathExtension] lowercaseString];
                
                if([imageTypes() indexOfObject:extenstion] != NSNotFound) {
                    [self.messagesViewController sendImage:obj file_data:nil isMultiple:isMultiple addCompletionHandler:nil];
                } else {
                    [self.messagesViewController sendVideo:obj];
                }
                
            }];
        }];
    }];
    [attachPhotoOrVideoItem setImage:image_AttachPhotoVideo()];
    [attachPhotoOrVideoItem setHighlightedImage:image_AttachPhotoVideoHighlighted()];
    [theMenu addItem:attachPhotoOrVideoItem];
    
    
    NSMenuItem *attachTakePhotoItem = [NSMenuItem menuItemWithTitle:NSLocalizedString(@"Attach.TakePhoto", nil) withBlock:^(id sender) {
        
        IKPictureTaker *pictureTaker = [IKPictureTaker pictureTaker];
        [pictureTaker setValue:[NSNumber numberWithBool:YES] forKey:IKPictureTakerShowEffectsKey];
        [pictureTaker setValue:[NSValue valueWithSize:NSMakeSize(640, 640)] forKey:IKPictureTakerOutputImageMaxSizeKey];
        [pictureTaker beginPictureTakerSheetForWindow:self.window withDelegate:self didEndSelector:@selector(pictureTakerValidated:code:contextInfo:) contextInfo:nil];
    }];
    [attachTakePhotoItem setImage:image_AttachTakePhoto()];
    [attachTakePhotoItem setHighlightedImage:image_AttachTakePhotoHighlighted()];
    [theMenu addItem:attachTakePhotoItem];
    
    NSMenuItem *attachLocationItem = [NSMenuItem menuItemWithTitle:NSLocalizedString(@"Attach.Location", nil) withBlock:^(id sender) {
        
//        MapPanel *panel = [MapPanel sharedPanel];
//        [self.window beginSheet:panel completionHandler:^(NSModalResponse returnCode) {
//            
//        }];
        
        
        
        //        [FileUtils showPanelWithTypes:[NSArray arrayWithObjects:@"png", @"tiff", @"jpeg", @"jpg", @"mp4",@"mov",@"avi", nil] completionHandler:^(NSString *result) {
        //
        //            DLog(@"result %@", result);
        //
        //            [self.messagesViewController sendImage:result file_data:nil toDialog:self.messagesViewController.conversation];
        //        }];
    }];
    
    
    
    [attachLocationItem setImage:image_AttachLocation()];
    [attachLocationItem setHighlightedImage:image_AttachLocationHighlighted()];
    
    
  //  if(self.messagesViewController.conversation.type != DialogTypeSecretChat && floor(NSAppKitVersionNumber) > 1187)
     //   [theMenu addItem:attachLocationItem];
    
    NSMenuItem *attachFileItem = [NSMenuItem menuItemWithTitle:NSLocalizedString(@"Attach.File", nil) withBlock:^(id sender) {
        [FileUtils showPanelWithTypes:nil completionHandler:^(NSArray *paths) {
            
            [paths enumerateObjectsUsingBlock:^(NSString *obj, NSUInteger idx, BOOL *stop) {
                [self.messagesViewController sendDocument:obj];
            }];
            
            
            
            
        }];
    }];
    [attachFileItem setImage:image_AttachFile()];
    [attachFileItem setHighlightedImage:image_AttachFileHighlighted()];
    
    
    
    [theMenu addItem:attachFileItem];
    
    return theMenu;
}

- (void)recordAudioMouseEntered:(BTRButton *)button {
    if(!self.recordCircleLayer.isHidden) {
        [self.recordAudioButton setSelected:YES];
        [self.recordHelpLayer setTextColor:NSColorFromRGB(0x9b9b9b)];
    }
}

- (void)recordAudioMouseExited:(BTRButton *)button {
    if(!self.recordCircleLayer.isHidden) {
        [self.recordAudioButton setSelected:NO];
        [self.recordHelpLayer setTextColor:NSColorFromRGB(0xee6363)];
    }
}

- (void)setRecordHelperStringValue:(NSString *)string {
    self.recordHelpLayer.string = string;
    [self.recordHelpLayer sizeToFit];
    
    [self.recordHelpLayer setFrameOrigin:CGPointMake( roundf( (self.bounds.size.width - self.recordHelpLayer.bounds.size.width) / 2.f ), roundf( (self.bounds.size.height - self.recordHelpLayer.bounds.size.height) / 2.f ) - 1)];
}

- (void)startRecord:(BTRButton *)button {
    weak();

    self.recordTime = 0;
    [self.recordDurationLayer setString:@"00:00"];
    [self.recordDurationLayer setHidden:NO];
    [self.inputMessageTextField.containerView removeFromSuperview];

    [self.smileButton setHidden:YES];
    [self.attachButton setHidden:YES];
    
    [self.recordCircleLayer setHidden:NO];
    
    [self setRecordHelperStringValue:NSLocalizedString(@"Audio.ReleaseOut", nil)];
    [self.recordHelpLayer setHidden:NO];
    [self recordAudioMouseEntered:button];
    
    [self.recordTimer invalidate];
    
    
    self.recordTimer = [[TGTimer alloc] initWithTimeout:1.0 repeat:YES completion:^{
        
        
        [TGSendTypingManager addAction:[TL_sendMessageRecordAudioAction create] forConversation:self.dialog];
        
        
        weakSelf.recordTime++;
        [weakSelf.recordDurationLayer setString:[NSString durationTransformedValue:weakSelf.recordTime]];
    } queue:dispatch_get_main_queue()];
    [self.recordTimer start];
    

    TMAudioRecorder *recorder = [TMAudioRecorder sharedInstance];
    [recorder setPowerHandler:^(float power) {
        power = mappingRange(power, 0, 1, 0.5, 1);
        POPLayerSetScaleXY(weakSelf.recordCircleLayer, CGPointMake(power, power));
    }];
    
    [recorder startRecord];
}

- (void)stopRecord:(BTRButton *)button {
    
    
    NSPoint pos = [self convertPoint:[[NSApp currentEvent] locationInWindow] fromView:nil];
    
    BOOL isInside = NSPointInRect(pos, self.bounds);
    [[TMAudioRecorder sharedInstance] stopRecord:isInside];

    
    
    [self.recordAudioButton setSelected:NO];
    [self.recordTimer invalidate];
    
    [self.inputMessageTextField.containerView removeFromSuperview];
    NSMutableArray *subviews = [[self.normalView subviews] mutableCopy];
    [subviews insertObject:self.inputMessageTextField.containerView atIndex:subviews.count - 1];
    [self.normalView setSubviews:subviews];
    [self.inputMessageTextField.window makeFirstResponder:self.inputMessageTextField];
    
    [self.smileButton setHidden:NO];
    [self.attachButton setHidden:NO];
    
    [self.recordCircleLayer setHidden:YES];
    [self.recordDurationLayer setHidden:YES];
    [self.recordHelpLayer setHidden:YES];
}

- (void)stopRecordInside:(BTRButton *)button {
    [self stopRecord:button];
}

- (void)stopRecordOutside:(BTRButton *)button {
    [self stopRecord:button];
}

- (void)insertEmoji:(NSString *)emoji {
    [self.inputMessageTextField insertText:emoji];
}

-(void)closeEmoji {
    [self.smilePopover close];
}

- (void)smileButtonClick:(BTRButton *)button {
    EmojiViewController *emojiViewController = [EmojiViewController instance];
    weak();
    if(!self.smilePopover) {
       
       self.smilePopover = [[RBLPopover alloc] initWithContentViewController:(NSViewController *)emojiViewController];
        [self.smilePopover setHoverView:self.smileButton];
        [self.smilePopover setDidCloseBlock:^(RBLPopover *popover){
            [weakSelf.smileButton setSelected:NO];
        }];
    }
    
    [emojiViewController setInsertEmoji:^(NSString *emoji) {
        [weakSelf insertEmoji:emoji];
    }];
    
    [self.smileButton setSelected:YES];
    
    NSRect frame = self.smileButton.bounds;
    frame.origin.y += 4;
    
    if(!self.smilePopover.isShown) {
        [self.smilePopover showRelativeToRect:frame ofView:self.smileButton preferredEdge:CGRectMaxYEdge];
        [[EmojiViewController instance] showPopovers];
    }
}

- (TMView *)secretInfoView {
    if(self->_secretInfoView)
        return self->_secretInfoView;
    
    self->_secretInfoView = [[TMView alloc] initWithFrame:NSMakeRect(0, 0, self.bounds.size.width, self.bounds.size.height - 1)];
    [self.secretInfoView setAutoresizesSubviews:YES];
    [self.secretInfoView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    
    
    self.encryptedStateTextField = [TMTextField defaultTextField];
    [self.encryptedStateTextField setFont:[NSFont fontWithName:@"HelveticaNeue" size:12]];
    [self.encryptedStateTextField setAutoresizingMask:NSViewMaxXMargin | NSViewMaxYMargin | NSViewMinXMargin | NSViewMinYMargin];
    [self.encryptedStateTextField setTextColor:NSColorFromRGB(0xa1a1a1)];
    [self.secretInfoView addSubview:self.encryptedStateTextField];
    
    
    return self.secretInfoView;
}

- (void)setState:(MessagesBottomViewState)state animated:(BOOL)animated {
    
    if(state == MessagesBottomViewNormalState) {
        if(self.dialog.type == DialogTypeSecretChat) {
            EncryptedParams *params = self.dialog.encryptedChat.encryptedParams;
            if(params.state != EncryptedAllowed) {
                state = MessagesBottomViewBlockSecretState;
            }
        }
        
        if(!self.dialog.canSendMessage && self.dialog.type  == DialogTypeChat)
            state = MessagesBottomViewBlockChat;
    }
    
    
    self->_stateBottom = state;
    
    TMView *oldView, *newView;
    for(TMView *view in self.subviews) {
        if(!view.isHidden) {
            oldView = view;
            break;
        }
    }
    
    switch (state) {
        case MessagesBottomViewActionsState: {
            newView = self.actionsView;
            
            [self.messagesSelectedCount setHidden:YES];
            
            
            
            [self.forwardButton setDisable:YES];
            [self.deleteButton setDisable:YES];
            
            break;
        }
            
        case MessagesBottomViewNormalState: {
            newView = self.normalView;
            break;
        }
            
        default:
            newView = self.secretInfoView;
            break;
    }
    
    if(self.dialog && !self.dialog.canSendMessage) {
        animated = NO;
        [self.encryptedStateTextField setStringValue:[self.dialog blockedText]];
        [self.encryptedStateTextField sizeToFit];
        [self.encryptedStateTextField setCenterByView:self.encryptedStateTextField.superview];
    }
    
    if(oldView == newView) {
        [self becomeFirstResponder];
        return;
    }
    
    if(newView) {
    
        NSMutableArray *subviews = [[self subviews] mutableCopy];
        [subviews removeObject:newView];
        [subviews addObject:newView];
        [self setSubviews:subviews];
    }

    
    
    static float duration = 0.2;
    
    if(!animated) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [oldView setHidden:YES];
        [newView setHidden:NO];
        [CATransaction commit];
    } else {
        [oldView setHidden:YES];
        
        [newView.layer setOpacity:0];
        [newView setHidden:NO];
        
        POPBasicAnimation *anim = [POPBasicAnimation animationWithPropertyNamed:kPOPLayerOpacity];
        anim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        anim.fromValue = @(0.);
        anim.toValue = @(1.);
        anim.duration = duration;
        [anim setCompletionBlock:^(POPAnimation *anim, BOOL result) {
           // [oldView setHidden:YES];
        }];
        [newView.layer pop_addAnimation:anim forKey:@"fade"];
        
    }
    
    
    
    [self becomeFirstResponder];
}

- (void)sendButtonAction {
    
    [self.messagesViewController sendMessage];
    
    [self.messagesViewController sendAttachments:[_imageAttachmentsController attachments] addCompletionHandler:nil];
    
    if(_imageAttachmentsController.isShown) {
        [_imageAttachmentsController hide:YES deleteItems:YES];
        [self updateBottomHeight:YES];
        [self TMGrowingTextViewTextDidChange:nil];
    }
    
    
    [self.messagesViewController performForward:self.dialog];
    
}

- (BOOL) TMGrowingTextViewCommandOrControlPressed:(id)textView isCommandPressed:(BOOL)isCommandPressed {
    BOOL isNeedSend = ([SettingsArchiver checkMaskedSetting:SendEnter] && !isCommandPressed) || ([SettingsArchiver checkMaskedSetting:SendCmdEnter] && isCommandPressed);
    
    if(isNeedSend && ![TGMentionPopup isVisibility] && ![TGHashtagPopup isVisibility]) {
         [self sendButtonAction];
    }
    return isNeedSend;
}

- (void) TMGrowingTextViewFirstResponder:(id)textView isFirstResponder:(BOOL)isFirstResponder {
    static BOOL oldValue;
    if(oldValue != isFirstResponder) {
        oldValue = isFirstResponder;
//        [self.inputMessageTextField setBackgroundImage:isFirstResponder ? msg_input_active() : msg_input()];
    }
}

- (void)TMGrowingTextViewTextDidChange:(id)textView {
    
    [self.messagesViewController saveInputText];
    
    
    if([self.inputMessageTextField.stringValue trim].length > 0 || self.fwdContainer || _imageAttachmentsController.isShown) {
        
        
        if([self.inputMessageTextField.stringValue trim].length > 0 && textView)
            [TGSendTypingManager addAction:[TL_sendMessageTypingAction create] forConversation:self.dialog];
       // [self.messagesViewController sendTypingWithAction:[TL_sendMessageTypingAction create]];
        
        
        [self.sendButton setTextColor:LINK_COLOR forState:TMButtonNormalState];
        [self.sendButton setTextColor:NSColorFromRGB(0x467fb0) forState:TMButtonNormalHoverState];
        [self.sendButton setTextColor:NSColorFromRGB(0x2e618c) forState:TMButtonPressedState];
        [self.sendButton setDisabled:NO];
    } else {
        [self.sendButton setTextColor:NSColorFromRGB(0xaeaeae) forState:TMButtonNormalState];
        [self.sendButton setDisabled:YES];
    }
    
    if(self.inputMessageTextField.stringValue.length || self.fwdContainer || _imageAttachmentsController.isShown) {
        [self.sendButton setHidden:NO];
        [self.recordAudioButton setHidden:YES];
    } else {
        [self.sendButton setHidden:YES];
        [self.recordAudioButton setHidden:NO];
    }
    
    
    [self updateWebpage:YES];
    
    [self checkMentionsOrTags];
    
    
    
}

-(void)checkMentionsOrTags {
    
        
    NSRect rect = [self.inputMessageTextField firstRectForCharacterRange:[self.inputMessageTextField selectedRange]];
    
    NSRect textViewBounds = [self.inputMessageTextField convertRectToBase:[self.inputMessageTextField bounds]];
    textViewBounds.origin = [[self.inputMessageTextField window] convertBaseToScreen:textViewBounds.origin];
    
    rect.origin.x -= textViewBounds.origin.x;
    rect.origin.y-= textViewBounds.origin.y;
    
    rect.origin.x += 100;
    
    
    NSString *string = [self.inputMessageTextField string];
    
    NSRange range;
    
    NSString *search;
    
    NSRange selectedRange = self.inputMessageTextField.selectedRange;
    
    
    BOOL isMention;
    
    while ((range = [string rangeOfString:@"@"]).location != NSNotFound || (range = [string rangeOfString:@"#"]).location != NSNotFound) {
        
        isMention = [[string substringWithRange:range] isEqualToString:@"@"];
        
        search = [string substringFromIndex:range.location + 1];
        
        NSRange space = [search rangeOfString:@" "];
        
        if(space.location != NSNotFound)
            search = [search substringToIndex:space.location];
        
        
        
        if(search.length > 0) {
            
            if(selectedRange.location == range.location + search.length + 1)
                break;
            else
                search = nil;
        }
        
        string = [string substringFromIndex:range.location +1];
        
    }
    if(search != nil && ![string hasPrefix:@" "]) {
        
        
        
        
        void (^callback)(NSString *fullUserName) = ^(NSString *fullUserName) {
            NSMutableString *insert = [[self.inputMessageTextField string] mutableCopy];
            
            [insert insertString:[fullUserName substringFromIndex:search.length] atIndex:selectedRange.location];
            
            
            
            [self.inputMessageTextField insertText:[fullUserName stringByAppendingString:@" "] replacementRange:NSMakeRange(range.location + 1, search.length)];
            
        };
        
        if(isMention) {
            if(self.dialog.type == DialogTypeChat)
                [TGMentionPopup show:search chat:self.dialog.chat view:self.window.contentView ofRect:rect callback:callback];
        } else {
            [TGHashtagPopup show:search peer_id:self.dialog.peer_id view:self.window.contentView ofRect:rect callback:callback];
        }
        
    } else {
        [TGMentionPopup close];
        [TGHashtagPopup close];
    }
    

}

-(void)checkFwdMessages:(BOOL)updateHeight animated:(BOOL)animated {
    
    
    [_fwdContainer removeFromSuperview];
    
    _fwdContainer = nil;
    
    
    NSArray *fwdMessages = [self.messagesViewController fwdMessages:self.dialog];
    
    
    if(fwdMessages.count > 0) {
        
        _fwdContainer = [[TGForwardContainer alloc] initWithFrame:NSMakeRect(self.attachButton.frame.origin.x + self.attachButton.frame.size.width + 21, NSHeight(self.inputMessageTextField.containerView.frame) + NSMinX(self.inputMessageTextField.frame) + 20 + (self.replyContainer ? 45 : 0), NSWidth(self.inputMessageTextField.containerView.frame), 30)];
        
        
        TGForwardObject *fwdObj = [[TGForwardObject alloc] initWithMessages:fwdMessages];
        
        [_fwdContainer setFwdObject:fwdObj];
        
        weak();
        
        [_fwdContainer setDeleteHandler:^{
           
            [weakSelf.messagesViewController clearFwdMessages:weakSelf.dialog];
            
        }];
        
        _fwdContainer.autoresizingMask = NSViewWidthSizable;
        
        
        
        [self.normalView addSubview:_fwdContainer];
        
        if(updateHeight) {
            [self updateBottomHeight:animated];
        }
        
        
    } else {
        
        if(updateHeight) {
            [self updateBottomHeight:animated];
        }
        
    }
   
    
    [self TMGrowingTextViewTextDidChange:nil];
    
}

-(void)updateBottomHeight:(BOOL)animated
{
    dispatch_block_t block = ^ {
        
        [self TMGrowingTextViewHeightChanged:self.inputMessageTextField height:NSHeight(self.inputMessageTextField.containerView.frame) cleared:animated];
    };
    
    dispatch_block_t animationBlock = ^ {
        
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            
            [context setDuration:0.2];
            [context setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
            
            block();
            
        } completionHandler:^{
            
        }];
        
    };
    
    if(animated)
        animationBlock();
    else
        block();
}


-(void)checkReplayMessage:(BOOL)updateHeight animated:(BOOL)animated {
    
    [self.replyContainer removeFromSuperview];
    
    self.replyContainer = nil;
    
    
    __block TL_localMessage *replyMessage;
    
    [[Storage yap] readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        
        NSData *serialized = [transaction objectForKey:[NSString stringWithFormat:@"%d",self.dialog.peer_id] inCollection:REPLAY_COLLECTION];
        
        if(serialized) {
            replyMessage = [TLClassStore deserialize:serialized];
        }
        
        
    }];
    
    
    
   
    
    if(replyMessage) {
        int startX = self.attachButton.frame.origin.x + self.attachButton.frame.size.width + 21;
        
        TGReplyObject *replyObject = [[TGReplyObject alloc] initWithReplyMessage:replyMessage];
        
        
        _replyContainer = [[MessageReplyContainer alloc] initWithFrame:NSMakeRect(startX, NSHeight(self.inputMessageTextField.containerView.frame) + NSMinX(self.inputMessageTextField.frame) + 20 , NSWidth(self.inputMessageTextField.containerView.frame), replyObject.containerHeight)];
        
        [_replyContainer setReplyObject:replyObject];
        
        [_replyContainer setBackgroundColor:NSColorFromRGB(0xfafafa)];
        
        _replyContainer.autoresizingMask = NSViewWidthSizable;
        
        weak();
        
        [_replyContainer setDeleteHandler:^{
           
            [weakSelf.messagesViewController removeReplayMessage:YES animated:YES];
            
        }];
        
        
        
        [self.normalView addSubview:_replyContainer];
        
        if(updateHeight) {
            [self updateBottomHeight:animated];
        }
        
        
    } else {
        
        if(updateHeight) {
            [self updateBottomHeight:animated];
        }
        
    }
}

-(void)updateWebpage:(BOOL)animated {
    
#ifdef TGDEBUG
    
  //  if(!ACCEPT_FEATURE)
    //    return;
    
#endif
    
    
    if([self.webpageAttach.link isEqualToString:[self.inputMessageString webpageLink]] && !self.messagesViewController.noWebpage)
        return;
    
    
    
        
    TLWebPage *webpage = !self.messagesViewController.noWebpage ? [Storage findWebpage:[self.inputMessageString webpageLink]] : nil;
    
    if(!webpage && !self.webpageAttach)
        return;
    
   
    if([webpage isKindOfClass:[TL_webPage class]] || [webpage isKindOfClass:[TL_webPagePending class]]) {
        
        [_webpageAttach removeFromSuperview];
        _webpageAttach = nil;
        
        int startX = self.attachButton.frame.origin.x + self.attachButton.frame.size.width + 21;
        
        _webpageAttach = [[TGWebpageAttach alloc] initWithFrame:NSMakeRect(startX, NSHeight(self.inputMessageTextField.containerView.frame) + NSMinX(self.inputMessageTextField.frame) + 20 , NSWidth(self.inputMessageTextField.containerView.frame), 30) webpage:webpage link:[self.inputMessageString webpageLink]];
        
        _webpageAttach.autoresizingMask = NSViewWidthSizable;
        
        [self.normalView addSubview:_webpageAttach];
        
    } else {
        [_webpageAttach removeFromSuperview];
        _webpageAttach = nil;
    }
    
    [self updateBottomHeight:animated];
    
}





- (void) TMGrowingTextViewHeightChanged:(id)textView height:(int)height cleared:(BOOL)isCleared {
    height += 24;

    
//    DLog(@"height %d", height);
    height = height % 2 == 1 ? height + 1 : height;
//    DLog(@"height %d", height);
    
    if(_imageAttachmentsController.isShown ) {
        height += 75;
    }

    
    if(self.replyContainer != nil) {
        height+= self.replyContainer.replyObject.containerHeight + 5;
    }
    
    if(self.fwdContainer != nil) {
        height+= 35;
    }
    
    if(self.webpageAttach != nil && self.inputMessageString.length > 0) {
        height+= 35;
    }
    
    
    if(self.stateBottom == MessagesBottomViewNormalState) {
        [self.layer setNeedsDisplay];
        
        NSSize layoutSize = NSMakeSize(self.bounds.size.width, height);
        
        if(isCleared) {
            
            
           // [[self.smileButton animator] setFrameOrigin:NSMakePoint(NSMinX(self.smileButton.frame), NSMinY(self.inputMessageTextField.containerView.frame) + NSHeight(self.inputMessageTextField.containerView.frame)- NSHeight(self.smileButton.frame) - 6)];
            
            [self.animator setFrameSize:layoutSize];
            [self.messagesViewController bottomViewChangeSize:height animated:isCleared];
            
            int offset = _imageAttachmentsController.isShown ? 95 : 20;
            
            [[_replyContainer animator] setFrameOrigin:NSMakePoint(NSMinX(_replyContainer.frame), NSHeight(self.inputMessageTextField.containerView.frame) + offset )];
            
            [[_fwdContainer animator] setFrameOrigin:NSMakePoint(NSMinX(_fwdContainer.frame), NSHeight(self.inputMessageTextField.containerView.frame) + offset + (_replyContainer ? 40 : 0))];
            
            [[_webpageAttach animator] setFrameOrigin:NSMakePoint(NSMinX(_webpageAttach.frame), NSHeight(self.inputMessageTextField.containerView.frame) + offset + (_fwdContainer ? (_replyContainer ? 80 : 40) : _replyContainer ? 40 : 0))];
            
        } else {

       //     [self.smileButton setFrameOrigin:NSMakePoint(NSMinX(self.smileButton.frame), NSMinY(self.inputMessageTextField.containerView.frame) + NSHeight(self.inputMessageTextField.containerView.frame) - NSHeight(self.smileButton.frame) - 6)];
             [self setFrameSize:layoutSize];
             [self.messagesViewController bottomViewChangeSize:height animated:isCleared];
            
            int offset = _imageAttachmentsController.isShown ? 95 : 20;
            
            [_replyContainer setFrameOrigin:NSMakePoint(NSMinX(_replyContainer.frame), NSHeight(self.inputMessageTextField.containerView.frame) + offset )];
            
            
            [_fwdContainer setFrameOrigin:NSMakePoint(NSMinX(_fwdContainer.frame), NSHeight(self.inputMessageTextField.containerView.frame) + offset + (_replyContainer ? 40 : 0))];
            
            [_webpageAttach setFrameOrigin:NSMakePoint(NSMinX(_webpageAttach.frame), NSHeight(self.inputMessageTextField.containerView.frame) + offset + (_fwdContainer ? _replyContainer ? 80 : 40 : _replyContainer ? 40 : 0))];
        }
        
        
        
        
        
       // [self.layer setNeedsDisplay];
    }
}


-(void)setFrame:(NSRect)frame {
    [super setFrame:frame];
    
    int offsetX = self.attachButton.frame.origin.x + self.attachButton.frame.size.width + 21;
    
    self.inputMessageTextField.containerView.frame = NSMakeRect(offsetX, 11, self.bounds.size.width - offsetX - self.sendButton.frame.size.width - 33, 30);
    [self.inputMessageTextField textDidChange:nil];
}


- (void) attachButtonPressed {
    [self.attachButton setSelected:YES];

    if(!self.menuPopover) {
        self.menuPopover = [[TMMenuPopover alloc] initWithMenu:self.attachMenu];
        [self.menuPopover setHoverView:self.attachButton];
    }
    
    if(!self.menuPopover.isShown) {
        NSRect rect = self.attachButton.bounds;
        rect.origin.x += 80;
        rect.origin.y += 10;
        weak();
        [self.menuPopover setDidCloseBlock:^(TMMenuPopover *popover) {
            [weakSelf.attachButton setSelected:NO];
        }];
        [self.menuPopover showRelativeToRect:rect ofView:self.attachButton preferredEdge:CGRectMaxYEdge];
    }
    
//    [self.attachMenu popUpForView:self.attachButton];
}

- (void)setStateBottom:(MessagesBottomViewState)stateBottom {
    [self setState:stateBottom animated:NO];
}


- (void) pictureTakerValidated:(IKPictureTaker*) pictureTaker code:(int) returnCode contextInfo:(void*) ctxInf {
    if(returnCode == NSOKButton){
        NSImage *outputImage = [pictureTaker outputImage];
        [self.messagesViewController sendImage:nil file_data:[outputImage TIFFRepresentation]];

    }
}

- (void)setInputMessageString:(NSString *)message disableAnimations:(BOOL)disableAnimations {
    [self.inputMessageTextField setString:message];
    
    
    self.inputMessageTextField.disableAnimation = disableAnimations;
    

    
    [self.inputMessageTextField textDidChange:nil];

    self.inputMessageTextField.disableAnimation = YES;
    
}

- (NSString *)inputMessageString {
    return [self.inputMessageTextField stringValue];
}

- (BOOL)becomeFirstResponder {
    if(self.stateBottom == MessagesBottomViewNormalState) {
        [[self window] makeFirstResponder:self.inputMessageTextField];
    } else {
        if(self.window.firstResponder == self.inputMessageTextField) {
            [[self window] makeFirstResponder:nil];
        }
    }
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    
    
    [GRAY_BORDER_COLOR set];
    NSRectFill(NSMakeRect(0, self.bounds.size.height - 1, self.bounds.size.width, 1));
}

@end


/*
 if(self.dialog.type == DialogTypeSecretChat)
 return;
 
 NSArray *links = [self.inputMessageTextField.stringValue locationsOfLinks];
 
 NSArray *acceptExtensions = @[@"jpg",@"png",@"tiff"];
 
 
 BOOL needUpdate = self.attachments.count > 0;
 
 [self.attachments enumerateObjectsUsingBlock:^(TGAttachImageElement *obj, NSUInteger idx, BOOL *stop) {
 
 [obj removeFromSuperview];
 
 }];
 
 [self.attachments removeAllObjects];
 
 
 __block int startX = self.attachButton.frame.origin.x + self.attachButton.frame.size.width + 16;
 
 __block int k = 0;
 
 [links enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
 
 NSRange range = [obj range];
 
 NSString *link = [self.inputMessageTextField.stringValue substringWithRange:range];
 
 __block BOOL checkIgnore = YES;
 
 
 [self.attachmentsIgnore enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
 
 NSString *l = obj[@"link"];
 NSRange r = [obj[@"range"] rangeValue];
 
 if((range.location == r.location && range.length == r.length) && [link isEqualToString:l])
 {
 *stop = YES;
 checkIgnore = NO;
 }
 
 }];
 
 if([acceptExtensions indexOfObject:[link pathExtension]] != NSNotFound && checkIgnore) {
 
 
 TGAttachImageElement *attach = [[TGAttachImageElement alloc] initWithFrame:NSMakeRect(startX, NSHeight(self.inputMessageTextField.containerView.frame) + NSMinX(self.inputMessageTextField.frame) + 20, 70, 70)];
 
 startX +=80;
 
 [attach setDeleteCallback:^{
 
 [self.attachmentsIgnore addObject:@{@"link":link,@"range":[NSValue valueWithRange:range]}];
 
 // [self checkAttachImages];
 
 }];
 
 [attach setLink:link range:range];
 
 
 
 [self.attachments addObject:attach];
 
 [self.normalView addSubview:attach];
 
 
 k++;
 
 }
 
 if(k == 4)
 *stop = YES;
 
 }];
 
 needUpdate = (self.attachments.count == 0 && needUpdate) || (self.attachments.count > 0 && !needUpdate);
 
 if(self.inputMessageString.length > 0 || needUpdate)

*/