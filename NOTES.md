
Architecture assumptions:

* Assumes that there are more many more documents than there are reactive observers.
* Assumes that there are many more reads than writes.
* Assumes that groups of writes often happen in the same task of the event loop.