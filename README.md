# Minimal Home Assistant Lab

Minimal reproducible baseline: template virtual light + Met weather.

## Quick Start

```
cp .env.example .env
docker compose up -d
```

Open http://localhost:8123 and create the first user.

## Entities Provided

- `light.lab_virtual_light` (state helper: `input_boolean.virtual_light_state`)
- `weather.forecast_home` (friendly name: Oslo Weather)

## Optional Automation

`config/automations/example_toggle.yaml` (periodic toggle). Remove if undesired.

## Snapshot

```
./scripts/snapshot.sh baseline
```

Produces `snapshots/ha-snapshot-<timestamp>-baseline.tar.gz`.

## Digest Pin (Optional)

```
docker image inspect homeassistant/home-assistant:${HA_VERSION} --format '{{json .RepoDigests}}'
```

Put digest in `.env` as `HA_IMAGE_DIGEST` and switch compose image reference.

## Clean / Reset

```
docker compose down -v
docker compose up -d
```

## Restart running instance

```
docker compose restart homeassistant
```

## CI

Script `scripts/check_entities.sh` asserts presence of virtual light + weather and absence of legacy entities.
