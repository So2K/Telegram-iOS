# Fix guide: сборка, подпись, иконки, релизный процесс

Поток: как этот форк реально собирается и подписывается, какие падения зафиксированы в логах и что мешает выпустить следующую сборку.
`[V]` — проверено вручную, `[R]` — из read-only аудита, `[?]` — гипотеза.

---

## B-1 (S1, процесс) Падение Bazel-analysis: `Building for device, but no provisioning_profile attribute was set`  [V]

**Лог.** `build-output/build-10016.log:3143-3155`:

```
ERROR: /Users/fackeuser/Documents/Telegram/Telegram/BUILD:1760:16: in ios_application rule //Telegram:Telegram:
    .../rules_apple/internal/partials/provisioning_profile.bzl, line 41, column 13, in _provisioning_profile_partial_impl
Error in fail: ERROR: In @@//Telegram:Telegram:
Building for device, but no provisioning_profile attribute was set.
ERROR: Analysis of target '//Telegram:Telegram' (config: 903af9f) failed
ERROR: Analysis of target '...Telegram_xcodeproj:Telegram_xcodeproj' failed; build aborted: Analysis failed
```

**Причина.** В конфигурации того запуска не было ни флага `--//Telegram:disableProvisioningProfiles`, ни файла профиля в конфигурационном репозитории, поэтому селект `:Telegram_xcode_profile` отдал цель без файла. Сборки, которые действительно выпускали IPA, шли другим путём (см. B-3), поэтому это не «сломанный код», а неверный режим вызова.

**Фикс (выбрать режим и закрепить его в скрипте).**
- Для сборки через Xcode-managed signing (как в реальных запусках):
  ```sh
  python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache \
    generateProject \
    --configurationPath=build-input/local-development-configuration.json \
    --xcodeManagedCodesigning
  ```
  после чего собирать `xcodebuild` (см. B-3); `generateProject` с `xcodeManagedCodesigning` сам выставит `--//Telegram:disableExtensions` и `disableProvisioningProfiles` (`build-system/Make/Make.py:575-576`).
- Для «ручного» режима: положить профили в `build-input/configuration-repository/provisioning/` и убрать флаг.

**Проверка.** `bazel build //Telegram:Telegram --announce_rc` — в выводе видно эффективные флаги; анализ должен проходить без ошибки provisioning_profile.

## B-2 (S1, процесс) Падение скрипт-фазы `Create swift_debug_settings.py`  [V/R]

**Лог.** `build-output/build-10016-framework.log:3133-3141` — цепочка падает на
`PhaseScriptExecution Create\ swift_debug_settings.py .../Script-FF0100000000000000000005.sh (in target 'BazelDependencies')`, сборка схемы `TelegramUIFramework`, в конце `** BUILD FAILED ** (2 failures)`; по отчёту аудита причина — паника Perl на локали `C.UTF-8` (в системе нет такой локали).

**Фикс.** Запускать сборку с нормализованной локалью:
```sh
export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
```
(или `unset LC_ALL`), либо использовать `env -i` в CI. Это же стоит закрепить в `scripts/custom-client/check_toolchain.sh`/обёртке сборки, чтобы не ловить снова.
**Проверка.** Повторить сборку схемы, фаза должна пройти; в логе нет `panic: locale.c`.

## B-3 (справка) Фактический рабочий конвейер сборки и подписи  [V/R]

1. Генерация проекта (регистр `build-input/configuration-repository` + `local-development-configuration.json`: bundle `com.so2k.StableGram`, team `Y2Z28K7RV6`), см. `build-system/Make/Make.py`.
2. Сборка device-таргета через `xcodebuild` (команда из сохранённого лога `build-output/custom-client/iphoneos-supergram-universal-doubletap-release-build.log:2`):
   ```sh
   xcodebuild build -project Telegram/Telegram.xcodeproj -scheme Telegram \
     -configuration Release -destination generic/platform=iOS \
     -allowProvisioningUpdates \
     CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=Y2Z28K7RV6 \
     PRODUCT_BUNDLE_IDENTIFIER=com.so2k.StableGram ONLY_ACTIVE_ARCH=YES
   ```
   В логе установки/запуска (`build-output/custom-client/devicectl-*.log`) используется уже `-destination id=00008130-0004298110698D3A -allowProvisioningDeviceRegistration`.
