# An unused method still needs a declared predicate

The signature refers to `Missing` as a predicate, but no module defines or imports
it. The method is never called; lexical validation must still report the undeclared
predicate. Otherwise typos could remain hidden until a future call.
