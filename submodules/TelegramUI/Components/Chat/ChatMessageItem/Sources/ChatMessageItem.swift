import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import ChatHistoryEntry
import ChatControllerInteraction
import TelegramPresentationData
import ChatMessageItemCommon

public enum ChatMessageItemContent: Sequence {
    case message(message: EngineRawMessage, read: Bool, selection: ChatHistoryMessageSelection, attributes: ChatMessageEntryAttributes, location: EngineMessageHistoryEntryLocation?)
    case group(messages: [(EngineRawMessage, Bool, ChatHistoryMessageSelection, ChatMessageEntryAttributes, EngineMessageHistoryEntryLocation?)])

    public func effectivelyIncoming(_ accountPeerId: EnginePeer.Id, associatedData: ChatMessageItemAssociatedData? = nil) -> Bool {
        if let subject = associatedData?.subject, case let .messageOptions(_, _, info) = subject {
            if case .forward = info {
                return false
            } else if case let .link(link) = info {
                return link.isCentered
            }
        }
        switch self {
            case let .message(message, _, _, _, _):
                return message.effectivelyIncoming(accountPeerId)
            case let .group(messages):
                return messages[0].0.effectivelyIncoming(accountPeerId)
        }
    }
    
    public var index: EngineMessage.Index {
        switch self {
            case let .message(message, _, _, _, _):
                return message.index
            case let .group(messages):
                return messages[0].0.index
        }
    }
    
    public var firstMessage: EngineRawMessage {
        switch self {
            case let .message(message, _, _, _, _):
                return message
            case let .group(messages):
                return messages[0].0
        }
    }
    
    public var firstMessageAttributes: ChatMessageEntryAttributes {
        switch self {
            case let .message(_, _, _, attributes, _):
                return attributes
            case let .group(messages):
                return messages[0].3
        }
    }
    
    public func makeIterator() -> AnyIterator<(EngineRawMessage, ChatMessageEntryAttributes)> {
        var index = 0
        return AnyIterator { () -> (EngineRawMessage, ChatMessageEntryAttributes)? in
            switch self {
                case let .message(message, _, _, attributes, _):
                    if index == 0 {
                        index += 1
                        return (message, attributes)
                    } else {
                        index += 1
                        return nil
                    }
                case let .group(messages):
                    if index < messages.count {
                        let currentIndex = index
                        index += 1
                        return (messages[currentIndex].0, messages[currentIndex].3)
                    } else {
                        return nil
                    }
            }
        }
    }
}

public enum ChatMessageItemAdditionalContent {
    case eventLogPreviousMessage(EngineRawMessage)
    case eventLogPreviousDescription(EngineRawMessage)
    case eventLogPreviousLink(EngineRawMessage)
    case eventLogGroupedMessages([EngineRawMessage], Bool)
}

public enum ChatMessageMerge: Int32 {
    case none = 0
    case fullyMerged = 1
    case semanticallyMerged = 2
    
    public var merged: Bool {
        if case .none = self {
            return false
        } else {
            return true
        }
    }
}

public struct ChatMessageHeaderSpec: Equatable {
    public var hasDate: Bool
    public var hasTopic: Bool
    
    public init(hasDate: Bool, hasTopic: Bool) {
        self.hasDate = hasDate
        self.hasTopic = hasTopic
    }
}

public protocol ChatMessageDateHeaderNode: ListViewItemHeaderNode {
    func updateItem(hasDate: Bool, hasPeer: Bool)
}

public protocol ChatMessageAvatarHeaderNode: ListViewItemHeaderNode {
    func updateSelectionState(animated: Bool)
    func updateAvatarIsHidden(isHidden: Bool, transition: ContainedViewLayoutTransition)
}

public protocol ChatMessageItem: ListViewItem {
    var presentationData: ChatPresentationData { get }
    var context: AccountContext { get }
    var chatLocation: ChatLocation { get }
    var associatedData: ChatMessageItemAssociatedData { get }
    var controllerInteraction: ChatControllerInteraction { get }
    var content: ChatMessageItemContent { get }
    var disableDate: Bool { get }
    var effectiveAuthorId: EnginePeer.Id? { get }
    var additionalContent: ChatMessageItemAdditionalContent? { get }

    var headers: [ListViewItemHeader] { get }
    
    var message: EngineRawMessage { get }
    var read: Bool { get }
    var unsent: Bool { get }
    var sending: Bool { get }
    var failed: Bool { get }
    
