import CoreText
import Foundation

/// Регистрирует встроенные шрифты приложения в текущем процессе.
enum AppFonts {
    /// Регистрирует все `.ttf`/`.otf` из ресурсов бандла.
    ///
    /// Шрифты ищутся и в корне ресурсов, и в подпапке `Fonts`:
    /// в зависимости от настроек проекта XcodeGen кладёт файлы плоско
    /// или сохраняет папку. Повторный вызов безопасен — CoreText
    /// отклоняет уже зарегистрированные файлы без падения.
    static func register() {
        var urls = Set<URL>()

        for ext in ["ttf", "otf"] {
            let root = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? []
            let directory = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: "Fonts") ?? []
            urls.formUnion(root)
            urls.formUnion(directory)
        }

        for url in urls {
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
