#!/bin/zsh

set -euo pipefail

project_root=${0:A:h:h}
xcode_path=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
scheme=FoundationChat-iOS
destination=${FOUNDATIONCHAT_IOS_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0}
action=${1:-build}

if ! command -v xcodegen >/dev/null 2>&1; then
    print -u2 "XcodeGen не найден. Установите его командой: brew install xcodegen"
    exit 1
fi

if [[ ! -d "$xcode_path" ]]; then
    print -u2 "Xcode не найден: $xcode_path"
    exit 1
fi

cd "$project_root"
xcodegen generate --spec project.yml

case "$action" in
    build)
        DEVELOPER_DIR="$xcode_path" xcodebuild \
            -project FoundationChat.xcodeproj \
            -scheme "$scheme" \
            -destination "$destination" \
            build
        ;;
    test)
        DEVELOPER_DIR="$xcode_path" xcodebuild \
            -project FoundationChat.xcodeproj \
            -scheme "$scheme" \
            -destination "$destination" \
            test
        ;;
    open)
        open FoundationChat.xcodeproj
        ;;
    *)
        print -u2 "Использование: $0 [build|test|open]"
        exit 2
        ;;
esac
