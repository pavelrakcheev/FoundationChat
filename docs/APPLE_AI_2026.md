# Apple AI landscape 2026

Актуальность: 25 июля 2026 года, macOS 27 Beta 4 и Xcode 27 Beta 4.

Foundation Chat остаётся Apple-only полигоном. Он использует только
`SystemLanguageModel` и `PrivateCloudComputeLanguageModel`. Core AI, MLX,
Anthropic, Google и другие провайдеры не добавляются: новый общий
`LanguageModel` protocol делает их технически совместимыми с Foundation Models,
но они не являются моделями Apple и выходят за scope проекта.

## Что уже интегрировано

| Направление Apple | Состояние в Foundation Chat |
|---|---|
| Local Apple Foundation Model | Реальная потоковая генерация, отдельные sessions и runtime capability checks |
| Private Cloud Compute | Реальный API, reasoning levels, typed errors и проверка managed entitlement |
| Vision | Image attachments, drag & drop и runtime-проверка capability |
| System tools | `OCRTool`, `BarcodeReaderTool`, opt-in `SpotlightSearchTool` |
| Guided generation | Типизированный `@Generable` ответ и просмотр raw JSON |
| Token usage | Input, output, cached и reasoning tokens, context size и TK/s |
| Instructions | Редактируемая библиотека prompts и пересоздание session без потери сохранённой истории |
| Tool calling lab | Имя вызова и JSON-аргументы; изменяющие систему tools пока не регистрируются |
| Feedback and diagnostics | `logFeedbackAttachment`, privacy-safe JSON и переход в Instruments |
| Siri / App Intents | New/Open Chat intents, chat `AppEntity`, App Shortcuts и Spotlight index |

## Чего ещё нет из WWDC26

### Приоритет P0 — до первого публичного релиза

1. **Нативные Dynamic Profiles.** Сейчас приложение пересобирает session при
   изменении модели, instructions и tools, сохраняя сообщения. Следующий шаг —
   перейти на `LanguageModelSession.DynamicProfile`, profile modifiers и
   `historyTransform`, чтобы динамически выбирать Local/Cloud, reasoning и tools,
   сокращать tool calls и суммировать старый контекст без ручной оркестрации.
2. **Настоящий Evaluations framework.** Текущий smoke suite полезен для быстрой
   проверки, но не даёт статистической оценки. Нужны datasets, несколько прогонов,
   graders, сравнение профилей и regression baseline для каждой beta macOS.
3. **AppIntentsTesting.** Требуется прогнать New/Open Chat через реальные
   системные пути Siri, Shortcuts и Spotlight, проверить entity resolution,
   ошибки и локализацию без UI automation.
4. **Semantic App Entities.** Сейчас чаты индексируются как
   `CSSearchableItem`. Для Siri AI нужны `IndexedEntity`,
   `IndexedEntityQuery`, актуализация semantic index и аккуратная индексация
   только безопасной метаинформации.
5. **View Annotations и onscreen awareness.** Нужно разметить выбранный чат и
   сообщения как доступный Siri контекст, не передавая приватный transcript без
   явного действия пользователя.
6. **PCC release path.** Нужны managed entitlement, Development/TestFlight
   provisioning, проверка квот, регионов, офлайн-состояния и понятный экран
   восстановления после ошибки.
7. **Release hardening.** App Sandbox, hardened runtime, privacy policy,
   локализация RU/EN, VoiceOver, Full Keyboard Access, Increase Contrast,
   Reduce Motion, крупный текст и проверка всех размеров окна.

### Приоритет P1 — максимум пользы каждый день

- Share Extension и macOS Services: «Суммировать», «Переписать», «Извлечь
  действия» для текста из Safari, Mail, Notes и Finder.
- Быстрый clipboard workflow и menu bar-команда без создания лишнего чата.
- Локальный RAG по выбранным папкам с file-scoped разрешениями, цитатами,
  ссылками на исходные файлы и явной областью поиска.
