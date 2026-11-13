# Fix guide: overlay, плеер, gallery, жесты, медиа

Поток: round-video overlay / мини-плеер / z-order / плеер и его деградации / жесты gallery / сетевые таймауты.
Все якоря `файл:строка` сверены по текущему рабочему дереву (2026-09-15). `[V]` — проверено вручную, `[R]` — из read-only аудита, `[?]` — гипотеза.

Связанные сценарии QA: MEDIA-02…MEDIA-34, VIS-14, GEST-01…GEST-09, PERF-03/04/05/07, ENERGY-05.

---

## M-25 (MEDIA-25, S1) Отвязанный overlay round-video остаётся поверх чат-листа и профиля  [V]

**Симптом.** Запустили round video → ушли в список чатов или в профиль → поверх интерфейса остаётся крупный кружок (150×150) с видео, который не должен там показываться.

**Цепочка (проверена).**
- Тап по round video запускает глобальный плеер: `submodules/TelegramUI/Sources/OpenChatMessage.swift:297` (`file.isVoice || file.isInstantVideo` + `.voiceOrInstantVideo`), плейлист ставится на `:325`.
- `PeerMessagesMediaPlaylist.swift:141-143` → `SharedMediaPlaybackDisplayData.instantVideo(...)`.
- `SharedMediaPlayer.swift:241` создаёт `OverlayInstantVideoNode(priority: .secondaryOverlay)`, `:271` → `overlayMediaManager.controller?.addNode(...)`.
- Контроллер оконный: `submodules/TelegramUI/Sources/AppDelegate.swift:1362` (`mainWindow.topLevelOverlayControllers = [... overlayMediaController ...]`) — поэтому кружок живёт поверх всех экранов.

**Корневая причина.** Видимость узла считается по владению контентом:
`OverlayMediaControllerNode.swift:102` — `hidden: !item.node.customTransition && !item.node.hasAttachedContext`.
Форковый запрет отвязанного overlay есть, но он **только событийный** (`OverlayMediaControllerNode.swift:8`, `:272-283`):

```swift
node.hasAttachedContextUpdated = { [weak self, weak node] hasAttachedContext in
    if !superGramAllowsDetachedInstantVideoOverlay, node is OverlayInstantVideoNode, hasAttachedContext {
        strongSelf.removeNode(node, customTransition: true)
        return
    }
    ...
}
```

Колбэк вызывается только при **изменении** значения (`UniversalVideoNode.swift:249-253`), а `OverlayInstantVideoNode.swift:73` выставляет `videoNode.canAttachContent = true` прямо в `init`, то есть контент может быть привязан **до** того, как `addNode` установит колбэк. В этом случае узел раскладывается с `hidden: false` и не удаляется. Плюс старый узел при смене элемента плейлиста не освобождает контент: `OverlayMediaControllerNode.swift:299` `node.setShouldAcquireContext(false)` — пустая база (`OverlayMediaItemNode.swift:43-44`), ни один подкласс её не переопределяет.

**Фикс** (`submodules/TelegramUI/Sources/OverlayMediaControllerNode.swift`, функция `addNode`, блок `:272-283`): добавить проверку начального состояния и останавливать плейлист, чтобы он не отвязывался заново.

```swift
node.hasAttachedContextUpdated = { [weak self, weak node] hasAttachedContext in
    guard let strongSelf = self, let node else { return }
    if !superGramAllowsDetachedInstantVideoOverlay, node is OverlayInstantVideoNode, hasAttachedContext {
        strongSelf.removeNode(node, customTransition: true)
        node.dismiss()
        return
    }
    if let validLayout = strongSelf.validLayout, !customTransition {
        strongSelf.containerLayoutUpdated(validLayout, transition: .animated(duration: 0.3, curve: .spring))
    }
}
if !superGramAllowsDetachedInstantVideoOverlay, node is OverlayInstantVideoNode, node.hasAttachedContext {
    self.removeNode(node, customTransition: true)
    node.dismiss()
}
```

`node.dismiss()` → `OverlayInstantVideoNode.swift:92-94` → `close` → `SharedMediaPlayer.swift:242` `setPlaylist(nil, type: .voice, control: .playback(.pause))`. `removeNode` реентерабельно безопасен: `:297` требует `node.supernode === self`.

**Регрессии.** Отключается только та поверхность, которая и так должна быть скрыта; побочно останавливается воспроизведение round video при уходе сообщения с экрана — это и есть выбранное поведение QA. Gallery PiP не затронут (он отдельно выключен: `UniversalVideoGalleryItem.swift:172`).