    func mergedWithItems(top: ListViewItem?, bottom: ListViewItem?, isRotated: Bool) -> (top: ChatMessageMerge, bottom: ChatMessageMerge, dateAtBottom: ChatMessageHeaderSpec)
}

public func hasCommentButton(item: ChatMessageItem) -> Bool {
    let firstMessage = item.content.firstMessage
    
    var hasDiscussion = false
    if let channel = firstMessage.peers[firstMessage.id.peerId] as? TelegramChannel, case let .broadcast(info) = channel.info, info.flags.contains(.hasDiscussionGroup) {
        hasDiscussion = true
    }
    if case let .replyThread(replyThreadMessage) = item.chatLocation, replyThreadMessage.effectiveTopId == firstMessage.id {
        hasDiscussion = false
    }

    if firstMessage.adAttribute != nil {
        hasDiscussion = false
    }
    
    if hasDiscussion {
        var canComment = false
        if case .pinnedMessages = item.associatedData.subject {
            canComment = false
        } else if firstMessage.id.namespace == Namespaces.Message.Local {
            canComment = true
        } else {
            for attribute in firstMessage.attributes {
                if let attribute = attribute as? ReplyThreadMessageAttribute, let commentsPeerId = attribute.commentsPeerId {
                    switch item.associatedData.channelDiscussionGroup {
                    case .unknown:
                        canComment = true
                    case let .known(groupId):
                        canComment = groupId == commentsPeerId
                    }
                    break
                }
            }
        }
        
        if canComment {
            return true
        }
    } else if firstMessage.id.peerId.isReplies {
        return true
    }
    return false
}

// SuperGram: `ChatMessageShareButton` is not only the share / repost button. The very same node renders the
// Comments button of a channel post, the "go to message" button of pinned-message lists, hashtag search results,
// Saved Messages / Replies and monoforums, and the close + report buttons of an ad. Only the last `else` branch of
// `ChatMessageShareButton.update` draws the plain share arrow, and only that arrow is hidden by "sgShowShareButton".
//
// This predicate therefore mirrors `ChatMessageShareButton.update`'s icon selection one branch at a time: it returns
// true whenever that method would pick anything other than `chatFreeShareButtonIcon`. Keep the two in sync — a
// branch missing here silently deletes a navigation affordance, and a branch too many leaves the arrow on screen.
// (The `hasTranslation` and `isSummarize` branches are deliberately absent: the quick-translate and summarize
// buttons are separate `ChatMessageShareButton` instances gated by their own flags, never by `needsShareButton`.)
/// - Parameter commentsDisabled: must match the `disableComments:` value the caller passes to
///   `ChatMessageShareButton.update`. When comments are disabled there, the node cannot render the Comments
///   variant (the bubble draws its own "N Comments" footer instead), so that branch must not keep the button alive.
public func superGramShareButtonActsAsNavigation(item: ChatMessageItem, commentsDisabled: Bool = false) -> Bool {
    let message = item.content.firstMessage

    // Ads: the node is the "close this ad" button, plus the "report" button underneath when the ad can be reported.
    if message.adAttribute != nil {
        return true
    }

    if let subject = item.associatedData.subject {
        // Public post / hashtag search results: "go to the original message".
        if case let .customChatContents(contents) = subject, case .hashTagSearch = contents.kind {
            return true
        }
        // The pinned message list: "go to the pinned message".
        if case .pinnedMessages = subject {
            return true
        }
    }

    if let channel = message.peers[message.id.peerId] as? TelegramChannel {
        if case .broadcast = channel.info {
            // `ChatMessageShareButton.update` clears `isReplies` for the root message of a reply thread, so the
            // node would fall through to the plain share arrow there even though the attribute is present.
            var isReplyThreadTopMessage = false
            if case let .replyThread(replyThreadMessage) = item.chatLocation, replyThreadMessage.effectiveTopId == message.id {
                isReplyThreadTopMessage = true
            }
            if !commentsDisabled && !isReplyThreadTopMessage {
                for attribute in message.attributes {
                    if let _ = attribute as? ReplyThreadMessageAttribute {
                        return true
                    }
                }
            }
        } else if channel.isMonoForum, case .peer = item.chatLocation {
            return true
        }
    }

    // Saved Messages, Replies and verification codes: "go to the original message".
    if message.id.peerId.isRepliesOrSavedMessages(accountPeerId: item.context.account.peerId) {
        return true
    }

    return false
}
