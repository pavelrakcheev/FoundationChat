# Foundation Chat 3.1

Первая публичная beta-сборка исследовательского клиента для Apple Foundation
Models на macOS 27.

## Главное

- Нативные быстрые параметры в popover из правой части toolbar.
- Вкладки «Ответ», «Инструкции» и «Модель» без постоянно открытой правой панели.
- Полный Inspector доступен по кнопке «Открыть все параметры…».
- Welcome-экран с четырьмя квадратными карточками в сетке 2 × 2.
- Apple-only модели: локальная Apple Intelligence и Private Cloud Compute.
- Markdown, системные инструкции, Vision attachments, инструменты, guided
  generation, App Intents и диагностика Foundation Models.

## Установка

1. Скачайте `FoundationChat-3.1-macOS27-arm64.dmg`.
2. Откройте DMG и перетащите **Foundation Chat** в **Applications**.
3. Запустите приложение.

Сборка требует macOS 27 beta, Mac с Apple silicon и включённую Apple
Intelligence.

## Важно о подписи

Эта beta имеет ad-hoc подпись и пока не нотариализована Apple. Если Gatekeeper
заблокирует первый запуск, откройте **System Settings → Privacy & Security** и
выберите **Open Anyway** только для DMG из официального репозитория.

Private Cloud Compute не работает в публичной ad-hoc сборке: Apple требует
managed entitlement и подписанную тестовую сборку.

## Проверка

- Release-бинарник успешно запускается.
- DMG успешно создан, проверен и смонтирован.
- Bundle содержит arm64 executable и проходит `codesign --verify`.
- 6 автоматических тестов пройдены без ошибок.

SHA-256:

```text
b63a08e1ba9226a2e97fada2e2ef057f84dd57995fa3606365bbe0c6ebb43a29
```

Полный список изменений находится в [CHANGELOG.md](../CHANGELOG.md).