**Проверка.** Чат с несколькими round video → играть один → (а) проскроллить сообщение за экран, (б) тапнуть следующий кружок, (в) выйти в список чатов, (г) открыть профиль через аватар. Ожидание: кружка 150 pt нет нигде; звук останавливается вместе с сообщением.

---

## M-26 (MEDIA-26, S2) Наслоение панели плеера и хедеров чата/папок  [V]

**Факты.** Глобальную панель плеера монтируют оба экрана из одного состояния:
- чат: `ChatControllerNode.swift:1413-1438` (`key: "media"`, `orderIndex: 1`, `MediaPlaybackHeaderPanelComponent`);
- список чатов: `ChatListControllerNode.swift:1469-1487` (та же панель, `orderIndex: 1`), а папки/табы и панели складываются в один контейнер `ChatListControllerNode.swift:1505-1647`;
- в чате «закреплённое сообщение» — соседняя панель в том же списке: `ChatControllerNode.swift:1565-1575` (`orderIndex: 3`), высота `ChatPinnedMessageTitlePanelNode.swift:538`.

**Корневая причина.** `HeaderPanelContainerComponent.View.update` укладывает панели **в порядке массива** и вообще не читает `orderIndex`: `submodules/TelegramUI/Components/HeaderPanelContainerComponent/Sources/HeaderPanelContainerComponent.swift:175` (`for panel in component.panels`), `:196` (позиция), `:223` (`size.height += panelSize.height`); `orderIndex` используется только в `:15/18/20/28` как поле структуры. Дополнительно высота каждой панели анимируется от 0, а аккумулятор сразу прибавляет конечную высоту (`:203-207`, `:223`), и нет арбитража между двумя контейнерами (чат и чат-лист живут одновременно в навигационном стеке, плюс inline chat list: `ChatListController.swift:3674 setInlineChatList`).

**Фикс A (порядок).** `HeaderPanelContainerComponent.swift`, перед `:175`:

```swift
let orderedPanels = component.panels.sorted { $0.orderIndex < $1.orderIndex }
var validPanelKeys: [AnyHashable] = []
for panel in orderedPanels {
```

**Фикс B (арбитраж, обязательно вместе с A).** `ChatControllerNode.swift:1413` — монтировать глобальную панель плеера только когда этот чат действительно на экране, по образцу уже существующей проверки медиа-подсказки (`ChatControllerLoadDisplayNode.swift:2966`):

```swift
if self.chatPresentationInterfaceState.search == nil, let mediaPlayback = self.controller?.globalControlPanelsContextState?.mediaPlayback, self.isInFocus {
```

**Регрессии.** A — чистый переупорядочивающий проход (у каждой панели свой `key` и свой view, состояние не теряется). B скрывает панель, пока сверху другой экран; проверить отсутствие мигания на переходе чат → список → чат.

**Проверка.** Чат с закреплённым сообщением + round video; в списке чатов есть папки. Выйти из чата: табы папок + закреплённая плашка + панель плеера одновременно. Ожидание: ровно одна полоса плеера 40 pt, всегда ниже навигации/табов, без пересечения с закреплённой панелью и строками списка.

---

## M-27 (MEDIA-27, S2) Тултип «Unmute» перекрывает нижние контролы  [V]

**Что это за UI.** `TooltipController` с текстом `Conversation.PressVolumeButtonForSound` («Press volume button to unmute the video»), создаётся в `ChatControllerLoadDisplayNode.swift:2981` (`timeout: 3.5`, `dismissByTapOutside`, `dismissImmediatelyOnLayoutUpdate`) и презентуется **в корневое окно**: `:2989-2994` (`present(..., in: .window(.root), ...)`).

**Корневая причина (upstream).** Подсказка живёт в окне и переживает экран чата. Гашение — таймер 3.5 с (`submodules/Display/Source/TooltipController.swift:225-238`), тап мимо и явные dismiss (`ChatController.swift:10216`, `ChatControllerLoadDisplayNode.swift:5472`, `ChatControllerNode.swift:5406`). Ветка «dismiss» недостижима, когда чат уже не виден, потому что ранний `guard` стоит **до** неё: `ChatControllerLoadDisplayNode.swift:2966` возвращает управление раньше, чем `:2995-2997` (`tooltipController.dismissImmediately()`).

