# SuperGram: план глубокого ручного тестирования

## 1. Цель и контрольная сборка

Цель: проверить текущую кастомную ветку как цельный iOS-клиент, а не только отдельные фичи. Приоритеты: отсутствие падений и черных экранов, корректные уведомления, быстрый вход в чат, стабильное воспроизведение медиа, отсутствие рекламы, предсказуемые жесты, низкий нагрев и отсутствие визуальных наложений.

Контрольная сборка до исправлений:

| Поле | Значение |
| --- | --- |
| Клиент | SuperGram 12.8 |
| Build | 10014 |
| Bundle ID | `app.tomato7991.lime1486` |
| Устройство | iPhone 15 Pro |
| iOS | 27.0 |
| UDID | `00008130-0004298110698D3A` |
| IPA | `output/SuperGram-12.8-10014-Transcription-AdFree-Final.ipa` |
| Git branch | `codex/stable-custom-client` |
| Время теста | фиксируется в журнале каждого прогона |

Перед релизным прогоном нужно отдельно записать свободное место, состояние Low Power Mode, температуру устройства, тип сети и настройки уведомлений iOS.

## 2. Правила результата

Статусы:

- `PASS`: фактический результат полностью совпал с ожидаемым.
- `FAIL`: дефект воспроизводится; обязательны шаги, скриншот/видео и время.
- `PARTIAL`: выполнена только часть итераций или проверен не весь набор вариантов.
- `BLOCKED`: нет нужного внешнего условия, разрешения или тестовых данных.
- `NOT RUN`: сценарий еще не выполнялся.
- `N/A`: сценарий неприменим к этой конфигурации.

Серьезность:

- `S0`: потеря данных, компрометация аккаунта, неустранимый цикл падений.
- `S1`: приложение не запускается, черный экран, падение, не приходят уведомления, не открываются чаты или медиа.
- `S2`: сломан важный сценарий, сильный нагрев, зависание, неверная навигация, перекрывающий интерфейс overlay.
- `S3`: локальный визуальный или UX-дефект без потери функции.
- `S4`: косметика.

Релиз запрещен при любом открытом `S0/S1`, новом воспроизводимом падении, зависании дольше 3 секунд в основном сценарии, черном экране дольше 1 секунды или росте числа `.ips` после прогона.

## 3. Границы автоматического ручного прогона

Можно выполнять без изменения внешнего состояния:

- запускать, сворачивать и завершать SuperGram;
- открывать списки, чаты, каналы, профили, медиа, ссылки и настройки;
- прокручивать, искать локально, менять вкладки и ориентацию;
- запускать уже полученные голосовые, видео, GIF и расшифровку;
- временно менять локальные настройки и возвращать их исходные значения;
- читать системные логи, измерять время и делать скриншоты.

Не входит в автономный прогон:

- отправка сообщений, реакций, файлов, историй и голосовых;
- звонки, присоединение к live stream, нажатие bot-кнопок с сетевым действием;
- покупка Premium, Stars или любых планов;
- удаление чатов, сообщений, аккаунта или очистка пользовательских данных.

Для реального push-теста нужен входящий месседж от другого аккаунта. Тест считается `BLOCKED`, пока такого события нет; badge, banner, sound и lock-screen проверяются отдельно.

## 4. Карта рисков текущих локальных патчей

| Риск | Измененный код | Что может сломаться | Обязательные тесты |
| --- | --- | --- | --- |
| Ранний `ready` чата | `ChatControllerLoadDisplayNode.swift` | черный/пустой кадр, скачок layout, чат виден до данных | `CHAT-01..07`, `PERF-02` |
| Анимации x0.5 глобально | `Transition.swift`, `UIKitUtils.m` | обрыв completion, некликабельность, мерцание, гонки | `NAV-01..12`, `STRESS-01..04` |
| Матовый glass глобально | `GlassBackgroundComponent`, `LegacyGlassView` | неправильные формы, квадраты, непрозрачные/обрезанные панели | `VIS-01..15` |
| Жест блокируется по направлению | `InteractiveTransitionGestureRecognizer.swift`, `SparseItemGridScrollingArea.swift` | случайный боковой переход или сломанный back swipe | `GEST-01..10` |
| Gallery open cancellation | `OpenChatMessage.swift`, `ChatController.swift` | позднее открытие не того видео, вечный interaction block | `MEDIA-01..08`, `STRESS-05` |
| Double tap +/-5 секунд | `UniversalVideoGalleryItem.swift` | zoom вместо seek, листание соседнего медиа, неверная граница | `MEDIA-09..18` |
| Отключение PiP | gallery и universal video | остаточный mini-player, фоновый звук, overlay поверх экранов | `MEDIA-19..29` |
| Адаптивный плеер 30 Hz вместо постоянных 60 Hz | `ChunkMediaPlayerV2.swift` | рывки, задержка scrubber, рассинхрон A/V | `MEDIA-30..36` |
| Ранний streaming и новые chunks | `GalleryController.swift`, `FetchV2.swift`, `MultipartFetch.swift` | быстрее старт, но больше запросов/ошибок/нагрев | `NET-01..12`, `PERF-03..07` |
| Performance Mode | `SharedAccountContext.swift` | GIF/stickers не оживают, фоновые загрузки выключены неожиданно | `ENERGY-01..10` |
| GIF zero-frame guard | `BatchVideoRenderingContext.swift` | исправляет 100% CPU, но может скрыть валидный GIF | `GIF-01..07` |
| Локальная транскрибация | Speech + Opus conversion + settings | зависший progress, неверный язык, temp-файлы, повторный запрос | `VOICE-01..14` |
| Полное удаление sponsored content | ad engine + history rendering | рекламный запрос/баннер остался в другом surface | `ADS-01..09` |
| Production APNs | app delegate, entitlements | token неверной среды, push не приходит | `PUSH-01..12` |
| Background keep-alive | `SharedWakeupManager.swift` | нагрев, батарея, audio indicator, конфликт с музыкой | `PUSH-08..12`, `ENERGY-06..10` |
| Local notification fallback | `ApplicationContext.swift` | дубликаты, неверный sender/thread, уведомление в открытом чате | `PUSH-03..10` |
| API credential override | authorization + MTProto | login error, reconnect loop, invalid API_ID | `AUTH-01..09`, `NET-11` |

