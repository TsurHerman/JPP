# A do block cannot capture a future binding

A callback captures the sequential environment at construction. Mentioning an
outer local whose initializer follows the do block is a frontend error, even
when the callback would only be invoked after that initializer.
