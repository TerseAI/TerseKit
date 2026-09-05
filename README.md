# Terse Swift client

`TerseKit` is the native Swift client for the provider-neutral Terse agent API. It supports iOS 17+, macOS 14+, async request APIs, streamed room events, shared composer leases, synchronized drafts, image uploads, and chat history.

## Add the package locally

Add `packages/terse-swift` as a local package in Xcode, or reference it from another Swift package:

```swift
dependencies: [
    .package(path: "../terse-swift"),
]
```

Then add `TerseKit` to the target and import it:

```swift
import Foundation
import TerseKit

let terse = Terse.connect(
    apiKey: "terse_dev_key",
    baseURL: URL(string: "http://127.0.0.1:8790")!
)
let agent = terse.agent("hello-world")
try await terse.connect(name: "Diane", to: agent)

let eventTask = Task {
    for try await event in agent.events() {
        // Handle room-wide history, presence, composer, reasoning, and text events.
    }
}

try await agent.sendPrompt("Hello from Swift")
eventTask.cancel()
try? await eventTask.value
try await terse.disconnect()
```

`Terse` owns its connected user and presence heartbeat. `TerseAgent` owns the room operations: events, active users, composer state, prompts, uploads, and history. Each `Terse` instance allows one active agent connection at a time; disconnect it before connecting that instance to another agent.

Run the package tests independently with:

```bash
swift test --package-path packages/terse-swift
```
