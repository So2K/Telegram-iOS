# Fix guide: локальные фичи форка и остатки бэклога

Поток: реклама, Stories, override API-ключей, брендинг, а также пересмотр `docs/custom-client/bug-backlog.md` и новые находки в guard'ах.
`[V]` — проверено вручную, `[R]` — из read-only аудита, `[?]` — гипотеза.

---

## Часть A. Локальные фичи форка

### A-1 (без дефекта) Подавление рекламы работает  [V]

Точки подавления:
- `submodules/TelegramCore/Sources/TelegramEngine/Messages/AdMessages.swift:6` — `let telegramSponsoredContentEnabled = false` (глобальный отключатель), используется в `:456`, `:487`;
- `submodules/TelegramCore/Sources/TelegramEngine/Peers/AdPeers.swift:42` — ранний выход по тому же флагу;
- `submodules/TelegramUI/Sources/ChatControllerNode.swift:756` — `let displayAdPeer: PeerId? = nil`;
- поиск: реклама в результатах вырезана (`ChatListSearchListPaneNode.swift:2597`, `:2607`), вызовов `searchAdPeers` не осталось;
- пагинация не страдает: контекст рекламы nil, механика интервала между сообщениями не активируется.

**Остаток:** форковый тестовый путь инъекции рекламы `ChatHistoryListNode.swift:843-922` под флагом `fakeAds` (объявлен в `ExperimentalUISettings.swift:67`, по умолчанию `false` — `:119`). Он не влияет на релиз, но при включении начнёт показывать ненастоящую рекламу. Решение: либо пометить как debug-only, либо удалить.
**Проверка.** ADS-01 (публичный канал без спонсорских сообщений) + прокрутка/вставка/удаление в истории без аномалий.

### A-2 (S3) `hideStories`: применяется только после перезапуска  [R]

`ExperimentalUISettings.swift:54` (`hideStories`), значение по умолчанию `false` (`:106`), переключатель в `submodules/DebugSettingsUI/Sources/DebugController.swift`. Логика в `submodules/ChatListUI/Sources/ChatListController.swift:2067` читает **кэшированный** атомар настроек один раз, поэтому переключение требует перезапуска (в UI так и написано: «[Restart App]»).
Утечек и висящих подписок нет: все четыре story-disposable'а освобождаются на `:809-813`, прелоады чистятся на `:2117-2141`.
**Фикс (если хочется live-переключение).** Подписаться на изменение `hideStories` и пересоздать/переразложить chat list без перезапуска; либо оставить как есть и не считать дефектом.
**Проверка.** STORY-* сценарии: с включённым флагом Stories-хедер отсутствует, прогресс загрузки не наблюдается, ресурсы preload не тянутся (`log stream` — нет запросов за сторис).

### A-3 (S3) Override `api_id`/`api_hash` на экране входа  [R]

`submodules/AuthorizationUI/Sources/AuthorizationApiCredentials.swift:28-32`, `:50-54` — значения хранятся в обычном `UserDefaults`, валидация корректная. Проблемы:
1. авто-подсказка о необходимости своих ключей **никогда не срабатывает**, потому что сборка уже содержит официальные `APP_CONFIG_API_ID=8` и официальный `api_hash` (`Telegram/Telegram-iOS/Config-Fork.xcconfig:8`), которые проходят собственную проверку `isValid` (`AuthorizationSequencePhoneEntryController.swift:178`);
2. `api_hash` показывается в незащищённом текстовом поле;
3. расширения override не читают (`NotificationService.swift:876-877` и др.) — то есть при своих ключах расширения будут работать с чужими/пустыми.
**Фикс.** Решить, какой сценарий продуктовый: (а) свои ключи обязательны — тогда убрать официальные из `Config-Fork.xcconfig`/`Config-AppStoreLLC.xcconfig` и показывать экран ввода при первом запуске; (б) ключи форка — тогда убрать экран-заглушку и мёртвую ветку проверки. Хранение перенести в Keychain, поле `api_hash` — `isSecureTextEntry`. Для расширений — читать тот же источник, что и приложение.
**Проверка.** Чистая установка: понятно, какие ключи используются; `api_hash` не виден при вводе; расширения видят те же значения.

### A-4 (S2) Брендинг и идентификаторы  [V]

Уровень приложения оформлен как SuperGram (`Config-Fork.xcconfig:1-2`), но app group трёхсторонне не согласован: `AppDelegate.swift:59` (`group.ffcd1c12e1a9728e.1`) против девяти мест `group.\(baseAppBundleId)` в расширениях против `group.{telegram_bundle_id}` из `Telegram/BUILD:538-548`, и всё это держится на внедрённой `AppGroupFix.dylib`. Подробности и фикс — `fix-guide-push.md` P-2/P-4.

---

## Часть B. Пересмотр `docs/custom-client/bug-backlog.md` (41 пункт)

Бэклог ведён 2026-07-02 и отмечает 5 пунктов как «Fixed locally». Аудит показал, что **два из них закрыты не полностью**, а остальные 36 не проверялись на устройстве (статусы «hardened locally; needs runtime proof» — это не «исправлено»).

