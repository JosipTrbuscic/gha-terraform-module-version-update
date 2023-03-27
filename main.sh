#!/bin/bash

echo "Executing script"
set -euo pipefail
# set -x
#

function print_array() {
    arr=$1
    for value in "${arr[@]}"
    do
      echo $value
    done
}

ENV="${INPUT_ENVIRONMENT}"
GITHUB_TOKEN="${INPUT_GITHUB_API_TOKEN}"
TARGET_TAG=""
BRANCH=""

eval `ssh-agent -s`
ssh-add - <<< "${INPUT_SSH_PRIVATE_KEY}"

changed=()
errored=()

current_dir=$(pwd)
start_dir="${INPUT_ROOT_PATH}"

function git_commit() {
  dir=$1
  module=$2
  target_version=$3

  BRANCH="${ENV}-${target_version}"
  git switch -C $BRANCH
  git commit -am "Bumped ${module} to ${target_version}"
}

function git_revert() {
  git checkout .
}

function get_tags_api_url_for_source() {
  source=$1
  org_repo=$(echo $source | sed -E 's/(")?git@github.com://' | sed -E  's/(.git)?\/\/.*//')
  url="https://api.github.com/repos/${org_repo}/tags"
  echo "$url"
}

function get_latest_tag() {
  api_url=$1
  tags=$(curl -L \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    "$api_url")
  tag_name=$(echo $tags | jq '.[0].name' | sed 's/"//g')
  echo "$tag_name"
}

echo "PWD"
pwd
echo "LS"
ls -al 
echo "Start dir: $start_dir"
# Iterate over directories which contain backend.tf file
for dir in $(find $start_dir -type f -name "backend.tf" -not -path "*.terraform/*" | sed 's/backend.tf//')
do
    cd $dir
    echo "DIR: $dir"
    # Iterate over *.tf files
    for file in $(find . -type f -name "*.tf" -not -path "*.terraform/*")
    do
      # Check if tf file contains modules
      modules=$(hcledit block list -f $file | { grep module || true; })
      if [[ -z "$modules" ]]; then
        continue
      fi
      echo "File $file"

      # For each module, try bumping its version to latest
      for module in $modules
      do
        source=$(hcledit attribute get "${module}.source" -f $file)
        if [[ -z $TARGET_TAG ]]; then
          url=$(get_tags_api_url_for_source $source)
          echo "URL: $url"
          tag=$(get_latest_tag $url)
          echo "TAG: $tag"
          TARGET_TAG="$tag"
        fi
        if [[ "$source" != "\"git@github.com"* ]]; then
          echo "Local: $source"
          continue
        else
          if [[ "$source" == *"$TARGET_TAG"* ]]; then
            echo "Already at latest change"
            break
          fi
          ns=$(echo $source | sed "s/ref=v.*\"/ref=$TARGET_TAG\"/")
          hcledit attribute set "$module".source $ns -f $file -u
        fi
        new_source=$(hcledit attribute get "${module}.source" -f $file)
        echo "$source -> $new_source"
        terraform init
        ret=0
        terraform plan -detailed-exitcode || ret=$?

        case $ret in
          2)
            echo "Error during plan, not commiting this change"
            errored+=("${dir}-${module}")
            git_revert
            ;;
          1)
            echo "Changes detected during plan, not commiting this change"
            changed+=("${dir}-${module}")
            git_revert
            ;;
          *)
            echo "No changes, commiting"
            git_commit $dir $module $TARGET_TAG
            ;;
        esac
      done
    done
    cd $current_dir
done

echo "Pushing"
git push -u origin $BRANCH
echo "Changed:"
print_array $changed
echo "Errored:"
print_array $errored
