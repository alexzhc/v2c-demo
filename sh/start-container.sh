#!/bin/bash -x

vm_name=$1

echo "A placeholder here for now because the pod is created externally"

kubectl wait --for=condition=ready --timeout=1200s pod/${vm_name}-0