## 5. Подготовка и сбор доказательств

| ID | Проверка | Шаги | Ожидаемый результат | Статус |
| --- | --- | --- | --- | --- |
| PRE-01 | Идентификация | Записать iOS, модель, build, bundle ID, сеть | Данные однозначно привязаны к прогону | NOT RUN |
| PRE-02 | Свободное место | Проверить storage до прогона | Не менее 5 GB, иначе пометка в отчете | NOT RUN |
| PRE-03 | Состояние питания | Записать заряд, Low Power Mode, температуру | Базовая точка известна | NOT RUN |
| PRE-04 | Настройки уведомлений | Проверить Allow Notifications, banners, sounds, lock screen | Все включено для push-прогона | NOT RUN |
| PRE-05 | Crash baseline | Снять список Telegram/SuperGram `.ips` с датами | Зафиксирован baseline до теста | NOT RUN |
| PRE-06 | Чистый запуск | Force quit, 10 секунд ожидания, запуск | Нет остаточного audio/mini-player | NOT RUN |
| PRE-07 | Каталог артефактов | Создать `output/qa/<build>-<timestamp>/` | Скриншоты и журнал лежат в одном прогоне | NOT RUN |

Для каждого `FAIL` сохраняются: ID, время, экран до действия, экран после действия, длительность, сеть, повторяемость из 3 попыток и наличие нового crash/hang log.

## 6. Запуск и жизненный цикл

| ID | Сценарий | Шаги | Ожидаемый результат | Приоритет | Статус |
| --- | --- | --- | --- | --- | --- |
| LIFE-01 | Cold launch | Force quit, запуск | Первый полезный экран без черного кадра >1 с | S1 | NOT RUN |
| LIFE-02 | Warm launch | Home и сразу назад | Возврат <0.7 с, layout не прыгает | S2 | NOT RUN |
| LIFE-03 | Background 30 с | Свернуть, подождать, вернуть | Тот же экран и scroll position | S2 | NOT RUN |
| LIFE-04 | Background 10 мин | Свернуть, вернуть | Нет зависания, reconnect завершается | S1 | NOT RUN |
| LIFE-05 | Lock/unlock | Заблокировать при открытом списке, разблокировать | UI активен, privacy корректна | S2 | NOT RUN |
| LIFE-06 | Lock during video | Видео играет, заблокировать | При выключенном фоне playback останавливается | S1 | NOT RUN |
| LIFE-07 | Memory resume | Открыть тяжелое медиа, background, вернуть | Нет белого/черного snapshot и падения | S1 | NOT RUN |
| LIFE-08 | Repeated launches | 10 циклов kill/launch | 10/10 без crash и повреждения state | S1 | NOT RUN |
| LIFE-09 | Upgrade install | Установить новый IPA поверх текущего | Аккаунт, кэш и настройки сохранены | S0 | NOT RUN |

## 7. Авторизация и аккаунты

| ID | Сценарий | Шаги | Ожидаемый результат | Приоритет | Статус |
| --- | --- | --- | --- | --- | --- |
| AUTH-01 | Текущая сессия | Запуск онлайн | Нет повторного login/API prompt | S1 | NOT RUN |
| AUTH-02 | Смена сети | Wi-Fi -> cellular -> Wi-Fi | Сессия не сбрасывается | S1 | NOT RUN |
| AUTH-03 | API credentials | Открыть экран только если он появляется | Сохраненные валидные данные принимаются; bot token не нужен | S1 | NOT RUN |
| AUTH-04 | Account switch UI | Открыть account switch без переключения | Список и аватары не обрезаны | S3 | NOT RUN |
| AUTH-05 | Passcode screen | Заблокировать приложение локальным passcode, открыть | Клавиатура кликабельна, быстрые анимации не пропускают ввод | S1 | NOT RUN |
| AUTH-06 | Face ID cancel | Отменить Face ID один раз | Появляется корректный fallback | S2 | NOT RUN |
| AUTH-07 | Deep link while locked | Открыть локально доступную t.me ссылку при lock | Сначала unlock, затем нужный чат | S1 | NOT RUN |
| AUTH-08 | Login UI smoke | Только визуально открыть add-account до номера и выйти | Страны, номер, API-кнопка без наложений | S2 | NOT RUN |
| AUTH-09 | Reconnect token | Force quit после смены сети, запуск | Нет `CONNECTION_API_ID_INVALID` | S1 | NOT RUN |

