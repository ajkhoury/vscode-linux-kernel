#!/usr/bin/env bash
# The script assumes it is located in .vscode/ within the Linux source tree
# and that the modules have been built.

# Get the parent directory of the script (i.e., the Linux source root)
LINUX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_VERSION="$(uname -r)"
MODULES_BUILD_ROOT="/lib/modules/$KERNEL_VERSION/build"
echo "Linux source root: $LINUX_ROOT"
echo "Kernel version:    $KERNEL_VERSION"

SRC_KVM="$LINUX_ROOT/arch/x86/kvm/kvm.ko"
SRC_INTEL="$LINUX_ROOT/arch/x86/kvm/kvm-intel.ko"

# Get the destination paths for the modules.
DST_KVM="$(modinfo -n kvm)"
DST_INTEL="$(modinfo -n kvm_intel)"
echo "DST_KVM=$DST_KVM"
echo "DST_INTEL=$DST_INTEL"

# Strip debug symbols to reduce size
echo "Stripping debug symbols..."
strip --strip-debug "$SRC_KVM" "$SRC_INTEL"

# Sign the modules
echo "Signing modules..."
"$LINUX_ROOT/scripts/sign-file" sha512 "$MODULES_BUILD_ROOT/certs/signing_key.pem" "$MODULES_BUILD_ROOT/certs/signing_key.x509" "$SRC_KVM"
"$LINUX_ROOT/scripts/sign-file" sha512 "$MODULES_BUILD_ROOT/certs/signing_key.pem" "$MODULES_BUILD_ROOT/certs/signing_key.x509" "$SRC_INTEL"
echo "Signer(kvm):       $(modinfo -F signer "$SRC_KVM" 2>/dev/null || echo '?')"
echo "Signer(kvm_intel): $(modinfo -F signer "$SRC_INTEL" 2>/dev/null || echo '?')"

# Install kvm
if [ "${DST_KVM##*.}" = "zst" ]; then
	echo "Compressing kvm.ko to kvm.ko.zst"
	zstd -q -f -19 -o "${SRC_KVM}.zst" "$SRC_KVM"
	sudo install -m 0644 "${SRC_KVM}.zst" "$DST_KVM"
else
	sudo install -m 0644 "$SRC_KVM" "$DST_KVM"
fi

# Install kvm_intel
if [ "${DST_INTEL##*.}" = "zst" ]; then
	echo "Compressing kvm-intel.ko to kvm-intel.ko.zst"
	zstd -q -f -19 -o "${SRC_INTEL}.zst" "$SRC_INTEL"
	sudo install -m 0644 "${SRC_INTEL}.zst" "$DST_INTEL"
else
	sudo install -m 0644 "$SRC_INTEL" "$DST_INTEL"
fi

# Update module dependencies
echo "Updating module dependencies..."
sudo depmod -a "$KERNEL_VERSION"

echo "Done. Reloading modules..."

# unload in dependency order
sudo modprobe -r kvm_intel kvm
# reload in dependency order
sudo modprobe kvm
sudo modprobe kvm_intel
