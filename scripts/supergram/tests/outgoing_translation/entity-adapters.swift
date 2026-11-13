public struct MessageTextEntity:Equatable { public var range:Range<Int>;public let type:EntityType }
public enum EntityType:Equatable { case Bold,Italic,Code,Strikethrough,Underline,TextMention(peerId:Int64),TextUrl(url:String),FormattedDate(format:String?,date:Int32),Spoiler,CustomEmoji(stickerPack:Int?,fileId:Int64),BlockQuote(isCollapsed:Bool),Pre(language:String?),Url }
struct ChatTextInputTextMentionAttribute { let peerId:Int64 }
struct ChatTextInputTextUrlAttribute { let url:String }
struct ChatTextInputTextDateAttribute { let date:Int32 }
struct ChatTextInputTextCustomEmojiAttribute { let fileId:Int64 }
// ACTUAL_QUOTE_ATTRIBUTE
struct EnabledEntityTypes { static let allUrl=EnabledEntityTypes() }
func generateTextEntities(_ text:String,enabledTypes:EnabledEntityTypes)->[MessageTextEntity] { fatalError("Unexpected link-generator fixture path") }
func isSafeGeneratedUrl(_ url:String)->Bool { fatalError("Unexpected url fixture path") }

struct ReplyMessageSubject { let subjectModel:Int }
struct PostSuggestionState { let price:Int?;let timestamp:Int32? }
struct SynchronizeableChatInputState {
    struct SuggestedPost { let price:Int?;let timestamp:Int32? }
    let entities:[MessageTextEntity]
    init(replySubject:Int?,text:String,entities:[MessageTextEntity],timestamp:Int32,textSelection:Range<Int>,messageEffectId:Int64?,suggestedPost:SuggestedPost?) { self.entities=entities }
}
// ACTUAL_COLLAPSED_EXPANDER
// ACTUAL_ATTRIBUTE_KEYS
// ACTUAL_ENTITY_GENERATOR
