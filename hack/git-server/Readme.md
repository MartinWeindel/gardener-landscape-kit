## Start server

```bash
make git-server-up
```

## Access Web UI

http://localhost:5123/test

```txt
> User: `test`  
> Password: `testtest`
```

## Clone

- Base repo
```bash
git clone http://test:testtest@git.local.gardener.cloud:5123/test/base.git
```

- Test landscape repo
```bash
git clone http://test:testtest@git.local.gardener.cloud:5123/test/test-landscape.git
```

## Configure Git Remote in Landscape Repo

`git-sync-secret.yaml`:
```yaml
stringData:
  password: testtest
  username: test
```

`gotk-sync.yaml`:
```yaml
  url: http://git.local.gardener.cloud:3000/test/test-landscape
```

## Gardener Local Configurations

`helm-release.yaml`:
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: gardener-operator
  namespace: garden
spec:
  values:
    env:
      - name: GARDENER_OPERATOR_LOCAL
        value: "true"
    hostAliases:
      - hostnames:
          - api.virtual-garden.local.gardener.cloud
        ip: 10.2.10.2
        # config:
        # featureGates:
        # IstioTLSTermination: true
        # VPAInPlaceUpdates: true
```

`kustomization.yaml`:
```yaml
patches:
  - path: helm-release.yaml
```
