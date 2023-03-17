#!/bin/bash

echo "Executing script"
set -euo pipefail
# set -x

ENV="${INPUT_ENVIRONMENT}"
GITHUB_TOKEN="${INPUT_GITHUB_API_TOKEN}"

mkdir -p ~/.ssh
ssh-keyscan github.com >> ~/.ssh/known_hosts
echo "Known hosts"
cat ~/.ssh/known_hosts

changed=()
errored=()

current_dir=$(pwd)
start_dir="${INPUT_ROOT_PATH}"

function git_commit() {
  dir=$1
  module=$2

  git switch -C "${ENV}-${TARGET_VERSION}"
  git commit -am "Bumped ${module} to ${TARGET_VERSION}"
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
        url=$(get_tags_api_url_for_source $source)
        echo "URL: $url"
        tag=$(get_latest_tag $url)
        echo "TAG: $tag"
        if [[ "$source" != "\"git@github.com"* ]]; then
          echo "Local: $source"
          continue
        else
          if [[ "$source" == *"$tag"* ]]; then
            echo "Already at latest change"
            break
          fi
          ns=$(echo $source | sed "s/ref=v.*\"/ref=$tag\"/")
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
            git_commit $dir $module
            ;;
        esac
      done
    done
    cd $current_dir
done

git log | head -n 50
echo "Changed: ${changed}"
echo "Errored: ${errored}"
