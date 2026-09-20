# A misspelled error is never an input variable

The UI spells `EndOfStream` as `EndOfStrem`. A qualified member is a lookup in a
defined native error set. The compiler rejects it even though the method is
unused. It must not introduce a new binder or invent a new failure.

Repair: spell the existing member `ReadError.EndOfStream`.