3. Ручная упаковка: собранный `Telegram.app` кладётся в `output/<имя>-stage/Payload/Telegram.app`.
4. Переподпись **zsign** (`ipa-signing-work/tools/zsign-src`, кэш `.zsign_cache/`) с чужим профилем и своим списком entitlement'ов: `ipa-signing-work/entitlements/SuperGram.entitlements`, bundle `app.tomato7991.lime1486`, имя `SuperGram`; результат — `output/SuperGram-12.8-<build>-<tag>.ipa`.
5. Установка и запуск: `xcrun devicectl device install app --device 00008130-0004298110698D3A <ipa|app>` → `xcrun devicectl device process launch`.

Точные строки zsign/zip в репозитории не сохранены (`[R]`): шаг 3-4 реконструирован по кэшу zsign и содержимому staged-каталогов. Рекомендую зафиксировать этот конвейер скриптом `scripts/custom-client/build-release.sh` — иначе он повторим только «по памяти», а `build-output/custom-client/*devicectl*.log` — единственный след прошлых запусков.

## B-4 (S2) Xcode 16.2 против требуемого 26.2 и иконки  [V/R]

`versions.json` требует Xcode `26.2`, установлен `16.2`. Обход сделан в незакоммиченном изменении `Telegram/BUILD:1779`: вместо `app_icons = [ ":{}_icon".format(name) for name in composer_icon_folders ]` стоит `app_icons = [":DefaultAppIcon"]` (цель объявлена на `:306`; цель `Telegram_icon` со `.icon`-бандлами остаётся неиспользуемой), а `:1785` — `#":DefaultAppIcon"` в `resources` закомментирован.

**Что это даёт.** Основная иконка идёт через `DefaultAppIcon.xcassets` (`CFBundleIconName=AppIconLLC` в собранном Info.plist), alternate-иконки (`:1780-1782`) не затронуты — то есть на устройстве и в сборке всё выглядит рабочим.
**Чем рискует.** Icon Composer `.icon`-путь (использование которого требует Xcode 26) полностью выпадает; при переходе на Xcode 26 обход нужно снять и проверить, что иконки собираются штатным путём; для App Store отдельно проверить требование нового формата иконки (у форка App Store-сборка и так не основной сценарий).
**Действие.** Оставить обход, но пометить его комментарием в `Telegram/BUILD` (или вынести в флаг), чтобы он не «потерялся» при апгрейде Xcode.

## B-5 (S2) Рассинхрон версий внутри пакета: приложение 10016, фреймворки 10000 — ✅ ИСПРАВЛЕНО (заход №3/№4)

Статус: `scripts/supergram/build_check.sh` принимает `BUILD_NUMBER` (дефолт 10000) и передаёт `--define=buildNumber=$BUILD_NUMBER` в командную строку Bazel (переопределяет значение из `xcodeproj.bazelrc:7`); `scripts/supergram/make_ipa.sh` после правки plist сверяет `CFBundleVersion` всех `Frameworks/*.framework` с запрошенным номером.

Проверено сквозняком: `BUILD_NUMBER=10017 scripts/supergram/build_check.sh //Telegram:Telegram` → в собранном `Telegram.app` и во всех пяти вложенных фреймворках `CFBundleVersion = 10017`; затем `scripts/supergram/make_ipa.sh 10017 Fix1` → `output/SuperGram-12.8-10017-Fix1.ipa` (82 МБ, `codesign --verify --deep --strict` проходит, `Identifier=app.tomato7991.lime1486`, `TeamIdentifier=G6TLPRYW6Y`, SHA-256 `d7f9f990a8829891d6031ef43c49ef6584af4667928fa57b7a38d3557a452a5c`), внутри IPA также 10017 у приложения и у всех фреймворков.

Порядок релиза теперь такой: `BUILD_NUMBER=<n> scripts/supergram/build_check.sh //Telegram:Telegram` → `scripts/supergram/make_ipa.sh <n> <tag> [--install]`.

Что осталось из исходного пункта: `xcodeproj.bazelrc:7` по-прежнему содержит `10000` — это значение действует для сборок, запускаемых из Xcode напрямую (без скрипта), поэтому при подготовке App Store-архива номер нужно переопределять либо флагом, либо правкой файла.