**Статус в форке.** Триггер уже отключён: `ChatControllerNode.swift:72` `private let superGramVideoUnmuteTipEnabled = false` и `:5404-5408` (`guard superGramVideoUnmuteTipEnabled else { self.interfaceInteraction?.displayVideoUnmuteTip(nil); return }`). Единственный боевой вызов `displayVideoUnmuteTip` с непустым location — `ChatControllerNode.swift:5437`; остальные конформансы — заглушки `{ _ in }`. Значит, **на текущем дереве MEDIA-27 через этот путь не воспроизводится**; в отчёте 10014 он зафиксирован на более раннем состоянии. Отдельно: `ChatControllerNode.swift:5430` отфильтровывает `!isVideoMessage`, а у round video `isVideoMessage == true` и `badgeNode == nil` (`ChatMessageInteractiveInstantVideoNode.swift:1749-1786`) — то есть формулировка сценария («round video между экранами») текущему триггеру не соответствует, перед перепроверкой стоит уточнить, какое видео было на экране.

**Фикс (hardening, чтобы не полагаться на флаг).** `ChatControllerLoadDisplayNode.swift`, заменить `:2965-2968`:

```swift
}, displayVideoUnmuteTip: { [weak self] location in
    guard let strongSelf = self else { return }
    if location == nil {
        strongSelf.videoUnmuteTooltipController?.dismissImmediately()
        return
    }
    guard !strongSelf.didDisplayVideoUnmuteTooltip, let layout = strongSelf.validLayout, strongSelf.traceVisibility() && isTopmostChatController(strongSelf) else {
        return
    }
```

и добавить гашение при разборке узла: рядом с `videoUnmuteTooltipController?.dismiss()` в `ChatController.swift:10216` — `self.videoUnmuteTooltipController?.dismissImmediately()`.

**Регрессии.** Низкие: подсказка и так выключена, фикс лишь сокращает её жизнь. Не включать `superGramVideoUnmuteTipEnabled` без этого фикса.

**Проверка.** Зажать кнопку громкости на приглушённом (не round) видео в чате → сразу выйти назад / переключить вкладку: подсказка обязана исчезнуть вместе с чатом и не висеть над таб-баром или полем ввода.

---

## V-14 (VIS-14, S1) Z-order: закреплённая плашка + плеер + клавиатура  [V]

**Слои (проверено).**
- Панель плеера в чате живёт в `floatingTopicsPanelContainer`: `ChatControllerNode.swift:883` (addSubnode) и `:2690` (addSubview), позиция `y = sidePanelTopInset + 8`, где `sidePanelTopInset = insets.top - 4` (`:2012`, `:2682-2684`), итого `insets.top + 4`.
- Контейнер закреплённого сообщения — `y = insets.top`, высота 200 (`:2004`), и он в навигационном баре: `:915` `navigationBar?.additionalContentNode.addSubnode(titleAccessoryPanelContainer)` — добавлен **после** контейнера хедер-панелей (`:885-887`), то есть выше по z.
- Поле ввода и клавиатура — другой родитель, добавлены позже (`:901-903`), footer-панели считаются от высоты ввода: `:2697`.
- Общий контейнер — `ChatControllerTitlePanelNodeContainer`, и его `hitTest` идёт по `view.subviews` и возвращает **первый** попавший (`ChatControllerTitlePanelNodeContainer.swift:8-19`), то есть нижний слой может перехватить тап у плеера.

**Корневая причина.** Единая «поверхность плеера» эмитится в несколько независимых владельцев слоёв без единой точки арбитража (хедер-панели / нав-бар / footer) + `orderIndex` не соблюдается (см. M-26) + геометрия хедер-панелей начинается внутри полосы закреплённого сообщения.

**Фикс.**
1. Применить A и B из M-26 (одно монтирование + соблюдённый порядок).
2. Не позволять хедер-панелям заходить в полосу закреплённого сообщения: в `ChatControllerNode.swift:2683-2684` ограничить `sidePanelTopInset` снизу высотой аксессуара, например
   ```swift
   sidePanelTopInset = max(sidePanelTopInset, (self.currentTitleAccessoryPanelNode?.bounds.height ?? 0.0))
   ```
3. Починить hit-test контейнера (`ChatControllerTitlePanelNodeContainer.swift:8-19`): сначала спрашивать `super.hitTest(point, with: event)`, и только при `nil` идти по своим субвью, чтобы верхний слой выигрывал.

**Регрессии.** Пункт 3 меняет попадание тапов для forum-topics и footer-панелей того же контейнера (проверить тапы по панели тем и по панели перевода/платежей). Пункт 2 сдвигает хедер-панели вниз до высоты закреплённой плашки.

**Проверка.** Чат с закреплённым сообщением, играющее round video, открытая клавиатура, папки в списке. Ожидание: плеер и закреплённая полоса не пересекаются; клавиатура поднимает только нижние слои; тапы по кнопкам плеера попадают в плеер, а не в закреплённую панель.

