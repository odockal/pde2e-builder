param(
    [Parameter(Mandatory,HelpMessage='folder on target host where assets are copied')]
    $targetFolder,
    [Parameter(Mandatory,HelpMessage='Results folder')]
    $resultsFolder="results",
    [Parameter(HelpMessage = 'Fork')]
    [string]$fork = "podman-desktop",
    [Parameter(HelpMessage = 'Branch')]
    [string]$branch = "main",
    [Parameter(HelpMessage = 'Npm Target command')]
    [string[]]$pnpmCommand = "pnpm compile",
    [Parameter(HelpMessage = 'Environmental variables to be passed from the CI into a script, tests parameterization')]
    $envVars=''
)

# Program Versions
$nodejsLatestVersion = "v20.11.1"
$gitVersion = '2.42.0.2'

# Global variables
$global:scriptEnvVars = @()
$global:envVarDefs = @()

# Function to check if a command is available
function Command-Exists($command) {
    $null = Get-Command -Name $command -ErrorAction SilentlyContinue
    return $?
}

# Loading variables as env. var from the CI into image
function Load-Variables() {
    Write-Host "Loading Variables passed into image"
    Write-Host "Input String: '$envVars'"
    # Check if the input string is not null or empty
    if (-not [string]::IsNullOrWhiteSpace($envVars)) {
        # Split the input using comma separator
        $variables = $envVars -split ','

        foreach ($variable in $variables) {
            # Split each variable definition
            $global:envVarDefs += $variable
            $parts = $variable -split '=', 2
            Write-Host "Processing $variable"

            # Check if the variable assignment is in VAR=Value format
            if ($parts.Count -eq 2) {
                $name = $parts[0].Trim()
                $value = $parts[1].Trim('"')

                # Set and test the environment variable
                Set-Item -Path "env:$name" -Value $value
                $global:scriptEnvVars += $name
            } else {
                Write-Host "Invalid variable assignment: $variable"
            }
        }
    } else {
        Write-Host "Input string is empty."
    }
}

function Invoke-Admin-Command {
    param (
        [string]$Command,            # Command to run (e.g., "pnpm install")
        [string]$WorkingDirectory,   # Working directory where the command should be executed
        [string]$TargetFolder,       # Target directory for storing the output/log files
        [string]$EnvVarName="",      # Environment variable name (optional)
        [string]$EnvVarValue="",     # Environment variable value (optional)
        [string]$Privileged='0',     # Whether to run command with admin rights, defaults to user mode,
        [string]$SetSecrets='0',     # Whether to process secret file and load it as env. vars., only in privileged mode,
        [int]$WaitTimeout=300,     # Default WaitTimeout 300 s, defines the timeout to wait for command execute
        [bool]$WaitForCommand=$true  # Wait for command execution indefinitely, default true, use timeout otherwise
    )

    cd $WorkingDirectory
    # Define file paths to capture output and error
    $outputFile = Join-Path -Path $WorkingDirectory -ChildPath "tmp_stdout_$([System.Datetime]::Now.ToString("yyyymmdd_HHmmss")).txt"
    $errorFile = Join-Path -Path $WorkingDirectory -ChildPath "tmp_stderr_$([System.Datetime]::Now.ToString("yyyymmdd_HHmmss")).txt"
    $tempScriptFile = Join-Path -Path $WorkingDirectory -ChildPath "tmp_script_$([System.Datetime]::Now.ToString("yyyymmdd_HHmmss")).ps1"

    # We need to create a local tmp script in order to execute it with admin rights with a Start-Process
    # We also want a access to the stdout and stderr which is not possible otherwise
    if ($Privileged -eq "1") {
        # Create the temporary script content
        $scriptContent = @"
# Change to the working directory
Set-Location -Path '$WorkingDirectory'

"@
        # If the environment variable name and value are provided, add to script
        if (![string]::IsNullOrWhiteSpace($EnvVarName) -and ![string]::IsNullOrWhiteSpace($EnvVarValue)) {
            $scriptContent += @"
# Set the environment variable
Set-Item -Path Env:\$EnvVarName -Value '$EnvVarValue'
"@
        }
        
        # If we have a set of env. vars. provided, add this code to script
        if (![string]::IsNullOrWhiteSpace($global:envVarDefs)) {
            Write-Host "Parsing Global Input env. vars in inline script: '$global:envVarDefs'"
            foreach ($definition in $global:envVarDefs) {
                # Split each variable definition
                Write-Host "Processing $definition"
                $parts = $definition -split '=', 2

                # Check if the variable assignment is in VAR=Value format
                if ($parts.Count -eq 2) {
                    $name = $parts[0].Trim()
                    $value = $parts[1].Trim('"')

                    # Set and test the environment variable
                    $scriptContent += @"
# Set the environment variable from array
Set-Item -Path Env:\$name -Value '$value'

"@
                } else {
                    Write-Host "Invalid variable assignment: $definition"
                }
            }
        }

        # Add secrets handling into tmp script
        if ($SetSecrets -eq "1") {
            Write-Host "SetSecrets flag is set"
            if ($secretFile) {
                Write-Host "SecretFile is defined and found..."
$scriptContent += @"
`$secretFilePath="$resourcesPath\$secretFile"
if (Test-Path `$secretFilePath) {
    `$properties = Get-Content `$secretFilePath | ForEach-Object {
        # Ignore comments and empty lines
        if (-not `$_.StartsWith("#") -and -not [string]::IsNullOrWhiteSpace(`$_)) {
            # Split each line into key-value pairs
            `$key, `$value = `$_ -split '=', 2

            # Trim leading and trailing whitespaces
            `$key = `$key.Trim()
            `$value = `$value.Trim()

            # Set the environment variable
            Set-Item -Path "env:`$key" -Value `$value
        }
    }
    Write-Host "Secrets loaded from '`$secretFilePath' and set as environment variables."
} else {
    Write-Host "File '`$secretFilePath' not found."
}

"@
            }
        }

        # Add the command execution to the script
        $scriptContent += @"
