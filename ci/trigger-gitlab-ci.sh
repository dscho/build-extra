#!/bin/sh

# This script should be run in a git.git clone. It takes a remote branch,
# adds the appropriate configuration for the GitLab CI Runner, and then
# pushes it to Git for Windows' GitLab space to trigger the build.

die () {
	echo "$*" >&2
	exit 1
}

test $# = 2 ||
die "Usage: $0 <URL> <ref>"

url=$1
ref=$2

script_dir="$(dirname "$0")"

ref2="refs/heads/$(echo "$url/$ref" |
	sed -e 's/^https\?:\/\///' -e 's/^git@//' -e 'y/:/-/')"

git fetch "$url" +"$ref:$ref2" ||
die "Could not fetch $ref from $url"

run_via_sdk='C:\git-sdk-64\git-cmd.exe --command=usr\bin\sh.exe -l -c'
timeout='timeout -k 30s -s KILL 25m'
yaml_sha1="$(git hash-object -w --stdin <<EOF)"
before_script:
  - $run_via_sdk "./gitlab-ci-helper.sh setup"

build:
  stage: build
  script:
    - $run_via_sdk "$timeout ./gitlab-ci-helper.sh build"
  artifacts:
    paths:
      - test-artifacts.tar.xz
$(counter=1
for range in 5525-6031 5000-5523 4002-5000 7702-9107 9107-9134 9136-9163 6031-7201 7301-7509 3308-3405 7509-7700 9163- 3405-3421 3421-3426 1006-2014 -1006 2014-3306 3426-3600 3600-4000 9134-9136 7201-7301 7700-7702 4000-4002 5523-5525 3306-3308
do
	printf '\ntest%03d:\n%s\n%s\n%s\n%s\n%s %s "%s %s %s"\n' $counter \
		'  stage: test' \
		'  dependencies:' \
		'    - build' \
		'  script:' \
		'    -' "$run_via_sdk" "$timeout" \
		'./gitlab-ci-helper.sh test' $range
	prev_no=$no
	counter=$(($counter+1))
done
)
EOF

helper_sha1="$(git hash-object -w --stdin <"$script_dir"/gitlab-ci-helper.sh)"

GIT_INDEX_FILE="$(git rev-parse --git-dir)/gitlab-ci-index" &&
export GIT_INDEX_FILE &&
git read-tree "$ref2" &&
git update-index --add --cacheinfo 100644,$yaml_sha1,.gitlab-ci.yml &&
git update-index --add --cacheinfo 100755,$helper_sha1,gitlab-ci-helper.sh &&
tree="$(git write-tree)" &&
commit="$(git commit-tree -p "$ref2" -m "GitLab CI configuration" $tree)" &&
git update-ref -m "GitLab CI configuration" "$ref2" "$commit" &&
git push git@gitlab.com:git-for-windows1/git.git +"$ref2" ||
die "Could not trigger GitLab CI for $ref of $url"
