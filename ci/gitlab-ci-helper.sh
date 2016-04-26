#!/bin/sh

# This script sets up a build directory ci/ (to work around left-over git.exe
# being picked up when calling "git fetch"), or builds the artifacts required
# for testing, or performs a chunk of the tests, depending on the command:
#
# <script> ( setup | build | test <test-scripts> )

die () {
	echo "$*" >&2
	exit 1
}

parallel=$(git config test.maxjobs)
parallel=-j${parallel:-15}

case "$1" in
setup)
	HEAD="$(git rev-parse HEAD)"
	if ! grep -q '^ci$' .git/info/exclude
	then
		echo "ci" >> .git/info/exclude
	fi &&
	if test -d ci
	then
		cd ci &&
		rm -f git.exe &&
		git config core.autocrlf false &&
		git reset --hard $HEAD
	else
		git config core.autocrlf false &&
		git worktree add ci $HEAD &&
		cd ci
	fi ||
	die "Could not set up the ci/ directory"
	;;
build)
	cd ci &&
	cat >ci-extra.mak <<\EOF
-include Makefile

test-artifacts.tar.xz: GIT-BUILD-OPTIONS templates/blt po/build \
	$(TEST_PROGRAMS) $(test_bindir_programs) $(ALL_PROGRAMS) \
	$(NO_INSTALL) $(BUILT_INS) $(OTHER_PROGRAMS) $(SCRIPT_LIB)
	tar cJf $@ $^

templates/blt:
	make -C templates

po/build: $(MOFILES)
EOF
	make $parallel -f ci-extra.mak test-artifacts.tar.xz &&
	mv test-artifacts.tar.xz ../ ||
	die "Could not build the artifacts for testing"
	;;
test)
	shift &&
	cd ci &&
	tar xJf ../test-artifacts.tar.xz &&
	# fix the (absolute) GIT_EXEC_PATH that was correct during the build
	wrong="$(sed -n "s|^GIT_EXEC_PATH='\(.*\)'$|\1|p" <bin-wrappers/git)" &&
	sed -i "s|$wrong|$PWD|g" bin-wrappers/* &&
	cd t &&
	rm -rf trash\ directory.t* &&
	ret=0 &&
	from=${1%%-*} &&
	until=${1#*-} &&
	tests="$(ls t[0-9]*.sh)" &&
	if test -n "$from"
	then
		tests="$( (echo "$tests"; printf 't%04d \n' $from) |
			sort | sed -e '1,/ $/d')"
	fi &&
	if test -n "$until"
	then
		tests="$( (echo "$tests"; printf 't%04d \n' $until) |
			sort | sed -e '/ $/,$d')"
	fi &&
	if ! eval make -k $parallel $tests
	then
		for t in trash\ directory.t*
		do
			test -d "$t" || die "No directory: $t"
			script=${t#trash directory.} &&
			echo "Re-running $script.sh (could have been failing due resource problems)" &&
			if ! sh $script.sh
			then
				bash $script.sh -i -v -x || ret=$?
			fi
		done
	fi &&
	test 0 = $ret ||
	die "Could not test $@"
	;;
*)
	die "Usage: $0 ( setup | build | test <test-scripts> )"
	;;
esac
