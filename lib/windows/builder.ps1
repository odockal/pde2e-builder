param(
    [Parameter(Mandatory,HelpMessage='folder on target host where assets are copied')]
    $targetFolder,
    [Parameter(Mandatory,HelpMessage='Results folder')]
    $resultsFolder="results",
    [Parameter(HelpMessage = 'Fork')]
    [string]$fork = "containers",
    [Parameter(HelpMessage = 'Branch')]
    [string]$branch = "main"
)

# Program Versions
$nodejsLatestVersion = "v20.11.1"
$gitVersion = '2.42.0.2'

# Function to check if a command is available
function Command-Exists($command) {
    $null = Get-Command -Name $command -ErrorAction SilentlyContinue
    return $?
}

Write-Host "Podman desktop E2E builder script is being run..."

write-host "Switching to a target folder: " $targetFolder
cd $targetFolder
write-host "Create a resultsFolder in targetFolder: $resultsFolder"
mkdir $resultsFolder
$workingDir=Get-Location
write-host "Working location: " $workingDir

# Specify the user profile directory
$userProfile = $env:USERPROFILE

# Specify the shared tools directory
$toolsInstallDir = Join-Path $userProfile 'tools'

# Output file for built podman desktop binary
$outputFile = "pde2e-binary-path.log"

# Create the tools directory if it doesn't exist
if (-not (Test-Path -Path $toolsInstallDir -PathType Container)) {
    New-Item -Path $toolsInstallDir -ItemType Directory
}

if (-not (Command-Exists "node -v")) {
    # Download and install the latest version of Node.js
    write-host "Installing node"
    # $nodejsLatestVersion = (Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' | Sort-Object -Property version -Descending)[0].version
    if (-not (Test-Path -Path "$toolsInstallDir\node-$nodejsLatestVersion-win-x64" -PathType Container)) {
        Invoke-WebRequest -Uri "https://nodejs.org/dist/$nodejsLatestVersion/node-$nodejsLatestVersion-win-x64.zip" -OutFile "$toolsInstallDir\nodejs.zip"
        Expand-Archive -Path "$toolsInstallDir\nodejs.zip" -DestinationPath $toolsInstallDir
    }
    $env:Path += ";$toolsInstallDir\node-$nodejsLatestVersion-win-x64"
}
# node and npm version check
Write-Host "Node.js Version: $nodejsLatestVersion"
node -v
npm -v

if (-not (Command-Exists "git version")) {
    # Download and install Git
    write-host "Installing git"
    Invoke-WebRequest -Uri "https://github.com/git-for-windows/git/releases/download/v2.42.0.windows.2/MinGit-$gitVersion-64-bit.zip" -OutFile "$toolsInstallDir\git.zip"
    if (-not (Test-Path -Path "$toolsInstallDir\git" -PathType Container)) {
        Expand-Archive -Path "$toolsInstallDir\git.zip" -DestinationPath "$toolsInstallDir\git"
    }
    $env:Path += ";$toolsInstallDir\git\cmd"
}

# git verification
git.exe version

# Install Yarn
write-host "Installing yarn"
npm install -g yarn
yarn --version

# GIT clone and checkout part
# clean up previous folder
if (Test-Path -Path "podman-desktop") {
    write-host "Removing older podman-desktop github repo"
    Remove-Item -Recurse -Force -Path "podman-desktop"
}
# Clone the GitHub repository and switch to the specified branch
$repositoryURL ="https://github.com/$fork/podman-desktop.git"
write-host "Checking out" $repositoryURL
git clone $repositoryURL
write-host "checking out into podman-desktop"
cd podman-desktop
# Fetch all so we can either checkout to a branch or tag
write-host "Fetch all refs"
git fetch --all
write-host "checking out branch: $branch"
git checkout $branch

## YARN INSTALL AND BUILD PART
write-host "Installing dependencies"
yarn --frozen-lockfile --network-timeout 180000
write-host "Build a podman desktop on a local machine"
yarn compile

# If all went well, there should be a podman desktop executable "Podman Desktop.exe" in dist/win-unpacked/
$expectedFilePath="$workingDir\podman-desktop\dist\win-unpacked"
$oldFileName="Podman Desktop.exe"
$newFileName="pd.exe"
# Write down the location of podman desktop executable into a file
if (Test-Path -Path "$expectedFilePath\$oldFileName" -PathType Leaf) {
    # Rename the file
    Rename-Item -Path "$expectedFilePath\$oldFileName" -NewName $newFileName
    Write-Host "The file has been renamed to $newFileName."
    $absolutePath = Convert-Path -Path "$expectedFilePath\$newFileName"  # Get the absolute path
    Write-Host "The file exists at $absolutePath."
    cd "$workingDir\$resultsFolder"
    # results directory should already exist
    write-host "Storing information about Podman Desktop executable to the resulting file: $outputFile"
    "$absolutePath" | Out-File -FilePath $outputFile -NoNewline
} else {
    Write-Host "The file does not exist."
    cd "$workingDir\$results"
    "Error compiling and building the podman desktop ouptut binary" | Out-File -FilePath $outputFile
}
write-host "Script finished..."
