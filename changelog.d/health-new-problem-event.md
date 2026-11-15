### Fixed

- **New problems on a server already to watch are notified**: a server to watch (or critical) that gains another reason — reboot required on top of a full disk, a second disk, a reason that becomes critical — logs a new “to watch” / “critical” event naming only the new problem (“New problem on “web”, still to watch: reboot required”). Before, nothing was logged until the state itself changed. A measure that moves (a disk from 91 to 92 %) is not a new problem; the same applies to the Docker state.
