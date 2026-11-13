#!/usr/bin/env python3
"""SuperGram: generate main-bundle loc-keys for plaintext (unencrypted) Telegram APNs alerts.

Without a NotificationService extension the app registers its APNs token without a secret, so the Telegram
server sends readable pushes of the form aps.alert = {"loc-key": "MESSAGE_TEXT", "loc-args": [...]}. iOS
localizes `loc-key` from the MAIN app bundle's Localizable.strings and shows the raw key when it is missing.

The NotificationService extension uses the same server keys with a "PUSH_" prefix and a "title|body" format.
This script derives, for every PUSH_X key of Telegram-iOS/en.lproj/Localizable.strings, a key X whose value
renders as a single alert string "Title\\nBody", keeping the positional argument indices identical.

Outputs (consumed by Telegram/BUILD, which appends/copies them into each <lang>.lproj/Localizable.strings):
  Telegram/SuperGramPushStrings/en.strings
  Telegram/SuperGramPushStrings/ru.strings
  Telegram/SuperGramPushStrings/fallback.strings  (English, every key; for the other bundled localizations)

Run from the repository root:  python3 scripts/supergram/generate_push_alert_strings.py
"""
import json
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SOURCE = os.path.join(ROOT, "Telegram", "Telegram-iOS", "en.lproj", "Localizable.strings")
OUT_DIR = os.path.join(ROOT, "Telegram", "SuperGramPushStrings")

# NSE-only helpers, not server loc-keys.
EXCLUDED = {"PUSH_REMINDER_TITLE", "PUSH_SENDER_YOU"}

# The NSE appends a suffix (e.g. the account name) through %1$@; the server's generic alerts carry no
# loc-args for these, and a format with more placeholders than arguments is unsafe. Extra args are ignored.
STRIP_ARGS = {"ENCRYPTED_MESSAGE", "LOCKED_MESSAGE", "ENCRYPTION_REQUEST", "ENCRYPTION_ACCEPT"}

# Multi-item keys the server sends with a count argument. The NSE handles them through the plural helpers
# PUSH_<KEY>_TEXT_1 / PUSH_<KEY>_TEXT_any; argument order follows the existing PUSH_*_VIDEOS keys
# (private/channel: [peer, count]; group: [author, group, count]).
DERIVED_EN = {
    "MESSAGES": "%1$@|sent you %2$@ messages",
    "MESSAGE_FILES": "%1$@|sent you %2$@ files",
    "MESSAGE_DOCS": "%1$@|sent you %2$@ files",
    "MESSAGE_FWDS": "%1$@|forwarded you %2$@ messages",
    "MESSAGE_PHOTOS": "%1$@|sent you %2$@ photos",
    "CHANNEL_MESSAGES": "%1$@|posted %2$@ messages",
    "CHANNEL_MESSAGE_DOCS": "%1$@|posted %2$@ files",
    "CHANNEL_MESSAGE_PHOTOS": "%1$@|posted %2$@ photos",
    "CHAT_MESSAGES": "%2$@|%1$@ sent %3$@ messages",
    "CHAT_MESSAGE_DOCS": "%2$@|%1$@ sent %3$@ files",
    "CHAT_MESSAGE_FWDS": "%2$@|%1$@ forwarded %3$@ messages",
    "CHAT_MESSAGE_PHOTOS": "%2$@|%1$@ sent %3$@ photos",
}

