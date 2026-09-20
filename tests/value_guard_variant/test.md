# Send text packets to the text decoder

A packet receiver accepts three kinds of packet:

| Received packet | Contents | Handler |
|---|---|---|
| Text | `"hello"` | Text decoder |
| Count | `42` | Control handler |
| Ping | No contents | Control handler |

The application declares one special rule and a default:

```jpp
route(packet<:Any) where needsTextDecoder(packet) = "text decoder"
route(<:Any) = "control handler"
```

`needsTextDecoder` checks the selected packet type. It does **not** inspect the
message contents. The compiler knows that each text packet qualifies and each
other packet does not, so it can build the complete dispatch table before the
program runs. The runtime receiver still supplies the actual tag and contents.

The source separates two jobs deliberately:

```jpp
needsTextDecoder(packet::T) where T = isTextPacket(T)
textBytes(packet<:Any) where needsTextDecoder(packet) = byteCount(packet.payload)
```

The predicate uses the selected type/tag as a compile-time fact. The selected
method later reads the runtime payload. The five-byte text produces `5`; count
and ping packets use a default of `0` without attempting to read a text field.

The ground `hasTextTag` bridges native type reflection. It receives type values,
not an invented or undefined runtime packet. Guards that inspect runtime
payload data are not supported by this increment and must be rejected.
