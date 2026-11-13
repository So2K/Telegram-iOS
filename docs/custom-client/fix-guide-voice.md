# Fix guide: локальная расшифровка голосовых (Apple Speech без Premium)

Поток: кастомная фича «расшифровка голосовых/аудио на устройстве» и её настройки.
Якоря `файл:строка` сверены по рабочему дереву. `[V]` — проверено вручную, `[R]` — из read-only аудита, `[?]` — гипотеза.

Ключевые файлы:
- движок — `submodules/Media/LocalAudioTranscription/Sources/LocalAudioTranscription.swift` (7.9 КБ);
- UI голосового/аудио-баббла — `submodules/TelegramUI/Components/Chat/ChatMessageInteractiveFileNode/Sources/ChatMessageInteractiveFileNode.swift`;
- настройки — `submodules/TelegramUIPreferences/Sources/MediaDisplaySettings.swift`, `submodules/SettingsUI/Sources/Data and Storage/DataAndStorageSettingsController.swift`;
- хранение — `submodules/TelegramCore/Sources/TelegramEngine/Messages/TelegramEngineMessages.swift` (`storeLocallyTranscribedAudio`, `id: 0`).

Что уже сделано правильно (не трогать):
- ключ `NSSpeechRecognitionUsageDescription` присутствует во всех трёх описаниях: `Telegram/BUILD:1649-1650`, `Telegram/Telegram-iOS/Info.plist:298-299`, `Telegram/Telegram-iOS/InfoBazel.plist:132-133`;
- при `voiceTranscriptionOnDeviceOnly = true` онлайн-фолбэка нет: `LocalAudioTranscription.swift:163-164` и `:76` (`request.requiresOnDeviceRecognition`), ветка ретрая в онлайн (`:171`) — только в `false`-ветке;
- обход Premium для голосовых сделан корректно: `ChatMessageInteractiveFileNode.swift:365` (upsell только при `!useLocalTranscription`), `:799` (кнопка без Premium), `:500-514` (серверный API не вызывается);
- Opus не скармливается Speech напрямую: `:461-463` `convertOpusToAAC` → `transcribeAudio(path:)`;
- временные файлы убираются на всех исходах (`:475-477`, уникальная папка на вызов);
- транскрипт хранится локально: `TelegramEngineMessages.swift:724-736` (транзакция postbox, `id: 0`, без сети).

---

## V-1 (S1) Фаза загрузки/конвертации без предела → вечный `.inProgress`, кнопка мертва, ретрая нет  [R]

QA: VOICE-13, VOICE-14 (оба сейчас проваливаются).

`ChatMessageInteractiveFileNode.swift:437` — `let fetchDisposable = context.engine.resources.fetch(...).start()` без обработчика ошибки; `:439-449` — единственный выход по неудаче это `completed:` у сигнала данных MediaBox. Для неполного файла этот сигнал никогда не завершается: `MediaBoxFileContextV2Impl.swift:563-576` отдаёт `complete: false` и держит запрос, а `:491-505` (`processFetchError`) чистит range/status-запросы, но **не** `partialDataRequests`. Пока идёт ожидание, кнопка инертна (`:355-357` — `if case .inProgress = self.audioTranscriptionState { return }`, `:420` — `transcribeDisposable == nil`), сбрасывается состояние только на успехе/ошибке/`deinit` (`:280`).

**Важно:** переменная `emittedPath` и корректные ветки `completed` в коде **уже есть** (`:439` `var emittedPath = false`, `:444-449` `next`/`completed`). Не хватает только ограничения по времени — новых переменных заводить не нужно.

**Фикс (любой из двух).**
1. Watchdog внутри существующего `Signal`-блока, сразу после `var emittedPath = false` (`:439`):
```swift
let timeoutDisposable = Queue.mainQueue().after(20.0) {
    if !emittedPath {
        emittedPath = true
        subscriber.putNext(nil)
        subscriber.putCompletion()
    }
}
```
и `timeoutDisposable.dispose()` в уже существующий `ActionDisposable` (`:450-453`, рядом с `fetchDisposable.dispose()` и `dataDisposable.dispose()`).
2. Либо одной строкой на внешнем сигнале (`:479-480`, где уже стоит `self.transcribeDisposable = (signal |> deliverOnMainQueue)`): добавить до `deliverOnMainQueue`:
```swift
|> timeout(120.0, queue: Queue.mainQueue(), alternate: .single(nil))
```
(тип сигнала — `Signal<LocallyTranscribedAudio?, NoError>`, ветка `nil` уже обрабатывается на `:489-492`; оператор из SwiftSignalKit, пример использования — `SettingsUI/Sources/ChangePhoneNumberController.swift:33`).

