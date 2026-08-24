#!/bin/sh
set -eu

output=
compile=0
previous=
for argument in "$@"
do
	if test "$previous" = "-o"
	then
		output=$argument
	fi
	if test "$argument" = "-c"
	then
		compile=1
	fi
	previous=$argument
done

interrupt=0
case "${BMK_INTERRUPT_MODE:-}" in
	compile)
		test "$compile" -eq 1 && interrupt=1
		;;
	link)
		test "$compile" -eq 0 && test -n "$output" && interrupt=1
		;;
esac

if test "$interrupt" -eq 1
then
	printf 'incomplete build output\n' > "$output"
	printf '%s\n' "$$" > "${BMK_INTERRUPT_MARKER:?}"
	trap 'exit 143' TERM INT
	while :
	do
		sleep 1
	done
fi

exec "${BMK_REAL_COMPILER:?}" "$@"