## 8. Список чатов, папки и поиск

| ID | Сценарий | Шаги | Ожидаемый результат | Приоритет | Статус |
| --- | --- | --- | --- | --- | --- |
| LIST-01 | Основной список | Медленно прокрутить вниз/вверх | 60 fps визуально, нет белых ячеек | S2 | NOT RUN |
| LIST-02 | Быстрый fling | 10 быстрых прокруток | Нет зависания, неверных аватаров и скачков | S2 | NOT RUN |
| LIST-03 | Папки | Переключить все folder tabs | Правильная вкладка, нет перекрытия player bar | S2 | NOT RUN |
| LIST-04 | Вертикаль под 45° | 20 диагональных свайпов | Список остается вертикальным, камера/папка не открывается | S2 | NOT RUN |
| LIST-05 | Back swipe edge | Открыть чат, вернуться edge swipe | Back gesture работает при явно горизонтальном движении | S2 | NOT RUN |
| LIST-06 | Archive preview | Открыть архив и вернуться | Offset и folder сохраняются | S3 | NOT RUN |
| LIST-07 | Global search | Поиск по существующему имени | Результаты появляются без долгой паузы | S2 | NOT RUN |
| LIST-08 | Search tabs | Переключить Chats/Media/Links/Files/Voice | Заголовки не обрезаны, результат соответствует вкладке | S2 | NOT RUN |
| LIST-09 | Search cancel | Быстро ввести/стереть/закрыть 10 раз | Нет зависшего overlay/keyboard | S2 | NOT RUN |
| LIST-10 | Badge/unread | Сверить счетчики видимых чатов | Нет отрицательных/дублированных badge | S2 | NOT RUN |
| LIST-11 | Story camera conflict | Вертикальные свайпы от левого края | Камера не активируется случайно | S2 | NOT RUN |
| LIST-12 | Mini-player contamination | При активном voice/round video перейти в список | Player не закрывает tabs и кнопки | S2 | NOT RUN |

## 9. Открытие чата и навигация

| ID | Сценарий | Шаги | Ожидаемый результат | Приоритет | Статус |
| --- | --- | --- | --- | --- | --- |
| CHAT-01 | Обычный личный чат | 5 cold opens одного чата | Контент появляется сразу, без черного кадра | S1 | NOT RUN |
| CHAT-02 | Тяжелый канал | 5 opens media-heavy channel | Первый кадр <1 с, UI сразу кликабелен | S1 | NOT RUN |
| CHAT-03 | Чат со стикерами | Открыть и быстро скроллить | Нет 2-5 с freeze/crash | S1 | NOT RUN |
| CHAT-04 | Чат с wallpaper | Открыть после force quit | Wallpaper не вспыхивает черным/белым | S2 | NOT RUN |
| CHAT-05 | Pinned message | Открыть/закрыть pinned panel | Header не наслаивается на media player | S2 | NOT RUN |
| CHAT-06 | Reply navigation | Открыть существующую reply-ссылку | Переход к сообщению и назад корректен | S2 | NOT RUN |
| CHAT-07 | Unread position | Открыть чат с unread | Позиция соответствует first unread/newest policy | S2 | BLOCKED |
| CHAT-08 | Topic/forum | Открыть topic и вернуться | Нет лишней задержки cached peer data | S2 | NOT RUN |
| CHAT-09 | Comments thread | Открыть комментарии поста | Thread загружается и закрывается корректно | S2 | NOT RUN |
| CHAT-10 | Profile round-trip | Chat -> profile -> media -> back | Возврат в тот же чат и позицию | S2 | NOT RUN |
| CHAT-11 | Link round-trip | Chat -> in-app browser -> chat | После закрытия web-tab нет stale bottom inset | S2 | NOT RUN |
| CHAT-12 | Rapid switching | 30 быстрых открытий разных чатов | Нет неверного контента и crash | S1 | NOT RUN |

## 10. Отрисовка сообщений

| ID | Тип | Проверка | Ожидаемый результат | Приоритет | Статус |
| --- | --- | --- | --- | --- | --- |
| MSG-01 | Text | Короткие/длинные/emoji/RTL сообщения | Нет обрезки и overlap | S3 | NOT RUN |
| MSG-02 | Links | Preview, длинный URL, instant view | Карточки кликабельны, текст помещается | S2 | NOT RUN |
| MSG-03 | Photo | Portrait/landscape/panorama | Верный aspect ratio, placeholder исчезает | S2 | NOT RUN |
| MSG-04 | Album | Открыть каждую плитку и вернуться | Открывается выбранный элемент | S2 | NOT RUN |
| MSG-05 | File | Фото как document, PDF, ZIP | Иконка/status корректны, black screen отсутствует | S1 | NOT RUN |
| MSG-06 | GIF | Статичный preview и запуск по tap | Performance Mode соблюдается | S2 | NOT RUN |
| MSG-07 | Sticker | Обычный/animated/video sticker | При mode ON покой до tap, затем один play | S2 | NOT RUN |
| MSG-08 | Premium sticker | Tap effect | Нет бесконечной анимации/нагрева | S2 | NOT RUN |
| MSG-09 | Voice | Play/pause/seek/speed | Waveform, время и состояние синхронны | S1 | NOT RUN |
| MSG-10 | Round video | Play/pause/open/close | Нет зависшего overlay после закрытия | S1 | NOT RUN |
| MSG-11 | Poll | Открыть существующий poll без голосования | Layout и результаты читаемы | S3 | NOT RUN |
| MSG-12 | Location/contact | Открыть preview без внешнего действия | Нет crash, back корректен | S2 | NOT RUN |
| MSG-13 | Forward/reply | Header и переходы | Автор/источник не перекрывают body | S3 | NOT RUN |
| MSG-14 | Reactions | Открыть список реакций без новой реакции | Sheet не квадратный и кликабельный | S3 | NOT RUN |
| MSG-15 | Bot keyboard | Только визуальный/безопасный просмотр | Кнопки не перекрываются input | S2 | NOT RUN |