# Russian, same "title|body" convention and the same placeholder set per key (verified below).
RU = {
    "ALBUM": "%1$@|отправил(а) вам альбом",
    "AUTH_REGION": "Новый вход|с неизвестного устройства %1$@, местоположение: %2$@",
    "AUTH_UNKNOWN": "Новый вход|с неизвестного устройства %1$@",
    "CHANNEL_ALBUM": "%1$@|опубликовал альбом",
    "CHANNEL_MESSAGE": "%1$@|опубликовал сообщение",
    "CHANNEL_MESSAGE_AUDIO": "%1$@|опубликовал голосовое сообщение",
    "CHANNEL_MESSAGE_CONTACT": "%1$@|опубликовал контакт",
    "CHANNEL_MESSAGE_DOC": "%1$@|опубликовал файл",
    "CHANNEL_MESSAGE_FWD": "%1$@|опубликовал пересланное сообщение",
    "CHANNEL_MESSAGE_GAME": "%1$@|приглашает вас сыграть в %2$@",
    "CHANNEL_MESSAGE_GEO": "%1$@|опубликовал карту",
    "CHANNEL_MESSAGE_GEOLIVE": "%1$@|опубликовал геопозицию в реальном времени",
    "CHANNEL_MESSAGE_GIF": "%1$@|опубликовал GIF",
    "CHANNEL_MESSAGE_NOTEXT": "%1$@|опубликовал сообщение",
    "CHANNEL_MESSAGE_PAID_MEDIA": "%1$@ опубликовал платный пост за %2$@ звёзд",
    "CHANNEL_MESSAGE_PHOTO": "%1$@|опубликовал фото",
    "CHANNEL_MESSAGE_POLL": "%1$@|опубликовал опрос",
    "CHANNEL_MESSAGE_QUIZ": "%1$@|опубликовал викторину",
    "CHANNEL_MESSAGE_ROUND": "%1$@|опубликовал видеосообщение",
    "CHANNEL_MESSAGE_STICKER": "%1$@|опубликовал %2$@стикер",
    "CHANNEL_MESSAGE_STORY": "%1$@|поделился историей",
    "CHANNEL_MESSAGE_TEXT": "%1$@|%2$@",
    "CHANNEL_MESSAGE_TODO": "%1$@|опубликовал список задач %2$@",
    "CHANNEL_MESSAGE_TODO_APPEND": "%1$@|добавил задачи: %2$@",
    "CHANNEL_MESSAGE_TODO_DONE": "%1$@|отметил задачи: %2$@",
    "CHANNEL_MESSAGE_VIDEO": "%1$@|опубликовал видео",
    "CHANNEL_MESSAGE_VIDEOS": "%1$@ опубликовал видео: %2$@",
    "CHAT_ADD_MEMBER": "%2$@|%1$@ пригласил(а) %3$@ в группу",
    "CHAT_ADD_YOU": "%2$@|%1$@ пригласил(а) вас в группу",
    "CHAT_ALBUM": "%2$@|%1$@ отправил(а) альбом",
    "CHAT_CREATED": "%2$@|%1$@ пригласил(а) вас в группу",
    "CHAT_DELETE_MEMBER": "%2$@|%1$@ удалил(а) %3$@ из группы",
    "CHAT_DELETE_YOU": "%2$@|%1$@ удалил(а) вас из группы",
    "CHAT_JOINED": "%2$@|%1$@ вступил(а) в группу",
    "CHAT_LEFT": "%2$@|%1$@ покинул(а) группу",
    "CHAT_LIVESTREAM_END": "%2$@|%1$@ завершил(а) трансляцию",
    "CHAT_LIVESTREAM_INVITE": "%2$@|%1$@ пригласил(а) %3$@ в трансляцию",
    "CHAT_LIVESTREAM_INVITE_YOU": "%2$@|%1$@ пригласил(а) вас в трансляцию",
    "CHAT_LIVESTREAM_START": "%2$@|%1$@ начал(а) трансляцию",
    "CHAT_MESSAGE": "%2$@|%1$@ отправил(а) сообщение",
    "CHAT_MESSAGE_AUDIO": "%2$@|%1$@ отправил(а) голосовое сообщение",
    "CHAT_MESSAGE_CONTACT": "%2$@|%1$@ поделился(-ась) контактом",
    "CHAT_MESSAGE_DOC": "%2$@|%1$@ отправил(а) файл",
    "CHAT_MESSAGE_FWD": "%2$@|%1$@ переслал(а) сообщение",
    "CHAT_MESSAGE_GAME": "%2$@|%1$@ приглашает группу сыграть в %3$@",
    "CHAT_MESSAGE_GAME_SCORE": "%1$@ набрал(а) %4$@ в игре %3$@ в группе %2$@",
    "CHAT_MESSAGE_GEO": "%2$@|%1$@ отправил(а) карту",
    "CHAT_MESSAGE_GEOLIVE": "%2$@|%1$@ транслирует геопозицию",
    "CHAT_MESSAGE_GIF": "%2$@|%1$@ отправил(а) GIF",
    "CHAT_MESSAGE_INVOICE": "%2$@|%1$@ отправил(а) счёт на %3$@",
    "CHAT_MESSAGE_NOTEXT": "%2$@|%1$@ отправил(а) сообщение в группу",
    "CHAT_MESSAGE_NOTHEME": "%1$@|отключил(а) тему в группе %2$@",
    "CHAT_MESSAGE_PAID_MEDIA": "%1$@ отправил(а) платный пост в группу %2$@ за %3$@ звёзд",
    "CHAT_MESSAGE_PHOTO": "%2$@|%1$@ отправил(а) фото",
    "CHAT_MESSAGE_POLL": "%2$@|%1$@ отправил(а) опрос %3$@ в группу",
    "CHAT_MESSAGE_QUIZ": "%2$@|%1$@ отправил(а) викторину %3$@ в группу",
    "CHAT_MESSAGE_ROUND": "%2$@|%1$@ отправил(а) видеосообщение",
    "CHAT_MESSAGE_STICKER": "%2$@|%1$@ отправил(а) %3$@стикер",
    "CHAT_MESSAGE_STORY": "%2$@|%1$@ поделился(-ась) историей в группе",
    "CHAT_MESSAGE_TEXT": "%2$@|%1$@: %3$@",
    "CHAT_MESSAGE_THEME": "%1$@|установил(а) тему %3$@ в группе %2$@",
    "CHAT_MESSAGE_TODO": "%2$@|%1$@ отправил(а) список задач %3$@",
    "CHAT_MESSAGE_TODO_APPEND": "%2$@|%1$@ добавил(а) задачи: %3$@",
    "CHAT_MESSAGE_TODO_DONE": "%2$@|%1$@ отметил(а) задачи: %3$@",
    "CHAT_MESSAGE_VIDEO": "%2$@|%1$@ отправил(а) видео",
    "CHAT_MESSAGE_VIDEOS": "%1$@ отправил(а) в группу %2$@ видео: %3$@",
    "CHAT_PHOTO_EDITED": "%2$@|%1$@ изменил(а) фото группы",
    "CHAT_REACT_AUDIO": "%2$@|%1$@: %3$@ на ваше голосовое сообщение",
    "CHAT_REACT_CONTACT": "%2$@|%1$@: %3$@ на ваш контакт %4$@",
    "CHAT_REACT_DOC": "%2$@|%1$@: %3$@ на ваш файл",
    "CHAT_REACT_GAME": "%2$@|%1$@: %3$@ на вашу игру",
    "CHAT_REACT_GEO": "%2$@|%1$@: %3$@ на вашу карту",
    "CHAT_REACT_GEOLIVE": "%2$@|%1$@: %3$@ на вашу геопозицию",
    "CHAT_REACT_GIF": "%2$@|%1$@: %3$@ на ваш GIF",
    "CHAT_REACT_INVOICE": "%2$@|%1$@: %3$@ на ваш счёт",
    "CHAT_REACT_NOTEXT": "%2$@|%1$@: %3$@ на ваше сообщение",
    "CHAT_REACT_PAID_MEDIA": "%2$@|%1$@: %3$@ на ваш платный пост",
    "CHAT_REACT_PHOTO": "%2$@|%1$@: %3$@ на ваше фото",
    "CHAT_REACT_POLL": "%2$@|%1$@: %3$@ на ваш опрос %4$@",
    "CHAT_REACT_QUIZ": "%2$@|%1$@: %3$@ на вашу викторину %4$@",
    "CHAT_REACT_ROUND": "%2$@|%1$@: %3$@ на ваше видеосообщение",
    "CHAT_REACT_STICKER": "%2$@|%1$@: %3$@ на ваш %4$@стикер",
    "CHAT_REACT_TEXT": "%2$@|%1$@: %3$@ на «%4$@»",
    "CHAT_REACT_TODO": "%2$@|%1$@: %3$@ на ваш список задач %4$@",
    "CHAT_REACT_VIDEO": "%2$@|%1$@: %3$@ на ваше видео",
    "CHAT_REQ_JOINED": "%2$@|%1$@ принят(а) в группу",
    "CHAT_RETURNED": "%2$@|%1$@ вернулся(-ась) в группу",
    "CHAT_TITLE_EDITED": "%2$@|%1$@ изменил(а) название группы",
    "CHAT_VOICECHAT_END": "%2$@|%1$@ завершил(а) видеочат",
    "CHAT_VOICECHAT_INVITE": "%2$@|%1$@ пригласил(а) %3$@ в видеочат",
    "CHAT_VOICECHAT_INVITE_YOU": "%2$@|%1$@ пригласил(а) вас в видеочат",
    "CHAT_VOICECHAT_START": "%2$@|%1$@ начал(а) видеочат",
    "CONTACT_JOINED": "%1$@|теперь в Telegram!",
    "ENCRYPTED_MESSAGE": "У вас новое сообщение%1$@",
    "ENCRYPTION_ACCEPT": "Ваш запрос на секретный чат принят%1$@",
    "ENCRYPTION_REQUEST": "Новый запрос на секретный чат%1$@",
    "LOCKED_MESSAGE": "У вас новое сообщение%1$@",
    "MESSAGE": "%1$@|отправил(а) вам сообщение",
    "MESSAGE_AUDIO": "%1$@|отправил(а) вам голосовое сообщение",
    "MESSAGE_CHANNEL_MESSAGE_GAME_SCORE": "%1$@ набрал(а) %3$@ в игре %2$@",
    "MESSAGE_CONTACT": "%1$@|поделился(-ась) с вами контактом",
    "MESSAGE_DOC": "%1$@|отправил(а) вам файл",
    "MESSAGE_FWD": "%1$@|переслал(а) вам сообщение",
    "MESSAGE_GAME": "%1$@|приглашает вас сыграть в %2$@",
    "MESSAGE_GAME_SCORE": "%1$@ набрал(а) %3$@ в игре %2$@",
    "MESSAGE_GEO": "%1$@|отправил(а) вам карту",
    "MESSAGE_GEOLIVE": "%1$@|транслирует вам геопозицию",
    "MESSAGE_GIF": "%1$@|отправил(а) вам GIF",
    "MESSAGE_INVOICE": "%1$@|отправил(а) вам счёт на %2$@",
    "MESSAGE_NOTEXT": "%1$@|отправил(а) вам сообщение",
    "MESSAGE_NOTHEME": "%1$@|отключил(а) тему чата",
    "MESSAGE_PAID_MEDIA": "%1$@ отправил(а) вам платный пост за %2$@ звёзд",
    "MESSAGE_PHOTO": "%1$@|отправил(а) вам фото",
    "MESSAGE_PHOTO_SECRET": "%1$@|отправил(а) вам исчезающее фото",
    "MESSAGE_POLL": "%1$@|отправил(а) вам опрос",
    "MESSAGE_QUIZ": "%1$@|отправил(а) вам викторину",
    "MESSAGE_RECURRING_PAY": "%1$@|С вас списано %2$@",
    "MESSAGE_ROUND": "%1$@|отправил(а) вам видеосообщение",
    "MESSAGE_SAME_WALLPAPER": "%1$@ установил(а) те же обои для чата с вами",
    "MESSAGE_SCREENSHOT": "%1$@|сделал(а) снимок экрана",
    "MESSAGE_STARGIFT": "%1$@|отправил(а) вам подарок стоимостью %2$@ звёзд",
    "MESSAGE_STARGIFT_UPGRADE": "%1$@ улучшил(а) ваш подарок",
    "MESSAGE_STICKER": "%1$@|отправил(а) вам %2$@стикер",
    "MESSAGE_STORY": "%1$@|поделился(-ась) с вами историей",
    "MESSAGE_STORY_MENTION": "%1$@|упомянул(а) вас в истории",
    "MESSAGE_SUGGEST_USERPIC": "%1$@|предлагает вам новое фото профиля",
    "MESSAGE_TEXT": "%1$@|%2$@",
    "MESSAGE_THEME": "%1$@|изменил(а) тему чата на %2$@",
    "MESSAGE_TODO": "%1$@|отправил(а) вам список задач %2$@",
    "MESSAGE_UNIQUE_STARGIFT": "%1$@ отправил(а) вам подарок",
    "MESSAGE_VIDEO": "%1$@|отправил(а) вам видео",
    "MESSAGE_VIDEOS": "%1$@ отправил(а) вам видео: %2$@",
    "MESSAGE_VIDEO_SECRET": "%1$@|отправил(а) вам исчезающее видео",
    "MESSAGE_WALLPAPER": "%1$@ установил(а) новые обои для чата с вами",
    "PHONE_CALL_MISSED": "%1$@|Пропущенный звонок",
    "PHONE_CALL_REQUEST": "%1$@|звонит вам!",
    "PINNED_AUDIO": "%1$@|закрепил(а) голосовое сообщение",
    "PINNED_CONTACT": "%1$@|закрепил(а) контакт %2$@",
    "PINNED_DOC": "%1$@|закрепил(а) файл",
    "PINNED_GAME": "%1$@|закрепил(а) игру",
    "PINNED_GAME_SCORE": "%1$@ закрепил(а) счёт в игре",
    "PINNED_GEO": "%1$@|закрепил(а) карту",
    "PINNED_GEOLIVE": "%1$@|закрепил(а) геопозицию в реальном времени",
    "PINNED_GIF": "%1$@|закрепил(а) GIF",
    "PINNED_INVOICE": "%1$@|закрепил(а) счёт",
    "PINNED_NOTEXT": "%1$@|закрепил(а) сообщение",
    "PINNED_PAID_MEDIA": "%1$@|закрепил(а) платный пост за %2$@",
    "PINNED_PHOTO": "%1$@|закрепил(а) фото",
    "PINNED_POLL": "%1$@|закрепил(а) опрос %2$@",
    "PINNED_QUIZ": "%1$@|закрепил(а) викторину %2$@",
    "PINNED_ROUND": "%1$@|закрепил(а) видеосообщение",
    "PINNED_STICKER": "%1$@|закрепил(а) %2$@стикер",
    "PINNED_TEXT": "%1$@|закрепил(а) «%2$@»",
    "PINNED_TODO": "%1$@|закрепил(а) список задач %2$@",
    "PINNED_VIDEO": "%1$@|закрепил(а) видео",
    "REACT_AUDIO": "%1$@|%2$@ на ваше голосовое сообщение",
    "REACT_CONTACT": "%1$@|%2$@ на ваш контакт %3$@",
    "REACT_DOC": "%1$@|%2$@ на ваш файл",
    "REACT_GAME": "%1$@|%2$@ на вашу игру",
    "REACT_GEO": "%1$@|%2$@ на вашу карту",
    "REACT_GEOLIVE": "%1$@|%2$@ на вашу геопозицию",
    "REACT_GIF": "%1$@|%2$@ на ваш GIF",
    "REACT_HIDDEN": "Новая реакция на ваше сообщение",
    "REACT_INVOICE": "%1$@|%2$@ на ваш счёт",
    "REACT_NOTEXT": "%1$@|%2$@ на ваше сообщение",
    "REACT_PHOTO": "%1$@|%2$@ на ваше фото",
    "REACT_POLL": "%1$@|%2$@ на ваш опрос %3$@",
    "REACT_QUIZ": "%1$@|%2$@ на вашу викторину %3$@",
    "REACT_ROUND": "%1$@|%2$@ на ваше видеосообщение",
    "REACT_STICKER": "%1$@|%2$@ на ваш %3$@стикер",
    "REACT_STORY": "%1$@|%2$@ на вашу историю",
    "REACT_STORY_HIDDEN": "Новая реакция на вашу историю",
    "REACT_TEXT": "%1$@|%2$@ на «%3$@»",
    "REACT_TODO": "%1$@|%2$@ на ваш список задач %3$@",
    "REACT_VIDEO": "%1$@|%2$@ на ваше видео",
    "STORY_HIDDEN_AUTHOR": "Опубликована новая история",
    "STORY_NOTEXT": "%1$@|опубликовал(а) историю",
    "VIDEO_CALL_MISSED": "%1$@|Пропущенный видеозвонок",
    "VIDEO_CALL_REQUEST": "%1$@|звонит вам по видео!",
    # Derived multi-item keys (see DERIVED_EN).
    "MESSAGES": "%1$@|отправил(а) вам сообщения: %2$@",
    "MESSAGE_FILES": "%1$@|отправил(а) вам файлы: %2$@",
    "MESSAGE_DOCS": "%1$@|отправил(а) вам файлы: %2$@",
    "MESSAGE_FWDS": "%1$@|переслал(а) вам сообщения: %2$@",
    "MESSAGE_PHOTOS": "%1$@|отправил(а) вам фото: %2$@",
    "CHANNEL_MESSAGES": "%1$@|опубликовал сообщения: %2$@",
    "CHANNEL_MESSAGE_DOCS": "%1$@|опубликовал файлы: %2$@",
    "CHANNEL_MESSAGE_PHOTOS": "%1$@|опубликовал фото: %2$@",
    "CHAT_MESSAGES": "%2$@|%1$@ отправил(а) сообщения: %3$@",
    "CHAT_MESSAGE_DOCS": "%2$@|%1$@ отправил(а) файлы: %3$@",
    "CHAT_MESSAGE_FWDS": "%2$@|%1$@ переслал(а) сообщения: %3$@",
    "CHAT_MESSAGE_PHOTOS": "%2$@|%1$@ отправил(а) фото: %3$@",
}