---

## F1 (S2) Жестовая блокировка в gallery: ratio 1.7 рвёт всю последовательность касания  [V]

`submodules/GalleryUI/Sources/GalleryPagerNode.swift:16-29`:

```swift
if abs(movement.x) + abs(movement.y) < 1.0 { movement = self.panGestureRecognizer.translation(in: self) }
let horizontalMovement = abs(movement.x); let verticalMovement = abs(movement.y)
if horizontalMovement + verticalMovement > 0.0 && horizontalMovement < verticalMovement * 1.7 { return false }
```

Скорость берётся в начале жеста (шумно для медленных свайпов, fallback только ниже 1 pt/s), возврат `false` убивает пагинацию на весь жест. `1.7` = конус ~30.5°.

**Фикс** (`:18-26`): скорость — только если она осмысленная, порог 1.8, «мягкий» отказ:

```swift
let velocity = self.panGestureRecognizer.velocity(in: self)
var movement = velocity
if abs(velocity.x) + abs(velocity.y) < 50.0 { movement = self.panGestureRecognizer.translation(in: self) }
let horizontalMovement = abs(movement.x)
let verticalMovement = abs(movement.y)
if horizontalMovement + verticalMovement > 0.0 && horizontalMovement < verticalMovement * 1.8 { return false }
```

**Регрессии.** `isDirectionalLockEnabled` (`:183-190`) и вертикальная dismiss-прокрутка: чрезмерно низкий ratio не должен давать вертикали листать галерею.
**Проверка.** 20 медленных горизонтальных свайпов под ~35° → 0 перелистываний; 20 быстрых флик-свайпов под 15° с вертикальным сносом → 20/20; 2 минуты вертикальной прокрутки → ни одного перелистывания (MEDIA-08, GEST-01/03/04).

## F2 (S2) Блокировка навигационного жеста: ровно на границе GEST-02 + жёсткий `.failed`  [V]

`submodules/Display/Source/InteractiveTransitionGestureRecognizer.swift:203`, `:207`, `:209-215`:
`directionLockRatio = isEdgeGesture ? max(1.75, self.horizontalDirectionLockRatio) : self.horizontalDirectionLockRatio`; `|dy| ≥ 6 && |dy| > 1.1|dx|` → `.failed`; при достижении дистанции активации проверяется `|dx| ≥ |dy| * ratio`, иначе `.failed`.

Центральные/папочные жесты принимают до 30.5° (1.7) — по арифметике QA-сценарий GEST-02 («диагональ 30° не должна переключать папки») требует >1.732, то есть **сейчас FAIL предсказуем**. Краевые (back-swipe) требуют ≤29.7°; `.failed` при 6 pt вертикального сноса не откатывается в рамках того же касания → «мёртвые» свайпы назад (LIST-04, GEST-06).

**Фикс.** `:203` → `let directionLockRatio = max(1.75, self.horizontalDirectionLockRatio)`; передавать `1.8` в вызывающих: `ChatListControllerNode.swift:559`, `:1305`, `ChatListSearchPaneContainerNode.swift:285`, `PeerInfoPaneContainerNode.swift:721`; опционально `:207` → `> |dx| * 1.35`.
**Регрессии.** Переключение папок, back-swipe, панель профиля; цена — более «липкое» ощущение жеста.
**Проверка.** 20 центральных свайпов под 30° → 0 переключений папок; 20 back-swipe под 35° (dx 120 pt, dy 70 pt) → 20/20.

## F3 (S3) Фоновый пауз помечает `didPause` всем элементам пейджера  [V]

`submodules/GalleryUI/Sources/Items/UniversalVideoGalleryItem.swift:1040-1042` (наблюдатель `didEnterBackground` в `init` для каждого живого узла) и `:1230-1240` (`pauseVideoForBackgroundIfNeeded` выставляет `didPause = true`, `:1234`). Далее `:1873-1874` (`statusNodeShouldBeHidden = ... (didPause || !isPaused) ...`) скрывает кнопку загрузки, а `:1881` показывает `.playback(paused: true)` вместо `.fetch` — нескачанное видео теряет кнопку загрузки до переработки узла.

**Фикс.** В `:1230` перед `:1234` добавить:
```swift
guard self.isCentral == true, case .playing? = self.playerStatusValue?.status else { return }
```
**Регрессии.** Соседние играющие узлы продолжат играть, пока не свайпнуты (центр переопределяет позже); реальные паузы по-прежнему ставят `didPause` в `:1082`.
**Проверка.** Открыть незакачанное видео, свернуть/развернуть, тап по центру → кнопка загрузки на месте и запускает fetch (MEDIA-21/23/24).