**Регрессии.** Долгая, но живая загрузка теперь уйдёт в ветку неудачи — безопасно, если сделан V-2.
**Проверка.** VOICE-13/14: открыть чат, выключить Wi-Fi/включить авиарежим до догрузки файла → через ~20 с кнопка снова активна, есть сообщение об ошибке, повтор запускается.

## V-2 (S2) Ошибки сохраняются, но не показываются: VOICE-07 «понятный отказ» не проходит, все причины сливаются в «тишину»  [R]

`:488-492` кладёт `error: .generic` и выставляет `audioTranscriptionState = .collapsed`; при этом текст ошибки строится только в состоянии `.expanded` (`:837-869`, текст на `:859-868`), а `.collapsed` — это `effectiveAudioTranscriptionState` (`:832`). Итог: нет разрешения на Speech, неподдерживаемая локаль, `supportsOnDeviceRecognition == false` (`LocalAudioTranscription.swift:37-69` — все три пути молча `putNext(nil)`) выглядят как «спиннер, потом ничего».

**Фикс.** В `nil`-ветке оставить сохранение, но переключить состояние после записи:
```swift
let _ = arguments.context.engine.messages.storeLocallyTranscribedAudio(messageId: arguments.message.id, text: "", isFinal: true, error: .generic).startStandalone(completed: { [weak self] in
    guard let self else { return }
    self.audioTranscriptionState = .expanded
    self.requestUpdateLayout(true)
})
```
строки `:490-491` удалить. Дополнительно различать причины: отдельный кейс ошибки для «нет разрешения / локаль не поддерживается» и предложение «Открыть настройки» через `UndoOverlayController`.

**Проверка.** VOICE-07: запретить Speech в системных настройках или выбрать казахский при включённом «только на устройстве» → пользователь видит внятную ошибку, а не тишину.

## V-3 (S2) Жёсткий лимит 45 с молча обрезает текст и сохраняет обрезанное как финальный результат  [V]

`LocalAudioTranscription.swift:125-129`:
```swift
Queue.mainQueue().after(45.0, { complete(latestResult.map { ... isFinal: true }) })
```
то же на ошибочном пути `:117-121`. Далее `ChatMessageInteractiveFileNode.swift:486-487` сохраняет `isFinal` (значит `isPending == false`), а `:409-413` не перезапускает расшифровку для непендингового транскрипта, только разворачивает его. Симптом: сообщения длиннее ~60 с (а на устройстве распознавание медленнее) обрываются на полуслове без пометки, повторный тап лишь разворачивает тот же огрызок.

**Фикс.** Передавать длительность файла в `transcribeAudio` и считать дедлайн как `max(45.0, Double(duration) * 2.0)`; при срабатывании watchdog возвращать различимый частичный результат (добавить `isTruncated` в `LocallyTranscribedAudio` и сохранять `error: .tooLong` либо маркер-многоточие) вместо фабрикации `isFinal: true`.

**Проверка.** VOICE-03: сообщение 90–120 с с включённым «только на устройстве» → нет обрыва без пометки; повторный запуск доступен.

## V-4 (S2) Язык по умолчанию жёстко русский, «Автоматически» берёт язык интерфейса, в списке есть заведомо неподдерживаемые языки  [R]

`MediaDisplaySettings.swift:22`, `:33`, `:58` — `voiceTranscriptionLocale: "ru-RU"` по умолчанию для всех; `ChatMessageInteractiveFileNode.swift:425` — `appLocale = presentationData.strings.baseLanguageCode`, `LocalAudioTranscription.swift:161` — `preferredLocale == "auto" ? appLocale`; `SettingsUI/.../DataAndStorageSettingsController.swift:23-31` предлагает `kk-KZ`, `uk-UA`, которых нет в `SFSpeechRecognizer.supportedLocales()` на актуальных iOS, а `LocalAudioTranscription.swift:14-26` в таком случае возвращает nil → гарантированный тихий отказ (это же объясняет BLOCKED у VOICE-06).

