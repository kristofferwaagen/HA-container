# Minimal Home Assistant Lab

Minimal reproducible baseline: template virtual light + Met weather.

## Quick Start

```
cp .env.example .env
docker compose up -d
```

Open http://localhost:8124 and create the first user.

## Entities Provided

- Lights
  - `light.lab_virtual_light` (state helper: `input_boolean.virtual_light_state`)
  - `light.virtual_living_room_light` (helper: `input_boolean.virtual_light_living_room`)
  - `light.virtual_bedroom_light` (helper: `input_boolean.virtual_light_bedroom`)
- Sensors
  - `sensor.living_room_temperature` (from `input_number.virtual_temp_living_room`)
  - `sensor.air_quality_index` (from `input_number.virtual_air_quality_index`)
- Camera
  - Add a Generic Camera via Settings → Devices & Services (YAML platform config is no longer supported).
- Weather
  - `weather.forecast_home` (friendly name: Oslo Weather)

## Automations

- `config/automations/example_toggle.yaml` (periodic toggle demo)
- `config/automations/lights_schedules.yaml` (sunset on, 23:30 off)
- `config/automations/virtual_values_drift.yaml` (drift temp/AQI values)
- `config/automations/air_quality_reacts.yaml` (react to AQI thresholds)

You can tweak the virtual values in the UI under Settings → Devices & Services → Helpers.

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

## Notes

- The container is bound to host port 8124 to avoid conflicts with other services using 8123. Change the `ports` mapping in `docker-compose.yml` if you prefer a different port.
