# base_folder

The bundled `Base/` is a namespace with a customary `Base/Base.jpp` facade.
`using Base` imports its selected arithmetic, Any/order, tuple utilities, and
test assertions without separate leaf imports. The facade explicitly imports
`Base.*`, which excludes itself and gathers sibling files/subfolder interfaces.
The second program demonstrates direct `Base.Arithmetic`, `Base.Any`, and
`Base.Test` imports. These remain ordinary authored context entries.
