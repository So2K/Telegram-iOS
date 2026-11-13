# SuperGram Ultra — мастер-план работ

Дата: 2026-09-15. Ветка `codex/stable-custom-client`, база upstream `6e370e06`, Swiftgram `swiftgram/master` (та же база).
Точка восстановления до начала работ: `git update-ref refs/backup/pre-ultra-2026-09-15` → `6da08c64` (снимок всех незакоммиченных изменений, `git stash apply 6da08c64` вернёт их).
Исследования (21 агент, 286 находок): `output/ultra/research/*.md`, сводка `output/ultra/research/_all.json`, критика `output/ultra/research/critic.md`.

## Цели пользователя → статус до работ

| # | Цель | Что уже было | Что осталось (главное) |
|---|---|---|---|
| 1 | Убрать всю рекламу | Спонсорские посты в каналах/ботах/галерее и спонсоры в поиске выключены на уровне данных | Закреплённый «спонсор прокси»/PSA-канал, премиум/подарочные баннеры в списке чатов, иконка подарка в поле ввода и вкладка Gift, промо-строки в Настройках, тосты «купи Premium ради скорости» (4 точки), апселлы Premium (≈39 лимит-шторок, 23 тоста), телеметрия ads (view/click/report, reportReadMetrics) |
| 2 | Разблокировать клиентские премиум-замки | — | Сохранение чужих историй (в т.ч. защищённых), HD-истории, запрет скриншотов историй/защищённых чатов, Copy/Save в защищённых чатах, «Сохранить оригинал» в галерее, премиум-иконки, лимит аккаунтов 3→10, перевод чата |
| 3a | Расшифровка голоса без Premium (Swiftgram) | Голосовые: локально через Apple Speech | Кружки всё ещё Premium; баги: зависание при ошибке загрузки, обрезка >45 c с пометкой «финал», задача распознавания не отменяется, пункт «оценить расшифровку» для локальных, локаль захардкожена ru-RU |
| 3b | Видео из галереи → кружок (Swiftgram «Telescope») | — | Перенос 1-в-1: флаг `sendAsTelescope` в adjustments, пресет VideoMessageHD, кнопка в редакторе медиа, квадратный кроп + 60 c + атрибут `instantRoundVideo`, запрет группировки в альбом |
| 3c | Прочие фичи Swiftgram | — | Инфраструктура настроек SG (SGSimpleSettings/SGSettingsUI) + ~40 клиентских фич (см. волну 2) |
| 4 | Оптимизации и баги | Часть стабилизации (HEAD 9fe18208) | Busy-loop плеера V2 (подтверждённое убийство `cpu_resource_fatal`), двойной free в аудио-декодере, файловое логирование включено по умолчанию, прогресс загрузки на main по каждой части, вечный 60fps аниматор прогресса, 25 Гц таймер HLS, регрессии прошлой работы (анимации ×0.5, sticker tap, жесты, тап-навигация галереи) |
| 5 | Тяжёлые загрузки → лаги/вылеты | Размеры частей FetchV2 | Нет глобального лимита параллельных загрузок, FetchManager не деактивирует старые верхние записи, превью видео — отдельный поток+FFmpeg без очереди, фоновый PrefetchManager (30 чатов) и 10 историй сразу без учёта нагрузки, нет реакции на memory pressure/thermal, сортировка очереди запросов с аллокациями на каждом событии, запись .meta + SQLite на каждую часть |
| 6 | Стриминг «наполовину скачано — не смотрится» | — | `.earlierStart` в галерее (пауза ~раз в секунду), HLS игнорирует уже скачанный оригинал, тап по скачиваемому не-streamable видео отменяет загрузку, ошибка части FetchV2 = вечное молчаливое зависание (включая FILE_REFERENCE_EXPIRED), диапазон `0..<Int64.max` теряет приоритет и отменяется, EOF-заморозка трека V2, CDN hash-range без повтора, дублирующиеся запросы частей (`subtract` вместо `formUnion`) |

## Решения, принятые автономно (по рекомендациям критика)

1. **Хранилище настроек**: вендорим `SGSimpleSettings` (упрочнённый) — единое хранилище для всех новых переключателей. Существующие поля `MediaDisplaySettings` остаются и показываются на том же экране. Одна строка «SuperGram» в главных Настройках → экран на базе `SGSettingsUI` (без Pro/API/IAP/анонсов/NY/regdate).
2. **Без rebase** на новый upstream (ничто upstream не чинит цели 5–6); порт на `6e370e06`.
3. **Тулчейн**: Xcode 16.2 / Swift 6.0.3 / iOS SDK 18.2, `-warnings-as-errors`. Никакого синтаксиса Swift ≥6.1 и символов iOS 26 без `#if compiler(>=6.2)`.
4. **Защищённый контент**: разрешить сохранение/копирование/шаринг в iOS/скриншоты в noforwards-чатах, каналах и историях (по умолчанию ВКЛ, переключатель). **Не** трогаем секретные чаты и одноразовые (view-once) медиа, **не** подавляем уведомления о скриншотах в секретных чатах — это приватность собеседника. Пересылка защищённого остаётся серверным ограничением.
5. **Реклама**: скрыть PSA/спонсора прокси, премиум/xmas/birthday-баннеры, подарочные CTA, 4 точки «ускорь за Premium», апселлы лимитов/тостов (информативный текст без кнопки покупки), выключить ad-телеметрию и `reportReadMetrics`. Оставляем: уведомление о низком балансе Stars для уже оплаченных подписок, похожие каналы (без панели «разблокируй больше»).
6. **Расшифровка**: у Premium — серверная, иначе локальная Apple Speech; «auto» = язык чата (predicted) → язык приложения → системный; длинные записи — чанками без пометки «финал» при таймауте.
7. **Призрачный режим**: два отдельных переключателя (по умолчанию ВЫКЛ): «Не отправлять прочтения» (`skipReadHistory` + отметки прослушивания голосовых) и «Призрачный просмотр историй» (локальная отметка просмотренного, без `stories.readStories`).
8. **performanceMode** разделяется: «Без автовоспроизведения инлайн-видео» по умолчанию ВКЛ до появления бюджета плееров; `extendBackgroundWork`, зацикливание стикеров (ломало тап по стикеру) и автоплей кружков — обычное поведение.
9. **Фоновый keep-alive (тихое аудио)** — оставляем (это единственный путь уведомлений без NSE), но: переключатель, уважение настроек превью/пароля в локальных уведомлениях, никакого прикрепления инлайн-видео в фоне.
10. **Лимит аккаунтов**: 10 (не 500 — RAM).
11. **Кэш-пресеты Swiftgram 1 ГБ / 1 час** — только как опции (не по умолчанию; конфликтуют со стримингом), с фиксом выхода за границы массива.
12. **Swiftgram download/upload speed boost** не переносим как есть (конфликтует с целью 5); вместо него — наш глобальный лимитер и политика частей.
13. **PiP** остаётся выключенным (не цель).

