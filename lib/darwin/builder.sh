#!/bin/bash

targetFolder=""
resultsFolder="results"
fork="containers"
branch="main"

# Version variables
nodeVersion="v20.11.1"
gitVersion="2.42.0"

while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
        -t|--targetFolder)
        targetFolder="$2"
        shift # past argument
        shift # past value
        ;;
        -r|--resultsFolder)
        resultsFolder="$2"
        shift # past argument
        shift # past value
        ;;
        -f|--fork)
        fork="$2"
        shift # past argument
        shift # past value
        ;;
        -b|--branch)
        branch="$2"
        shift # past argument
        shift # past value
        ;;
        *)    # unknown option
        shift # past argument
        ;;
    esac
done

if [ -z "$targetFolder" ]; then
    echo "Error: targetFolder is required"
    exit 1
fi

echo "Podman desktop E2E builder script is being run..."
echo "Switching to a target folder: $targetFolder"
cd "$targetFolder" || exit
echo "Create a resultsFolder in targetFolder: $resultsFolder"
mkdir -p "$resultsFolder"
workingDir=$(pwd)
echo "Working location: $workingDir"

# Specify the user profile directory
userProfile="$HOME"

# Specify the shared tools directory
toolsInstallDir="$userProfile/tools"

# Output file for built podman desktop binary
outputFile="pde2e-binary-path.log"

# Determine the system's arch
architecture=$(uname -m)

# Create the tools directory if it doesn't exist
if [ ! -d "$toolsInstallDir" ]; then
    mkdir -p "$toolsInstallDir"
fi

# node installation
if ! command -v node &> /dev/null; then
    if [ "$architecture" = "x86_64" ]; then
        nodeUrl="https://nodejs.org/download/release/$nodeVersion/node-$nodeVersion-darwin-x64.tar.xz"
    elif [ "$architecture" = "arm64" ]; then
        nodeUrl="https://nodejs.org/download/release/$nodeVersion/node-$nodeVersion-darwin-arm64.tar.xz"
    else
        echo "Error: Unsupported architecture $architecture"
        exit 1
    fi

    # Check if Node.js is already installed
    echo "$(ls $toolsInstallDir)"
    if [ ! -d "$toolsInstallDir/node-$nodeVersion-darwin-x64" ]; then
        # Download and install Node.js
        echo "Installing node $nodeVersion for $architecture architecture"
        echo "curl -O $nodeUrl | tar -xJ -C $toolsInstallDir"
        curl -o "$toolsInstallDir/node.tar.xz" "$nodeUrl" 
        tar -xf $toolsInstallDir/node.tar.xz -C $toolsInstallDir
    fi
    if [ -d "$toolsInstallDir/node-$nodeVersion-darwin-${architecture}/bin" ]; then
        echo "Node Installation path found"
        export PATH="$PATH:$toolsInstallDir/node-$nodeVersion-darwin-${architecture}/bin"
    else
        echo "Node installation path not found"
    fi
fi

# node and npm version check
echo "Node.js Version: $(node -v)"
echo "npm Version: $(npm -v)"

if ! command -v git &> /dev/null; then
    # Check if Git is already installed
    if [ ! -d "$toolsInstallDir/git-$gitVersion" ]; then
        # Download and install Git
        echo "Installing git $gitVersion"
        gitUrl="https://github.com/git/git/archive/refs/tags/v$gitVersion.tar.gz"
        mkdir -p "$toolsInstallDir/git-$gitVersion"
        curl -O "$gitUrl" | tar -xz -C "$toolsInstallDir/git-$gitVersion" --strip-components 1
        cd "$toolsInstallDir/git-$gitVersion" || exit
        make prefix="$toolsInstallDir/git-$gitVersion" all
        make prefix="$toolsInstallDir/git-$gitVersion" install
    fi
    export PATH="$PATH:$toolsInstallDir/git-$gitVersion/bin"
fi

# git verification
git --version

# Install Yarn
echo "Installing yarn"
npm install -g yarn
echo "Yarn Version: $(yarn --version)"

# GIT clone and checkout part
# clean up previous folder
if [ -d "podman-desktop" ]; then
    echo "Removing older podman-desktop github repo"
    rm -rf "podman-desktop"
fi

# Clone the GitHub repository and switch to the specified branch
repositoryURL="https://github.com/$fork/podman-desktop.git"
echo "Checking out $repositoryURL"
git clone "$repositoryURL"
cd "podman-desktop" || exit
# Fetch all so we can either checkout to a branch or tag
git fetch --all
echo "Checking out branch: $branch"
git checkout "$branch"

## YARN INSTALL AND BUILD PART
echo "Installing dependencies"
yarn --frozen-lockfile --network-timeout 180000
echo "Build a podman desktop on a local machine"
yarn compile

# If all went well, there should be a podman desktop executable "Podman Desktop.exe" in dist/win-unpacked/
expectedFilePath="$workingDir/podman-desktop/dist/mac-$architecture/"
oldFileName="Podman Desktop.app"
newFileName="pd.app"
# Write down the location of podman desktop executable into a file
if [ -d "$expectedFilePath/$oldFileName" ]; then
    # Rename the file
    mv "$expectedFilePath/$oldFileName" "$expectedFilePath/$newFileName"
    echo "The file has been renamed to $newFileName."
    absolutePath=$(realpath "$expectedFilePath/$newFileName")  # Get the absolute path
    echo "The file exists at $absolutePath."
    echo "Re-signing the app so we can open it on the lab machine"
    codesign --force --deep --sign - $absolutePath
    cd "$workingDir/$resultsFolder" || exit
    # results directory should already exist
    echo "Storing information about Podman Desktop executable to the resulting file: $outputFile"
    echo -n "$absolutePath" > "$outputFile"
else
    echo "The file does not exist."
    cd "$workingDir/$results" || exit
    echo "Error compiling and building the podman desktop output binary" > "$outputFile"
fi
echo "Script finished..."
