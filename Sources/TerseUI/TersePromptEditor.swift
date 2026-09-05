import Foundation
import Observation
import TerseKit

@MainActor
@Observable
public final class TersePromptEditor {
    public private(set) var text = ""
    public private(set) var attachments: [ImageAttachmentResponse] = []
    public private(set) var isSubmitting = false
    public private(set) var errorMessage: String?

    public var editingUser: ConnectedUser? { promptLock?.user }
    public var isEditing: Bool { promptLock != nil }
    public var isGenerating: Bool { observer.isGenerating }

    public var isBusy: Bool { isGenerating || isSubmitting }
    public var ownsLock: Bool {
        promptLock?.lockId == activePromptLockID
    }
    public var isLockedByAnother: Bool {
        promptLock != nil && !ownsLock
    }
    public var isLockPending: Bool {
        activePromptLockID != nil && !ownsLock && !isLockedByAnother
    }
    public var canEdit: Bool {
        observer.status == .connected && !isBusy && !isLockedByAnother
    }
    public var canSend: Bool { canEdit && ownsLock }

    private let connection: Connection
    private let observer: TerseAgentObserver
    private let maximumMessageLength: Int
    private var promptLock: PromptLockResponse? { observer.promptLock }
    private var eventHandlerID: UUID?
    private var promptLockRefreshTask: Task<Void, Never>?
    private var textSyncTask: Task<Void, Never>?
    private var promptReleaseTask: Task<Void, Never>?
    private var activePromptLockID: String?
    private var lastPromptLockStartedAt: Double = 0
    private var textSequence = 0

    init(
        connection: Connection,
        observer: TerseAgentObserver,
        maximumMessageLength: Int
    ) {
        self.connection = connection
        self.observer = observer
        self.maximumMessageLength = maximumMessageLength
        if let draft = observer.promptDraft {
            text = draft.text
            attachments = draft.attachments
            textSequence = draft.sequence
        }
        eventHandlerID = observer.addEventHandler { [weak self] event in
            self?.receive(event)
        }
    }

    public func close() async {
        endEditing()
        await promptReleaseTask?.value
        promptReleaseTask = nil
        promptLockRefreshTask?.cancel()
        promptLockRefreshTask = nil
        if let eventHandlerID {
            observer.removeEventHandler(eventHandlerID)
            self.eventHandlerID = nil
        }
    }

    public func beginEditing() {
        guard canEdit, activePromptLockID == nil else {
            return
        }

        let lockID = UUID().uuidString
        let now = (Date().timeIntervalSince1970 * 1_000).rounded(.down)
        let startedAt = max(now, lastPromptLockStartedAt + 1)
        lastPromptLockStartedAt = startedAt
        activePromptLockID = lockID
        textSequence = 0

        promptLockRefreshTask = Task { [weak self] in
            while let self, self.activePromptLockID == lockID, !self.isSubmitting {
                do {
                    let lock = try await connection.acquirePromptLock(
                        lockID: lockID,
                        startedAt: startedAt
                    )
                    guard self.activePromptLockID == lockID else {
                        if lock.lockId == lockID {
                            try? await connection.releasePromptLock(lockID: lockID)
                        }
                        return
                    }
                    guard lock.lockId == lockID else {
                        self.activePromptLockID = nil
                        self.promptLockRefreshTask = nil
                        return
                    }
                    self.schedulePromptDraftSync(delayNanoseconds: 0)
                    try await Task.sleep(nanoseconds: 7_500_000_000)
                } catch is CancellationError {
                    return
                } catch {
                    guard self.activePromptLockID == lockID else { return }
                    self.activePromptLockID = nil
                    self.promptLockRefreshTask = nil
                    self.errorMessage = error.localizedDescription
                    return
                }
            }
        }
    }