## Реестр ключей SuperGram (UserDefaults.standard, читаются и без модуля SGSimpleSettings)

Читать из любого модуля (включая TelegramCore/ObjC) так: `UserDefaults.standard.object(forKey: "<key>") as? Bool ?? <default>` (кэшировать на горячих путях, обновлять по `UserDefaults.didChangeNotification`). W1-INFRA объявляет эти ключи в `SGSimpleSettings.Keys` с теми же строками и дефолтами и выводит строки на экран SuperGram.

| Ключ | Дефолт | Владелец логики | Смысл |
|---|---|---|---|
| `sgStreamAllVideos` | true | W1-PLAYER | Любое видео (кроме секретных) воспроизводится потоком |
| `sgPreferDownloadedOriginal` | true | W1-PLAYER | Скачанный/частично скачанный оригинал вместо HLS |
| `sgDownloadLimiter` | true | W1-FETCH | Глобальный бюджет параллельных частей |
| `sgPauseDownloadsUnderPressure` | true | W1-FETCH | Фоновые загрузки/предзагрузки ставятся на паузу при memory pressure / thermal serious / Low Power |
| `sgInlineAutoplayVideos` | false | W1-CHATMEDIA | Автовоспроизведение видео/GIF в ленте (замена связки с performanceMode) |
| `sgBackgroundKeepAlive` | true | W1-APP | Тихий аудио keep-alive для уведомлений в фоне |
| `sgFileLogging` | false | W1-APP | Файловые логи приложения |
| `sgNetworkLogging` | false | W1-APP | Логи MTProto/FetchV2 |
| `sgDisableReadMetrics` | true | W1-ADS | Не отправлять `messages.reportReadMetrics` |
| `sgAllowSaveProtectedContent` | true | W1-STORIES, W1-GALLERY, W2-CONTEXT, W2-PROTECT | Сохранение/копирование защищённого (не секретные чаты, не view-once) |
| `sgAllowScreenCaptureProtected` | true | W1-STORIES, W2-PROTECT | Скриншоты/запись экрана защищённого |
| `sgStoryHDWithoutPremium` | true | W1-STORIES | HD-истории без Premium |
| `sgTelescopeButton` | true | W1-TELESCOPE | Кнопка «отправить кружком» в редакторе видео |
| `sgSkipReadReceipts` | false | W2-GHOST | Не отправлять прочтения (+ прослушивание голосовых) |
| `sgStoryGhostMode` | false | W2-GHOST | Просмотр историй без отметки |

Ключи Swiftgram переносятся с оригинальными именами (`SGSimpleSettings.Keys`). Новые ключи потоки добавляют с префиксом `sg` и перечисляют в отчёте.

## Правила исполнения

- Агенты работают в одном дереве (диск: 27 ГБ свободно, worktree невозможны); **внутри волны множества файлов агентов не пересекаются**. Файл из чужой зоны не редактировать — записать в отчёт «нужно в зоне X».
- Никаких коммитов/`git stash`/`reset`/`checkout`. Перед каждой волной — снапшот `git stash create` → `refs/backup/ultra-wave-N`.
- Сборка только через `scripts/supergram/build_check.sh` и только координатором (одна сборка за раз). Агенты волн не собирают.
- Код в стиле окружения; hunk'и Swiftgram копируются дословно, помечаются `// MARK: Swiftgram` (или `// SuperGram:` для наших), серверные гейты SG (`sgWebSettings`, Pro) заменяются константами.
- Каждый агент пишет отчёт в `output/ultra/impl/<stream>.md`: что сделано (файл:строка), что не сделано и почему, риски компиляции.

## Волна 0 — подготовка (координатор)
- [x] Бэкап-реф, каталог исследований, `scripts/supergram/build_check.sh` (Bazel CLI на тёплом output base).
- [ ] Эталонная сборка текущего дерева (`build-output/ultra/baseline-before-ultra.log`).

## Волна 1 — фундамент и исправления без переключателей (параллельно)

