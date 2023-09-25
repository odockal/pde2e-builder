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

# NVM, NODE, YARN PART
write-host "Installing Node JS"
# Check if NVM is installed
if (-not (Command-Exists "node")) {
    write-host "Command 'node' does not exist"
    # alternative to using nvm installer - using winget
    winget install OpenJs.NodeJS.LTS
    # add node on the path
    $env:PATH += ";$env:C:\Program Files\nodejs\;"
}

# verify node installation
node -v
npm -v

# Check if Git is installed
write-host "Installing git"
if (-not (Command-Exists "git")) {
    write-host "Command 'git' does not exist"
    # user scoped installation using winget
    # winget install --id Git.Git -e --source winget --scope user
    winget install --id Git.Git -e --source winget
    # add node on the path
    $env:PATH += ";$env:C:\Program Files\Git\bin;"
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
write-host "checking out branch: $branch"
git checkout $branch

## YARN INSTALL AND BUILD PART
write-host "Installing dependencies"
yarn install
write-host "Build a podman desktop on a local machine"
yarn compile

# If all went well, there should be a podman desktop executable "Podman Desktop.exe" in dist/win-unpacked/
$expectedFilePath="$workingDir\podman-desktop\dist\win-unpacked\"
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
    "pdPath=$absolutePath" | Out-File -FilePath pde2e-builder-results.log
} else {
    Write-Host "The file does not exist."
    cd "$workingDir\$results"
    "Error compiling and building the podman desktop ouptut binary" | Out-File -FilePath pde2e-builder-results.log
}
write-host "Script finished..."
