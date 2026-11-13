# vps branch

This branch is Evolution API `2.3.7` with the smallest changes needed to run it
through the `vps-admin` Node pipeline on the VPS (systemd unit with a fixed
`ExecStart=node dist/index.js`, `GET /saude` health check, `npm run db:migrar`,
`ProtectSystem=strict`). Without the `EVOLUTION_DADOS` variable it behaves like
upstream.

## Patches

| File | Change | Why |
|---|---|---|
| `package.json` | `build` is `db:generate && tsup` (no `tsc`); new `typecheck` keeps `tsc --noEmit` | the deploy build runs outside the unit's memory limit; with `tsc` it peaked at 2.2 GB |
| `tsup.config.ts` | entries `src/main.ts` and `src/index.ts` only, `cjs` only | `entry: ['src']` bundles every file separately: 1.2 GB peak, now ~150 MB |
| `package.json` | new `db:migrar` → `db:deploy` | name the pipeline runs |
| `package.json` | `prepare` is `true` | husky needs `.git`, which deploys don't have |
| `package-lock.json` | adds `@img/sharp-libvips-linux-x64@1.2.4` | upstream lock only has the musl (Alpine) build; `sharp` fails on Debian |
| `src/index.ts` | `import './main';` | tsup builds all of `src/`, so this yields `dist/index.js` |
| `src/api/routes/index.router.ts` | `GET /saude` → `{"status":"ok"}` | deploy health check; no auth, no data |
| `src/config/path.config.ts` | `INSTANCE_DIR`, `AUTH_DIR`, `STORE_DIR` under `EVOLUTION_DADOS` | sessions survive deploys and rollbacks; release dir is read-only |
| `src/main.ts`, `src/api/abstract/abstract.repository.ts` | use `STORE_DIR` instead of `ROOT_DIR/store` | same reason |

Required env beyond upstream defaults: `DATABASE_SAVE_DATA_INSTANCE=true`
(without it Baileys has no auth state and instance creation fails).

## Files in this folder

- `smoke.sh` — typechecks, builds, migrates against a throwaway Postgres 17 (Docker), boots,
  checks `/saude` and where instance data is written. `SMOKE_SEM_DADOS=1` runs it
  without `EVOLUTION_DADOS`.
- `instalar.sh` — one-time VPS setup, run from the PC after creating the app in
  the painel.

## Upgrading to a new Evolution version

```bash
git fetch upstream --tags
git switch -c vps-<new> <new-tag>
git cherry-pick <first vps commit>..vps   # or re-apply the table above by hand
npm install --save-optional @img/sharp-libvips-linux-x64@<version sharp expects>
bash vps/smoke.sh && SMOKE_SEM_DADOS=1 bash vps/smoke.sh
```

Then point the app's branch at the new one (or fast-forward `vps`) and deploy.
