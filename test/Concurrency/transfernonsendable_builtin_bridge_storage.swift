// RUN: %target-swift-frontend -emit-sil -swift-version 6 -parse-stdlib -verify %s -o /dev/null

// REQUIRES: concurrency

// These tests model the shape of Array's storage: a non-Sendable wrapper whose
// heap buffer is reached through a struct holding a Builtin.BridgeObject (like
// the stdlib's _BridgeStorage). Region analysis treats a non-Sendable value
// projected out of a Sendable aggregate as a fresh root, so the storage struct
// must not be Sendable or a value stored into the buffer is not merged into the
// wrapper's region.

import Swift

////////////////////////
// MARK: Declarations //
////////////////////////

final class NonSendable {
  var value = 0
}

// Stand-in for the array's heap buffer.
final class Buffer {
  var element: NonSendable? = nil
}

///////////////////////////////////////////////////////
// MARK: Wrapper holds the buffer directly (control) //
///////////////////////////////////////////////////////

struct DirectArray<Element> {
  var buffer: Buffer
}
extension DirectArray: @unchecked Sendable where Element: Sendable {}

func consume(_ x: sending DirectArray<NonSendable>) {}

func directBuffer() {
  let p = NonSendable()
  let arr = DirectArray<NonSendable>(buffer: Buffer())
  let buf = arr.buffer
  buf.element = p
  consume(arr) // expected-error {{sending 'arr' risks causing data races}}
  // expected-note @-1 {{'arr' used after being passed as a 'sending' parameter}}
  p.value = 1 // expected-note {{access can happen concurrently}}
}

////////////////////////////////////////////////////////////////////
// MARK: Buffer reached through non-Sendable BridgeObject storage //
////////////////////////////////////////////////////////////////////

// This has the same shape as _BridgeStorage.  Since Builtin.BridgeObject is not Sendable,
// this struct is not inferred Sendable. This allows us to correctly detect races with their contents.
@frozen
@usableFromInline
internal struct BridgeStorage {
  @usableFromInline
  internal var rawValue: Builtin.BridgeObject

  init(native: Buffer) {
    rawValue = Builtin.reinterpretCast(native)
  }
}

@available(*, unavailable)
extension BridgeStorage: Sendable {}

struct BridgedArray<Element> {
  var storage: BridgeStorage
}
extension BridgedArray: @unchecked Sendable where Element: Sendable {}

func consume(_ x: sending BridgedArray<NonSendable>) {}

func bridgedBuffer() {
  let p = NonSendable()
  let arr = BridgedArray<NonSendable>(storage: BridgeStorage(native: Buffer()))
  let buf: Buffer = Builtin.castReferenceFromBridgeObject(arr.storage.rawValue)
  buf.element = p
  consume(arr) // expected-error {{sending 'arr' risks causing data races}}
  // expected-note @-1 {{'arr' used after being passed as a 'sending' parameter}}
  p.value = 1 // expected-note {{access can happen concurrently}}
}
