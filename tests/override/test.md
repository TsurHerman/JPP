# override

**Validates (README §1):** shadowing by position — BY CONTRAST. Two
programs, same calls: `plain` gets base's tag (1); `shadowed` leads
with `loud` (same signature, same rank) and gets 99, both at the
call site and inside `lib.probe`, a module that imports nothing.
Equal specificity, so position alone flips the answer.