## F4 (S3) Двойной тап ищет ±5 с без проверки seekable и от устаревшей базы времени  [R]

`UniversalVideoGalleryItem.swift:1217-1228` (`targetTimestamp = max(0, status.timestamp + delta)` — без экстраполяции) и `:1242-1258` (`seekVideo(by: isForward ? 5.0 : -5.0)` без проверки `disablePlayerControls`/статуса).

**Фикс.** Перед сдвигом — `guard !self.disablePlayerControls, self.playerStatusValue?.status != .paused, self.playerStatusValue?.status != .buffering(...)` (или переиспользовать флаг seekable из футера); базу считать как
```swift
let base = status.timestamp + (status.status == .playing ? (CACurrentMediaTime() - status.generationTimestamp) * status.baseRate : 0.0)
var targetTimestamp = max(0.0, base + delta)
```
**Регрессии.** MEDIA-15 (зум фото) не затронут; MEDIA-16 (Live Photo) уже отсечён по `isLivePhoto` (`:1248`); не использовать строгий флаг `duration >= 30` из `:1826`.
**Проверка.** MEDIA-09/10 (ровно ±5 с), MEDIA-11 (граница 50 %), MEDIA-12 (клэмп в 0), MEDIA-13 (без рестарта, ≤ duration−0.2), видео в story — тап не должен искать.

## F5 (S2) Нативный PiP выключен глобально  [V]

`UniversalVideoGalleryItem.swift:172` `private let superGramPictureInPictureEnabled = false` (используется `:1266`, `:1931`, `:2964`, `:3124`, `:3249`) и независимый глушитель `submodules/AccountContext/Sources/UniversalVideoNode.swift:443-445` (`enterNativePictureInPicture() { false }`). Кнопка PiP, «свайп вверх → PiP» и само PiP недоступны (сценарии MEDIA-19/20), `playVideoInBackground` остаётся единственным фоновым путём, при этом нет обработчика возврата в foreground (единственный наблюдатель — `didEnterBackground`), поэтому вероятен застывший кадр `AVSampleBufferDisplayLayer`.

**Фикс.** Либо удалить мёртвую ветку `:1237-1239` и задокументировать «звук продолжается, кадр может застыть», либо вернуть `true` в `:172` и восстановить делегирование в `UniversalVideoNode.swift:443-445`.
**Регрессии.** Гейт `maybePerformActionForSwipeDismiss` решает, свайп закрывает галерею или стартует PiP; путь `customUnembedWhenPortrait` (`:1266`, `:3037`) достижим только при включённом флаге.
**Проверка.** MEDIA-19/20 или явная фиксация «PiP не поддерживается» в релиз-заметках; проверить, что при возврате в foreground видео не остаётся замороженным.

## F6 (S2) `.earlierStart` для всех видео галереи без гистерезиса  [V]

`GalleryController.swift:301`, `:372`, `:481`, `:485` — `streamVideo: .earlierStart`; профиль в `submodules/MediaPlayer/Sources/MediaPlayer.swift:85-86` = `1/1/2 с`, гистерезиса нет (`submodules/MediaPlayer/Sources/MediaTrackFrameBuffer.swift:148-167`). Все видео в галерее стартуют с агрессивным запасом → больше трафика и CPU на слабых сетях.

**Фикс.** Использовать `.conservative` (`MediaPlayer.swift:94`) для всего, кроме активного центрального элемента, либо добавить гистерезис в буфер.
**Проверка.** PERF-04 на медленной сети (медиана открытия незакачанного видео < 1.5 с), отсутствие роста трафика (NET-*).

## F7 (S1) Плеер и HLS без таймаутов: заморозка видео навсегда  [V]

Ключевые якоря (проверены):
- `submodules/TelegramUniversalVideoContent/Sources/HLSVideoJSNativeContentNode.swift:758` — строковый таймаут закомментирован: `//|> timeout(5.0, queue: self.queue, alternate: .single(nil))`;
- там же `:287-288` — пустой обработчик ошибок (`error: { _ in }`) у fetch-сигнала: при неудаче ничего не эмитится, `take(1)` не срабатывает, JS-промис не резолвится → вечный спиннер;
- `:300-313` — `next` реагирует только на `result.complete`;
- `semaphore.wait()` без предела: `submodules/MediaPlayer/Sources/ChunkMediaPlayerDirectFetchSourceImpl.swift:33`, `FFMpegMediaFrameSourceContext.swift:115`, `:173`, `:236`, `:434`, `UniversalSoftwareVideoSource.swift:67`;
- `submodules/TelegramCore/Sources/Network/FetchV2.swift:713`, `:763`, `:955` — `state = .failed` без вызова `onError` и без ретраев (12 вхождений `onError`, все — объявления/присваивания).

