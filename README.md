# Foundation Chat

Нативный исследовательский клиент исключительно для моделей Apple Foundation
Models. Это полигон для проверки реальных возможностей и ограничений Apple
Intelligence, а не универсальный LLM-клиент.

> Проект использует beta API macOS 27 и Xcode 27. Интерфейсы и требования Apple
> могут измениться до финального релиза.

## Что уже работает

- Apple `SystemLanguageModel` полностью локально;
- потоковая генерация через `LanguageModelSession`;
- отдельная сессия и transcript для каждого чата без утечки контекста;
- изменение системных инструкций с корректным пересозданием сессии и
  восстановлением истории;
- Markdown-рендеринг строкового ответа: заголовки, inline-разметка, списки,
  цитаты, code blocks и таблицы;
- реальные счётчики input/output/cached/reasoning tokens из
  `LanguageModelSession.Usage`;
- реальный `contextSize` системной и PCC-модели вместо жёстко заданных чисел;
- `ContextOptions.reasoningLevel` для PCC;
- сохранение истории и настроек локально через `UserDefaults`;
- typed-диагностика `LanguageModelError`, `LanguageModelSession.Error` и
  `PrivateCloudComputeLanguageModel.Error`;
- нативный SwiftUI-интерфейс macOS 27: sidebar чатов, правый Inspector с
  разделами «Генерация / Инструкции / Модели» и Liquid Glass composer;
- нативный composer в обычной layout-иерархии без ручного позиционирования;
- проекты, закрепление и переименование чатов;
- welcome-экран с рабочими карточками для документов, Vision, guided
  generation, Spotlight RAG и tool calling;
- понятные объяснения для каждой настройки и Apple-only статусы моделей;
- библиотека редактируемых prompts и адаптированный Siri AI community preset;
- Vision attachments, drag & drop изображений и текстовых файлов;
- `OCRTool`, `BarcodeReaderTool` и opt-in RAG через `SpotlightSearchTool`;
- reasoning transcript, точная скорость генерации TK/s и raw JSON guided output;
- контекстное «Уточнить» для выделенного фрагмента ответа;
- smoke evaluations, tool-call журнал, privacy-safe diagnostics и
  `logFeedbackAttachment`;
- App Intents, App Entity чата и Siri/Shortcuts actions;
- адаптивная Icon Composer-иконка: `actool` сохраняет Default, Dark, Tinted и
  Clear renditions в `Assets.car`.

## Какие модели доступны

| Режим | Чья модель | Где работает | Контекст | Важные ограничения |
|---|---|---|---:|---|
| `SystemLanguageModel` | Apple | На устройстве | Определяется в runtime через `contextSize` и зависит от версии системной модели | Apple Intelligence, поддерживаемый Mac, guardrails, без управляемого reasoning |
| `PrivateCloudComputeLanguageModel` | Apple | Серверы PCC | 32K | Managed entitlement, подходящий аккаунт/регион, сеть, дневная квота |

У Apple не «набор выбираемых локальных чат-моделей» в привычном смысле.
Публичный системный API даёт `SystemLanguageModel` с use cases `.general` и
`.contentTagging`; это профили одной управляемой Apple системной модели, а не
каталог весов. В macOS 27 Apple также открыла отдельную серверную модель PCC.

WWDC26 Core AI позволяет приложениям запускать собственные и open-source модели
через `CoreAILanguageModel`, но это не дополнительные модели Apple. Поэтому
Core AI, MLX, Hugging Face и любые сторонние провайдеры намеренно не подключены
к Foundation Chat и не показываются в интерфейсе.

Официальные источники:

