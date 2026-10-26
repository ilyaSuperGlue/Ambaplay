import Foundation
import AmbaplayInstallerCore

enum InstallerMessage {
    static func describe(_ error: Error) -> String {
        guard let error = error as? InstallerError else { return error.localizedDescription }
        switch error {
        case .invalidRelease: return tr("The release information is invalid. Try again later.")
        case .networkFailure: return tr("Could not reach the release server. Check your connection and try again.")
        case .invalidDestination: return tr("The application location is not safe to update.")
        case .archiveTooLarge, .invalidArchiveLength: return tr("The download is incomplete or has an unexpected size. Try again.")
        case .signatureMismatch: return tr("The download could not be verified. Your installed application has been kept.")
        case .writeFailure: return tr("The download could not be saved. Check available space and folder permissions.")
        case .unsupportedSystem: return tr("This release requires a newer macOS version or an Apple silicon Mac.")
        case .invalidInstallation: return tr("The existing application could not be read. Check the application in Finder before trying again.")
        case .otherAppInstalled: return tr("Another application already uses the install location. Move it in Finder before trying again.")
        case .downgrade: return tr("A newer Ambaplay build is already installed. It has been kept.")
        case .alreadyCurrent: return tr("This Ambaplay version is already installed. Check again to continue.")
        case .appIsRunning: return tr("Quit Ambaplay and its updater, then try again.")
        case .installLocked: return tr("Another installation is in progress, or the installer lock cannot be accessed. Try again after it finishes.")
        case .appValidation: return tr("The downloaded application did not pass validation. Your installed application has been kept.")
        case .replacementFailure: return tr("The application could not be replaced. Check the app and its previous-version backup in Applications before trying again.")
        case .componentsFailure(let detail): return tr("Ambaplay is installed, but Steam, Apple's graphics or the engine could not be set up. Try again.") + "\n\n" + detail
        }
    }
}