Итог: транзиентная ошибка (`-500`, миграция DC, `FILE_TOKEN_INVALID`) навсегда блокирует поток предзагрузки в `semaphore.wait()`, держа ядро декодера; статус остаётся `.Fetching`, помогает только закрытие экрана (MEDIA-33/36, PERF-07 — нагрев).

**Фикс.**
1. `FetchV2.swift:954-955` — ретраи с backoff до терминального состояния:
```swift
self.consecutiveFailures += 1
if self.consecutiveFailures > 6 {
    self.state = .failed
    self.onError(.generic)
} else {
    self.retryNotBefore = CFAbsoluteTimeGetCurrent() + min(8.0, 0.5 * pow(2.0, Double(self.consecutiveFailures - 1)))
    self.queue.after(...) { self.update() }
}
```
плюс пропускать планирование, пока `now < retryNotBefore`, и сбрасывать счётчик на каждом успешном `.data`.
2. `HLSVideoJSNativeContentNode.swift:758` — вернуть таймаут (`|> timeout(5.0, queue: .mainQueue(), alternate: .single(nil))`, ветка `nil` уже отдаёт HTTP 500 в `:762-764`); `:287-288` → `error: { _ in subscriber.putNext(nil); subscriber.putCompletion() }`.
3. Заменить «голые» ожидания на ограниченные: `if semaphore.wait(timeout: .now() + 20) == .timedOut { return FFMPEG_CONSTANT_AVERROR_EOF }` в пяти местах (для очень медленных сетей сделать адаптивно, напр. 20 с + 1 с/МБ).

**Регрессии.** Ретраи ×6 увеличивают время до отказа на 400-ошибках (ограничено ≤8 с); 20-секундный таймаут чтения может рубить очень медленные соединения — проверить PERF-04.
**Проверка.** MEDIA-32/33/36: открыть незакачанное видео, переключить сеть в момент старта, воспроизвести ошибку RPC (VPN off/on) → плеер обязан либо восстановиться, либо показать понятную ошибку, но не зависать; в `log stream` не должно быть повторяющихся `FetchV2` failure без последующего успеха.

## F8 (S2) HLS игнорирует уже скачанный оригинал  [R]

`GalleryController.swift:356-373` — при выборе HLS-контента не проверяется наличие полностью/частично скачанного файла, поэтому закачанное видео всё равно стримится (лишний трафик, медленный старт).

**Фикс.** Перед выбором HLS проверять локальный `MediaBox`-файл (как в ветке `:301`) и предпочитать локальный контент; при частичной закачке — догружать вместо стрима.
**Проверка.** Полностью закачанное видео в режиме «полёт» → воспроизводится без сети.

## F9 (S3) Спиннер буферизации скрыт, когда плеер на паузе  [R]

`submodules/MediaPlayer/Sources/ChunkMediaPlayerV2.swift:718-729` и `:775-789` — статус обновляется по таймеру, и в паузе индикатор буферизации не появляется.

**Фикс.** Обновлять статус и при `paused`, если состояние буфера не готово (или гейтить таймер по `status != .playing` только для прогресса, не для готовности).
**Проверка.** MEDIA-17/18: поставить видео на паузу во время буферизации → индикатор обязан быть виден.

## F10 (S2) Off-main чтение `UIApplication.shared` и сворачивание `applicationIsActive` в visibilityPromise  [V]

`submodules/TelegramUI/Components/Chat/ChatMessageInteractiveMediaNode/Sources/ChatMessageInteractiveMediaNode.swift:508` (`private var applicationIsActive = UIApplication.shared.applicationState == .active` — поле инициализируется вне main-очереди, вызов из `asyncLayout`), `:512` (участвует в `visibility`) и `:2463-2507` (видимость гейтит `.full`/`.prefetch`-загрузки). Следствие: каждый уход приложения в фон отменяет видимые автозагрузки и прелоады, а при возврате они стартуют заново (лишние запросы, потеря прогресса).

