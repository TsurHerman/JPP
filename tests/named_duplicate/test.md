# One parcel cannot supply its weight twice

The call supplies `grams = 1` and `grams = 2`. Named arguments are not a sequence of
overwrites: the frontend must report `DuplicateNamedArgument` before binding.
