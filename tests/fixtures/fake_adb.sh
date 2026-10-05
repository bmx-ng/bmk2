#!/bin/sh
set -eu

if test "$1" = devices
then
	printf '%s\n' 'List of devices attached' \
		'TESTSERIAL device usb:1-2 product:test_product model:Test_Phone device:test_device transport_id:1'
	exit 0
fi

if test "$1" = -s && test "$2" = TESTSERIAL && test "$3" = shell && test "$4" = getprop
then
	printf '%s\n' \
		'[ro.product.manufacturer]: [Example]' \
		'[ro.product.model]: [Test Phone]' \
		'[ro.product.name]: [test_product]' \
		'[ro.product.device]: [test_device]' \
		'[ro.build.version.release]: [15]' \
		'[ro.build.version.sdk]: [35]' \
		'[ro.product.cpu.abilist]: [arm64-v8a]' \
		'[ro.hardware]: [test_hardware]' \
		'[ro.build.display.id]: [TEST.1]' \
		'[ro.build.fingerprint]: [example/test/test:15/TEST.1:user/test-keys]'
	exit 0
fi

printf 'unexpected fake adb arguments: %s\n' "$*" >&2
exit 1