# Russian-only extras: the local fallback (ApplicationContext.superGramGenericNotificationBody) reads these
# PUSH_ keys from the main bundle; ru.lproj previously had an empty Localizable.strings.
RU_EXTRA = {
    "PUSH_ENCRYPTED_MESSAGE": "У вас новое сообщение%1$@",
    "PUSH_LOCKED_MESSAGE": "У вас новое сообщение%1$@",
}

PLACEHOLDER = re.compile(r"%(\d+)\$@")


def load_strings(path):
    data = subprocess.check_output(["plutil", "-convert", "json", "-o", "-", path])
    return json.loads(data)


def render(key, value):
    """'title|body' -> 'Title\\nBody' with identical argument indices."""
    value = value.strip()
    if key in STRIP_ARGS:
        value = PLACEHOLDER.sub("", value).strip()
    value = value.lstrip("|")
    value = value.replace("@:%", "@: %")          # "%1$@:%3$@" -> "%1$@: %3$@"
    value = re.sub(r"(%\d+\$@)(?=[^\W\d_])", r"\1 ", value) if key.endswith("PAID_MEDIA") else value
    if "|" in value:
        title, body = value.split("|", 1)
        title, body = title.strip(), body.strip()
        if body and body[0].islower():
            body = body[0].upper() + body[1:]
        value = title + "\n" + body if title else body
    return value


