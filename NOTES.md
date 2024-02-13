File Persistence Isolate:

Create long-lived worker isolate used for performing persist/hydrate.

On hydration, the worker isolate reads all files from the file system, parses their data and delivers it to the main isolate. It keeps a map of all
existing data it hydrated so that changes to collections that need to be re-persisted can just pass diffs to the isolate, not the full collections as that would
involve a lot of memory copying.

