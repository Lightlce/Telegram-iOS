import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramPresentationData
import AccountContext
import ContextUI
import TelegramCore
import TextFormat
import ReactionSelectionNode
import WallpaperBackgroundNode

private final class ChatSendMessageActionSheetControllerImpl: ViewController, ChatSendMessageActionSheetController {
    private var controllerNode: ChatSendMessageActionSheetControllerNode {
        return self.displayNode as! ChatSendMessageActionSheetControllerNode
    }
    
    private let context: AccountContext
    
    private let peerId: EnginePeer.Id?
    private let isScheduledMessages: Bool
    private let forwardMessageIds: [EngineMessage.Id]?
    private let hasEntityKeyboard: Bool
    
    private let gesture: ContextGesture
    private let sourceSendButton: ASDisplayNode
    private let textInputView: UITextView
    private let attachment: Bool
    private let canSendWhenOnline: Bool
    private let completion: () -> Void
    private let sendMessage: (SendMode, MessageEffect?) -> Void
    private let schedule: (MessageEffect?) -> Void
    private let reactionItems: [ReactionItem]?
    
    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?
    
    private var didPlayPresentationAnimation = false
    
    private var validLayout: ContainerViewLayout?
    
    private let hapticFeedback = HapticFeedback()
    
    private let emojiViewProvider: ((ChatTextInputTextCustomEmojiAttribute) -> UIView)?

    public init(context: AccountContext, updatedPresentationData: (initial: PresentationData, signal: Signal<PresentationData, NoError>)? = nil, peerId: EnginePeer.Id?, isScheduledMessages: Bool = false, forwardMessageIds: [EngineMessage.Id]?, hasEntityKeyboard: Bool, gesture: ContextGesture, sourceSendButton: ASDisplayNode, textInputView: UITextView, emojiViewProvider: ((ChatTextInputTextCustomEmojiAttribute) -> UIView)?, attachment: Bool = false, canSendWhenOnline: Bool, completion: @escaping () -> Void, sendMessage: @escaping (SendMode, MessageEffect?) -> Void, schedule: @escaping (MessageEffect?) -> Void, reactionItems: [ReactionItem]? = nil) {
        self.context = context
        self.peerId = peerId
        self.isScheduledMessages = isScheduledMessages
        self.forwardMessageIds = forwardMessageIds
        self.hasEntityKeyboard = hasEntityKeyboard
        self.gesture = gesture
        self.sourceSendButton = sourceSendButton
        self.textInputView = textInputView
        self.emojiViewProvider = emojiViewProvider
        self.attachment = attachment
        self.canSendWhenOnline = canSendWhenOnline
        self.completion = completion
        self.sendMessage = sendMessage
        self.schedule = schedule
        self.reactionItems = reactionItems
        
        self.presentationData = updatedPresentationData?.initial ?? context.sharedContext.currentPresentationData.with { $0 }
        
        super.init(navigationBarPresentationData: nil)
        
        self.blocksBackgroundWhenInOverlay = true
        
        self.presentationDataDisposable = ((updatedPresentationData?.signal ?? context.sharedContext.presentationData)
        |> deliverOnMainQueue).startStrict(next: { [weak self] presentationData in
            if let strongSelf = self {
                strongSelf.presentationData = presentationData
                if strongSelf.isNodeLoaded {
                    strongSelf.controllerNode.updatePresentationData(presentationData)
                }
            }
        }).strict()
        
        self.statusBar.statusBarStyle = .Hide
        self.statusBar.ignoreInCall = true
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.presentationDataDisposable?.dispose()
    }
    