**Фикс.** (1) Читать состояние только на main-очереди (кэшировать значение, обновлять по уведомлениям); (2) не включать `applicationIsActive` в `visibilityPromise` — вместо этого приостанавливать прогресс, не отменяя запрос, либо возобновлять с сохранённым диапазоном.
**Регрессии.** Отмена прелоадов в фоне была защитой от фоновой активности — после фикса проверить ENERGY-05/06 (расход батареи в фоне).
**Проверка.** Видимое незакачанное медиа → свернуть/развернуть → загрузка продолжается, а не начинается с нуля; CPU в фоне не растёт.

## F11 (S2/S3) `performanceMode` конфликтует с keep-alive аудио  [V]

`submodules/TelegramUIPreferences/Sources/MediaDisplaySettings.swift:18` (`performanceMode: true` по умолчанию) → `submodules/TelegramUI/Sources/SharedAccountContext.swift:110-124` (`superGramEffectiveEnergyUsageSettings`) выключает `extendBackgroundWork`/автозагрузку в фоне, но `submodules/TelegramUI/Sources/SharedWakeupManager.swift:1104-1147` держит аудио-сессию, а `:1155/1161/1166` считает `silenceAudioRenderer != nil` признаком «сервис жив». Утечки нет, но получается постоянная фоновая работа с отключённым фоновым менеджментом — прямой путь к jetsam-терминациям и нагреву.

**Фикс.** Развязать флаги: keep-alive — отдельный опциональный переключатель (по умолчанию off) с ограничением по времени простоя; `performanceMode` не должен отключать фоновые задачи, если keep-alive включён.
**Проверка.** ENERGY-06/07/08/09: 30-минутный замер дренажа в фоне, отсутствие Now Playing записи, стоп всей активности после force quit.

## F12 (S3) Локальные уведомления: текст на локскрине и обход Focus  [V]

`submodules/TelegramUI/Sources/ApplicationContext.swift:136-221` (вызов только для `.background` — `:601-605`): нет проверки `appLockContext.isCurrentlyLocked`, игнорируется `displayPreviews`, всё помечается `interruptionLevel = .timeSensitive` (обход Focus), приходят только `messages.first` (`:137`), идентификатор `"background-message-..."` (`:211`) не понимается `ClearNotificationsManager` (схема `m<peer>:<namespace>:<id>`), а `.inactive` (свитчер, баннер звонка) вообще не обрабатывается.

**Фикс — минимальный набор:**
```swift
// :137 — расширить guard
guard telegramLocalNotificationFallbackEnabled, notify, let firstMessage = messages.first,
      !appLockContext.isCurrentlyLocked,
      inAppNotificationSettings.displayPreviews else { return }
```
```swift
// :601 — обрабатывать и .inactive
} else if UIApplication.shared.applicationState != .active {
```
```swift
// :211 — идентификатор, который понимает ClearNotificationsManager
let identifier = "m\(firstMessage.id.peerId.toInt64()):\(Namespaces.Message.Cloud):\(firstMessage.id.id)"
```
плюс: при выключенных previews использовать `strings.Notification_Message` вместо текста (`:179-180`); для `.muted`/секретных чатов — `.active` вместо `.timeSensitive` (`:207`); батч обрабатывать целиком, а не `messages.first`.
**Регрессии.** Уведомлений станет меньше (это и требуется); ключи payload (`:195-205`) читает форковый парсер `AppDelegate.swift:442-444` — их не менять.
**Проверка.** Пароль + «без превью» → текст не виден на локскрине, баннер приходит; чтение чата убирает запись из центра уведомлений; сообщение в свёрнутом состоянии без ухода в фон (inactive) тоже приходит.

## F13 (S3) Нескачанное медиа: бюджет прелоадов и кэш HLS  [R]

- `ChatMessageInteractiveMediaNode.swift:2463-2507` — `.prefetch` для каждого видимого сообщения без глобального лимита, а части `FetchV2` — 256 КБ по 8 запросов на DC; те же слоты обслуживают воспроизведение → прелоады тормозят плейхед (PERF-03/04).
- `HLSVideoJSNativeContentNode.swift:269-308` (`HLSJSServerSource.fileData`) создаёт временный контекст и файл на каждый запрос и пишет результат через `storeResourceData`; таймер статуса 25 Гц `:1173-1178` живёт до `deinit` (`:1205`); `SharedHLSVideoJSContext` держится 10 с после последнего узла (`:870-892`).

**Фикс.** (1) Глобальный бюджет одновременных `.prefetch` (например 4) с паузой при `.buffering` плеера; (2) создавать таймер статуса лениво и останавливать в `pause()`, помня про `playerNotifySeekedOnNextStatusUpdate` (`:1180-1187`); (3) не писать каждый сегмент заново, если диапазон уже в `MediaBox`.
**Проверка.** PERF-03/04/05/06/07, ENERGY-05; 15-минутный soak HLS — размер `TempBox`/`mediaBox` не растёт на каждом цикле.

