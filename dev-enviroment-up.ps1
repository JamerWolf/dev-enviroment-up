#TODO: agregar funcionalidad de ejecutar una linea especifica por medio del StateFile
# Verify that the script is running as an administrator
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$ScriptPath = $MyInvocation.MyCommand.Path

function relaunch_admin_script {
    # Relaunch script with administrator privileges
    Start-Process powershell -ArgumentList `
        "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`"" `
        -Verb RunAs
}

if (-not $IsAdmin) {
    Write-Host "El script no se está ejecutando como administrador. Relanzando..."

    relaunch_admin_script

    exit
}

$StateFile = "$env:TEMP\script_state.txt"

$Checkpoint = if (Test-Path $StateFile) { Get-Content $StateFile } else { "start" }

switch ($Checkpoint) {
    "start" {
        # Enable necessary features
        dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
        dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
  
        $Command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

        # Add to RunOnce in the registry
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce" `
            -Name "MiScriptRunOnce" -Value $Command

        "wsl_setup" | Out-File $StateFile -Encoding UTF8

        Restart-Computer -Force
    }

    "wsl_setup" {
        wsl --install --no-distribution -ErrorAction SilentlyContinue

        Invoke-WebRequest -Uri https://cloud-images.ubuntu.com/wsl/releases/22.04/current/ubuntu-jammy-wsl-amd64-wsl.rootfs.tar.gz `
            -OutFile $env:TEMP\ubuntu-jammy-wsl-amd64-wsl.rootfs.tar.gz

        New-Item -ItemType Directory -Force -Path C:\WSL\Ubuntu2204\

        wsl --import Ubuntu-22.04 C:\WSL\Ubuntu2204 $env:TEMP\ubuntu-jammy-wsl-amd64-wsl.rootfs.tar.gz --version 2
        
        $Usuario = $env:USERNAME
        $Password = "1234"

        wsl -d Ubuntu-22.04 -- bash -c "useradd -m -s /bin/bash $Usuario && echo '${Usuario}:${Password}' | chpasswd && usermod -aG sudo $Usuario"

        wsl -d Ubuntu-22.04 -- bash -c "echo -e '[user]\ndefault=$Usuario' >> /etc/wsl.conf"
        
        wsl --terminate Ubuntu-22.04

        "docker_setup" | Out-File $StateFile -Encoding UTF8

        relaunch_admin_script

        exit

    }

    "docker_setup" {
        Start-BitsTransfer -Source "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe" `
            -Destination "$env:TEMP\Docker%20Desktop%20Installer.exe"

        Start-Process -FilePath "$env:TEMP\Docker%20Desktop%20Installer.exe" -ArgumentList "install", "--quiet" -Wait

        docker version

        "clean" | Out-File $StateFile -Encoding UTF8

        relaunch_admin_script

        exit

    }

    "clean" {
        Remove-Item -Path `
        "$env:TEMP\ubuntu-jammy-wsl-amd64-wsl.rootfs.tar.gz", `
        "$env:TEMP\wsl.2.5.10.0.x64.msi", `
        "$env:TEMP\Docker%20Desktop%20Installer.exe" `
        #"$env:TEMP\script_state.txt" `
        -Force -ErrorAction SilentlyContinue

        exit
    }
}
