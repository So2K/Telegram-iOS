import Foundation
import TelegramCore
import AccountContext

// SuperGram: feeds the chat list "History" button (SuperGramChatHistory). A chat is recorded when it appears and
// its reading position when the user leaves it, so the history can reopen it where they stopped.
extension ChatControllerImpl {
    /// Peer and thread of this chat if it is a regular chat that belongs in the history.
    private var superGramHistoryTarget: (peerId: EnginePeer.Id, threadId: Int64?)? {
        guard case .standard(.default) = self.presentationInterfaceState.mode else {
            return nil
        }
        if let subject = self.subject {
            switch subject {
            case .message:
                break
            default:
                // Scheduled / pinned messages, tag filters, message options and custom contents are not chats to return to
                return nil
            }
        }
        switch self.chatLocation {
        case let .peer(peerId):
            if peerId == self.context.account.peerId || peerId.namespace == Namespaces.Peer.SecretChat {
                return nil
            }
            return (peerId, nil)
        case let .replyThread(message):
            // Forum topics can be reopened directly; comment threads of channel posts and Saved Messages
            // sub-chats cannot
            if message.isForumPost && message.peerId != self.context.account.peerId {
                return (message.peerId, message.threadId)
            }
            return nil
        case .customChatContents:
            return nil
        }
    }

    func superGramRecordHistoryVisit() {
        guard let target = self.superGramHistoryTarget else {
            return
        }
        var title = ""
        if target.threadId != nil {
            // Forum topic: the peer (forum) is resolved for display, the topic title is shown as a subtitle
            if let threadData = self.presentationInterfaceState.threadData {
                title = threadData.title
            }
        } else if let peer = self.presentationInterfaceState.renderedPeer?.peer {
            title = EnginePeer(peer).displayTitle(strings: self.presentationData.strings, displayOrder: self.presentationData.nameDisplayOrder)
        }
        SuperGramChatHistory.shared.recordVisit(accountPeerId: self.context.account.peerId, peerId: target.peerId, threadId: target.threadId, title: title)
        // Keep the position current if the app goes to the background (or is closed) while this chat is open
        SuperGramChatHistory.shared.setActivePositionSaver(owner: self, saver: { [weak self] in
            self?.superGramSaveHistoryPosition()
        })
    }

    /// Leaving the chat: save the position once more and stop saving it on app background.
    func superGramFinishHistoryVisit() {
        SuperGramChatHistory.shared.setActivePositionSaver(owner: self, saver: nil)
        self.superGramSaveHistoryPosition()
    }

    func superGramSaveHistoryPosition() {
        guard let target = self.superGramHistoryTarget else {
            return
        }
        guard let range = self.chatDisplayNode.historyNode.superGramCurrentTopVisibleMessageRange, !range.isLoading else {
            return
        }
        // The history list is inverted, but ChatTopVisibleMessageRange is in chronological order: lowerBound is the
        // oldest visible message (top of the screen), upperBound the newest one (bottom of the screen), and isLast
        // means the newest loaded message is visible, i.e. the user is at the bottom of the chat. In that case there
        // is nothing to restore: a normal open shows the latest messages.
        // The newest visible message is the furthest point read; reopening centers it (ChatControllerSubject.message
        // scrolls to .center), so the lower half of the previous screen stays in view above it. Only cloud messages
        // can be found again by id (ads and local placeholders cannot).
        let messageId: EngineMessage.Id?
        if range.isLast {
            messageId = nil
        } else if range.upperBound.id.namespace == Namespaces.Message.Cloud {
            messageId = range.upperBound.id
        } else if range.lowerBound.id.namespace == Namespaces.Message.Cloud {
            messageId = range.lowerBound.id
        } else {
            return
        }
        SuperGramChatHistory.shared.updatePosition(accountPeerId: self.context.account.peerId, peerId: target.peerId, threadId: target.threadId, messageId: messageId)
    }
}