**Фикс.** По умолчанию `"auto"`, и резолвить его из `Locale.preferredLanguages.first` (а не из языка интерфейса); в пикере (строка ~`:1060`) фильтровать список по `SFSpeechRecognizer.supportedLocales()` и помечать/дизейблить недоступные, с пояснением причины.

**Проверка.** VOICE-04/05/06: пользователь с русским интерфейсом и английскими голосовыми получает корректный результат; выбор неподдерживаемого языка невозможен.

## V-5 (S3) У локальных транскриптов есть серверный виджет «оценить расшифровку», и оценка уходит на сервер с `transcriptionId = 0`  [R]

`TelegramEngineMessages.swift:730` (`id: 0`) → `ChatInterfaceStateContextMenus.swift:1074-1086` показывает оценщик при `hasExpandedAudioTranscription && !didRate` → `rateAudioTranscription(messageId:id:isGood:)` → `Transcription.swift:100-143` (в частности `:138` — реальный RPC `messages.rateTranscribedAudio(transcriptionId: id)`), `:108-111` навсегда ставит `didRate`.

**Фикс.** В `ChatInterfaceStateContextMenus.swift:1074` добавить условие `audioTranscription.id != 0`.
**Проверка.** Расшифровать локально → виджета оценки нет, в `log stream` нет RPC `rateTranscribedAudio`.

## V-6 (S3) Round video (видео-заметки) по-прежнему используют платный серверный путь  [R]

`ChatMessageInteractiveInstantVideoNode.swift:840-856` (гейт только по `isPremium`/триалу), `:1827-1829` и `:1843-1867` (Upsell), `:1895` (серверный API). `mediaDisplaySettings.localVoiceTranscription` вне `ChatMessageInteractiveFileNode.swift:361,471-472,799,828` и `SettingsUI` не читается вообще.

**Фикс.** Либо повторить локальную ветку для instant video, либо честно указать охват фичи в описании (`DataAndStorageSettingsController.swift:784-787`).
**Проверка.** VOICE-10 + ручная проверка round video на аккаунте без Premium.

## V-7 (S3) Ретрай рассинхронизирует состояние: показывается старая ошибка, прогресс невидим, `isWaitingForCollapse` залипает  [R]

`:820-822` (`case .inProgress: if transcribedText != nil { updatedAudioTranscriptionState = .expanded }`) разворачивает баббл сразу при ретрае → нет спиннера, виден старый текст ошибки; `:1116-1118` пишет это обратно в узел; тап в этот момент попадает в `:520-524` и ставит `isWaitingForCollapse = true` (`:1124-1128` инвертирует направление).

**Фикс.** `:820` → `if case .success = transcribedText`; сбрасывать `isWaitingForCollapse = false` в `:421`.
**Проверка.** VOICE-11/12: провалить расшифровку, запустить повтор → виден спиннер, затем результат; повторный тап не «схлопывает» баббл наоборот.

## V-8 (S4) Осиротевший экспериментальный флаг участвует в работе, но не в гейте кнопки  [R]

`:361` — `mediaDisplaySettings.localVoiceTranscription || context.sharedContext.immediateExperimentalUISettings.localTranscription`, а `:799` — только `mediaDisplaySettings`. Флаг `localTranscription` объявлен в `TelegramUIPreferences/Sources/ExperimentalUISettings.swift`, нигде не пишется; в `DebugSettingsUI` элементов нет.

**Фикс.** Убрать `||` в `:361` либо использовать комбинированный флаг и в `:799`.

## V-9 (S2, условно) Версионный гейт может сбросить приватный выбор пользователя  [?]

`MediaDisplaySettings.swift:52-57` при отсутствии ключа версии (то есть <2) принудительно ставит `voiceTranscriptionOnDeviceOnly = false`, а `:70` всегда пишет 2. Если предыдущая сборка сохранила ключ без версии, апгрейд выключит «только на устройстве», и следующая расшифровка уйдёт в Apple.

