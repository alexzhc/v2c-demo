#!/bin/bash -x

vm_name=$1

echo "A placeholder here for now because the pod is created externally"

#kubectl wait --for=condition=ready --timeout=1200s pod/${vm_name}-0

kubectl wait --for=jsonpath='{.status.readyReplicas}'=1 --timeout=1200s sts/${vm_name}
