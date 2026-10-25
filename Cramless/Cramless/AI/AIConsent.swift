import Foundation

/// Cloud AI consent. `settings.cloudConsentVersion` holds the version the person accepted (0: never); a request
/// goes to the relay only while it is at least `currentVersion`. Sending page photos is a separate switch
/// (`settings.sendPhotos`) that only counts together with this consent.
enum AIConsent {
    /// Version 1: page text, typed answers and tutor questions go to Anthropic's models through Capling's relay;
    /// page photos only with the second switch; nothing is used for training. **Bump it when a request starts to
    /// carry a new kind of data or reaches a new processor** (for example switching on Private Cloud Compute), so
    /// everyone is asked again under the new terms.
    static let currentVersion = 1

    /// Who processes cloud requests, named in the consent sheet.
    static let processor = "Anthropic"

    static func isGranted(_ settings: AppSettings) -> Bool {
        settings.cloudConsentVersion >= currentVersion
    }

    /// Page photos may be sent: consent plus the photos switch.
    static func photosGranted(_ settings: AppSettings) -> Bool {
        isGranted(settings) && settings.sendPhotos
    }
}