## 11. Медиа, gallery, жесты и mini-player

| ID | Сценарий | Шаги | Ожидаемый результат | Приоритет | Статус |
| --- | --- | --- | --- | --- | --- |
| MEDIA-01 | Photo open | Tap фото | Gallery появляется без задержанного второго открытия | S1 | NOT RUN |
| MEDIA-02 | Video open | Tap загруженное видео | Первый кадр <1 с, controls доступны | S1 | NOT RUN |
| MEDIA-03 | Rapid multi-tap | Быстро tap двух разных media | Открывается последнее намерение, не оба gallery | S1 | NOT RUN |
| MEDIA-04 | Cancel open | Tap media и сразу back/chat switch | Поздний gallery не появляется | S1 | NOT RUN |
| MEDIA-05 | Reopen same video | Закрыть и сразу открыть | Нет interaction lock | S1 | NOT RUN |
| MEDIA-06 | Swipe dismiss | Открыть и вертикально закрыть | Нет остаточного snapshot/overlay | S2 | NOT RUN |
| MEDIA-07 | Landscape | Повернуть в gallery и назад | Aspect/layout восстанавливаются | S2 | NOT RUN |
| MEDIA-08 | Adjacent item swipe | Листать gallery явно горизонтально | Переход работает только явным swipe | S2 | NOT RUN |
| MEDIA-09 | Double tap left | Двойной tap в левой половине | Seek ровно -5 с, без zoom/previous | S1 | NOT RUN |
| MEDIA-10 | Double tap right | Двойной tap в правой половине | Seek ровно +5 с, без zoom/next | S1 | NOT RUN |
| MEDIA-11 | Center boundary | Double tap по обе стороны 50% | Направление стабильно и предсказуемо | S2 | NOT RUN |
| MEDIA-12 | Start clamp | На 1 с double tap left | Позиция 0, playback жив | S2 | NOT RUN |
| MEDIA-13 | End clamp | За 1 с до конца double tap right | Нет restart на 0; позиция у конца | S2 | NOT RUN |
| MEDIA-14 | Seek feedback | Double tap 10 раз | Короткий ненавязчивый overlay, без крупных кнопок | S3 | NOT RUN |
| MEDIA-15 | Photo double tap | Double tap фото | Zoom работает как обычно | S2 | NOT RUN |
| MEDIA-16 | Live Photo double tap | Проверить существующий Live Photo | Нет ошибочного seek | S2 | BLOCKED |
| MEDIA-17 | Scrubber | Drag медленно и быстро | Position и thumb следуют пальцу | S2 | NOT RUN |
| MEDIA-18 | Play/pause glyph | Tap центральный glyph | Две полосы/play видимы, hit area достаточна | S3 | NOT RUN |
| MEDIA-19 | Native PiP control | Осмотреть controls | Кнопка PiP отсутствует | S2 | NOT RUN |
| MEDIA-20 | Swipe-to-PiP | Swipe down/close video | Floating video не создается | S1 | NOT RUN |
| MEDIA-21 | Background video OFF | Видео -> Home | Видео и звук останавливаются | S1 | NOT RUN |
| MEDIA-22 | Lock video OFF | Видео -> lock | Видео не продолжает играть | S1 | NOT RUN |
| MEDIA-23 | Background video ON | Включить setting, видео -> Home | Playback разрешен только при явном ON | S2 | NOT RUN |
| MEDIA-24 | Restore OFF | Вернуть setting OFF | Следующий video больше не играет в фоне | S2 | NOT RUN |
| MEDIA-25 | Round-video overlay | Запустить round video, уйти в list/profile | Нет крупного floating circle поверх UI | S1 | FAIL |
| MEDIA-26 | Top player stacking | Round video + pinned header + folder tabs | Панели не наслаиваются | S2 | FAIL |
| MEDIA-27 | Unmute pill | Round video между экранами | `Unmute` не перекрывает input/tab bar | S2 | FAIL |
| MEDIA-28 | Overlay close | Закрыть mini-player штатной кнопкой | Все overlay удалены, звук остановлен | S1 | NOT RUN |
| MEDIA-29 | Force quit cleanup | Активный media -> force quit -> launch | Overlay и audio не восстанавливаются самопроизвольно | S1 | NOT RUN |
| MEDIA-30 | 24/30 fps video | Смотреть 30 с | Нет заметных пропусков кадров | S2 | NOT RUN |
| MEDIA-31 | 60 fps video | Смотреть 30 с | Плавность приемлема, A/V sync | S2 | NOT RUN |
| MEDIA-32 | Long video | Seek в 3 точки | Быстрый resume, нет black frame >1 с | S2 | NOT RUN |
| MEDIA-33 | Streaming uncached | Открыть нескачанное видео | Старт раньше полного download, buffer понятен | S1 | NOT RUN |
| MEDIA-34 | Replay position | 10 с -> close -> reopen | Позиция сохраняется согласно ожидаемой UX-модели | S2 | NOT RUN |
| MEDIA-35 | Audio route | Play video silent/unmute | Нет зависшего muted state между файлами | S2 | NOT RUN |
| MEDIA-36 | Unsupported codec | Открыть известный MKV/VP9 если есть | Нет hang; ясный fallback вместо вечного black screen | S1 | BLOCKED |