| Поток | Владение файлами | Находки |
|---|---|---|
| **W1-INFRA** Инфраструктура SG | `Swiftgram/{SGAppGroupIdentifier,SGLogging,SGSimpleSettings,SGStrings,SGItemListUI,SGSettingsUI}/**` (новые), `submodules/ItemListUI/**`, `Telegram/BUILD` (только строки SG), `PeerInfoScreen/BUILD`, `PeerInfoSettingsItems.swift`, `PeerInfoScreenSettingsActions.swift`, `PeerInfoScreen.swift` (только enum секций настроек), `PresentationResourcesSettings.swift`, `SettingsUI/Sources/Data and Storage/DataAndStorageSettingsController.swift` | INFRA-1..13, CRIT-05, SGUI-01, chat-00, SGM-F1; экран SuperGram с файлом-секцией на каждый поток волны 2; ВСЕ ключи (SG + SuperGram) заранее |
| **W1-PLAYER** Плеер и стриминг | `submodules/MediaPlayer/**`, `submodules/FFMpegBinding/**`, `submodules/TelegramUniversalVideoContent/**`, `GalleryUI/Sources/GalleryController.swift`, `AccountContext/Sources/IsMediaStreamable.swift`, HLS-бандл | CRIT-01 (.earlierStart→.conservative), CRIT-02 (Int64.max-1), STREAM-12 (double free), MEM-01 (busy loop), STREAM-9/10/11/14, MC-13, MEM-02 (status storm), MEM-06/08 (HLS debug/таймер), CRIT-09 (HLS dedup/ошибки/зависание), STREAM-1 (оригинал вместо HLS), STREAM-2 (streamAllVideos), DL-02 (preloadVideoResource ограничить диапазон/очередь) |
| **W1-FETCH** Загрузочный пайплайн | `TelegramCore/Sources/Network/{FetchV2,Fetch,MultipartFetch,MultiplexedRequestManager,Network}.swift`, `Postbox/Sources/{MediaBox*.swift,MediaResource*.swift}`, `submodules/FetchManagerImpl/**`, `AccountContext/Sources/FetchMediaUtils.swift`, `TelegramUI/Sources/PrefetchManager.swift`, новый `TelegramCore/Sources/Network/MediaDownloadPressure.swift` | DL-01 (глобальный бюджет с `isInteractive`, CRIT-08), DL-03, DL-04/STREAM-6 (onError+retry+refresh reference), DL-05/STREAM-5 (приоритетные полосы, сортировка без аллокаций), DL-06 (formUnion), DL-07 (CDN retry), DL-08 (memory pressure/thermal/Low Power), DL-09 (prefetch под нагрузкой), DL-10/MEM-10 (коалесцирование .meta/StorageBox), DL-11, DL-12/PERF-STATUS-1 (троттлинг статусов), DL-13/CRIT-07 (части 256K default / ≤128K elevated, maxPendingParts 6), DL-14/PERF-LOG-3, ADS-DATA-F5 (событие speed-limit), CRIT-13 (не удалять активные partial) |
| **W1-CHATMEDIA** Медиа-ячейки чата и перф анимаций | `ChatMessageInteractiveMediaNode/**`, `SemanticStatusNode/**`, `RadialStatusNode/**`, `TelegramUI/Sources/OverlayInstantVideoNode.swift`, `TelegramUI/Sources/OverlayMediaControllerNode.swift`, `TelegramUI/Sources/SharedMediaPlayer.swift`, `TelegramUIPreferences/Sources/MediaDisplaySettings.swift`, `TelegramUI/Sources/SharedAccountContext.swift`, `ChatMessageAnimatedStickerItemNode/**` | MEM-03 (applicationIsActive в layout), CRIT-16/MC-06 (не отменять видимые автозагрузки при переключении приложений), MEM-07 (бюджет инлайн-плееров), STREAM-2 (тап не отменяет, открывает поток), PERF-ANIM-1/2/3, MC-01/KB-04 (кружок: стоп плейлиста при detach), CRIT-17/C15 (разделить performanceMode), MC-05 (тап по стикеру) |
| **W1-TRANSCRIBE** Расшифровка | `Media/LocalAudioTranscription/**`, `Media/ConvertOpusToAAC/**`, `ChatMessageInteractiveFileNode/**`, `ChatMessageInteractiveInstantVideoNode/**`, новый модуль `submodules/TelegramUI/Components/Chat/SuperGramLocalTranscription/**` | T1 (кружки локально, общий помощник), T2, T3, T4, T5, T7, T8, T9, T10, T12, T13, UPS-14, MC-02, MC-09 |
| **W1-ADS** Реклама и апселлы (константы) | `TelegramCore/Sources/TelegramEngine/Messages/{AdMessages,ReportAds}.swift`, `TelegramCore/Sources/TelegramEngine/Peers/AdPeers.swift`, `TelegramCore/Sources/State/ManagedProxyInfoUpdates.swift`, `TelegramCore/Sources/TelegramEngine/Messages/ChatList.swift`, `TelegramCore/Sources/Suggestions.swift`, `GlobalControlPanelsContext/**`, `AccountContext/Sources/Premium.swift`, `PremiumUI/Sources/PremiumLimitScreen.swift`, `UndoUI/**`, `TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift`, `ChatListUI/Sources/{ChatListSearchContainerNode,ChatListSearchListPaneNode,ChatListControllerNode,ChatListController}.swift`, `TelegramUI/Sources/ChatHistoryListNode.swift` (только read metrics), `ChatTextInputPanelNode/**` (только иконка подарка), `AttachmentUI/**` (вкладка Gift), `PeerInfoScreen/Sources/PeerInfoProfileItems.swift` + `PeerInfoHeaderNode.swift` (подарочные CTA), `ChatEntityKeyboardInputNode/**` + реакции (UPS-07/08), `TranslateHeaderPanelComponent/**` | ADS-DATA-F1..F6, UPS-01..13, CRIT-10, CRIT-11 (a–d), CRIT-12, SGP-03 |
| **W1-STORIES** Истории | `TelegramUI/Components/Stories/**` (кроме `StoryChatContent.swift` — ghost в волне 2), `PeerInfoStoryGridScreen/**` | stories-save-others-gate (+C12), stories-save-in-protected-share-sheet, stories-capture-protection/PROT-3 (+C13), stories-hd-quality-gate/F5, stories-save-profile-grid, stories-promo-upsells, stories-caption-entities |
| **W1-TELESCOPE** Видео → кружок | `submodules/LegacyComponents/**`, `submodules/LegacyMediaPickerUI/**`, `submodules/MediaPickerUI/**`, `TelegramCore` пресеты качества медиа (если там), вызовы в `AttachmentUI`?→ через отчёт, `VideoMessageCameraScreen/**`, `Camera/**` | RV-1..9, SGP-15, SGM-F8/C6 (задняя камера) |
| **W1-GALLERY** Галерея | `GalleryUI/**` (кроме `GalleryController.swift`), `GalleryData/**` | ADS-DATA-F3 (контекст рекламы), F3 (Сохранить оригинал), MC-07, MC-08, MC-11/KB-16, MC-12/KB-15, STREAM-8 (кнопка статуса не отменяет чужие загрузки), PROT-7/8 (Save/Share для защищённого, Copy image SG), SGM-F14? (нет), KB-12 (HLS Save to Photos) |
| **W1-APP** Приложение, логи, фон | `TelegramUI/Sources/{AppDelegate,ApplicationContext,SharedWakeupManager}.swift`, `TelegramCore/Sources/Utils/Log.swift`, `MtProtoKit/**` (логирование), `DebugSettingsUI/**`, `WidgetItems/**`, `Telegram/NotificationService/**`, `Telegram/Share/**`, `Display/**`, `ComponentFlow/**` | PERF-LOG-1/2/4 (файловые логи выкл. по умолчанию, тумблер «сетевые логи»), F7, KB-05 (утечка текста в локальных уведомлениях), MC-04/KB-03/PERF-BG-1 (keep-alive: переключатель читает UserDefaults-ключ SG), MC-03/S1/BP-06/KB-18 (app group), F1 (анимации ×0.5 и двойное масштабирование), F4 (seek bubbles), F6 (fast scroller), F8/KB-17 (жесты), SGP-01 (raw-locale crash), KB-07 (CFSocketInvalidate) |
| **W1-MISC** Мелкие разблокировки | `AccountUtils/**`, `SettingsUI/Sources/{DeleteAccountOptionsController,LogoutOptionsController}.swift`, `SettingsUI/Sources/Search/SettingsSearchableItems.swift`, `SettingsUI/Sources/Themes/**` (иконки), `ChatListUI/Sources/ChatContextMenus.swift`, `ShareController/**` | F4/SGM-F2/SGP-07 (10 аккаунтов, напоминание), SGP-08, F2 (премиум-иконки), SGP-13/SGUI-07 (Архив в меню), CRIT-14 (VoiceOver в Share), SGP-05, SGP-11 |

