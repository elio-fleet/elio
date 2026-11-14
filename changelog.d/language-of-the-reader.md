### Changed

- **The language of a new installation** is the one its first administrator set it up in (it was always English): emails, runs and channels without their own language follow it.
- **Runs and automation results in the reader's language** ("8/8 servers inventoried" showed in English in the French interface of an English installation): the label of a run and the result of the inventories, the reachability check and the key scan are written for each reader. Older runs keep their text.
- **The invitation page** is in the language chosen for the invitation (that of its email and of the account it creates), no longer in the browser's.

### Upgrading

- One migration (`background_tasks.localized_label`), run on start as usual.