## 12. GIF, stickers и анимации

| ID | Сценарий | Шаги | Ожидаемый результат | Приоритет | Статус |
| --- | --- | --- | --- | --- | --- |
| GIF-01 | Saved GIF panel | Открыть и листать 60 с | Нет 100% CPU/freeze | S1 | NOT RUN |
| GIF-02 | Unsupported yuv444p | Открыть подготовленный repro | Декодер прекращает попытки, UI жив | S1 | BLOCKED |
| GIF-03 | Valid yuv420p | Открыть обычные GIF | Guard не ломает валидный playback | S1 | NOT RUN |
| GIF-04 | Panel close | GIF panel -> close | CPU/анимации останавливаются | S2 | NOT RUN |
| GIF-05 | Performance ON | Видимые GIF/stickers без tap | Нет autoplay loop | S2 | NOT RUN |
| GIF-06 | Sticker tap | Tap нескольких stickers | Каждый играет один раз, список не тормозит | S2 | NOT RUN |
| GIF-07 | Performance OFF | Временно выключить mode | Стандартный autoplay возвращается | S2 | NOT RUN |

## 13. Голосовые и транскрибация

| ID | Сценарий | Шаги | Ожидаемый результат | Приоритет | Статус |
| --- | --- | --- | --- | --- | --- |
| VOICE-01 | Existing transcript | Открыть ранее расшифрованное voice | Текст появляется <1 с без повторной сети | S1 | PASS |
| VOICE-02 | Fresh short RU | Запустить transcript 5-15 с | Progress завершается, русский текст видим | S1 | PASS |
| VOICE-03 | Fresh long RU | Voice >60 с | UI не зависает, timeout/результат понятен | S2 | NOT RUN |
| VOICE-04 | EN locale | Выбрать English, расшифровать EN | Используется выбранный locale | S2 | NOT RUN |
| VOICE-05 | Auto locale | Выбрать Automatic | Используется app locale без crash | S2 | NOT RUN |
| VOICE-06 | Kazakh locale | Выбрать Kazakh при наличии записи | Корректный fallback supported locale | S2 | BLOCKED |
| VOICE-07 | On-device ON | Включить offline only | Нет обращения online; при unsupported ясный fail | S2 | NOT RUN |
| VOICE-08 | On-device OFF | Выключить offline only | Apple online fallback разрешен и завершается | S2 | NOT RUN |
| VOICE-09 | Button OFF | Скрыть transcription button | Кнопка исчезает без изменения сообщений | S2 | NOT RUN |
| VOICE-10 | Feature OFF | Отключить local transcription | Premium gating возвращается корректно | S2 | NOT RUN |
| VOICE-11 | Rapid repeated tap | 10 taps во время progress | Только одна task, нет duplicate/freeze | S1 | NOT RUN |
| VOICE-12 | Navigate away | Начать и сразу уйти из чата | Task отменяется/завершается безопасно | S2 | NOT RUN |
| VOICE-13 | Missing download | Transcript на нескачанном voice | Файл сначала скачивается, затем конвертируется | S1 | NOT RUN |
| VOICE-14 | Failure retry | Вызвать fail и повторить | Нет вечного `.inProgress`, повтор доступен | S1 | NOT RUN |

## 14. Реклама

| ID | Surface | Шаги | Ожидаемый результат | Приоритет | Статус |
| --- | --- | --- | --- | --- | --- |
| ADS-01 | Public channel bottom | Открыть несколько крупных каналов, ждать 60 с | Sponsored message отсутствует | S1 | PASS |
| ADS-02 | Between posts | Долго листать канал | Dynamic ad не вставляется | S1 | NOT RUN |
| ADS-03 | Video overlay/banner | Смотреть public-channel video 2 мин | Нет рекламного banner поверх/снизу | S1 | NOT RUN |
| ADS-04 | Search peers | Выполнить global search | Sponsored peer отсутствует | S2 | NOT RUN |
| ADS-05 | Chat reopen | Force quit и открыть тот же канал | Кэшированный ad не появляется | S1 | NOT RUN |
| ADS-06 | Multiple accounts | Просмотреть канал на доступных accounts | Нет ads во всех contexts | S2 | BLOCKED |
| ADS-07 | Stories | Просмотреть существующие stories | Sponsored story отсутствует | S2 | NOT RUN |
| ADS-08 | Web page | Открыть link preview | Реклама сайта не считается Telegram ad; UI не ломается | S3 | NOT RUN |
| ADS-09 | Network evidence | Проверить логи запроса sponsored methods | Клиент не вызывает ad fetch | S2 | NOT RUN |

## 15. Уведомления и фон

