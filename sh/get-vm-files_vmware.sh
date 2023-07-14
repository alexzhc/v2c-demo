#!/bin/bash -x

# Use govc

export GOVC_URL=$VCSA_HOST
export GOVC_USERNAME=$VCSA_USERNAME
export GOVC_PASSWORD=$VCSA_PASSWORD
export GOVC_INSECURE=true

vm=$1

govc about || exit 1

do_restart=false
while [[ $(govc vm.info --json "$vm" | jq -r .VirtualMachines[0].Runtime.PowerState) != "poweredOff" ]]; do
    do_restart=true
    govc vm.power -s -wait "$vm" || \
    govc vm.power -off -wait "$vm"
    sleep 2
done

govc export.ovf -verbose=true -vm "$vm" /vm/

mv -v /vm/${vm}/* /vm/
rmdir /vm/${vm}

ls -lh /vm/

if ${do_restart}; then 
    govc vm.power -on -wait "$vm"
fi

