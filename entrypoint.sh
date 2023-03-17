#!/bin/sh -l

echo "Workspace: $GITHUB_WORKSPACE"
echo "PWD"
pwd
cd $GITHUB_WORKSPACE
echo "Running script"
bash main.sh