Координатор после волны 1: сборка → агенты-фиксеры по модулям (зоны те же) → повтор до зелёной сборки → снапшот.

## Волна 2 — фичи Swiftgram на переключателях SuperGram (параллельно, после зелёной волны 1)

Каждый поток владеет своим файлом секции `Swiftgram/SGSettingsUI/Sources/SuperGramSections/<Stream>Section.swift` плюс перечисленными файлами.

| Поток | Файлы | Фичи |
|---|---|---|
| **W2-CONTEXT** Контекстные меню и выделение | `TelegramUI/Sources/ChatInterfaceStateContextMenus.swift`, `ChatMessageSelectionInputPanelNode/**`, `TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift` (панель выделения) | PROT-5, PROT-6 (выделение текста — в FileNode через отчёт), PROT-9, T6, CRIT-11b, chat-06 (подменю Swiftgram: Save to Cloud, Forward без имени, Select from Author, Restrict), chat-07, SGM-F13 (JSON сообщения) |
| **W2-PROTECT** Скриншоты и защита | `UIKitRuntimeUtils/**`, `MediaPlayer/Sources/MediaPlayerNode.swift`, `GalleryUI/Sources/Items/{ChatImageGalleryItem,ChatDocumentGalleryItem}.swift`, документ-превью, авто-сохранение | PROT-0 (ключи SG), PROT-1, PROT-2, PROT-10 |
| **W2-GHOST** Приватность и профиль | `StoryChatContent.swift`, `PeerMessagesMediaPlaylist.swift`, `ChatHistoryListNode.swift` (read receipts), `PeerInfoScreen/Sources/{PeerInfoProfileItems,PeerInfoHeaderNode}.swift`, звонки | C9/CRIT-15 (read receipts + story ghost + прослушивание), SGUI-05 (ID, DC, дата создания/вступления), SGUI-14 (скрыть номер), SGM-F11 (подтверждение звонков), SGM-F16 (пароль 5 c), SGUI-13 (предупреждение перед историями) |
| **W2-CHATLIST** Список чатов и навигация | `ChatListUI/**` (кроме ChatContextMenus), `TabBarUI/**`, `TelegramUI/Sources/TelegramRootController.swift`, `CallListUI/**` | SGUI-02 (скрыть истории, свайп записи), SGUI-04 (вкладка контактов), SGUI-08 (запоминать папку), SGUI-09/10/11/15/16 (таб-бар, папки, компактный список) |
| **W2-CHATUI** Чат и ввод | `TelegramUI/Sources/{ChatController,ChatControllerContentData}.swift`, `ChatMessageBubbleItemNode/**`, `ChatMessageDateAndStatusNode/**`, `TextFormat/Sources/DateFormat.swift`, `ChatTextInputPanelNode/**`, `ChatEntityKeyboardInputNode/**`, `ChatMessageItemImpl/**`, стикеры, `SGInputToolbar` | chat-01..05, chat-08..12, SGUI-12, SGUI-18, SGM-F12, SGM-F17 |
| **W2-NET** Медиа/сеть/перевод | `MtProtoKit/Sources/MTDNS.m`/`MTTcpConnection.m`, `LegacyMediaPickerUI` (качество JPEG), in-app Safari `OpenUrl`, `TranslateUI/**`, `StorageUsageScreen/**`, камера в пикере | SGM-F4, SGM-F5, SGM-F7/SGP-02, SGM-F9, SGM-F15/SGP-04 (+фикс), F1/chat-13/SGP-06 (перевод чата без Premium, без Google-фоллбэка) |

## Волна 3 — интеграция, ревью, выпуск
1. Полная сборка + цикл фиксов до зелёной.
2. Многоагентное состязательное ревью всего диффа (корректность, краши, перф, регрессии стриминга, приватность/безопасность) → фиксы → сборка.
3. Аудит HEAD 9fe18208 на регрессии «guard → вечное зависание» в MediaPlayer/Network/Postbox (CRIT-03).
4. Сборка IPA 10017 (PlistBuddy + zsign), проверка подписи, установка через `devicectl` (телефон должен быть разблокирован).
5. Обновление `SUPERGRAM_MANUAL_QA_PLAN.md` новыми сценариями (стриминг, лимитер, истории, кружки, реклама).