# Run the command and redirect stdout and stderr
# Try running the command and capture errors
try {
    'Executing Command: $Command' | Out-File '$outputFile' -Append
    $Command >> '$outputFile' 2>> '$errorFile'
    'Command executed successfully.' | Out-File '$outputFile' -Append
} catch {
    'Error occurred while executing command: ' + `$_.Exception.Message | Out-File '$errorFile' -Append
}

"@
        # Write the script content to the temporary script file
        write-host "Creating a content of the script:"
        write-host "$scriptContent"
        write-host "Storing at: $tempScriptFile"
        $scriptContent | Set-Content -Path $tempScriptFile

        # Start the process as admin and run the temporary script file
        $process = Start-Process powershell.exe -ArgumentList "-NoProfile", "-ExecutionPolicy Bypass", "-File", $tempScriptFile -Verb RunAs -PassThru
        $waitResult = $null
        if ($WaitForCommand) {
            write-host "Starting process with script awaiting until it is finished..."
            $waitResult = $process.WaitForExit()
        } else {
            write-host "Starting process with script awaiting for $WaitTimeout sec"
            $waitResult = $process.WaitForExit($WaitTimeout * 1000)
        }
        Write-Host "Process ID: $($process.Id)"
        if ($waitResult) {
            Write-Host "Process completed waiting successfully."
        } else {
            Write-Host "Process failed waiting after with exit code: $($process.ExitCode)"
        }

    } else {
        cd $WorkingDirectory
        # Run the command normally without elevated privileges
        if (![string]::IsNullOrWhiteSpace($EnvVarName) -and ![string]::IsNullOrWhiteSpace($EnvVarValue)) {
            "Settings Env. Var.: $EnvVarName = $EnvVarValue" | Out-File $outputFile -Append
            Set-Item -Path Env:\$EnvVarName -Value $EnvVarValue
        }
        Set-Location -Path '$WorkingDirectory'
        "Running the command: '$Command' in non privileged mode" | Out-File $outputFile -Append
        $output = Invoke-Expression $Command >> $outputFile 2>> $errorFile
    }

    # Copying logs and scripts back to the target folder (to get preserved and copied to the host)
    cp $tempScriptFile $TargetFolder
    cp $outputFile $TargetFolder
    cp $errorFile $TargetFolder

    # After the process finishes, read the output and error from the files
    if (Test-Path $outputFile) {
        Write-Output "Standard Output: $(Get-Content -Path $outputFile)"
    } else {
        Write-Output "No standard output..."
    }

    if (Test-Path $errorFile) {
        Write-Output "Standard Error: $(Get-Content -Path $errorFile)"
    } else {
        Write-Output "No standard error..."
    }
}

Write-Host "Podman desktop E2E builder script is being run..."

write-host "Switching to a target folder: " $targetFolder
cd $targetFolder
write-host "Create a resultsFolder in targetFolder: $resultsFolder"
mkdir $resultsFolder
$workingDir=Get-Location
write-host "Working location: " $workingDir
$targetLocation="$workingDir\$resultsFolder"

# Specify the user profile directory
$userProfile = $env:USERPROFILE

# Specify the shared tools directory
$toolsInstallDir = Join-Path $userProfile 'tools'

# Output file for built podman desktop binary
$outputFile = "pde2e-binary-path.log"

# define targetLocationTmpScp for temporary script files
$targetLocationTmpScp="$targetLocation\scripts"
New-Item -ErrorAction Ignore -ItemType directory -Path $targetLocationTmpScp

# Create the tools directory if it doesn't exist
if (-not (Test-Path -Path $toolsInstallDir -PathType Container)) {
    New-Item -Path $toolsInstallDir -ItemType Directory
}

# load variables
Load-Variables

# Install VC Redistributable
write-host "Install VC_Redistributable"
if (-not (Test-Path -Path "$toolsInstallDir\vc_redist.x64.exe" -PathType Container)) {
    Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vc_redist.x64.exe" -OutFile "$toolsInstallDir\vc_redist.x64.exe"
    $vcredistInstaller = "$toolsInstallDir\vc_redist.x64.exe"

    if (Test-Path $vcredistInstaller) {
        Start-Process -FilePath $vcredistInstaller -ArgumentList "/install", "/passive", "/norestart" -Wait
    } else {
        Write-Host "Installer not found at $vcredistInstaller"
    }
}

if (-not (Command-Exists "node -v")) {
    # Download and install the latest version of Node.js
    write-host "Installing node"
    # $nodejsLatestVersion = (Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' | Sort-Object -Property version -Descending)[0].version
    if (-not (Test-Path -Path "$toolsInstallDir\node-$nodejsLatestVersion-win-x64" -PathType Container)) {
        Invoke-WebRequest -Uri "https://nodejs.org/dist/$nodejsLatestVersion/node-$nodejsLatestVersion-win-x64.zip" -OutFile "$toolsInstallDir\nodejs.zip"
        Expand-Archive -Path "$toolsInstallDir\nodejs.zip" -DestinationPath $toolsInstallDir
    }
    # we need to set node for local access in actually running script
    $env:Path += ";$toolsInstallDir\node-$nodejsLatestVersion-win-x64\"
    # Setting node to be available for the machine scope
    # requires admin access
    $command="[Environment]::SetEnvironmentVariable('Path', (`$Env:Path + ';$toolsInstallDir\node-$nodejsLatestVersion-win-x64\'), 'MACHINE')"
    Start-Process powershell.exe -ArgumentList "-NoProfile", "-ExecutionPolicy Bypass", "-Command $command" -Verb RunAs -Wait
    write-host "$([Environment]::GetEnvironmentVariable('Path', 'MACHINE'))"
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

# Install pnpm
write-host "Installing pnpm"
npm install -g pnpm@9
pnpm --version

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

## Pnpm INSTALL AND BUILD PART
$thisDir=Get-Location
write-host "Installing dependencies"
write-host "Calling: Invoke-Admin-Command -Command 'pnpm install --frozen-lockfile' -WorkingDirectory $thisDir -Privileged '1' -TargetFolder $targetLocationTmpScp"
Invoke-Admin-Command -Command "pnpm install --frozen-lockfile" -WorkingDirectory $thisDir -Privileged "1" -TargetFolder $targetLocationTmpScp
write-host "Build/Compile a podman desktop on a local machine"
write-host "Calling: Invoke-Admin-Command -Command '$pnpmCommand' -WorkingDirectory $thisDir -Privileged '1' -TargetFolder $targetLocationTmpScp"
Invoke-Admin-Command -Command "$pnpmCommand" -WorkingDirectory $thisDir -Privileged "1" -TargetFolder $targetLocationTmpScp

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
    cd "$workingDir\$resultsFolder"
    "Error compiling and building the podman desktop output binary" | Out-File -FilePath $outputFile
}
write-host "Script finished..."
