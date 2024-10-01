# If WSL does not remember the vm.max_map setting
# If WSL does not start the docker service automatically.
# I think it is me not spending enough time to do it right
# Run this script with sudo
sysctl -w vm.max_map_count=262144
service docker start
docker compose up -d