**Фикс.** `self.voiceTranscriptionOnDeviceOnly = (try container.decodeIfPresent(Int32.self, forKey: "voiceTranscriptionOnDeviceOnly") ?? 0) != 0` и убрать гейт. Перед правкой проверить, что писала предыдущая сборка.
**Проверка.** Установить новую сборку поверх 10014 с включённым «только на устройстве» → флаг сохраняется.

## V-10 (S3) Смена настроек не доходит до уже открытого чата  [R]

Узлы читают `sharedContext.currentMediaDisplaySettings` только внутри `asyncLayout` (`:794`) и `transcribe()` (`:360`). Атомар обновляется в `SharedAccountContext.swift:493-502`, но подписчиков среди узлов чата нет; обновления `presentationData` идут по строкам/теме (`:433-473`).

**Фикс.** Пробросить атомар в состояние чата и обновлять раскладку при изменении (или подписать узлы на `currentMediaDisplaySettings`).
**Проверка.** VOICE-09/10: переключить опцию в настройках и вернуться в чат без прокрутки → кнопка/поведение меняются сразу.

## V-11 (S4) Вероятный retain cycle в движке расшифровки  [R]

`LocalAudioTranscription.swift:83-91` (`complete` захватывает `task`), `:93-123` (обработчик задачи захватывает `complete`), `:131-138` (снова захват `task`).

**Фикс.** В `complete` после `task?.finish()` обнулить `task = nil`.

## V-12 (S4) Обращение к XPC на main-очереди  [R]

`LocalAudioTranscription.swift:13` `supportedLocales()` вызывается в `:47` внутри `Queue.mainQueue().async` (на каждую попытку, включая ретраи).
**Фикс.** Кэшировать/резолвить вне main-очереди.

## V-13 (S4) Тексты настроек вводят в заблуждение  [R]

`DataAndStorageSettingsController.swift:784-787` показывает «…кешируется только на этом устройстве…» даже при выключенной фиче (guard `:780` покрывает только `:781-783`); `:779` тумблер «Show Transcription Button» остаётся видимым и бессмысленным для не-Premium при выключенной фиче.
**Фикс.** Перенести info-строку внутрь `if mediaSettings.localVoiceTranscription`; дизейблить тумблер кнопки, когда фича выключена.

## V-14 (S4, приватность) По умолчанию первая попытка уходит в Apple  [V]

`MediaDisplaySettings.swift:21/32/54` — `voiceTranscriptionOnDeviceOnly == false` по умолчанию, значит `LocalAudioTranscription.swift:166` идёт с `requiresOnDeviceRecognition: false`, и аудио уходит в облако Apple. Дополнительно: при переводе локального транскрипта его текст отправляется в Telegram (`TranslateUI/Sources/ChatTranslation.swift:175`, `TelegramCore/.../Translate.swift:206`, `ChatHistoryListNode.swift:2877`).
**Рекомендация.** Сделать «только на устройстве» дефолтом = `true` (для форка с обещанием «без Premium и без утечек» это осознанный продуктовый выбор; зафиксировать в релиз-заметках).

## V-15 (S4) Мёртвая ветка  [V]

`LocalAudioTranscription.swift:33`, `:145-148` — при `minimum_os_version = "13.0"` (`Telegram/BUILD:163`) ветка `else` недостижима.

---

### Сводка по сценариям QA

| Сценарий | Итог | Причина |
| --- | --- | --- |
| VOICE-01, VOICE-02 | PASS (согласуется с кодом) | — |
| VOICE-03 | FAIL | V-3 (+V-4) |
| VOICE-04 | FAIL для пользователей с дефолтным `ru-RU` | V-4 |
| VOICE-05 | проходит технически, но язык берётся не оттуда | V-4 |
| VOICE-06 | FAIL по построению (неподдерживаемая локаль → тихий nil) | V-2, V-4 |
| VOICE-07 | приватная половина PASS, «понятный отказ» FAIL | V-2 |
| VOICE-08 | PASS | — |
| VOICE-09/10 | риск FAIL; 10 дополнительно утекает на round video | V-10, V-6 |
| VOICE-11 | защищено (`:355`, `:420`), но переходы ретрая путают состояние | V-7 |
| VOICE-12 | dispose только на `deinit`; отложенный таймер 45 с держит задачу | V-11 |
| VOICE-13 | FAIL | V-1 |
| VOICE-14 | FAIL | V-1 |
