# Multiple drafts

Implemented, awaiting manual verification by the owner. No app, build, analyzer, or tests were run for this change, as requested. Existing persistence tests describe the previous two-slot behavior and have not been updated or rerun for this change.

- New video starts a separate project and preserves existing drafts. An untouched empty editor does not create a draft; importing/editing or explicitly saving does.
- Every successful edit autosaves into the current draft. Save project flushes that same draft. Opening another project from the editor first saves current edits.
- The home screen and Projects tab list persisted drafts, newest edits first. Tap to resume; the overflow menu offers Rename and Delete. Delete asks for confirmation.
- Existing recovery draft and explicit saved snapshot migrate on first library access. Identical snapshots are deduplicated; different snapshots appear as separate projects. Legacy files remain backups and are never reimported once the library exists, even after deleting every draft.
- Storage is a versioned library envelope in Android AtomicFile (`projects/library.charpcut.json`) containing independently identified engine JSON documents plus names and edit dates. Rust remains authoritative for project editing and validation. No Rust bridge changes.
- Session operations serialize edits, migration, save, rename, and delete. The in-memory library changes only after a successful atomic write. Failed autosaves surface errors, and switching projects retries saving those edits before proceeding.
- Deleting a draft removes its entry and project JSON from the active library. Imported video copies are retained because multiple drafts can reference them. Reference-aware media cleanup and project duplication remain future work.

Stop the existing app session and run `flutter run` again manually: Android now accepts the library storage slot, requiring a full restart.

Manual acceptance: retain two different old snapshots through migration; create two new videos; reopen each and confirm independent edits after restart; rename a draft; cancel and confirm deletion; delete the last draft and restart to confirm it stays deleted. Storage-error recovery and invalid project handling also remain unverified.
