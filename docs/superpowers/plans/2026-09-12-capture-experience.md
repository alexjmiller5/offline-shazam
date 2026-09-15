# Capture Experience Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development for independent implementation and review.

**Goal:** Make recording cancellable, delivery self-recovering and accurately explained, and Shortcuts usable through Dynamic Island with coalesced result notifications.

**Architecture:** Keep the durable queue and background URLSession. Add native recording Live Activity and per-capture notification coordination. Enrollment checks use the existing capture service authentication boundary and never submit a valid capture.

**Tech Stack:** SwiftUI, ShazamKit, ActivityKit, AppIntents, SwiftData, UserNotifications, URLSession.

**Spec:** ../specs/2026-09-12-capture-experience-design.md

## Global constraints

No analytics, alternate recognizer, personal values, or secrets in code. Preserve pending captures and validated receipts. Force quit recovery happens on explicit user invocation, never through fabricated background guarantees.

### Task 1: Cancellable recording and recording Live Activity

Own App/AudioRecorder.swift, App/CaptureController.swift, App/Intents.swift, new shared Live Activity models/Widget files, project.yml and recording/controller tests. Keep ContentView and Runtime integration as a clearly described handoff for the root agent. Tests first: cancel before and after useful audio, preserve interrupted audio, repeated capture after cancel, intent metadata not foreground on iOS 18+, Live Activity state transitions. Use controller.cancelCapture() with scoped recording task cancellation; explicitly discarded capture throws CancellationError before store persistence. Build the real widget target and validate availability and extension embedding.

### Task 2: Coalesced native notifications

Own App/Notifications.swift, notification tests and notification-only fields/methods in CaptureStore.swift. Provide a coordinator that observes durable matched/delivered records, schedules recognition after 10 seconds, replaces by capture identifier on confirmed delivery, and records notification progress only after scheduling succeeds. Expose a reconciliation entry point root can call from controller/delivery callbacks and an authorization request entry point. Tests first: immediate delivery one combined request, delayed delivery same identifier without second sound, retry/relaunch dedupe, denied authorization no queue failure. Do not edit Runtime/ContentView/Delivery/controller.

### Task 3: Connection failure and integration

Root owns Delivery.swift, Configuration.swift, Runtime.swift, ContentView.swift and connection/UI tests. Inspect phone's durable status before editing; reproduce failing condition through UI/native integration. Add a non-mutating credentials check using malformed payload/authenticated validation response, with no redirect following or false positive on arbitrary 422. Distinguish setup/auth/internet/service failures and retain retry behavior. Reconnect must trigger recovery while executing, including intent execution. Wire cancellation, notification authorization and coordinator. Tests must prove stuck work can proceed after repair and reconnect and configuration persists.

### Task 4: Review, release and physical acceptance

Run native and UI tests with local custom-catalog recognition, mutate critical new assertions, inspect UI screenshots, and independently review whole diff. Build signed app and extension, verify signatures, install updated app, preserve enrollment. Commit all safe changes and push main (no deployment workflow). Record validation and remaining physical checks in the existing Notion build task. Physical acceptance covers cancellation, background Shortcut after swipe-away, Dynamic Island, notification permission, and actual Spotify confirmation.