    public func endEditing() {
        promptLockRefreshTask?.cancel()
        promptLockRefreshTask = nil
        textSyncTask?.cancel()
        textSyncTask = nil
        guard let lockID = activePromptLockID else { return }
        let text = text
        let attachments = attachments
        let sequence = nextPromptDraftSequence()
        activePromptLockID = nil
        promptReleaseTask = Task {
            _ = try? await connection.updatePromptDraft(
                lockID: lockID,
                text: text,
                sequence: sequence,
                attachments: attachments
            )
            try? await connection.releasePromptLock(lockID: lockID)
        }
    }

    public func setText(_ value: String) {
        let nextText = String(value.prefix(maximumMessageLength))
        guard nextText != text else { return }
        text = nextText
        schedulePromptDraftSync()
    }

    public func addAttachment(_ attachment: ImageAttachmentResponse) {
        guard
            canEdit,
            attachments.count < 4,
            !attachments.contains(where: { $0.id == attachment.id })
        else { return }
        attachments.append(attachment)
        schedulePromptDraftSync()
    }

    public func removeAttachment(_ attachmentID: String) {
        guard canEdit else { return }
        let next = attachments.filter { $0.id != attachmentID }
        guard next.count != attachments.count else { return }
        attachments = next
        schedulePromptDraftSync()
    }

    @discardableResult
    public func send() async -> Bool {
        let value = text
        let prompt = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumMessageLength))
        guard
            !prompt.isEmpty,
            canSend,
            let promptLockID = activePromptLockID
        else { return false }

        promptLockRefreshTask?.cancel()
        promptLockRefreshTask = nil
        textSyncTask?.cancel()
        textSyncTask = nil
        isSubmitting = true
        errorMessage = nil
        let promptAttachments = attachments

        do {
            try await connection.sendPrompt(
                prompt,
                promptLockID: promptLockID,
                attachments: promptAttachments
            )
            activePromptLockID = nil
            text = ""
            attachments = []
            isSubmitting = false
            return true
        } catch {
            activePromptLockID = nil
            errorMessage = error.localizedDescription
            isSubmitting = false
            return false
        }
    }

    private func nextPromptDraftSequence() -> Int {
        textSequence += 1
        return textSequence
    }

    private func schedulePromptDraftSync(delayNanoseconds: UInt64 = 75_000_000) {
        textSyncTask?.cancel()
        guard let lockID = activePromptLockID else { return }

        let text = text
        let attachments = attachments
        let sequence = nextPromptDraftSequence()
        let connection = connection
        textSyncTask = Task { [weak self] in
            do {
                if delayNanoseconds > 0 {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                }
                _ = try await connection.updatePromptDraft(
                    lockID: lockID,
                    text: text,
                    sequence: sequence,
                    attachments: attachments
                )
            } catch is CancellationError {
                return
            } catch {
                guard
                    let self,
                    self.activePromptLockID == lockID,
                    self.ownsLock
                else { return }
                self.errorMessage = "Could not sync the shared prompt. \(error.localizedDescription)"
            }
        }
    }

    private func receive(_ event: Event) {
        switch event {
        case .promptLockChanged(let lock):
            if let lock, lock.lockId != activePromptLockID {
                activePromptLockID = nil
                promptLockRefreshTask?.cancel()
                promptLockRefreshTask = nil
                textSyncTask?.cancel()
                textSyncTask = nil
            }

        case .promptDraftChanged(let draft):
            if draft.lockId == activePromptLockID {
                textSequence = max(textSequence, draft.sequence)
            } else {
                text = draft.text
                attachments = draft.attachments
            }

        case .generationStarted:
            errorMessage = nil
            text = ""
            attachments = []
            activePromptLockID = nil
            promptLockRefreshTask?.cancel()
            promptLockRefreshTask = nil
            textSyncTask?.cancel()
            textSyncTask = nil

        case .generationFailed(_, let message):
            errorMessage = message

        default:
            break
        }
    }
}

public extension Connection {
    @MainActor
    func promptEditor(
        observing observer: TerseAgentObserver,
        maximumMessageLength: Int = 4_000
    ) -> TersePromptEditor {
        TersePromptEditor(
            connection: self,
            observer: observer,
            maximumMessageLength: maximumMessageLength
        )
    }
}
