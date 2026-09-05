# TerseKit

`TerseKit` is the native Swift SDK for connecting iOS and macOS apps to Terse agents. It supports async requests, streamed agent events, presence, synchronized prompts, image uploads, reasoning deltas, and chat history.

## Requirements

- iOS 17 or later
- macOS 14 or later
- Swift 5.9 or later

## Installation

### Xcode

1. In Xcode, select **File → Add Package Dependencies…**.
2. Enter the repository URL:

   ```text
   https://github.com/TerseAI/TerseKit.git
   ```

3. Select the version you want to use.
4. Add `TerseKit` to your app target. Add `TerseUI` as well if you want the observable SwiftUI helpers.

### Package.swift

Add TerseKit to your package dependencies:

```swift
dependencies: [
    .package(
        url: "https://github.com/TerseAI/TerseKit.git",
        from: "0.1.0"
    )
]
```

Then add the products your target uses:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "TerseKit", package: "TerseKit"),
        .product(name: "TerseUI", package: "TerseKit")
    ]
)
```

`TerseUI` is optional. Omit it if you only need the core client.

Until the first tagged release is available, use the `main` branch instead:

```swift
.package(
    url: "https://github.com/TerseAI/TerseKit.git",
    branch: "main"
)
```

## Setup

Import the SDK and configure a `Terse` instance with the connection parameters for the current environment:

```swift
import Foundation
import TerseKit

let terse = Terse.connect(
    apiKey: "terse_dev_key",
    baseURL: URL(string: "http://127.0.0.1:8790")!
)
```

Fetch an agent, connect the current user, and keep the returned connection:

```swift
let agent = terse.agent("hello-world")
let connection = try await terse.connect(name: "Diane", to: agent)
```

Listen for live events and send prompts through the connection:

```swift
let eventTask = Task {
    for try await event in agent.events() {
        // Handle history, presence, prompt, reasoning, and text events.
    }
}

try await connection.sendPrompt("Hello from Swift")
```

Disconnect when the user leaves the agent:

```swift
eventTask.cancel()
try await terse.disconnect()
```

Each `Terse` instance supports one active agent connection at a time. `Terse` owns the connected user and presence heartbeat, `TerseAgent` exposes agent state and events, and `Connection` contains operations performed by that connected user.

## SwiftUI helpers

Import `TerseUI` to create observable agent and prompt-editor state:

```swift
import TerseUI

let observer = agent.observe()
let promptEditor = connection.promptEditor(observing: observer)

Task {
    await observer.observe()
}
```

Use `observer` for live messages, users, generation state, and connection status. Use `promptEditor` for synchronized prompt text, attachments, editing locks, and sending.

## Local development

To use a local checkout from another Swift package:

```swift
dependencies: [
    .package(path: "../terse-swift")
]
```

Run the test suite from this repository with:

```bash
swift test
```
