# Module values retain their identity and declaration home

Module constants are immutable comptime declarations. They admit names, member
paths, scalar literals and explicit Zig grounds. Dependencies may point forward;
cycles are errors. Ordinary calls in initializers remain a separate staging task.

Native namespace/type members and enum cases use generic member access. Constants
survive folder facades, re-export chains and public import-cycle units; private
declarations stay file-local. Each method's constants and fixed patterns resolve
in its lexical source context, independently of caller bindings. Defined enum
constants can be repeated in positional patterns and remain static through calls.