| ID | Сценарий | Шаги | Ожидаемый результат | Приоритет | Статус |
| --- | --- | --- | --- | --- | --- |
| PUSH-01 | Permission | Проверить системные настройки | Banner, sound, lock screen включены | S1 | NOT RUN |
| PUSH-02 | Token environment | Проверить entitlements и runtime log | `aps-environment=production`, token зарегистрирован production | S1 | NOT RUN |
| PUSH-03 | Foreground incoming | Получить сообщение при открытом другом чате | In-app banner один раз | S1 | BLOCKED |
| PUSH-04 | Same chat incoming | Получить сообщение в открытом чате | Нет дублированного system banner | S2 | BLOCKED |
| PUSH-05 | Background incoming | Home, получить сообщение | Banner+sound+badge без задержки | S1 | BLOCKED |
| PUSH-06 | Locked incoming | Lock, получить сообщение | Lock-screen notification один раз | S1 | BLOCKED |
| PUSH-07 | Force-quit incoming | Завершить app, получить сообщение | APNs banner приходит; local fallback невозможен после kill | S1 | BLOCKED |
| PUSH-08 | Duplicate prevention | Background incoming при живом APNs и MTProto | Ровно одно уведомление | S1 | BLOCKED |
| PUSH-09 | Thread identity | Несколько сообщений от двух chats | Верный title/body/thread grouping | S1 | BLOCKED |
| PUSH-10 | Muted chat | Incoming из muted chat | Поведение соответствует настройкам | S2 | BLOCKED |
| PUSH-11 | Music coexistence | Включить музыку, background SuperGram | Silent keep-alive не прерывает и не приглушает музыку | S1 | NOT RUN |
| PUSH-12 | Background endurance | Оставить background 30 мин | Нет заметного нагрева/audio indicator/быстрого drain | S1 | NOT RUN |

## 16. Сеть, загрузка и reconnect

| ID | Сценарий | Шаги | Ожидаемый результат | Приоритет | Статус |
| --- | --- | --- | --- | --- | --- |
| NET-01 | Wi-Fi normal | Открыть 10 thumbnails и 3 videos | Все ресурсы завершаются | S1 | NOT RUN |
| NET-02 | Cellular normal | Повторить на cellular | Нет вечного spinner | S1 | NOT RUN |
| NET-03 | Offline open | Airplane mode, открыть cached chat/media | Cached content доступен, offline state понятен | S1 | NOT RUN |
| NET-04 | Offline uncached | Открыть uncached media | Ошибка/ожидание без freeze | S2 | NOT RUN |
| NET-05 | Reconnect | Offline -> online на spinner | Загрузка автоматически продолжается | S1 | NOT RUN |
| NET-06 | Mid-video switch | Wi-Fi -> cellular во время stream | Playback восстанавливается без restart app | S1 | NOT RUN |
| NET-07 | Small files | 20 мелких thumbnails | Новые 64 KB parts не ухудшают latency | S2 | NOT RUN |
| NET-08 | Large file | Открыть файл >50 MB | 256 KB/8 parts не дают retry storm | S2 | NOT RUN |
| NET-09 | CDN path | Открыть популярное public media | CDN fetch завершается | S1 | NOT RUN |
| NET-10 | Cancel fetch | Начать media и сразу закрыть | Запрос отменяется, UI не блокируется | S2 | NOT RUN |
| NET-11 | MTProto reconnect | 10 сетевых переключений | Нет reconnect loop/API error | S1 | NOT RUN |
| NET-12 | Proxy UI | Открыть текущие proxy settings без изменения | Layout корректен, текущий status читаем | S2 | NOT RUN |

## 17. Визуальная целостность и glass

| ID | Surface | Проверка | Ожидаемый результат | Приоритет | Статус |
| --- | --- | --- | --- | --- | --- |
| VIS-01 | Tab bar | Все основные вкладки light/dark | Форма системная, не квадратная, label/icon центрированы | S2 | NOT RUN |
| VIS-02 | Navigation bars | List/chat/profile/settings | Нет лишнего блеска, фон не полностью прозрачный | S2 | NOT RUN |
| VIS-03 | Context menu | Long press без выбора action | Радиус единый, пункты не обрезаны | S2 | NOT RUN |
| VIS-04 | Action sheet | Открыть language picker и cancel | Sheet не квадратный, кнопки кликабельны | S2 | NOT RUN |
| VIS-05 | Alerts | Открыть безопасный confirmation и cancel | Текст помещается, кнопки разделены | S2 | NOT RUN |
| VIS-06 | Search bar | List/profile search | Контраст placeholder и cursor достаточный | S3 | NOT RUN |
| VIS-07 | Media controls | Light/dark video | Glyph не перекрывает кадр, hit area сохранена | S2 | NOT RUN |
| VIS-08 | Switches/sliders | Data & Storage | Glass fallback не ломает ticks/track | S2 | NOT RUN |
| VIS-09 | Keyboard/input | Text field + attachment panel | Нет overlap с home indicator | S2 | NOT RUN |
| VIS-10 | Dynamic text | Увеличить системный text size | Длинные строки SuperGram не обрезаны | S2 | NOT RUN |
| VIS-11 | Dark mode | Переключить iOS appearance | Нет белых вспышек и low-contrast matte panels | S2 | NOT RUN |
| VIS-12 | Rotation | Portrait/landscape в media/settings | Insets и radii корректны | S2 | NOT RUN |
| VIS-13 | Profile tabs | Media/Files/Links/Voice | Крайние labels не выглядят сломанно обрезанными | S3 | NOT RUN |
| VIS-14 | Overlay z-order | Pinned + player + keyboard | Ни один control не закрывает другой | S1 | FAIL |
| VIS-15 | Screenshot scan | Снимки всех основных экранов | Нет артефактов, случайных квадратов, stale views | S2 | NOT RUN |

