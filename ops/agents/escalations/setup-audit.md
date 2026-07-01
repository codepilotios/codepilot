# Setup Audit Escalation

Date: 2026-07-01

Remote Desktop pairing needs human review before public beta. The iOS pairing screen shows a pairing code field, but the current flow signs the challenge and the Mac approves the device immediately after `pairing.complete`; the Mac-side Approve/Reject UI is not part of the happy path. Because Remote Desktop controls the Mac, decide whether bearer-token possession is enough for pairing or whether pairing must require explicit Mac-side approval and clearer user copy.
