### Added

- **Manual DNS sources**: a new extension, *Manual DNS*, for a DNS that has no extension. Each source has a name and its records pasted as CSV (`name,type,value[,ttl]`, optional header, `,` `;` or tab; A, AAAA and CNAME). *Preview* shows what will be read and every refused line with its reason, without saving. Each save replaces the source's records, attached to the servers and checked like those of OVHcloud, Technitium or Gandi (DNS page and tab, conflicts between sources, alerts); deleting a source deletes its records. Changes are logged in the journal.