## 18. Жесты и доступность

| ID | Сценарий | Шаги | Ожидаемый результат | Приоритет | Статус |
| --- | --- | --- | --- | --- | --- |
| GEST-01 | Vertical 0° | Чисто вертикальный scroll media grid | Только vertical scroll | S2 | NOT RUN |
| GEST-02 | Diagonal 30° | 20 движений | Не срабатывает horizontal navigation | S2 | NOT RUN |
| GEST-03 | Diagonal 45° | 20 движений | Результат стабилен, без случайного far jump | S2 | NOT RUN |
| GEST-04 | Horizontal 80-90° | Явный swipe gallery | Horizontal navigation работает | S2 | NOT RUN |
| GEST-05 | Month scrubber | Scroll media рядом с month button | Случайный touch не переносит далеко | S2 | NOT RUN |
| GEST-06 | Edge back | Явный left-edge swipe | Back работает | S2 | NOT RUN |
| GEST-07 | Pinch video | Pinch на video | Не заменяет double-tap seek | S3 | NOT RUN |
| GEST-08 | Double tap timing | Медленный/быстрый double tap | Нет single-tap side effects | S2 | NOT RUN |
| GEST-09 | Rapid mixed gestures | Scroll+back+open media | Нет stuck recognizer/unclickable UI | S1 | NOT RUN |
| GEST-10 | VoiceOver smoke | Включить VoiceOver, пройти tab/chat/back | Основные controls доступны и названы | S2 | NOT RUN |

## 19. Производительность, нагрев и устойчивость

| ID | Сценарий | Метод | Порог | Приоритет | Статус |
| --- | --- | --- | --- | --- | --- |
| PERF-01 | Cold launch latency | 5 измерений до полезного экрана | median <1.5 с, max <2.5 с | S2 | NOT RUN |
| PERF-02 | Chat open latency | 10 открытий, screen capture timestamps | median <0.8 с, max <1.2 с | S1 | PARTIAL |
| PERF-03 | Cached video start | 5 видео | median <0.5 с | S2 | NOT RUN |
| PERF-04 | Uncached video start | 5 видео на Wi-Fi | median <1.5 с | S2 | NOT RUN |
| PERF-05 | Scroll stability | 2 мин тяжелого канала | Нет пауз >250 мс | S2 | NOT RUN |
| PERF-06 | Idle foreground heat | 10 мин chat list | Нет заметного роста температуры | S1 | NOT RUN |
| PERF-07 | Video heat | 10 мин 1080p | Нет abnormal thermal warning | S1 | NOT RUN |
| ENERGY-01 | Performance ON visuals | Chat со stickers/GIF | Autoplay выключен, tap работает | S2 | NOT RUN |
| ENERGY-02 | Performance OFF visuals | Повторить после OFF | Стандартные animations возвращаются | S2 | NOT RUN |
| ENERGY-03 | Setting persistence | Kill/launch после смены | Значение сохраняется | S2 | NOT RUN |
| ENERGY-04 | Background download | Mode ON и ожидающая загрузка | Поведение соответствует тексту settings | S2 | NOT RUN |
| ENERGY-05 | CPU after GIF close | Закрыть GIF panel, ждать 1 мин | CPU возвращается к idle | S1 | NOT RUN |
| ENERGY-06 | Background keep-alive | 30 мин background | Нет постоянного высокого drain | S1 | NOT RUN |
| ENERGY-07 | Audio session | Background без media | Нет unwanted Now Playing/audio route | S1 | NOT RUN |
| ENERGY-08 | Music coexistence | Музыка + SuperGram background | Музыка не прерывается | S1 | NOT RUN |
| ENERGY-09 | Force quit | Kill SuperGram | Любая background activity прекращается | S1 | NOT RUN |
| ENERGY-10 | Battery sample | Сравнить 30 мин idle foreground/background | Результат записан; нет резкого drain | S1 | NOT RUN |

## 20. Стресс и crash hunting

| ID | Сценарий | Шаги | Ожидаемый результат | Приоритет | Статус |
| --- | --- | --- | --- | --- | --- |
| STRESS-01 | Chat roulette | 100 открытий разных chats | 0 crash, 0 wrong-chat flashes | S1 | NOT RUN |
| STRESS-02 | Tabs + folders | 100 переключений | 0 unclickable state | S1 | NOT RUN |
| STRESS-03 | Search churn | 30 open/type/clear/cancel циклов | 0 stuck keyboard/overlay | S1 | NOT RUN |
| STRESS-04 | Settings churn | 30 экранов туда/назад | 0 layout corruption | S1 | NOT RUN |
| STRESS-05 | Media race | Быстро открыть/закрыть 30 media | 0 late gallery, 0 interaction lock | S1 | NOT RUN |
| STRESS-06 | Voice/video switching | 20 play/pause разных media | Один активный player, верный audio | S1 | NOT RUN |
| STRESS-07 | Foreground/background | 30 циклов Home/return | 0 black screen/crash | S1 | NOT RUN |
| STRESS-08 | Rotation churn | 20 rotations в gallery | 0 wrong frame/overlay | S1 | NOT RUN |
| STRESS-09 | Network churn | 10 offline/online циклов | 0 reconnect loop | S1 | NOT RUN |
| STRESS-10 | Crash log delta | Сравнить `.ips` после suite | Новых Telegram/SuperGram logs нет | S1 | NOT RUN |