- [What’s new in the Foundation Models framework — WWDC26](https://developer.apple.com/videos/play/wwdc2026/241/)
- [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)
- [PrivateCloudComputeLanguageModel](https://developer.apple.com/documentation/foundationmodels/privatecloudcomputelanguagemodel)
- [Core AI](https://developer.apple.com/core-ai/)

## Почему Markdown раньше «не работал»

Foundation Models возвращает `String` или структурированный `@Generable`
результат. Markdown не является отдельной гарантированной capability модели.
Приложение должно:

1. явно просить модель использовать Markdown в instructions;
2. не переиспользовать сессию со старой версией instructions;
3. интерпретировать полученную строку как Markdown в UI;
4. корректно показывать обычный текст, если модель не последовала инструкции.

В исходной версии пункт 2 был сломан: `ModelService` кэшировал сессию только по
типу модели. Новый чат и изменённый system prompt могли получить старую сессию.
Теперь сессии изолированы по `Conversation.ID`, а после изменения instructions
transcript пересобирается из сохранённых сообщений.

## Private Cloud Compute

PCC не заработает в неподписанном локальном bundle только от наличия класса
`PrivateCloudComputeLanguageModel`. Apple требует managed entitlement
`com.apple.developer.private-cloud-compute`. Доступ выдаётся подходящим
участникам Apple Developer Program; тестирование предусмотрено через TestFlight
или ad hoc distribution.

[Актуальные требования доступа к PCC](https://developer.apple.com/private-cloud-compute/)

Приложение теперь проверяет entitlement до запроса и различает:

- неподходящее устройство или регион;
- `systemNotReady`;
- отсутствие entitlement;
- network failure;
- service unavailable;
- исчерпанную квоту и дату сброса;
- общие ошибки модели и сессии.

Для подписанной локальной сборки:

```bash
export FOUNDATIONCHAT_SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)"
export FOUNDATIONCHAT_PROVISIONING_PROFILE="/absolute/path/to/profile.provisionprofile"
./script/build_and_run.sh --verify
```

Профиль и сертификат должны принадлежать аккаунту, которому Apple назначила
PCC entitlement. Ad-hoc подпись `-` годится для локального запуска UI, но не
даёт доступ к PCC.

## WWDC26 lab: статус

| Направление | Статус в v3 |
|---|---|
| Vision input | Реальные `Attachment(imageURL:)`, open panel и drag & drop; UI заранее проверяет `.vision` capability |
| System tools | Реальные `OCRTool`, `BarcodeReaderTool`, opt-in `SpotlightSearchTool` |
| Dynamic Profiles | Инструкции, tools, Local/Cloud и reasoning меняются без удаления сохранённого transcript; полный редактор правил автопереключения остаётся roadmap |
| Tool calling lab | Журнал имени и raw arguments; изменяющие систему tools намеренно не зарегистрированы, поэтому approval UI пока не требуется |
| Guided generation | `@Generable` schema и raw JSON в чате; произвольный визуальный schema editor остаётся roadmap |
| Evaluations | Встроенный smoke suite с pass/fail, latency и фактическим output; regression dashboard остаётся roadmap |
| Instruments | Кнопка запуска Instruments и privacy-safe diagnostic JSON |
| Feedback attachments | Экспорт Apple `logFeedbackAttachment`; приложение само ничего не отправляет |
| Siri AI / App Intents | New Chat intent, Open Chat intent, Local/Cloud `AppEnum`, chat `AppEntity`, App Shortcuts |
| fm CLI / Python SDK | Пока roadmap |

Подробный разбор незакрытых направлений, практических сценариев и приоритетов
первого публичного релиза находится в
[Apple AI landscape 2026](docs/APPLE_AI_2026.md). Визуальные проблемы и
результаты редизайна зафиксированы в
[UI/UX-аудите macOS 27](docs/UI_UX_AUDIT_2026.md).

Прямой personal context Siri, глобальная onscreen awareness и системный
orchestrator не выдаются стороннему приложению как обычный Foundation Models
API. Foundation Chat публикует собственные сущности и действия через App Intents
и не имитирует недоступные системные возможности.

Apple описывает эти направления в
[WWDC26 Foundation Models](https://developer.apple.com/videos/play/wwdc2026/241/),
[Core Spotlight LLM search](https://developer.apple.com/videos/play/wwdc2026/246/),
[Core AI](https://developer.apple.com/videos/play/wwdc2026/324/),
[Evaluations](https://developer.apple.com/videos/play/wwdc2026/298/) и
[fm CLI / Python SDK](https://developer.apple.com/videos/play/wwdc2026/334/).

## Siri AI: что относится к приложению

Новая Siri AI умеет использовать personal context, onscreen awareness,
Spotlight и действия между приложениями. Стороннее приложение не получает
прямой доступ к личному контексту Siri или её системному orchestrator. Правильная
интеграция — описывать собственные данные и действия через App Intents,
App Entities, App Schema domains, Spotlight index и view annotations.

- [Apple Intelligence and Siri AI](https://developer.apple.com/documentation/appintents/apple-intelligence-and-siri-ai)
- [Build intelligent Siri experiences with App Schemas](https://developer.apple.com/videos/play/wwdc2026/240/)

## Ограничения Apple Foundation Models

- доступность зависит от устройства, версии ОС, языка, региона и состояния
  Apple Intelligence;
- context window — общий бюджет prompt, history, tools, schema и ответа;
- модель может ошибаться, отказываться, нарушать ожидаемый формат или попадать
  под guardrails;
- системная модель и её поведение обновляются вместе с ОС, поэтому prompts
  требуют regression evaluations;
- Foundation Models не даёт разработчику веса системной Apple-модели,
  fine-tuning или выбор конкретной версии;
- on-device модель не имеет встроенного актуального веб-поиска и личного
  контекста Siri; знания приложения нужно давать через tools/RAG;
- PCC требует entitlement и квоты, а не является произвольным публичным cloud API;
- Markdown — соглашение в prompt и UI, не строгая модельная capability;
- Core AI не предоставляет дополнительные модели Apple: он предназначен для
  пользовательских и open-source моделей и потому находится вне scope проекта.

## Сборка

Требования:

- macOS 27 beta;
- Xcode 27 beta;
- Mac с Apple silicon;
- включённая Apple Intelligence для `SystemLanguageModel`.

```bash
git clone https://github.com/pavelrakcheev/FoundationChat.git
cd FoundationChat
./script/build_and_run.sh --verify
```

Доступные режимы:

```bash
./script/build_and_run.sh
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
./script/build_and_run.sh --debug
```

Старый `./build_and_run.sh` оставлен как совместимый wrapper. В Codex Desktop
кнопка Run настроена через `.codex/environments/environment.toml`.

## Структура

```text
Sources/FoundationChat/
├── FoundationChatApp.swift
├── Models/ChatModels.swift
├── Services/
│   ├── AppStateStore.swift
│   ├── AppIntentsService.swift
│   └── ModelService.swift
├── ViewModels/ChatViewModel.swift
└── Views/
    ├── ComposerView.swift
    ├── ContentView.swift
    ├── SidebarView.swift
    ├── ChatView.swift
    ├── WelcomeView.swift
    ├── MessageBubbleView.swift
    └── SettingsView.swift
```

## Авторы

Проект создан совместно:

- **Павел Ракчеев** — автор идеи, продукта и направления экспериментов;
- **DeepSeek v4 Flash (Max Reasoning)** в **OpenCode Desktop** — первая версия;
- **GPT‑5.6 Sol High** в **ChatGPT Codex** — аудит, исправление архитектуры,
  интеграций и нативный редизайн macOS 27.

Подробная атрибуция сохранена в [AUTHORS.md](AUTHORS.md).

## Лицензия

MIT. См. [LICENSE](LICENSE).
