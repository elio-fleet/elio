### Fixed

- **OVHcloud**: the "OVH network firewall disabled" health warning no longer shows for IPv6 blocks. OVHcloud has no network firewall for IPv6, so these blocks always came back without one; the health of every server is computed again after the upgrade, so the warning goes away by itself. The ports reachable in IPv6 are still reported by the optional "IPv6 not covered" warning.
