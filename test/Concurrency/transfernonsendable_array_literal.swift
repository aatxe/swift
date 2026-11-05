// RUN: %target-swift-frontend -emit-sil -swift-version 6 -verify %s -o /dev/null

// REQUIRES: concurrency

// Collection literals store their elements through the collection's
// _BridgeStorage. Region analysis treats a non-Sendable value projected out of
// a Sendable aggregate as a fresh root, so if _BridgeStorage were Sendable the
// stored element would not be merged into the collection's region and sending
// the collection would not send the element.

////////////////////////
// MARK: Declarations //
////////////////////////

final class NonSendable: Hashable {
  var value = 0

  static func == (lhs: NonSendable, rhs: NonSendable) -> Bool { lhs === rhs }
  func hash(into hasher: inout Hasher) {}
}

func consume(_ x: sending [NonSendable]) {}
func consume(_ x: sending [Int: NonSendable]) {}
func consume(_ x: sending Set<NonSendable>) {}

/////////////////
// MARK: Tests //
/////////////////

// FIXME: The temporary array is named after _finalizeUninitializedArray rather
// than being described by its type.
func arrayLiteral() {
  let p = NonSendable()
  consume([p]) // expected-error {{risks causing data races}}
  // expected-note @-1 {{used after being passed as a 'sending' parameter}}
  p.value = 1 // expected-note {{access can happen concurrently}}
}

func arrayLiteralViaLocal() {
  let p = NonSendable()
  let arr = [p]
  consume(arr) // expected-error {{sending 'arr' risks causing data races}}
  // expected-note @-1 {{'arr' used after being passed as a 'sending' parameter}}
  p.value = 1 // expected-note {{access can happen concurrently}}
}

func dictionaryLiteral() {
  let p = NonSendable()
  consume([0: p]) // expected-error {{sending value of non-Sendable type '[Int : NonSendable]' risks causing data races}}
  // expected-note @-1 {{Passing value of non-Sendable type '[Int : NonSendable]' as a 'sending' argument to global function 'consume' risks causing races in between local and caller code}}
  p.value = 1 // expected-note {{access can happen concurrently}}
}

func setLiteral() {
  let p = NonSendable()
  consume([p] as Set) // expected-error {{sending value of non-Sendable type 'Set<NonSendable>' risks causing data races}}
  // expected-note @-1 {{Passing value of non-Sendable type 'Set<NonSendable>' as a 'sending' argument to global function 'consume' risks causing races in between local and caller code}}
  p.value = 1 // expected-note {{access can happen concurrently}}
}