## Проверка (end-to-end)
- Компиляция: `scripts/supergram/build_check.sh //Telegram:Telegram` → `Build completed successfully`.
- Стриминг: открыть наполовину скачанное видео в канале → воспроизведение без пауз раз в секунду; видео >100 МБ без supportsStreaming → играет потоком; убить сеть на середине → после восстановления докачка продолжается (retry).
- Нагрузка: пролистать медиатяжёлый канал на 200 постов + запустить 20 загрузок файлов → нет лагов > 1 c, нет вылета; `.ips`/JetsamEvent отсутствуют.
- Реклама: нет закреплённого спонсора, нет премиум-баннеров, нет иконки подарка, нет тоста скорости.
- Истории: «Сохранить в галерею» у чужих и защищённых историй, HD без Premium, скриншот не чёрный.
- Расшифровка: голосовое >2 мин и кружок расшифровываются без Premium.
- Кружок: в редакторе медиа кнопка кружка → отправляется круглое видео ≤60 c.
- Экран «SuperGram» в Настройках, все переключатели работают и переживают перезапуск.

## Журнал выполнения

### 2026-09-15 — исследование и волна 1
- 21 исследовательский агент → `output/ultra/research/` (286 находок, критик).
- Эталонная сборка: весь код компилируется; упаковка `.app` падала на истёкшем профиле → `rules_apple` plisttool: истёкший профиль = предупреждение (IPA всё равно переподписывается zsign).
- Волна 1: завершены INFRA, PLAYER, CHATMEDIA, ADS-DATA, ADS-UI, STORIES, TELESCOPE; FETCH-CORE, FETCH-QUEUE, TRANSCRIBE, GALLERY, APP прерваны недельным лимитом, но основная часть их работы успела попасть в дерево (лимитер + MediaDownloadPressure + isInteractive, повторы FetchV2, коалесцирование .meta, модуль SuperGramLocalTranscription, логи по ключам). Параллельная сессия «Reasonix» закрыла overlay/жесты/уведомления/app group/crash-guards (`output/ultra/impl/FIXES-session2-20260915-reasonix.md`) и собрала 10017/10018.

### 2026-09-16 — скорость, фон, краши
- **Режим скорости загрузки** `sgDownloadSpeedMode` (0 стандарт / 1 быстро (дефолт) / 2 максимум): части для пользовательских загрузок 256K/512K/1MB, частей на большой файл 6/8/12, запросов на соединение 3/4/5 и соединений на DC 4/4/6, глобальный бюджет 32/40/64; при нагреве/нехватке памяти — прежние ограничения. Отправка медиа: параллельных частей 3/6/10.
- **Фоновая загрузка** `sgBackgroundDownloads` (дефолт вкл): `MediaDownloadActivity` (TelegramCore) — есть ли активные пользовательские загрузки (с 15 с задержкой выключения); `SharedWakeupManager` считает их фоновой задачей, держит соединения загрузки и тихое аудио, пока загрузки идут (даже если keep-alive уведомлений выключен).
- **Краш 0xDEAD10CC** (RunningBoard, найден в `output/diagnostics/device-crashlogs-20260916/`): при прерывании фонового аудио приложение засыпало, держа блокировку SQLite в app group. Теперь прерывание берёт фоновое окно 5 c, запрещает новые транзакции и отпускает keep-alive; после окончания прерывания keep-alive возвращается.
- **diskwrites_resource** (1 ГБ за 4.5 ч на 10014) — закрыт выключенными файловыми логами и пакетной записью .meta.
- **Лимит аккаунтов** 10.
- Сборка 10019 (скорость + фон) — зелёная, IPA установлена на iPhone 15 Pro.
- Волна 2 (сокращённая, без ревьюеров из-за лимита): CONTEXT, PROTECT, GHOST, CHATLIST, CHATUI-HISTORY, TRANSLATE.
- Волна 2 (6 потоков) + интеграция межзонных правок (4 агента): контекстное меню Swiftgram (Сохранить в Избранное, переслать без имени, выбрать от автора, ограничить автора, JSON сообщения), копирование/сохранение/шаринг в защищённых чатах и скриншоты защищённого (кроме секретных чатов и view-once), «не отправлять прочтения» и призрачные истории, ID/DC/даты в профиле, скрыть номер, подтверждение звонков, автоблокировка 5 c, предупреждение перед историями; список чатов (скрыть истории, вкладка контактов, запоминать папку, названия вкладок, компактные папки, скрыть таб-бар с кнопкой настроек, папки снизу, компактный список); чат (без свайпа к следующему каналу, без анимации пыли, секунды, скрыть реакции, двойной тап — редактировать, широкие посты каналов, фильтр слов); перевод чатов без Premium + быстрый перевод + перевод исходящих + on-device.
- Сборка 10020 зелёная с первого прохода, IPA `output/SuperGram-12.8-10020-Ultra.ipa` установлена на iPhone 15 Pro. 10019 остаётся запасной.
- Прицельное ревью крашей/зависаний (2 агента) → `output/ultra/impl/CRASH-REVIEW.md`.
- Ревью крашей (`output/ultra/impl/CRASH-REVIEW.md`), исправлено:
  - краш при удалении выбранной первой папки со скрытым «Все чаты» (ChatListController, PeerSelectionController);
  - отменённые CDN-загрузки продолжали качаться (захват self в FetchV2);
  - зависание зашифрованных файлов > 2 МБ при смешанных размерах частей (без укрупнения частей для encrypted);
  - флаг активной загрузки будил все вторичные аккаунты (только primary);
  - гонка остановки тихого аудио (путь к 0xDEAD10CC);
  - AppLock таймер 2.5 c только для автоблокировки ≤ 10 c.