## 21. Сборка, подпись и установка

| ID | Проверка | Критерий | Статус |
| --- | --- | --- | --- |
| BUILD-01 | `git diff --check` | Нет whitespace/errors | NOT RUN |
| BUILD-02 | Swift static checks | Измененные Swift-файлы без новых diagnostics | NOT RUN |
| BUILD-03 | Xcode Analyze Release | Успешно | NOT RUN |
| BUILD-04 | Xcode Build Release | Успешно | NOT RUN |
| SIGN-01 | Nested code signatures | Все frameworks/extensions валидны | NOT RUN |
| SIGN-02 | Main signature | `codesign --verify --deep --strict` успешно | NOT RUN |
| SIGN-03 | Entitlements | app group, keychain, production APNs соответствуют profile | NOT RUN |
| SIGN-04 | Bundle metadata | SuperGram, новый build, правильный bundle ID | NOT RUN |
| INSTALL-01 | Install over build 10014 | Установка успешна без удаления данных | NOT RUN |
| INSTALL-02 | Launch after upgrade | Аккаунт и settings сохранены | NOT RUN |
| INSTALL-03 | IPA checksum | SHA-256 записан в release report | NOT RUN |

## 22. Источники upstream, превращенные в тесты

- Telegram iOS issues: https://github.com/TelegramMessenger/Telegram-iOS/issues
- Delayed/missing banners with instant badge: https://github.com/TelegramMessenger/Telegram-iOS/issues/2237
- Saved GIF zero-frame infinite CPU loop: https://github.com/TelegramMessenger/Telegram-iOS/issues/2246
- Chat opening freeze/crash around stickers: https://github.com/TelegramMessenger/Telegram-iOS/issues/1739
- Background battery/heat regression: https://github.com/TelegramMessenger/Telegram-iOS/issues/1649
- Black screen for image-as-file: https://github.com/TelegramMessenger/Telegram-iOS/issues/1292
- Video playback position regression: https://github.com/TelegramMessenger/Telegram-iOS/issues/1922
- Diagonal/edge camera gesture conflicts: https://github.com/TelegramMessenger/Telegram-iOS/issues/1209 and https://github.com/TelegramMessenger/Telegram-iOS/issues/2009
- Stale minimized browser inset: https://github.com/TelegramMessenger/Telegram-iOS/issues/2041

Upstream issue считается только источником гипотезы. Исправление переносится лишь после воспроизведения на текущем SuperGram или после доказанного совпадения причины в коде.

## 23. Уже подтвержденные наблюдения baseline 10014

| Наблюдение | Результат |
| --- | --- |
| Короткое свежее голосовое на русском | PASS: локальная расшифровка появилась |
| Повторное открытие сохраненной расшифровки | PASS: около 626 мс |
| Открытие трех media-heavy каналов | PASS/PARTIAL: около 1.12-1.15 с, без black screen |
| Реклама внизу проверенного public channel | PASS: после ожидания не появилась |
| Новые crash logs после предыдущего smoke | PASS: не обнаружены |
| Round-video floating overlay между экранами | FAIL: большой круг остается поверх интерфейса |
| Top `Video Message` bar + pinned/folder header | FAIL: панели наслаиваются |
| Bottom `Unmute` pill | FAIL: перекрывает input/tab bar |

## 24. Порядок исполнения

1. Выполнить `PRE`, затем зафиксировать чистый baseline crash logs.
2. Пройти `LIFE`, `LIST`, `CHAT`, `VIS` без активного медиа.
3. Пройти `MEDIA`, отдельно воспроизвести три подтвержденных overlay-дефекта.
4. Пройти `VOICE`, `GIF`, `ADS` и `NET`.
5. Выполнить короткий `PERF/ENERGY`, затем `STRESS`.
6. Получить внешнее входящее сообщение и пройти `PUSH`; до этого тесты остаются `BLOCKED`.
7. Исправлять только воспроизводимые дефекты, начиная с `S1`.
8. После каждого патча выполнять узкий сценарий, затем соседние регрессии.
9. После финального патча выполнить `BUILD/SIGN/INSTALL` и повторить все `S1/S2`.

## 25. Release gate

Сборка допускается к установке как финальная только если:

- нет открытых `S0/S1`;
- mini-player, pinned header, folder tabs и input не перекрываются;
- video double tap всегда означает +/-5 секунд, а фото сохраняет zoom;
- background video по умолчанию выключено и не оставляет звук;
- локальная транскрибация успешно завершается и не застревает;
- sponsored content отсутствует во всех проверенных surfaces;
- уведомления подтверждены реальным background и force-quit тестом либо явно помечены как единственный внешний блокер;
- нет нового crash/hang `.ips`;
- Release build, Analyze, подпись и upgrade install успешны.
