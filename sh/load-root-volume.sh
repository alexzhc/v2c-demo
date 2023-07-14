#!/bin/bash -x


method=$1

disk=/vm/$2
disk_format=$3
disk_part=2

src_dir=/mnt
dest_dir=/vol
dest_dev=$( df "$dest_dir" --output=source | tail -1 )

if [[ "$method" == "7zip" ]]; then
    if [ -b "$dest_dev" ]; then
        # umount -vlf "$dest_dev"
        xfs_freeze -f ${dest_dir}
        wipefs -af "$dest_dev"
        7z e "$disk" "${disk_part}.img" -so > "$dest_dev"
        sync # MUST DO IT !
        xfs_freeze -f ${dest_dir}
        fdisk -N "$dest_dev"
        if ! xfs_info "$dest_dev"; then
            echo "XFS filesystem has issue!"
            exit 1
        fi 
    else
        echo Cannot find the block device
        exit 1 
    fi 
elif [[ "$method" == "libguestfs" ]]; then
    export LIBGUESTFS_BACKEND=direct
    if [ -c /dev/kvm ] && lsmod | grep kvm_intel; then 
        export LIBGUESTFS_BACKEND_SETTINGS=force_kvm
    else
        export LIBGUESTFS_BACKEND_SETTINGS=force_tcg
    fi
    printenv LIBGUESTFS_BACKEND_SETTINGS

    # Copy files
    if [ ! -f "$disk" ]; then
        echo "Cannot find root disk \"$disk\"!"
        exit 1
    fi

    # Check
    echo Verify "$disk" consistency
    qemu-img check -f "$disk_format" "$disk" || exit 1

    # Mount
    echo Mount "$disk" to "$src_dir"
    if [ -d "$src_dir" ]; then
        guestunmount -v --no-retry "$src_dir" \
        || umount -lf "$src_dir"
    else
        mkdir -vp "$src_dir"
    fi

    # Copy
    if guestmount -v --format="$disk_format" -a "$disk" -i --ro "$src_dir" -o kernel_cache; then
        df -hT "$src_dir"
        ls -lh "$src_dir"
        rsync -avAHS --stats \
        "${src_dir}/" "${dest_dir}/" \
        --exclude boot \
        --exclude sys \
        --exclude proc \
        --exclude dev \
        --exclude usr/lib/firmware \
        --exclude usr/lib/modules \
        --exclude usr/src \
        --exclude var/snap \
        --exclude var/cache \
        --exclude swap.img \
        --exclude etc/selinux \
        --exclude usr/share/doc \
        --delete \
        --delete-excluded
        # --exclude run \
        sync
        guestunmount -v --retry=3 "$src_dir" \
        || umount -lf "$src_dir"
        echo "Transferred completed:"
        ls -lh "${dest_dir}/"
    else
        echo "Failed to mount \"$disk\"!"
        exit 1 
    fi
fi