- Сборка 10021 зелёная, IPA `output/SuperGram-12.8-10021-Ultra.ipa` готова. Установка сорвалась (потеряно соединение с iPhone); установить: `xcrun devicectl device install app --device 00008130-0004298110698D3A output/SuperGram-12.8-10021-Ultra.ipa`.

### Отложено до сброса недельного лимита (18.09)
- W2-CHATUI-INPUT (панель форматирования SGInputToolbar, размер стикеров, скрыть кнопку записи, отправка по Return), W2-NET (in-app Safari, качество фото, системный DNS для прокси, отключение камеры в пикере, пресеты кэша), W2-PERFBUGS (downsampling фото, GIF-панель, повторные запросы аватаров), W2-HEADAUDIT (регрессии «guard → вечное ожидание» в коммите 9fe18208), CRIT-10…15 хвосты, ревью волны 1 (не было из-за лимита).
- Открытые вопросы ревью: при выключенном keep-alive и оффлайне фоновая загрузка может держать приложение активным; `tg://contacts` при скрытом таб-баре.

### 2026-09-18 — багфикс по отчёту с устройства (10022 → 10023)
- Жалобы пользователя на 10020/10022: часть медиа грузится бесконечно, посты с разметкой без медиа и со сломанной вёрсткой, кнопка репоста у сообщений.
- Раунд 1 (11 агентов): 10 причин «вечной загрузки» (отравленный контекст MediaBox после ошибки, потерянные байты записи, невозврат слота бюджета ждущим, дедлок шифрованных файлов, CDN-лайвлок, залипание уровня нагрузки, отсутствие сторожей), 8 причин зависаний стриминга, медиа в rich-сообщениях (фоновая очередь + документ-картинки без кнопки + нулевые размеры), расшифровка кружков и длинных голосовых, логи/keep-alive/уведомления, ревизия всего экрана настроек. Плюс 4 аудита без правок (64 находки).
- Раунд 2 (6 агентов): анимации ×0.5 → 1.0, автоплей в ленте обратно по умолчанию, Low Power/нагрев больше не «аварийный» режим, isInteractive на ~24 экранных путях загрузки, лимитеры предзагрузки с отменой безнадёжных задач, память в режиме «максимум» ограничена 32 МБ, фиксы таб-бара/папок/профиля/подтверждения звонков.
- Раунд 3 (4 агента) — по скриншоту пользователя (альбом из 2 фото с крестиком навсегда): **`cancelFullRangeFetches()` не завершал запросы других владельцев ресурса** (главная причина: отмена одним узлом навсегда вешала слот `.image` и крестик), сторож FetchV2 игнорировал «висящие» запросы MTProto, у записей FetchManager не было тайм-аута и отказа, пустой первый ответ навсегда кэшировал нулевой файл, `fetchedResource` не завершался без файлового контекста. Добавлены: самолечение по нарастающей (подтолкнуть → отменить и перезапустить → полный сброс состояния ресурса) и **экран «Диагностика загрузок»** (Настройки → SuperGram → Загрузки) с копированием отчёта и сбросом зависших загрузок.
- Кнопка репоста: скрыта по умолчанию (`sgShowShareButton`), «Комментарии» и переход к сообщению сохранены (первая попытка пропускала посты каналов — исправлено).
- Остаток волны 2: панель форматирования SGInputToolbar, размер стикеров, отправка по Return, скрытие кнопки записи/нижней панели канала, эмодзи-вкладка, in-app Safari, качество фото, системный DNS, оптимизации декодирования и панели GIF, аудит коммита 9fe18208.
- Сборки: 10022 (зелёная, установлена), 10023 (зелёная, установлена). Снапшоты: `refs/backup/ultra-round2-2026-09-18`, `refs/backup/ultra-stuck-2026-09-18`.

### 2026-09-18 (вечер) — финальная верификация целей (10024 → 10025)
- Адверсариальное ревью новых механизмов (5 агентов) поймало две P0: тайм-аут 60 с убивал честные медленные загрузки (теперь 60–240 с по размеру части), а сторож FetchManager перезапускал и «списывал» нормальные закачки (порог 75 → 300 с, отказ только при быстрых повторных падениях).
- Сквозной аудит целей (6 агентов, трассировка кода от действия к результату):
  - Реклама/промо: все точки подтверждены закрытыми; **найдено и закрыто новое** — страница покупки Premium (`PremiumIntroScreen`) была достижима примерно из 93 мест и показывала цены и кнопку подписки; теперь без цен, без покупки, `PremiumDemoScreen`/`PremiumLimitsListScreen` — информативные.
  - Истории: сохранение чужих/защищённых/канальных историй, HD, скриншоты, копирование в защищённых чатах — подтверждено по коду; добавлена предзагрузка историй в HD из списка чатов.
  - Расшифровка и кружки: подтверждены end-to-end; починены залипание кнопки в `.inProgress`, потеря частичного текста при повторе, ранний релиз ключа задачи.
  - Стриминг: 6 новых фиксов, в т.ч. неперезапускаемый после ошибки поток, зависшие `semaphore.wait()` на не-стриминговых путях, галерея наследовала `fetchAutomatically:false` от бабла, пауза + тап не возобновляли загрузку, неверный дефолт `sgInlineAutoplayVideos`.
  - Тяжёлое медиа: байтовый бюджет стал настоящим (urgent-части и «аварийные» выдачи больше не обходят его), отмена другим владельцем не штрафует, пустой hash-ответ не подвешивает, счётчик прогресса не маскирует зависшие запросы.
  - Скорость/фон: keep-alive теперь держится только на реальных пользовательских загрузках (`hasUserInitiatedEntries`), переключатель применяется на лету, диагностика показывает настоящие цифры.
- Сборки 10024 и 10025 зелёные, обе установлены на устройство. Снапшоты: `refs/backup/ultra-verify-2026-09-18`, `refs/backup/ultra-goalaudit-2026-09-18`.

