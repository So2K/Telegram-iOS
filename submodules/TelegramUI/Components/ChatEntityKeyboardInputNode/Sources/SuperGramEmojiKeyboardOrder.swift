// SuperGram (W2-CHATUI-INPUT, finding chat-03 `defaultEmojisFirst`): move the standard ("static") emoji group
// right after "recent", ahead of the premium / custom emoji packs.
//
// Swiftgram patches this inside `EntityKeyboardComponent` and had to relax
// `EmojiPagerContentComponent.panelItemGroups` / `contentItemGroups` from `let` to `var` to mutate the component
// in place. SuperGram does the same reordering one level up, in the chat keyboard node, with the existing public
// `withUpdatedItemGroups(...)` (which carries `inputInteractionHolder` over unchanged). That keeps the
// `EntityKeyboard` module untouched and leaves the other `EntityKeyboardComponent` users (status picker, avatar
// editor, reaction pickers, sticker picker) on stock ordering.
import Foundation
import EntityKeyboard

// MARK: Swiftgram
func sgPatchEmojiKeyboardItems(_ items: [EmojiPagerContentComponent.ItemGroup]) -> [EmojiPagerContentComponent.ItemGroup] {
    var items = items
    let staticEmojisIndex = items.firstIndex { item in
        if let groupId = item.groupId.base as? String, groupId == "static" {
            return true
        }
        return false
    }
    let recentEmojisIndex = items.firstIndex { item in
        if let groupId = item.groupId.base as? String, groupId == "recent" {
            return true
        }
        return false
    }
    if let staticEmojisIndex = staticEmojisIndex {
        let staticEmojiItem = items.remove(at: staticEmojisIndex)
        // SuperGram: `recentEmojisIndex` is an index into the array before the removal. "recent" is always built
        // before "static", so it is unaffected — but clamp anyway so a future ordering change cannot crash here.
        items.insert(staticEmojiItem, at: min(items.count, (recentEmojisIndex ?? -1) + 1))
    }
    return items
}
