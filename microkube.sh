#!/usr/bin/env bash

function usage() {
    cat >&2 <<EOT
Usage: $0 {start,stop,remove}

One-node kubernetes in docker for development. OS X users might want to use github.com/kubernetes/minikube instead.

Requirements:
	docker, kubectl.

EOT
    exit 2
}

function die() {
	echo "ERROR: $*" >&2
	exit 1
}

function announce_step() {
    echo
    echo "===> $*"
    echo
}

function wait_for_command() {
	local usage="$FUNCNAME <command> [poll_interval] [retries]"
	local cmd=${1:?$usage}
	local poll_interval=${2:-1}
	local attempts=${3:-10}

	attempt=1
	until eval "$cmd" >/dev/null 2>&1; do
		echo "Failed. Attempt $attempt of $attempts."

		if [[ "$attempt" -eq "$attempts" ]]; then
			die "all attempts were failed"
		fi

		sleep "$poll_interval"
		((attempt++))
	done
}

function wait_for_http() {
	local usage="$FUNCNAME <endpoint> [poll_interval] [retries]"
	local endpoint=${1:?$usage}
	local poll_interval=${2:-1}
	local attempts=${3:-10}

	wait_for_command \
		"curl --output /dev/null --silent --head --fail --max-time 1 '$endpoint'" \
		"$poll_interval" "$attempts"
}

function k8s_service_endpoint() {
	local usage="$FUNCNAME <service> <containerport> [namespace]"
	local service=${1:?$usage}
	local containerport=${2:?$usage}
	local namespace=${3:+"--namespace=$3"}

	local any_host=$(kubectl get nodes \
		-o jsonpath='{ .items[0].status.addresses[?(@.type == "InternalIP")].address }')
	local service_port=$(kubectl $namespace get service \
		-o jsonpath="{ .spec.ports[?(@.port == $containerport)].nodePort }" "$service")

	echo "${any_host}:${service_port}"
}

function wait_for_k8s() {
	announce_step "Waiting for K8S"

	local cmd="kubectl cluster-info"
	wait_for_command "$cmd" 5 30
}

function k8s_cluster_check() {
	announce_step "Deploying test services to K8S"

	kubectl run nginx-test --image=nginx --port=80

	# Wait pod to appear
	local cmd='kubectl get pods -l run=nginx-test | grep ^nginx-test'
	wait_for_command "$cmd" 5 30

	# Determine pod to expose
	local pod=$(kubectl get pods -l run=nginx-test --no-headers | awk '{ print $1 }')
	kubectl expose pod "$pod" --target-port=80 --name=nginx-test \
		--type=LoadBalancer

	local nginx_endpoint="http://$(k8s_service_endpoint nginx-test 80)"
	wait_for_http "$nginx_endpoint" 5 30

	kubectl delete service nginx-test
	kubectl delete deployment nginx-test
}

function k8s_wait_for_workers() {
	announce_step "Waiting for 3 worker nodes"

	local cmd='kubectl get node 127.0.0.1 -o jsonpath='"'"'{range @.status.conditions[*]}{@.type}={@.status};{end}'"'"' | tr ";" "\n"  | grep "Ready=True"'
	wait_for_command "$cmd" 5 30
}

function start() {
	announce_step 'Create kubernetes in docker'
	docker run \
		--volume=/:/rootfs:ro \
		--volume=/sys:/sys:ro \
		--volume=/var/lib/docker/:/var/lib/docker:rw \
		--volume=/var/lib/kubelet/:/var/lib/kubelet:shared \
		--volume=/var/run:/var/run:rw \
		--net=host \
		--pid=host \
		--privileged=true \
		--name=kubelet \
		-d \
		"gcr.io/google_containers/hyperkube-${ARCH}:${K8S_VERSION}" \
		/hyperkube kubelet \
			--containerized \
			--hostname-override="127.0.0.1" \
			--address="0.0.0.0" \
			--api-servers="http://$K8S_DOCKER_HOST:$K8S_API_PORT" \
			--config=/etc/kubernetes/manifests \
			--cluster-dns=10.0.0.10 \
			--cluster-domain=cluster.local \
			--allow-privileged=true \
			--v=2

	kubectl config use-context dev-docker

	wait_for_k8s
	k8s_wait_for_workers
	k8s_cluster_check
}

function stop() {
	announce_step 'Stop containers'
	docker rm -f $(docker ps --filter=name=k8s --filter=name=kube --quiet --all)
}

function remove() {
	announce_step 'Remove volumes'
	sudo umount $(cat /proc/mounts | grep /var/lib/kubelet | awk '{print $2}')
	sudo rm -rf /var/lib/kubelet
}


# Main logic

# Constants
SCRIPT_DIR="$(dirname "$0")"

K8S_VERSION=v1.3.0
K8S_CLUSTER_NAME=dev-docker
K8S_DOCKER_HOST=localhost
K8S_API_PORT=8080
ARCH=amd64

export KUBECONFIG="${SCRIPT_DIR}/kubeconfig"

# Parse args
FUNC=${1:?$(usage)}

# Run
set -e
"$FUNC"