### 2026-10-19 — «История» вместо кнопок историй/нового сообщения (10037)
- Шапка списка чатов: убраны кнопки «новая история» и «новое сообщение»; «Изменить» перенесена направо (в режиме редактирования там «Готово»); слева кнопка «История» (часы со стрелкой). Переключатель: Настройки → SuperGram → Список чатов → «Кнопка «История» в списке чатов» (`sgChatListHistoryButton`, по умолчанию вкл; выкл — стоковая шапка).
- «История» (как в браузере): каждый открытый чат/канал/тема форума записывается (`SuperGramChatHistory`, AccountContext, до 200 записей на аккаунт, UserDefaults), при уходе из чата сохраняется место чтения; тап открывает чат ровно на этом месте (`ChatControllerSubject.message`), «Назад» ведёт в список чатов. Свайп — убрать запись, «Очистить» — вся история. Долгое нажатие на кнопку — последние 8 чатов (как зажатая «Назад» в браузере). Секретные чаты и Избранное не записываются.
- Ревью (агент) нашло и исправило: пропадание «Готово» в режиме редактирования (выйти было нельзя), «Готово» при перестановке папок не на той стороне, название темы форума, свайп закрывал не ту строку, позиция на рекламе/локальном сообщении.
- Проверено на iPhone через «Видеоповтор»: новая шапка, режим «Изменить»/«Готово», канал → пролистал → назад → «История» → открылся на том же посте, «Назад» в список.
- Сборка 10037 (`build-output/ultra/history-10037c.receipt.json`), IPA `output/SuperGram-12.8-10037-History.ipa`, установлена.
- 10038: позиция сохраняется и при уходе приложения в фон (домой, переключатель, блокировка, завершение): открытый чат регистрирует «сохранялку» в `SuperGramChatHistory.setActivePositionSaver`, по `willResignActive`/`didEnterBackground`/`willTerminate` позиции сохраняются и история синхронно пишется на диск (без отложенной на 1 с записи). Проверено на iPhone: канал → пролистал → домой → процесс убит (SIGKILL через devicectl) → перезапуск → «История» → канал открылся на том же месте. IPA `output/SuperGram-12.8-10038-History.ipa`, установлена.

### 2026-10-19 — цепочка экранов не сбрасывается (10039)
- Причина: `navigateToChatControllerImpl` при `keepStack: .default` брал экспериментальный флаг `keepChatNavigationStack` (выкл.) и выбрасывал весь стек до списка чатов. Теперь ключ `sgKeepNavigationStack` (по умолчанию вкл., Настройки → SuperGram → Список чатов → «Не сбрасывать цепочку экранов») — чат открывается поверх.
- `useExisting` возвращается только к ближайшему чату ниже (профиль → «Сообщение» → назад в тот же чат), а не прыгает через другие чаты, срезая их.
- Ограничение глубины 12 экранов (старые аккуратно отбрасываются, модальные/iPad-боковые/истории не трогаются; они доступны через «Историю»).
- Исправлены точечные сбросы: «Показать в чате» из календаря медиа профиля, очистка стека после действия в таком чате, запуск attach-бота из ссылки, переход из историй к чату/профилю автора (прыгал к самому старому экземпляру).
- iPad split view: чаты из списка по-прежнему заменяют деталь, а не копятся.
- Оставлены намеренные сбросы: удаление/выход/блокировка чата, создание группы/канала, «Все чаты» в меню «Назад», смена аккаунта, ссылки tg://chats/контакты/камера историй, настройки.
- Проверено на iPhone: канал → профиль канала → обсуждение → профиль участника → «Сообщение» → «Назад» ×5 прошёл всю цепочку до списка чатов.
- IPA `output/SuperGram-12.8-10039-Navigation.ipa`, установлена.
- 10040: «Ответить в другом чате» (`moveReplyToChat`) больше не прыгает к самому старому такому чату в стеке, удаляя всё сверху: при `sgKeepNavigationStack` переиспользуется только текущий чат или ближайший чат ниже, иначе нужный чат открывается поверх, и «Назад» проходит цепочку. IPA `output/SuperGram-12.8-10040-Navigation.ipa`, установлена.

### 2026-10-19 — уведомления: отправитель/текст и правильный чат по тапу (10041)
- Пустые уведомления: без NotificationService-расширения (не подписать: профиль только на основной бандл) приложение регистрировало APNs-токен с шифрованием → сервер слал зашифрованный пуш, iOS показывала заглушку. Теперь при отсутствии расширения в бандле токен регистрируется без шифрования (`SharedAccountContext.swift`, `superGramHasNotificationServiceExtension`); с кодом-паролем приложения — по-прежнему зашифрованно (контент скрыт). Сервер соблюдает настройки превью (`*_NOTEXT`).
- Ключи локализации для обычных пушей: 191 ключ «Отправитель\nтекст» (`scripts/supergram/generate_push_alert_strings.py`, `Telegram/SuperGramPushStrings/`), русский файл раньше в сборке был пустым. Проверено в IPA: `ru.lproj/Localizable.strings` содержит `MESSAGE_TEXT`, `CHAT_MESSAGE_TEXT` и т.д.
- Дубли: локальный fallback ждёт 4 c и не показывается, если серверное уведомление с тем же сообщением уже доставлено.
- «Мёртвый Replies-чат»: у сообщений обычных супергрупп есть технический threadId (1 или id ответа); локальное уведомление записывало его, а тап открывал фиктивную «тему форума» без сообщений и ввода. Теперь threadId пишется только для настоящих форумов, а тап идёт через новый роутер `openChatFromNotification`: тема форума → тема на сообщении; комментарий/«Replies» → ветка обсуждения под постом на сообщении (фолбэк — группа на сообщении); группа/канал → чат на сообщении; ожидание пира/сообщения с тайм-аутами вместо пустого чата; аккаунт по `user_id`; быстрый ответ больше не отвечает на «сообщение 1».
- IPA `output/SuperGram-12.8-10041-Notifications.ipa`, установлена. Переключение на обычные пуши происходит при первом запуске новой версии.

