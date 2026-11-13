# Fix guide: расширения, push, app group, bundle id

Поток: почему уведомления работают не так, как ожидается, и почему расширения фактически не участвуют в сборке.
`[V]` — проверено вручную, `[R]` — из read-only аудита, `[?]` — гипотеза.

QA-сценарии: раздела 15 (PUSH-01…PUSH-07), INSTALL-01…03, SIGN-01…04.

---

## P-1 (S1) В собранном приложении нет ни одного расширения  [V]

**Факты.**
- `xcodeproj.bazelrc:9` — `build --//Telegram:disableExtensions` (файл форковый: `:7` `--define=buildNumber=10000`, `:8` disk cache).
- `Telegram/BUILD:1797-1807` — `extensions = select({":disableExtensionsSetting": [], "//conditions:default": [... :ShareExtension, :NotificationContentExtension, :NotificationServiceExtension, :IntentsExtension, :WidgetExtension, :BroadcastUploadExtension]})`; флаги объявлены в `Telegram/BUILD:72-95`.
- `build-system/Make/Make.py:575-576` — при `xcodeManagedCodesigning == True` тоже выставляется `disable_extensions = True`.
- Проверено на артефактах: в `output/SuperGram-10016-gesture-stage/Payload/Telegram.app/` каталога `PlugIns` **нет** (то же для `SuperGram-10014-apple-stage`), и в `_CodeSignature/CodeResources` нет ключей `PlugIns/...`.