    override public func loadDisplayNode() {
        var forwardedCount: Int?
        if let forwardMessageIds = self.forwardMessageIds, forwardMessageIds.count > 0 {
            forwardedCount = forwardMessageIds.count
        }
        
        var reminders = false
        var isSecret = false
        var canSchedule = false
        if let peerId = self.peerId {
            reminders = peerId == context.account.peerId
            isSecret = peerId.namespace == Namespaces.Peer.SecretChat
            canSchedule = !isSecret
        }
        if self.isScheduledMessages {
            canSchedule = false
        }
        
        self.displayNode = ChatSendMessageActionSheetControllerNode(context: self.context, presentationData: self.presentationData, reminders: reminders, gesture: gesture, sourceSendButton: self.sourceSendButton, textInputView: self.textInputView, attachment: self.attachment, canSendWhenOnline: self.canSendWhenOnline, forwardedCount: forwardedCount, hasEntityKeyboard: self.hasEntityKeyboard, emojiViewProvider: self.emojiViewProvider, send: { [weak self] in
            var messageEffect: MessageEffect?
            if let selectedEffect = self?.controllerNode.selectedMessageEffect {
                messageEffect = MessageEffect(id: selectedEffect.id)
            }
            self?.sendMessage(.generic, messageEffect)
            self?.dismiss(cancel: false)
        }, sendSilently: { [weak self] in
            var messageEffect: MessageEffect?
            if let selectedEffect = self?.controllerNode.selectedMessageEffect {
                messageEffect = MessageEffect(id: selectedEffect.id)
            }
            self?.sendMessage(.silently, messageEffect)
            self?.dismiss(cancel: false)
        }, sendWhenOnline: { [weak self] in
            var messageEffect: MessageEffect?
            if let selectedEffect = self?.controllerNode.selectedMessageEffect {
                messageEffect = MessageEffect(id: selectedEffect.id)
            }
            self?.sendMessage(.whenOnline, messageEffect)
            self?.dismiss(cancel: false)
        }, schedule: !canSchedule ? nil : { [weak self] in
            var messageEffect: MessageEffect?
            if let selectedEffect = self?.controllerNode.selectedMessageEffect {
                messageEffect = MessageEffect(id: selectedEffect.id)
            }
            self?.schedule(messageEffect)
            self?.dismiss(cancel: false)
        }, cancel: { [weak self] in
            self?.dismiss(cancel: true)
        }, reactionItems: self.reactionItems)
        self.displayNodeDidLoad()
    }
    
    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if !self.didPlayPresentationAnimation {
            self.didPlayPresentationAnimation = true
            
            self.hapticFeedback.impact()
            self.controllerNode.animateIn()
        }
    }
    
    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        self.validLayout = layout
        
        super.containerLayoutUpdated(layout, transition: transition)
        
        self.controllerNode.containerLayoutUpdated(layout, transition: transition)
    }
    
    override public func dismiss(completion: (() -> Void)? = nil) {
        self.dismiss(cancel: true)
    }
    
    private func dismiss(cancel: Bool) {
        self.statusBar.statusBarStyle = .Ignore
        self.controllerNode.animateOut(cancel: cancel, completion: { [weak self] in
            self?.completion()
            self?.didPlayPresentationAnimation = false
            self?.presentingViewController?.dismiss(animated: false, completion: nil)
        })
    }
}

public func makeChatSendMessageActionSheetController(
    context: AccountContext,
    updatedPresentationData: (initial: PresentationData, signal: Signal<PresentationData, NoError>)? = nil,
    peerId: EnginePeer.Id?,
    isScheduledMessages: Bool = false,
    forwardMessageIds: [EngineMessage.Id]?,
    hasEntityKeyboard: Bool,
    gesture: ContextGesture,
    sourceSendButton: ASDisplayNode,
    textInputView: UITextView,
    mediaPreview: ChatSendMessageContextScreenMediaPreview? = nil,
    mediaCaptionIsAbove: (Bool, (Bool) -> Void)? = nil,
    emojiViewProvider: ((ChatTextInputTextCustomEmojiAttribute) -> UIView)?,
    wallpaperBackgroundNode: WallpaperBackgroundNode? = nil,
    attachment: Bool = false,
    canSendWhenOnline: Bool,
    completion: @escaping () -> Void,
    sendMessage: @escaping (ChatSendMessageActionSheetController.SendMode, ChatSendMessageActionSheetController.MessageEffect?) -> Void,
    schedule: @escaping (ChatSendMessageActionSheetController.MessageEffect?) -> Void,
    reactionItems: [ReactionItem]? = nil,
    availableMessageEffects: AvailableMessageEffects? = nil,
    isPremium: Bool = false
) -> ChatSendMessageActionSheetController {
    if textInputView.text.isEmpty && !"".isEmpty {
        return ChatSendMessageActionSheetControllerImpl(
            context: context,
            updatedPresentationData: updatedPresentationData,
            peerId: peerId,
            isScheduledMessages: isScheduledMessages,
            forwardMessageIds: forwardMessageIds,
            hasEntityKeyboard: hasEntityKeyboard,
            gesture: gesture,
            sourceSendButton: sourceSendButton,
            textInputView: textInputView,
            emojiViewProvider: emojiViewProvider,
            attachment: attachment,
            canSendWhenOnline: canSendWhenOnline,
            completion: completion,
            sendMessage: sendMessage,
            schedule: schedule,
            reactionItems: nil
        )
    }
    
    return ChatSendMessageContextScreen(
        context: context,
        updatedPresentationData: updatedPresentationData,
        peerId: peerId,
        isScheduledMessages: isScheduledMessages,
        forwardMessageIds: forwardMessageIds,
        hasEntityKeyboard: hasEntityKeyboard,
        gesture: gesture,
        sourceSendButton: sourceSendButton,
        textInputView: textInputView,
        mediaPreview: mediaPreview,
        mediaCaptionIsAbove: mediaCaptionIsAbove,
        emojiViewProvider: emojiViewProvider,
        wallpaperBackgroundNode: wallpaperBackgroundNode,
        attachment: attachment,
        canSendWhenOnline: canSendWhenOnline,
        completion: completion,
        sendMessage: sendMessage,
        schedule: schedule,
        reactionItems: reactionItems,
        availableMessageEffects: availableMessageEffects,
        isPremium: isPremium
    )
}
