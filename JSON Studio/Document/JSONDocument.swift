// Document — Phase 3a. `JSONDocument: ReferenceFileDocument` (DC-01), `DocumentModel`
// (@Observable), and `ParseCoordinator` (debounce 150 ms + off-main parse + cancel, Phase 3c).
// Reads/writes UTF-8 and UTF-16 with/without BOM, detects encoding on open, preserves it on
// save (DC-09). External-change detection offers Reload / Keep (DC-10). Links JSONKit.