**Симптом.** `NotificationServiceExtension` (именно он расшифровывает payload и подставляет текст/аватар/`INSendMessageIntent`) не запускается никогда. Поэтому тело уведомления остаётся серверным generic-текстом (#2037/#833), нет Share-расширения, виджета, Siri-интентов, Broadcast. Весь форковый харденинг `NotificationService.swift` (~419 изменённых строк) в этой конфигурации — мёртвый код. QA PUSH-03 «PASS» относится к внутриэкранному баннеру (`ApplicationContext.swift:413-511`), а не к push.

**Фикс.** Убрать `xcodeproj.bazelrc:9` (или передавать `--//Telegram:disableExtensions=false`) **и** положить в `build-input/configuration-repository/provisioning/` профили для всех шести расширений (`Telegram`, `Share`, `NotificationService`, `NotificationContent`, `Intents`, `Widget`, `BroadcastUpload`), иначе анализ Bazel упадёт на отсутствующих лейблах (`Telegram/BUILD:1483`, `:1543` и далее).

**Регрессии.** Высокие: именно поэтому флаг и появился. Делать отдельной волной и отдельным коммитом.
**Проверка.** `bazel build //Telegram:Telegram` → `ls bazel-bin/Telegram/Telegram.app/PlugIns` показывает 6 `.appex`; на устройстве: убить приложение, отправить сообщение — в уведомлении должен быть настоящий текст.

## P-2 (S1) App group в расширениях не совпадает с подписанным entitlement  [V]

**Факты.** Все места вычисляют группу как `"group.\(baseAppBundleId)"`:
`NotificationService.swift:880`, `IntentHandler.swift:101` и `:881`, `NotificationViewController.swift:27`, `ShareRootController.swift:37`, `BroadcastUploadExtension.swift:325`, `TodayViewController.swift:84`, `WidgetItems.swift:362` (+ legacy-проверка `DebugController.swift:1686`).
Подписанный entitlement даёт только `group.ffcd1c12e1a9728e.1` (`ipa-signing-work/entitlements/SuperGram.entitlements:23-26`; профиль — `ipa-signing-work/secrets/profile.plist:47-54`, группы `.1…5`).
Главное приложение обходит вычисление: `AppDelegate.swift:59` `let telegramAppGroupIdentifier = "group.ffcd1c12e1a9728e.1"` (используется в `:536-537`, `:801`), плюс внедрённый `ipa-signing-work/patches/AppGroupFix.m:4-15` свайзлит `containerURLForSecurityApplicationGroupIdentifier:` (перекладывает `group.app.tomato7991.lime1486` → `group.ffcd1c12e1a9728e.1`). Этот dylib лежит в корне `.app` и **не загружается в процессах расширений**.

**Симптом.** После включения расширений (P-1): `containerURLForSecurityApplicationGroupIdentifier` вернёт nil → в `NotificationService.swift:880-885` ранний выход **до** `setupSharedLogger` (в логах расширения не будет вообще ничего), Share покажет пустой экран (`ShareRootController.swift:40-42`), Broadcast сразу завершится с ошибкой (`BroadcastUploadExtension.swift:328-331`), виджет покажет дефолт (`TodayViewController.swift:87-90`).

**Фикс.** Один общий идентификатор вместо вычисляемого:
1. Добавить константу в общий модуль (например `BuildConfigExtra` или `TelegramCore`), значение брать из Info.plist-ключа, который уже генерируется сборкой: `Telegram/BUILD:538-548` формирует `group.{telegram_bundle_id}` и `application-identifier`.
2. Заменить девять мест выше на эту константу (не на строковый литерал).
3. `AppDelegate.swift:59` перевести на ту же константу, чтобы не было двух источников истины.
4. После этого `AppGroupFix.dylib` можно удалить (свайзлинг станет ненужным) — но только вместе с переподписью, см. `fix-guide-build.md`.

**Регрессии.** Средние: смена группы требует соответствующего профиля; main-app и расширения должны получить одну и ту же строку.
**Проверка.** Расширения включены: отправить фото через Share в SuperGram (не должно зависать), разблокируемое уведомление на локскрине, виджет показывает чаты; `grep -rn 'group\.\\(' Telegram submodules` не находит жёстких вычислений.

## P-3 (S2) `aps-environment` отсутствует в генерируемых entitlement'ах  [V]

`build-input/configuration-repository/variables.bzl:13` — `telegram_aps_environment = ""`; при пустом значении `Telegram/BUILD:531-536` вообще не добавляет ключ `aps-environment` в свои entitlements. Рабочее значение `production` приходит только от пост-подписи (`ipa-signing-work/entitlements/SuperGram.entitlements:7-8`). Runtime-константа: `AppDelegate.swift:58` `telegramPushNotificationEnvironmentIsSandbox = false`, потребители — `AppDelegate.swift:571`, `SharedAccountContext.swift:348`, `:1624`.

**Симптом.** Любая сборочная ветка, не прошедшая через переподпись, регистрирует push без нужного entitlement: либо `didFailToRegisterForRemoteNotifications`, либо токен одного окружения с флагом другого → push молча не приходят.

**Фикс.** `variables.bzl:13` → `telegram_aps_environment = "production"` и проверка соответствия профилю в `build-system/prepare-build-variables-Telegram.sh:71`.
**Проверка.** `codesign -d --entitlements :- Payload/Telegram.app` показывает `aps-environment=production` на каждой сборке; `log stream --predicate 'eventMessage CONTAINS "didRegisterForRemoteNotifications"'`.

## P-4 (S2) Bundle id и team id расходятся между слоями  [V]

| Слой | Значение |
| --- | --- |
| `variables.bzl:3,6` (и `build-input/local-development-configuration.json`) | `com.so2k.StableGram` / `Y2Z28K7RV6` |
| Собранный и установленный `.app` (`Info.plist`) | `app.tomato7991.lime1486` |
| Подпись/профиль | team `G6TLPRYW6Y`, `application-identifier = G6TLPRYW6Y.app.tomato7991.lime1486` |
| Генерируемые entitlements (`Telegram/BUILD:538-548`) | `Y2Z28K7RV6.com.so2k.StableGram` и `group.com.so2k.StableGram` |

**Симптом.** Application identifier, group и keychain-group (`BuildConfig.m:231-238`) не совпадают ни с профилем, ни с runtime-id; спасает только wildcard keychain (`G6TLPRYW6Y.*`) и `AppGroupFix.dylib`. Вложенные фреймворки в IPA остаются `com.so2k.StableGram.*`.

**Фикс.** Привести `variables.bzl:3,6` к реально используемой подписи (или переподписывать профилем для `com.so2k.StableGram`) и зафиксировать одно значение в `build-input/local-development-configuration.json`, `Config-Fork.xcconfig` и `ipa-signing-work/entitlements/SuperGram.entitlements`.
**Проверка.** `codesign -d --entitlements` → `application-identifier == <team>.<CFBundleIdentifier>`; в релиз-отчёте записать bundle id, team и SHA-256 IPA.

## P-5 (S1) Локальный fallback уведомлений: текст на локскрине, обход Focus, только первое сообщение, `.inactive` не покрыт  [V]

`submodules/TelegramUI/Sources/ApplicationContext.swift:136-221`, вызов только для `.background` (`:601-605`); идентификатор `"background-message-\(account)-\(peer)-\(msg)"` (`:211`); строковый `userInfo` (`:195-201`). Keep-alive аудио: `SharedWakeupManager.swift:1104-1147`.

Проблемы:
1. нет проверки `appLockContext.isCurrentlyLocked` (в foreground-пути она есть на `:454-462`) → текст виден на локскрине при установленном пароле;
2. игнорируется `displayPreviews` (foreground-путь проверяет на `:509`) и mute-настройки чата;
3. все уведомления помечаются `.timeSensitive` (`:207`) — обход Focus;
4. обрабатывается только `messages.first` (`:137`) — при батче остальное теряется;
5. состояние `.inactive` (свитчер приложений, баннер звонка) не планирует ничего;
6. идентификатор не понимает `ClearNotificationsManager.NotificationManagedNotificationRequestId` (там схема `m<peer>:<namespace>:<id>` — `ClearNotificationsManager.swift:5-34`), поэтому прочитанное сообщение не убирается из центра уведомлений (`AppDelegate.swift:492-502` — `getPendingNotificationIds`).

**Фикс** (полный набор — в `fix-guide-media.md` F-12): расширить guard на `:137` (`!isCurrentlyLocked`, `displayPreviews`), обрабатывать `!= .active` на `:601`, генерировать совместимый идентификатор на `:211`, использовать `strings.Notification_Message` при выключенных превью, ставить `.active` для muted/секретных, батчить остальные сообщения.

**Регрессии.** Уведомлений станет меньше — это цель. Ключи payload читает форковый парсер `AppDelegate.swift:442-444` — не менять.
**Проверка.** Пароль + «без превью»: текста на локскрине нет, баннер приходит; чтение чата убирает запись; сообщение при `.inactive` приходит.

## P-6 (S3) Keep-alive через «тихую» аудио-сессию  [R]

`SharedWakeupManager.swift:1105-1147` — создаётся `MediaPlayerAudioRenderer`, вручную `setCategory(.playback, mixWithOthers)` + `setActive(true)`; `:1155/1161/1166` считают `silenceAudioRenderer != nil` признаком живого сервиса; фоновая аудио-возможность уже заявлена в `Telegram/BUILD:1663`.

**Риски.** Постоянная фоновая CPU/сеть, нагрев, jetsam-терминации (выглядят как «падения»); ручной `setActive(false)` может погасить сессию, только что поднятую голосовым/видео; обход `ManagedAudioSession` меняет поведение немого переключателя.
**Фикс.** Тумблер (по умолчанию off) + жёсткий стоп после N минут простоя; вместо ручной категории — `ManagedAudioSession.push(...)`, без ручного `setActive(false)`.
**Проверка.** ENERGY-06…09; 30-минутный замер дренажа; отсутствие лишней записи в Now Playing.

## P-7 (S3) Ошибка расшифровки подменяет серверный текст пустотой  [R]

`NotificationService.swift:1018-1022`, `:1040-1043`, `:1058-1061`, `:1067-1070`, `:1076-1079`, `:1085-1088` — на всех неудачах создаётся `NotificationContent(isLockedMessage: nil)` и вызывается `updateCurrentContent`; путь завершения `:2669-2673` предпочитает сгенерированный контент исходному, если атомар не nil → приходит пустое уведомление вместо серверного алерта.

**Фикс** (`:2669`):
```swift
if let content = content.with({ $0 }), content.title?.isEmpty == false || content.body?.isEmpty == false || content.badge != nil {
    contentHandler(content.generate())
} else if let initialContent = strongSelf.initialContent {
    contentHandler(initialContent)
}
```
**Регрессии.** Низко-средние: ветки «удалено/прочитано» намеренно пустые, но там всегда есть badge или их съедает очистка.
**Проверка.** Отправить сообщение в чат с неподдерживаемым типом вложения при включённом расширении → уведомление не пустое.

## P-8 (S3) Ответ на #2193 (Watch) и #623 (iPad) не подтверждён  [?]

Единственный контентный код группировки — `NotificationService.swift:763-765` (+ чтение `aps["thread-id"]` в `:1343`) и `ApplicationContext.swift:194`. Пока расширение выключено (P-1), группировка целиком определяется сервером, а #623 (фриз iPad после уведомления) в открытом виде остаётся проявлением того же: уведомление обрабатывает не то, что ожидается.
**Действие.** После включения расширений снять payload и лог `NotificationService`, зафиксировать идентификаторы и сравнить; до этого оба пункта бэклога держать «Needs repro».

## P-9 (не дефект) Проверено и можно не трогать  [R]

- Force unwraps в `NotificationService.swift:905`, `IntentHandler.swift:129` и `:905`, `ShareRootController.swift:26`, `NotificationViewController.swift:16`, `WidgetItems.swift:356`, `TodayViewController.swift:75` безопасны: ключи/соли всегда 32+16 байт (`BuildConfig.m:361-413`), `Bundle.main.bundleIdentifier` у appex не nil.
- Retain cycle в уведомлениях не найден: замыкания с `[weak self]` (`NotificationService.swift:2651-2677`, `SharedWakeupManager.swift:1109`, `:1119`), `Unmanaged.passUnretained` (`BroadcastUploadExtension.swift:493`, `:519`) используется синхронно.
- Основной поток расширения не блокируется: `Customoji.extractCGImage` (`:3049-3053`) уходит с main-очереди, `QueueLocalObject` генерирует на своей очереди, `DispatchSemaphore.wait()` на `NotificationService.swift:924` вне main-потока расширения.
- `mutable-content` в коде не выставляется вовсе (grep — 0 совпадений): это серверная часть, а не баг клиента.

---

### Рекомендация по развилке

Если владелец продукта не готов к волне с расширениями (6 профилей + переподпись), то минимум, который нужно сделать в этом потоке, это **P-5 и P-6**: без них продукт остаётся «push есть, но текст уведомления утекает на локскрин и обходит Focus», а фоновая работа объясняет PUSH-05 BLOCKED и часть жалоб на нагрев.
