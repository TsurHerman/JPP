# An empty tuple has no tail to remove

`tail(())` asks the Tuple library to remove the first element of a tuple that has
none. Compilation must report `tail requires a nonempty tuple`. The tail of a
singleton is valid and is checked in `pack_values`.
