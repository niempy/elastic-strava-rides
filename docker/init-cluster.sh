# Check if dependencies are met
if docker compose >/dev/null 2>&1; then
  COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE="docker-compose"
else
  abort "missing docker compose"
fi

# Initialize help vars
. .env
HEADERS=(
  -H "kbn-version: ${STACK_VERSION}"
  -H "kbn-xsrf: kibana"
  -H 'Content-Type: application/json'
)
CURL="curl -k --silent --user ${ELASTIC_USERNAME}:${ELASTIC_PASSWORD}"
export https_proxy=
export HTTPS_PROXY=

# Start cluster until kibana and wait for kibana to become healthy (see docker-compose.yml: kibana healthy = Kibana API is available)
echo "==== Starting kibana and dependencies ===="
$COMPOSE up -d --wait kibana
echo "===> Kibana healthy"
echo

# Configure Fleet settings
echo "==== Configure Fleet settings ===="
# Set Fleet server host
printf '{"fleet_server_hosts": ["%s"]}' "https://fleet-server:${FLEET_PORT}"| \
  $CURL -XPUT "${HEADERS[@]}" "${LOCAL_KBN_URL}/api/fleet/settings" -d @-| \
  grep -q '"item"'
# Set default output host and trusted fingerprint
printf '{"hosts": ["%s"]}' "https://es01:9200"| \
  $CURL -XPUT "${HEADERS[@]}" "http://kibana:5601/api/fleet/outputs/fleet-default-output" -d @-| \
  grep -q '"item"'
fingerprint=$(${COMPOSE} exec -w /usr/share/elasticsearch/config/certs/ca elasticsearch cat ca.crt| \
  openssl x509 -noout -fingerprint -sha256 | cut -d "=" -f 2 | tr -d :)
printf '{"ca_trusted_fingerprint": "%s"}' "${fingerprint}"| \
  $CURL -XPUT "${HEADERS[@]}" "http://kibana:5601/api/fleet/outputs/fleet-default-output" -d @-| \
  grep -q '"item"'
echo "===> done"
echo

# Enroll Fleet server, inclusive Fleet setup (docker-compose.yml: KIBANA_FLEET_SETUP=1)
# Wait for the Fleet server to be healthy (see docker-compose.yml: fleet-server healthy = Fleet server API status is healthy)
echo "==== Starting fleet server ===="
$COMPOSE up -d --no-deps --wait fleet-server
echo "===> Fleet server healthy"
echo

## Create agent policies: just the empty policy, as 8.13.4 Kibana seems to require an integration when specified via kibana.yml
echo "==== Creating empty agent policy \"private-location\" ===="
priv_loc_policy_id=$(printf '{"name":"private-location","description":"Synthetics Private Location policy","namespace":"default","monitoring_enabled":["logs","metrics"]}'| \
  $CURL -XPOST "${HEADERS[@]}" "${LOCAL_KBN_URL}/api/fleet/agent_policies?sys_monitoring=false" -d @-| \
  jq -r '.item.id')
  [ -z "${priv_loc_policy_id}" ] && abort "missing private location policy id"
echo "===> done"
echo

# Start agents
echo "==== Starting agent \"generic-agent\" ===="
$COMPOSE up -d --no-deps generic-agent
echo "===> done"
echo
echo "==== Starting agent \"private-location\" ===="
$COMPOSE up -d --no-deps private-location
echo "===> done"
echo
