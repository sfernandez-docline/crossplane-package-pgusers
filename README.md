# crossplane-package-pgusers

Crossplane Configuration package que define el XRD `XPgUser` (namespaced) +
Composition `pguser` para gestión declarativa de usuarios PostgreSQL con
integración opcional al pool pgbouncer.

## Modelo

```yaml
apiVersion: db.docline.io/v1alpha1
kind: XPgUser
metadata: { name: ms-marketplace, namespace: infra-int }
spec:
  env: int
  username: ms-marketplace-int
  passwordSecretRef:
    name: ms-marketplace-pg
    namespace: infra-int
    key: ms-marketplace-int
  pgbouncer:
    enabled: true
  database:
    name: ms-marketplace-int
    adminRole: useradmin
```

La Composition emite:

1. `Role` provider-sql (postgresql.sql.m.crossplane.io/v1alpha1) que crea el
   role en PG usando la password del `passwordSecretRef`.
2. Si `pgbouncer.enabled: true`: un `Object` provider-kubernetes que CREA
   un Secret en ns `pgbouncer` con labels `pgbouncer.docline.io/enabled=true`
   + `pgbouncer.docline.io/env=<env>`, inyectando la password desde el
   Secret origen vía `spec.references.patchesFrom`. El sidecar
   `userlist-reloader` del Deployment `pgbouncer-<env>` (emitido por
   `crossplane-package-databases-bootstrap`) detecta el Secret via
   label-watch y manda `SIGHUP` — reload zero-downtime sin restart de pods.
3. Si `spec.database` set: `Database` + `Grant` (`<adminRole>` MEMBER OF user).

## Add / remove / toggle

- **Add usuario al pool desde cualquier repo**: crear `XPgUser` con
  `pgbouncer.enabled: true` apuntando a un Secret con la password. Sin
  restart del Deployment pgbouncer.
- **Toggle pool sin tocar PG**: flip `pgbouncer.enabled: true ↔ false`. Solo
  cambia el Object (y por tanto el Secret etiquetado en `pgbouncer` ns).
  El Role en PG permanece intacto.
- **Remove**: borrar el `XPgUser` — Crossplane revoca Role, Database y
  Grant, y borra el Secret en `pgbouncer` ns. SIGHUP automático.

## Dependencias

- `crossplane-contrib/function-kcl` (Composition rendering)
- `crossplane-contrib/provider-sql` (Role, Database, Grant en PG)
- `crossplane-contrib/provider-kubernetes` (Object que crea el Secret destino)

## Build local

```sh
make build VERSION=v0.1.0
make push  VERSION=v0.1.0
```

Releases automáticos vía semantic-release + Argo Workflow `release.yaml`
(ver `workflows/`). Convencional Commits → tag semver + xpkg en ghcr.io.
