# Library backup and restore

Settings → Backup & Restore provides **Export Backup…** and **Import / Restore…** on Mac, iPhone and iPad. Backups are portable JSON, version1 (`ai.jotley.library-backup`), up to256MB. Jotley's current library has no saved audio files to package.

The file includes all current note text fields, original dates, transcript paragraphs, folder/tag relationships, note chat messages, markers and active custom summarization templates. It excludes account credentials, support conversations, device paths and runtime recording/generation state. Keep exported note text somewhere private.

Import validates the entire archive, supported fields, unique identifiers, template capacity and relationships before making changes. It requires transcription/generation to be idle and offers a native review sheet. Restore adds missing items. Existing note/template identifiers keep their current version; unambiguous matching folder/tag names are reused. A template-name collision gets a distinct “(restored)” name. Restored notes join normal private iCloud sync when enabled. It never deletes notes or replays an agent action or recording.

The Core Data additions save in one transaction; an error rolls them back while preserving pre-existing user edits. Prepared template data is applied after a successful note save. Old template deletion tombstones remain authoritative. A newer model with extra fields requires an updated backup format rather than silently omitting them.

Verification: six backup tests cover exact full-data round trips, repeated restore/newer edits, malformed archives, active-operation guards, database reopen, default-folder reuse, template-name collisions and capacity failure without a partial note import. Native Mac save/open/preview, empty-library restore and a second restore were checked using synthetic data. Mac and iOS Simulator builds passed. Mobile native document-picker acceptance and signed delivery are separate release gates; no personal library was restored or replaced during verification.