### 2026-10-19 — уведомления: настоящая причина «пустых» и пропадающих уведомлений (10042–10043)
- Проверено на устройстве журналом `telegram-data/logs/sg-notifications.txt` (новый, всегда включён, без текста сообщений; забирать: `xcrun devicectl device copy from --device <id> --domain-type appGroupDataContainer --domain-identifier group.ffcd1c12e1a9728e.1 --source telegram-data/logs/sg-notifications.txt --destination ./sg.txt`). Тест: кнопка бота ZOMBIE BUTTON в Telegram Desktop при SuperGram в фоне.
- Серверных пушей у этой сборки нет вообще: Telegram шлёт APNs только с сертификатом официального приложения, бандл `app.tomato7991.lime1486` их не получит. Все уведомления — локальный fallback живого процесса. Изменение 10041 (регистрация без шифрования + ожидание APNs 4 с) было бесполезным и вредным → откатено, токен снова регистрируется с шифрованием, без ожидания.
- «Нет отправителя, ноль информации»: fallback считал `AppLockContextImpl.isCurrentlyLocked` признаком код-пароля, а он равен `!appInForeground || locked` — всегда true в фоне. Теперь «заблокировано» = isCurrentlyLocked && код-пароль установлен. При выключенном превью чата отправитель показывается, скрывается только текст. Проверено: `title=13ch locked=false`.
- «То приходят, то нет»: keep-alive (беззвучное аудио) сам выключался через 2 ч без сообщений (20 мин в энергосбережении) и через 10 мин без сети — после этого iOS усыпляла приложение и уведомления пропадали до ручного открытия. Эти остановки убраны (осталась только критическая температура и выключатель `sgBackgroundKeepAlive`).
- Добавлен `BGAppRefreshTask` (`<bundle>.refresh`, раз в ≥15 мин по решению iOS): если приложение всё-таки выгружено/усыплено, система будит его, аккаунты синхронизируются, новые сообщения становятся уведомлениями, keep-alive перезапускается.
- IPA `output/SuperGram-12.8-10043-Notifications3.ipa`, установлена.

### 2026-10-19 — зависания: детектор и стресс-тест (10044–10046)
- `SuperGramHangDetector` (TelegramUI): сторожевой поток пингует main раз в 0,5 с; если main не отвечает ≥2 с, снимает стек main (frame-pointer walk, до 5 сэмплов) и пишет его в `logs/sg-notifications.txt` вместе с объёмом памяти. Символизация: `atos -arch arm64 -o <Framework> -l <base> <addr>`, системные — по `~/Library/Developer/Xcode/iOS DeviceSupport/iPhone16,1 27.0.1 (24A446)/Symbols`.
- `SuperGramLayerCensus`: при уходе в фон — число слоёв, память, топ-классы.
- Стресс-тест через «Видеоповтор»: музыка + видео + быстрое листание галереи (984 фото) + «Показать в чате» + комментарии → профиль → личка → «Назад» ×4 + баннер уведомления поверх галереи + быстрые открытия/закрытия медиа + циклы фон/возврат. Цепочки и тапы работают, новых зависаний нет.
- Пойман 3,4-секундный стоп при возврате из фона (10044, после частых циклов фон/возврат с открытым viewer): главный поток в `CA::Context::commit_transaction → _copyRenderLayer` (пересылка дерева слоёв в render server). Утечки слоёв нет (855–1453 слоёв, память ~380 МБ). 65-секундное зависание пользователя воспроизвести не удалось — детектор теперь снимет его стек.

### 2026-11-13 — экран канала, вкладки, вылет после галереи (10053–10054)
- Канал: нижняя панель (Mute / подарок / сообщение каналу) скрыта по умолчанию (`hideChannelBottomButton` = true; всё есть в профиле), лупа и стрелка «вниз» — под аватаркой (`ChatHistoryNavigationButtons.isTopAnchored`, кнопка `.search`). Заголовок чата 16 pt (было 17), счётчик на «Назад» 12 pt (было 13).
- Таб-бар: вкладки «Контакты» и «Звонки» выключены по умолчанию + разовая миграция (`sgTabsDefaultMigration1`); свернутая лупа справа убрана (поиск остаётся сверху, сам search view нужен как строка поиска в активном режиме); ширина кнопки ≤104 pt — компактная «таблетка» по центру.
- Вылет/усыпление после галереи (журнал с устройства, 12.11): при уходе в фон с открытым в галерее видео управляемая аудиосессия считалась «активной», тихий keep-alive не стартовал → iOS усыпляла приложение (паузы 101 с и 691 с), затем вылет через 13 с после ухода в фон (отчёт iOS пустой, 0 байт). Теперь keep-alive не запускается только при реальном воспроизведении (глобальный плеер / звонок).
- Системный отчёт: 4,3 ГБ записи на диск за ~10 ч, ~80% — запись скачиваемых медиа (`MediaBoxFileContextV2Impl.processWrite`), остальное SQLite. Причина объёма не выяснена.
- Ложные «hang» в журнале: после усыпления процесса детектор пишет стоп на всё время сна (стек — простой runloop).

### 2026-11-13 — перевод по запросу, баннер контактов, Wallet, учёт скачиваний (10055)
- Панель «Translate to …» теперь opt-in на чат: `SuperGramTranslatePanel` (AccountContext, UserDefaults `sgTranslatePanelShownPeers`). Включение — профиль → «ещё» → «Перевести»; «скрыть» в самой панели выключает обратно.
- Убран баннер «limited access to contacts» в списке контактов.
- Wallet (@wallet) скрыт из меню вложений везде, кроме чата самого бота.
- `MediaBoxWriteStats` (Postbox): байты, записанные загрузками, сколько из них поверх уже имеющихся диапазонов, сколько ресурсов открывалось повторно; при уходе в фон пишется в журнал строками `media(background): …`. Нужен для разбора жалобы «медиа качается дважды» и 4,3 ГБ записи за 10 ч — сам движок загрузки не менялся.
