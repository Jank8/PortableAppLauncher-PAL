# Portable Application Launcher (PAL)


<p align="center">
  <img src="PAL.svg" alt="PAL Logo" width="120" height="120">
</p>

## Overview

Portable Application Launcher (PAL) is a tool that allows you to make almost any Windows application portable. PAL creates a virtualized environment for applications by:

- Redirecting registry access
- Isolating application files
- Preserving application state between sessions

Originally created by Tritonio and updated by Jany for AutoIt3 3.3.16.1 (2025).

## Features

- **Registry Virtualization**: Redirects registry calls to portable storage
- **File Isolation**: Manages application files in a portable container
- **Simple Configuration**: Easy setup via PAL.ini
- **Zero Installation**: No installation required on host system
- **Clean Restoration**: Leaves no traces on the host system

## Requirements

- Windows operating system
- AutoIt3 (for running the uncompiled script)

## Usage

1. **Setup PAL.ini with your application details:**
   ```ini
   [PALOptions]
   Executable=YourApplication.exe
   RegistryPath=HKEY_CURRENT_USER\Software\YourApplication
   FilesPath=%APPDATA%\YourApplication
   ```

2. **Run PAL.exe** to launch your application in portable mode

3. **Portable Data** is stored in the PortableData directory and PortableRegistry.dat file

## How It Works

1. **First Run**: PAL backs up existing application data (if any) to LocalData and LocalRegistry.dat
2. **Virtualization**: PAL then creates a clean environment using the portable data
3. **Application Launch**: Your application runs in this virtualized environment
4. **On Exit**: PAL saves changes back to the portable storage and restores the original system state

## File Structure

- **PAL.exe**: Main executable
- **PAL.ini**: Configuration file
- **PAL.au3**: Source code (AutoIt3)
- **PAL.svg**: Project logo
- **PortableData/**: Directory containing portable application files
- **PortableRegistry.dat**: Registry data for portable application
- **LocalData/**: Backup of original application files (created on first run)
- **LocalRegistry.dat**: Backup of original registry data (created on first run)

## License

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

## Credits

- Original author: Tritonio
- Updated by: Jany (2025) 