def escape(value):
    return value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")


def write(path, entries, header):
    lines = ["/* " + header + " */", ""]
    for key in sorted(entries):
        lines.append("\"%s\" = \"%s\";" % (escape(key), escape(entries[key])))
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    subprocess.check_call(["plutil", "-lint", "-s", path])


def main():
    source = load_strings(SOURCE)
    # A few legacy plaintext keys (MESSAGE_INVOICE, MESSAGE_NOTHEME, CHAT_MESSAGE_INVOICE, ...) already exist in
    # en.lproj/Localizable.strings; keep those English values (they also back PresentationStrings) and only add
    # the missing ones to en. ru.lproj has no source table, so it gets every key.
    already_in_en = set()
    en_source = {}
    for key, value in source.items():
        if not key.startswith("PUSH_") or key in EXCLUDED:
            continue
        if key.endswith("_TEXT_1") or key.endswith("_TEXT_any"):
            continue
        server_key = key[len("PUSH_"):]
        if server_key in source:
            already_in_en.add(server_key)
        en_source[server_key] = value
    for key, value in DERIVED_EN.items():
        en_source.setdefault(key, value)

    en = {k: render(k, v) for k, v in en_source.items()}
    missing = sorted(set(en) - set(RU))
    extra = sorted(set(RU) - set(en))
    if missing or extra:
        sys.exit("ru table mismatch, missing=%s extra=%s" % (missing, extra))
    ru = {k: render(k, v) for k, v in RU.items()}
    for key in en:
        if set(PLACEHOLDER.findall(en[key])) != set(PLACEHOLDER.findall(ru[key])):
            sys.exit("placeholder mismatch for %s: %r vs %r" % (key, en[key], ru[key]))
        if set(PLACEHOLDER.findall(en[key])) - set(PLACEHOLDER.findall(source.get("PUSH_" + key, DERIVED_EN.get(key, "")))):
            sys.exit("new placeholder introduced for %s" % key)
    ru.update(RU_EXTRA)
    # English fallback for every other bundled localization (their Localizable.strings were empty): all keys.
    fallback = dict(en)
    for key in already_in_en:
        del en[key]

    os.makedirs(OUT_DIR, exist_ok=True)
    header = "SuperGram: generated by scripts/supergram/generate_push_alert_strings.py - plaintext APNs loc-keys. Do not edit."
    write(os.path.join(OUT_DIR, "en.strings"), en, header)
    write(os.path.join(OUT_DIR, "ru.strings"), ru, header)
    write(os.path.join(OUT_DIR, "fallback.strings"), fallback, header)
    print("en: %d new loc-keys (+%d already present in en.lproj: %s); ru: %d loc-keys + %d PUSH_ fallback keys; %d derived multi-item keys" % (len(en), len(already_in_en), ", ".join(sorted(already_in_en)), len(ru) - len(RU_EXTRA), len(RU_EXTRA), len(DERIVED_EN)))


if __name__ == "__main__":
    main()
