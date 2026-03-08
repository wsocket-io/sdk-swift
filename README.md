# wSocket SDK for Swift

Official Swift SDK for [wSocket](https://wsocket.io) — realtime pub/sub, presence, history, and push notifications for iOS, macOS, tvOS, and watchOS.

[![Swift](https://img.shields.io/badge/Swift-5.7+-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2015%20|%20macOS%2012%20|%20tvOS%2015%20|%20watchOS%208-blue.svg)](https://github.com/wsocket-io/sdk-swift)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/wsocket-io/sdk-swift.git", from: "0.1.0")
]
```

Or in Xcode: **File → Add Package Dependencies** → paste the repository URL.

## Quick Start

```swift
import WSocketIO

let client = WSocket(url: "wss://node00.wsocket.online", apiKey: "your-api-key")

client.onConnect {
    print("Connected!")
}

client.connect()

let channel = client.pubsub.channel("chat")

channel.subscribe { data, meta in
    print("Received: \(data ?? "nil")")
}

channel.publish(["text": "Hello from Swift!"])
```

## Presence

```swift
let channel = client.pubsub.channel("room")

channel.presence.enter(data: ["name": "Alice"])

channel.presence.onEnter { member in
    print("\(member.clientId) entered")
}

channel.presence.onLeave { member in
    print("\(member.clientId) left")
}

channel.presence.get()
channel.presence.onMembers { members in
    print("Online: \(members.count)")
}
```

## History

```swift
channel.history(limit: 50)
channel.onHistory { result in
    for msg in result.messages {
        print("\(msg.publisherId): \(msg.data ?? "nil")")
    }
}
```

## Push Notifications

```swift
let push = PushClient(baseUrl: "https://node00.wsocket.online", token: "secret", appId: "app1")

// Register device
push.registerAPNs(deviceToken: apnsToken, memberId: "user-123")

// Send to a member
push.sendToMember("user-123", payload: [
    "title": "New message",
    "body": "You have a new message"
])

// Broadcast
push.broadcast(payload: ["title": "Announcement", "body": "Server update"])

// Channel targeting
push.addChannel(subscriptionId: "sub-id", channel: "alerts") { result in }
push.removeChannel(subscriptionId: "sub-id", channel: "alerts") { result in }

// VAPID key
push.getVapidKey { result in }

// List subscriptions
push.listSubscriptions(memberId: "user-123") { result in }
```

## Requirements

- Swift 5.7+
- iOS 15.0+ / macOS 12.0+ / tvOS 15.0+ / watchOS 8.0+

## License

MIT
