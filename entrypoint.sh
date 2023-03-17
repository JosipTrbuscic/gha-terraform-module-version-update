#!/bin/sh -l

echo "Workspace: $GITHUB_WORKSPACE"
git config --global --add safe.directory $GITHUB_WORKSPACE
cd $GITHUB_WORKSPACE
pwd
ls -al 
env
echo "Running script"
bash /main.sh