- Typed tools для Calendar, Reminders и Notes. Любое создание, изменение или
  отправка должно показывать preview и запрашивать подтверждение.
- Профили «Быстро Local», «Глубоко Cloud», «Документы», «Изображения» и
  автоматический router на Dynamic Profiles.
- Image Playground как отдельный Apple-native режим для генерации изображений,
  а не как попытка заставить language model рисовать.
- Экспорт/импорт evaluation datasets и prompts, чтобы сравнивать beta-версии
  системной модели после обновления macOS.

### Приоритет P2 — исследовательская лаборатория

- Foundation Models framework utilities: skill API, transcript modifiers и
  повторно используемые agentic building blocks.
- Визуальный trace tool calls и переходы между profiles с привязкой к
  Foundation Models Instruments.
- Настраиваемый schema editor для `GenerationSchema`, а не одна встроенная
  структура.
- Human-in-the-loop approval center для будущих изменяющих tools.
- Интеграция с `fm` CLI и Python SDK для пакетных offline evaluations. Это
  дополнение для разработчика, а не новая модель в UI приложения.

## Чему учит практика других разработчиков

- Day One применяет модель к персонализированным подсказкам для дневника, а
  AllTrails — к рекомендациям маршрутов.
- SmartGym использует локальную историю тренировок для кратких выводов и
  адаптивных рекомендаций.
- Приложения для задач извлекают из обычного текста даты, теги, приоритеты и
  действия через structured generation.
- Образовательные приложения соединяют model tool calling со своей проверенной
  базой данных, чтобы ответ был основан на фактах приложения.
- CLI-проекты вроде `apfel` показывают пользу pipe-friendly workflows:
  резюме файлов, JSON, вложения и локальный OpenAI-compatible endpoint.

Главный вывод: системная модель особенно сильна не как универсальный чат, а как
быстрый приватный слой внутри конкретного workflow — классификация, extraction,
rewrite, summarization и tool routing.

## Как выжать максимум из Apple Foundation Models

1. Давать модели одну узкую задачу за запрос и конкретный формат результата.
2. Использовать `@Generable` и `@Guide` вместо парсинга произвольного текста.
3. Давать факты через tools/RAG, а не полагаться на знания небольшой Local-модели.
4. Держать prompts короткими, добавлять несколько качественных примеров только
   там, где они действительно улучшают результат.
5. Отправлять изображения разумного размера: крупные изображения занимают
   больше tokens и увеличивают latency.
6. Маршрутизировать быстрые и приватные задачи на Local, а сложное планирование
   — на PCC с reasoning.
7. Суммировать старый transcript, удалять неактуальные tool calls и измерять
   качество после каждого обновления системной модели.
8. Не выполнять изменяющее действие только потому, что его предложила модель:
   показывать preview, источник данных и подтверждение.

## Источники

- [What’s new in the Foundation Models framework — WWDC26](https://developer.apple.com/videos/play/wwdc2026/241/)
- [Build agentic app experiences with Foundation Models — WWDC26](https://developer.apple.com/videos/play/wwdc2026/242/)
- [Bring an LLM provider to Foundation Models — WWDC26](https://developer.apple.com/videos/play/wwdc2026/339/)
- [Meet Core AI — WWDC26](https://developer.apple.com/videos/play/wwdc2026/324/)
- [WWDC26 macOS guide](https://developer.apple.com/wwdc26/guides/macos/)
- [Build intelligent Siri experiences with App Schemas — WWDC26](https://developer.apple.com/videos/play/wwdc2026/240/)
- [Explore advanced App Intents features — WWDC26](https://developer.apple.com/videos/play/wwdc2026/343/)
- [Adding intelligent app features with generative models](https://developer.apple.com/documentation/foundationmodels/adding-intelligent-app-features-with-generative-models)
- [How developers are using Apple’s local AI models](https://techcrunch.com/2025/10/03/how-developers-are-using-apples-local-ai-models-with-ios-26/)
- [apfel — local Apple Foundation Models CLI](https://github.com/Arthur-Ficial/apfel)
