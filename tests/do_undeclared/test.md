# Dormant callbacks retain lexical declarations

The callback is neither constructed nor invoked, but its missing word still
fails lexical declaration checking. A later invoking context cannot repair it.
