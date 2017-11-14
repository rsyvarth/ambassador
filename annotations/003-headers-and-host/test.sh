#!/bin/bash

set -e -o pipefail

HERE=$(cd $(dirname $0); pwd)

cd "$HERE"

ROOT=$(cd ..; pwd)
PATH="${ROOT}:${PATH}"

source ${ROOT}/utils.sh

step "Building images"
docker build -t dwflynn/demo:1.0.0 --build-arg VERSION=1.0.0 demo-service
docker build -t dwflynn/demo:2.0.0 --build-arg VERSION=2.0.0 demo-service
docker push dwflynn/demo:1.0.0
docker push dwflynn/demo:2.0.0

step "Dropping old cluster"
kubernaut discard

step "Claiming new cluster"
kubernaut claim 
export KUBECONFIG=${HOME}/.kube/kubernaut

kubectl cluster-info

kubectl apply -f k8s
kubectl apply -f ${ROOT}/ambassador-deployment.yaml

set +e +o pipefail

wait_for_pods

CLUSTER=$(cluster_ip)
APORT=$(service_port ambassador)

BASEURL="http://${CLUSTER}:${APORT}"

echo "Base URL $BASEURL"
echo "Diag URL $BASEURL/ambassador/v0/diag/"

wait_for_ready "$BASEURL"

if ! check_diag "$BASEURL" 1 "No canary active"; then
    exit 1
fi

if ! demotest.py "$BASEURL" demo-1.yaml; then
    exit 1
fi

kubectl apply -f k8s/canary-50.yaml
wait_for_pods
wait_for_demo_weights "$BASEURL" x-demo-mode=canary 50 50

# This needs sorting crap before it'll work. :P
# if ! check_diag "$BASEURL" 2 "Canary 50/50"; then
#     exit 1
# fi

if ! demotest.py "$BASEURL" demo-2.yaml; then
    exit 1
fi

kubectl apply -f k8s/canary-100.yaml
wait_for_pods
wait_for_demo_weights "$BASEURL" x-demo-mode=canary 100

# This needs sorting crap before it'll work. :P
# if ! check_diag "$BASEURL" 3 "Canary 100"; then
#     exit 1
# fi

if ! demotest.py "$BASEURL" demo-3.yaml; then
    exit 1
fi

