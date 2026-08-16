#!/usr/bin/env bash

REDPANDA_IMAGE="docker.redpanda.com/redpandadata/redpanda:v25.2.7"
REDPANDA_CONTAINER="firemig-redpanda"
REDPANDA_DEFAULT_HTTP_URL="http://127.0.0.1:8082"
REDPANDA_SPEC="v25.2.7-single-node-v2"

ensure_redpanda_runtime_env() {
  local env_file="$1"

  if grep -q '^REDPANDA_HTTP_URL=' "$env_file"; then
    sed -i "s|^REDPANDA_HTTP_URL=.*$|REDPANDA_HTTP_URL=${REDPANDA_DEFAULT_HTTP_URL}|" "$env_file"
  else
    printf 'REDPANDA_HTTP_URL=%s\n' "$REDPANDA_DEFAULT_HTTP_URL" >>"$env_file"
  fi
}

redpanda_topic_partitions() {
  docker exec "$REDPANDA_CONTAINER" \
    rpk topic list -X brokers=127.0.0.1:9092 2>/dev/null | \
    awk '$1 == "firemig.commands" {print $2; exit}'
}

start_redpanda() {
  local data_dir="$1"
  local current_data_dir
  local current_image
  local current_spec
  local partitions
  local ready=0

  mkdir -p "$data_dir"
  chown 101:101 "$data_dir"
  chmod 0750 "$data_dir"

  if docker container inspect "$REDPANDA_CONTAINER" >/dev/null 2>&1; then
    current_image="$(docker inspect --format '{{.Config.Image}}' "$REDPANDA_CONTAINER")"
    current_spec="$(docker inspect --format '{{index .Config.Labels "io.runable.redpanda.spec"}}' "$REDPANDA_CONTAINER")"
    current_data_dir="$(docker inspect --format '{{index .Config.Labels "io.runable.redpanda.data-dir"}}' "$REDPANDA_CONTAINER")"

    if [[ "$current_image" != "$REDPANDA_IMAGE" || "$current_spec" != "$REDPANDA_SPEC" || "$current_data_dir" != "$data_dir" ]]; then
      docker rm -f "$REDPANDA_CONTAINER" >/dev/null
    fi
  fi

  if docker container inspect "$REDPANDA_CONTAINER" >/dev/null 2>&1; then
    if [[ "$(docker inspect --format '{{.State.Running}}' "$REDPANDA_CONTAINER")" != "true" ]]; then
      docker start "$REDPANDA_CONTAINER" >/dev/null
    fi
  else
    docker run -d \
      --name "$REDPANDA_CONTAINER" \
      --network host \
      --restart unless-stopped \
      --cpus 1 \
      --memory 512m \
      --memory-swap 512m \
      --health-cmd 'rpk cluster info -X brokers=127.0.0.1:9092 >/dev/null 2>&1' \
      --health-interval 5s \
      --health-timeout 3s \
      --health-retries 24 \
      --health-start-period 10s \
      --label "io.runable.redpanda.spec=$REDPANDA_SPEC" \
      --label "io.runable.redpanda.data-dir=$data_dir" \
      --volume "$data_dir:/var/lib/redpanda/data" \
      "$REDPANDA_IMAGE" \
      redpanda start \
      --node-id 0 \
      --smp 1 \
      --memory 384M \
      --reserve-memory 0M \
      --overprovisioned \
      --check=false \
      --kafka-addr internal://127.0.0.1:9092 \
      --advertise-kafka-addr internal://127.0.0.1:9092 \
      --pandaproxy-addr 127.0.0.1:8082 \
      --advertise-pandaproxy-addr 127.0.0.1:8082 \
      --rpc-addr 127.0.0.1:33145 \
      --advertise-rpc-addr 127.0.0.1:33145 >/dev/null
  fi

  for _attempt in $(seq 1 120); do
    if curl -fs --connect-timeout 1 --max-time 2 "$REDPANDA_DEFAULT_HTTP_URL/brokers" >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 0.5
  done

  if (( ready == 0 )); then
    echo "Redpanda did not become ready at $REDPANDA_DEFAULT_HTTP_URL/brokers" >&2
    docker logs --tail 40 "$REDPANDA_CONTAINER" >&2 || true
    return 1
  fi

  partitions="$(redpanda_topic_partitions)"
  if [[ -z "$partitions" ]]; then
    docker exec "$REDPANDA_CONTAINER" \
      rpk topic create firemig.commands --partitions 1 --replicas 1 \
      -X brokers=127.0.0.1:9092 >/dev/null
  fi

  for _attempt in $(seq 1 20); do
    partitions="$(redpanda_topic_partitions)"
    [[ -n "$partitions" ]] && break
    sleep 0.25
  done

  if [[ "$partitions" != "1" ]]; then
    echo "firemig.commands must have exactly one partition; found ${partitions:-none}" >&2
    return 1
  fi
}
