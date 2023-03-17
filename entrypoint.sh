#!/bin/sh -l

echo "Workspace: $GITHUB_WORKSPACE"
cd $GITHUB_WORKSPACE

git config --global --add safe.directory $GITHUB_WORKSPACE
git config --global user.email "autoupdater@test.com"
git config --global user.name "Autoupdater"

echo "Running script"
bash /main.sh