| Пункт бэклога | Заявлено | Вердикт аудита | Действие |
| --- | --- | --- | --- |
| Audio file export (#2031, `/` в метаданных) | Fixed locally | Подтверждено корректным | Закрыть, добавить сценарий регрессии в QA |
| #1189 | Fixed locally | Подтверждено корректным | Закрыть |
| `BrowserMarkdown` | Fixed locally | Подтверждено корректным | Закрыть |
| Startup crash (#2011, контакт с URL) | Fixed locally | **Неполно.** Коммит добавил `guard id > 0` только в две «парные» функции: `submodules/AccountContext/Sources/DeviceContactData.swift:221-223` и `Telegram/SiriIntents/IntentContacts.swift:37-39` (проверено `git diff origin/master...HEAD`). Третий такой же разбор остался без этой проверки: `submodules/UrlHandling/Sources/UrlHandling.swift:469-470` — `Int64(...)` защищён от nil через `let`, но отрицательный id по-прежнему превращается в `EnginePeer.Id` (severity S3: потребитель этого кейса до падения не прослежен, это риск, а не доказанный краш) | Добавить `guard idValue > 0 else { return <прежнее поведение> }` по образцу двух исправленных мест; сценарий регрессии — старт по ссылке/контакту с отрицательным `@id` |
| Share extension freeze (#2134) | Fixed locally | **Преувеличено:** путь «не залогинен» починен, но `ShareExtensionContext.swift:536` по-прежнему индексирует `phoneNumbers[0]` без проверки; и само расширение в сборку не попадает (P-1) | Добавить guard; до включения расширений сценарий в отчётах не закрывать |
| Остальные 36 пунктов | «Hardened/Mitigated locally; needs runtime proof» | Не подтверждены: ни один не проверен на устройстве | Оставить в статусе «не проверено», переносить в релиз только с device-доказательством (см. правило в `fix-guide.md`, §3 чеклиста) |

### Новые находки в guard'ах (сверх бэклога)

| ID | Файл:строка | Суть | Severity | Фикс |
| --- | --- | --- | --- | --- |
| G-1 | `submodules/TelegramApi/Sources/Buffer.swift:89-93` | `serializeBytes` пишет заголовок длины без полезной нагрузки, если буфер непустой, но без backing storage → молчаливый TL-десинк | S2 | ✅ Исправлено (заход №2): при `size != 0 && data == nil` длина пишется как 0 |
| G-2 | `submodules/DirectMediaImageCache/Sources/DirectMediaImageCache.swift:173-192` | legacy-ветка `0xcaf1` строит `CGImage` без проверки геометрии payload | S2 | ✅ Исправлено (заход №4): проверка `width/height > 0`, `bytesPerRow >= width * bytesPerPixel`, `bytesPerRow * height <= data.count` — по образцу ветки `0xcaf2:210`. Уточнение: трапа на коротком payload не было, заголовок уже обрамлён проверкой `data.count > 10` (`:143`) |
| G-3 | `submodules/AnimatedStickerNode/Sources/FrameCompression.swift:9-16` | `bytesPerRow` уходит в `vImage_Buffer.rowBytes` без проверки | S3 | ✅ Исправлено (заход №4): `guard bytesPerRow >= width * 4` (иначе vImage читает за буфером / отдаёт «чёрный кадр», который кэшировался) |
| G-4 | `submodules/AudioWaveform/Sources/AudioWaveform.swift:41` | `setBits` пишет 4 байта, полагаясь на запас +4 | S4 | ✅ Проверено — **не баг**: `makeBitstream` выделяет `bitstreamLength + 4` (`:94`), последняя запись укладывается; 4 байта нужны, поле может пересекать до 5 байт |
| G-5 | ~50 мест с `try!` (в т.ч. CoreML-пути cutout/face-scan) | Наследие upstream; инвентарь без обработки | S3 | Частично: заход №4 закрыл краши на пустом буфере (`Log.swift:252/397/506`, `MediaBox.swift:1256/1438`, `MediaBoxFileContextV2Impl.swift:630-641`, `SGLogger.swift:172`, `FetchV2.swift:440-460/1249-1275`, снапшот стикера `ChatMessageAnimatedStickerItemNode.swift:3293`, `BatchVideoRenderingContext.swift:400-407`). Остальное — по `run_crash_risk_scan.sh --all` перед релизом |

---

## Часть C. Как закрывать бэклог дальше (процесс)

1. Перед каждой правкой — воспроизведение на текущей ветке или доказанная причина по коду (правило уже зафиксировано в `SUPERGRAM_STABILITY_PLAN.md`).
2. В коммит класть: ссылку на issue, затронутую подсистему, шаги воспроизведения и сценарий регрессии (правило `docs/custom-client/README.md`).
3. Один пункт = один коммит. Не смешивать пункты с разными подсистемами.
4. После правки обновлять эту таблицу: статус меняется только с доказательством (`PASS` на устройстве или явная пометка «нужно runtime-доказательство»).
5. Пункты, требующие профилирования (#81 батарея, #1554 производительность, #447 память iPad, #1668 скроллинг), не чинятся «по чтению кода»: для них нужен прогон `Instruments` (Time Profiler + Allocations) и зафиксированный baseline — иначе правка будет угадыванием.
