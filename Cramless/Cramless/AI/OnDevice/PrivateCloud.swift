#if HAS_IOS27_SDK
import Foundation
import FoundationModels

// Private Cloud Compute (tier T2, iOS 27). **Coded and off.** The model needs a managed entitlement Apple grants
// on request (developer.apple.com/private-cloud-compute). No entitlement key appears in any SDK header and none is
// guessed here: an unknown key can break provisioning. Nothing constructs this backend or reads its state while
// `AIBuild.privateCloudEnabled` is false, and the file is absent from builds with an older SDK.
//
// Turning it on is the owner's decision: the entitlement, a Private Cloud Compute line in the consent sheet, an
// `AIConsent.currentVersion` bump, and `AIRouter` passing `privateCloudAvailable` through to the route.

@available(iOS 27.0, *)
enum PrivateCloudModel {
    /// Available, and today's quota not used up.
    static func isAvailable() -> Bool {
        let model = PrivateCloudComputeLanguageModel()
        guard case .available = model.availability else { return false }
        return !model.quotaUsage.isLimitReached
    }
}

@available(iOS 27.0, *)
struct PrivateCloudBackend: OnDeviceBackend {
    func respond<C: OnDeviceCall>(_ call: C) async throws -> C.Output {
        let model = PrivateCloudComputeLanguageModel()
        guard model.isAvailable, !model.quotaUsage.isLimitReached else { throw OnDeviceError.unavailable }
        let session = LanguageModelSession(model: model, instructions: C.instructions)
        let response = try await session.respond(to: call.prompt, generating: C.Output.self, includeSchemaInPrompt: true,
                                                 options: GenerationOptions(temperature: C.temperature,
                                                                            maximumResponseTokens: C.responseTokens))
        return response.content
    }
}
#endif