Историческая справка (как было): `xcodeproj.bazelrc:7` — `--define=buildNumber=10000`, при этом собранный app имеет `CFBundleVersion = 10016` (номер подставляется на этапе упаковки), а вложенные фреймворки остаются `com.so2k.StableGram.*` с версией 10000.

## B-6 (S2) Двухидентичностная подпись и профили  [V/R]

Сборка идёт как `com.so2k.StableGram` (Xcode-managed, team `Y2Z28K7RV6`), а поставляется подписанной чужим профилем `app.tomato7991.lime1486` (team `G6TLPRYW6Y`, `get-task-allow=false`, `aps-environment=production`). Смежные факты:
- бесплатный профиль Apple допускает 3 приложения на устройство — при нескольких параллельных сборках установка может упираться в лимит (`[R]`);
- профиль привязан к одному UDID и истекает (`ipa-signing-work/secrets/certificate_info.txt`);
- пароль `.p12` лежит в открытом виде в `ipa-signing-work/secrets/` (каталог в `.gitignore`, но не зашифрован);
- `AppGroupFix.dylib` — костыль под несовпадение app group (см. P-2), который придётся убирать вместе с этим.
**Действие.** Зафиксировать один сценарий подписи (или полностью Xcode-managed с одним bundle id, или полностью ручной профиль), перенести секреты из репозитория в Keychain/1Password, и только после этого включать расширения.

## B-7 (S3) Раскладка артефактов и .gitignore  [V]

`.gitignore` дополнен `+/ipa-signing-work/`, `+/.zsign_cache/`, `+/output/`, `+/build-output/`, `+/bazel-Telegram`. Сами каталоги в рабочем дереве занимают десятки ГБ (25 ГБ весь workspace), а `output/` содержит сотни файлов QA-доказательств, referenced в `SUPERGRAM_QA_RESULTS_10014.md`.
**Действие.** Оставить как есть (не коммитить), но для ревью фиксировать в отчёте SHA-256 IPA и точный набор использованных staged-каталогов: иначе доказательства невоспроизводимы.

## B-8 (S1, процесс) Ни одна текущая сборка не проверена на подпись  [V]

В отчёте 10014 нет фактических PASS по разделу 21 QA-плана: `SIGN-01` (nested signatures), `SIGN-02` (`codesign --verify --deep --strict`), `SIGN-03` (entitlements против профиля), `SIGN-04` (метаданные бандла), `INSTALL-01..03` — все `NOT RUN`.
**Фикс — обязательный релизный чеклист (запускать буквально):**
```sh
# 1. Структура
unzip -l output/SuperGram-<build>.ipa | grep -E 'PlugIns/|Watch/'   # что реально внутри
# 2. Подпись
codesign --verify --deep --strict --verbose=4 Payload/Telegram.app
# 3. Entitlements установленного бандла
codesign -d --entitlements :- Payload/Telegram.app | plutil -p -
# 4. Соответствие профилю
security cms -D -i ipa-signing-work/secrets/00008130-0004298110698D3A.mobileprovision | plutil -p -
# 5. Идентификатор
plutil -p Payload/Telegram.app/Info.plist | grep -E 'CFBundleIdentifier|CFBundleVersion|CFBundleShortVersionString'
# 6. Контрольная сумма
shasum -a 256 output/SuperGram-<build>.ipa
```
Успех = шаги 2-4 без ошибок, `application-identifier == <team>.<CFBundleIdentifier>` (шаг 5), `aps-environment=production`, `get-task-allow` соответствует типу подписи, версии app/фреймворков/расширений совпадают (см. B-5).

## B-9 (справка) Что делать в волне A по шагам

1. `scripts/custom-client/check_toolchain.sh` — зафиксировать текущие версии (Xcode 16.2, bazel из `build-input`).
2. Применить B-2 (локаль) в обёртку сборки.
3. Выбрать режим генерации проекта и записать его одной командой в скрипт (B-1, B-3).
4. Собрать device-таргет, убедиться, что `build-output/build-*.log` заканчивается `** BUILD SUCCEEDED **`.
5. Прогнать чеклист B-8 и записать результат в новый `docs/custom-client/build-smoke.md`-раздел «Run <дата>».
6. Только после этого начинать волны B/C/D/E/F/G (см. `fix-guide.md`).