## F14 (S3) App-group: main-only константа  [V]

См. `fix-guide-push.md` P-2/P-4 — тот же дефект, здесь только как потребитель: `AppDelegate.swift:59` `group.ffcd1c12e1a9728e.1` против девяти мест `group.\(baseAppBundleId)` в расширениях.

## F15 (S4) Мёртвый код и предупреждения вокруг подавления рекламы  [R]

`ChatHistoryEntriesForView.swift:148-150` (`if message.adAttribute != nil { continue }`), `ChatControllerContentData.swift:692` (`let adMessage: Signal<Message?, NoError> = .single(nil)`) делают параметры `adMessage`/`dynamicAdMessages` (`:60-61`, `:732-736`) неиспользуемыми. Функционально безопасно; при желании удалить параметры и мёртвые ветки `.ad(...)`.
**Проверка.** ADS-01 + сборка без новых предупреждений.

## F16 (S3) Фоновый keep-alive аудио: категория сессии и остановка  [R]

`SharedWakeupManager.swift:1104-1147` (создание `MediaPlayerAudioRenderer`, ручной `setCategory(.playback, mixWithOthers)` + `setActive(true)`), `:1155/1161/1166`. Риски: постоянная фоновая CPU/сеть и нагрев, jetsam-терминации, которые выглядят как «падения»; `setActive(false)` может погасить сессию, только что поднятую голосовым/видео; обход `ManagedAudioSession` меняет поведение немого переключателя.

**Фикс.** Опциональный тумблер (по умолчанию off) + жёсткий стоп после N минут простоя; вместо ручной категории — `ManagedAudioSession.push(params: ...(audioSessionType: .ambient / .play(mixWithOthers: true)) ...)` и без ручного `setActive(false)`.
**Проверка.** ENERGY-06…09 (см. F11).

## F17 (S4) Восстановление позиции воспроизведения — дефекта не найдено  [R]

`GalleryController.swift:1508-1520`, `GalleryData.swift:303` (`gallery.temporaryDoNotWaitForReady = autoplayingVideo`), `:325-326` (сохранённое состояние не применяется к обычным фото), `UniversalVideoGalleryItem.swift:1046-1068` (`startAtTimestamp` только для видео ≥ 600 с). Ничего не ломается; если MEDIA-34 должен продолжать с позиции после двойного тапа — это фича, а не фикс.

## F18 (KEEP) Исправление bag-индекса в `UniversalVideoContentManager` — оставить  [R]

`submodules/TelegramUniversalVideoContent/Sources/UniversalVideoContentManager.swift:289-298`, `:322-331`, `:355-364`, `:149-151` — форковый код убирает правильный bag и опускает `holderCallbacks` только когда все четыре bag пусты; это лечит upstream-баг, когда отписка от статуса удаляла коллизионный индекс и «подвисала» буферизация в галерее. Не откатывать при ребейзе.

## F19 (KEEP) Прочее, что не является багом

- `OverlayMediaItemNode.setShouldAcquireContext` — пустая база (`:43-44`), но её никто не переопределяет: вызов в `OverlayMediaControllerNode.swift:299` безвреден (не «утечка», а мёртвый код).
- `MediaDisplaySettings.showNextMediaOnTap` фактически не влияет: в `GalleryController.swift:1548` жёстко `let disableTapNavigation = true`.
- `orderIndex` у `HeaderPanelContainerComponent` — см. M-26 (это и есть дефект, а не баг вызова).

### Итог по предсказаниям QA-сценариев

| Сценарий | Ожидаемый статус | Причина |
| --- | --- | --- |
| MEDIA-25/26/27, VIS-14 | FAIL (27 — только на старом состоянии) | M-25, M-26, V-14 |
| MEDIA-30/31/32/33 | вероятно FAIL/частично | F7, F8, F9 |
| MEDIA-19/20 | N/A до решения по F5 | PiP выключен |
| MEDIA-03/08, GEST-01/02/03/04, LIST-04 | FAIL/частично | F1, F2 |
| MEDIA-21/23/24 | риск FAIL | F3 |
| MEDIA-34 | PASS (модель upstream) | F17 |
| PERF-03/04/05/07, ENERGY-05/06/07 | риск FAIL | F7, F10, F11, F13, F16 |
| ADS-01 | PASS | реклама подавлена (см. `fix-guide-misc.md`) |
