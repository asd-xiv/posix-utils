# Decisions

## Install records a receipt, it does not roll back

**2026-09-16**

`install` now writes `$XDG_STATE_HOME/posix-utils/receipt` before touching the
filesystem, recording `data_dir`, `bin_dir`, `group`, `ref`, and `archive_url`.
`uninstall` reads it and needs no options.

A partial install leaves both paths named in the receipt, so `uninstall` can
clean up without extra information.

**Rejected for now:** atomic installs via `<data-dir>.new` staging and swap.
`install` replaces an existing install, so a failed run would need to restore
the previous version rather than remove everything — requiring the old tree kept
aside, links rebuilt from it, and the previous ref recorded.

**Revisit when** upgrades must never break a working install.
