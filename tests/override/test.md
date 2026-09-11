# override

**Validates (README §1):** shadowing by position — BY CONTRAST. Two
programs, same calls: `plain` gets base's tag (1); `shadowed` leads
with `loud` (same signature, same rank) and gets 99, both at the
call site and inside `lib.probe`, a module that imports nothing.
Equal specificity, so position alone flips the answer.

The absent `tag` dependency in `lib` is a current language gap, not a
promise that names acquire lexical definitions from callers. A future
contract check must repair this fixture while preserving both answers;
see `design/word_contracts.md`.
