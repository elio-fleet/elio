### Changed

- **Unreachable servers**: a server is declared unreachable (journal and notifications) after two failed checks in a row, not at the first lost connection. A server never seen answering (just added with a wrong port, address being changed) no longer logs "unreachable" or "back online"; its badge still shows the last check.
