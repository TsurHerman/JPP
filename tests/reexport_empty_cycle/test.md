# Cyclic declarations do not implement a word

Mutual exports without bodies must produce a normal missing-method error, not a recursive metadata dependency or a synthetic fallback candidate.
