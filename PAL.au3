;======================================================================================
; Portable Application Launcher (PAL)
; Copyright 2011 Tritonio, Updated by Jany @ 2025 for AutoIt3 3.3.16.1
; http://inshame.blogspot.com
;
; This program is free software:
; you can redistribute it and/or modify it under the terms of
; the GNU General Public License as published by the Free Software Foundation,
; either version 3 of the License, or (at your option) any later version.
;
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
; See the GNU General Public License for more details.
;======================================================================================

#NoTrayIcon
#include <File.au3>
#include <MsgBoxConstants.au3>
#include <FileConstants.au3>
#include <ProgressConstants.au3>
#pragma compile(Icon, PAL.ico)
Opt("ExpandEnvStrings", 1)

;======================================================================================
; GLOBAL VARIABLES
;======================================================================================

; Registry type array for mapping numeric types to string names
Global Const $types[11] = [ _
    "REG_NONE", _
    "REG_SZ", _
    "REG_EXPAND_SZ", _
    "REG_BINARY", _
    "REG_DWORD", _
    "REG_DWORD_BIG_ENDIAN", _
    "REG_LINK", _
    "REG_MULTI_SZ", _
    "REG_RESOURCE_LIST", _
    "REG_FULL_RESOURCE_DESCRIPTOR", _
    "REG_RESOURCE_REQUIREMENTS_LIST" _
]

; Will hold the process ID of launched application
Global $pid = 0

; Main configuration variables - will be populated from PAL.ini
Global $exe = ""       ; The executable to run
Global $cmdl = ""      ; Command line arguments
Global $regpath = ""   ; Registry path to virtualize
Global $filespath = "" ; Files path to virtualize

;======================================================================================
; INITIALIZATION
;======================================================================================

; Debug - Script start message
ConsoleWrite(@CRLF & "========== PAL: Portable Application Launcher Started ==========" & @CRLF)
ConsoleWrite("[INIT] Script Directory: " & @ScriptDir & @CRLF)

; Change working directory to script directory
FileChangeDir(@ScriptDir)
ConsoleWrite("[INIT] Working Directory set to: " & @WorkingDir & @CRLF)

; Register exit function
OnAutoItExitRegister("restore")
ConsoleWrite("[INIT] Exit handler registered" & @CRLF)

;======================================================================================
; UTILITY FUNCTIONS
;======================================================================================

; Check if a path is a directory
Func IsDir($path)
    Return StringInStr(FileGetAttrib($path), "D") > 0
EndFunc

; Create a backup ZIP of a directory using PowerShell
Func CreateBackupZip($source, $destZip)
    ConsoleWrite("[BACKUP] Creating ZIP: " & $source & " -> " & $destZip & @CRLF)
    
    If Not FileExists($source) Or Not IsDir($source) Then
        ConsoleWrite("[BACKUP] ! Failed: Source directory does not exist: " & $source & @CRLF)
        Return False
    EndIf
    
    ; Delete existing zip if it exists
    If FileExists($destZip) Then
        ConsoleWrite("[BACKUP] Removing existing ZIP file: " & $destZip & @CRLF)
        FileDelete($destZip)
    EndIf
    
    ; Use PowerShell to create the zip file - quotes around the paths to handle any spaces
    Local $psCommand = 'powershell -Command "Compress-Archive -Path \"' & $source & '\*\" -DestinationPath \"' & $destZip & '\" -Force"'
    ConsoleWrite("[BACKUP] Executing: " & $psCommand & @CRLF)
    
    Local $iPID = Run($psCommand, "", @SW_HIDE, $STDOUT_CHILD)
    Local $sOutput = ""
    
    ; Wait for command to complete
    While ProcessExists($iPID)
        $sOutput &= StdoutRead($iPID)
        Sleep(100)
    WEnd
    
    ; Get any remaining output
    $sOutput &= StdoutRead($iPID)
    
    ; Check if file was created
    If FileExists($destZip) Then
        ConsoleWrite("[BACKUP] ✓ Successfully created backup ZIP: " & $destZip & @CRLF)
        Return True
    Else
        ConsoleWrite("[BACKUP] ! Failed to create ZIP file: " & $destZip & @CRLF)
        If $sOutput <> "" Then ConsoleWrite("[BACKUP] PowerShell output: " & $sOutput & @CRLF)
        Return False
    EndIf
EndFunc

; Convert hex to string - used for binary registry values
Func hex2str($from)
    Local $to = ""
    For $i = 1 To BinaryLen($from) Step 2
        Local $number = Dec(BinaryToString(BinaryMid($from, $i, 2)))
        If Not @error Then $to &= Chr($number)
    Next
    Return $to
EndFunc

; Convert string to hex - used for binary registry values
Func str2hex($from)
    Local $to = ""
    For $i = 1 To BinaryLen($from)
        $to &= Hex(BinaryMid($from, $i, 1))
    Next
    Return $to
EndFunc

;======================================================================================
; REGISTRY FUNCTIONS
;======================================================================================

; Load registry keys from a file
Func RegKeyLoad($regfile)
    ConsoleWrite("[REG-LOAD] Loading from file: " & $regfile & @CRLF)
    
    Local $h = FileOpen($regfile, $FO_READ)
    If $h = -1 Then
        ConsoleWrite("[REG-LOAD] ! Error: Unable to open registry file: " & $regfile & @CRLF)
        MsgBox($MB_ICONERROR, "Error", "Unable to open registry file: " & $regfile)
        Return
    EndIf
    
    Local $keyCount = 0
    
    Do
        $keyname = FileReadLine($h)
        If @error Then ExitLoop
        
        $valuename = FileReadLine($h)
        If @error Then ExitLoop
        
        $type = FileReadLine($h)
        If @error Then ExitLoop
        
        If $type == 3 Then
            $value = hex2str(FileReadLine($h))
        Else
            $value = FileReadLine($h)
        EndIf
        If @error Then ExitLoop
        
        RegWrite($keyname, $valuename, $types[$type], $value)
        $keyCount += 1
    Until @error <> 0
    
    FileClose($h)
    ConsoleWrite("[REG-LOAD] ✓ Loaded " & $keyCount & " registry values from: " & $regfile & @CRLF)
EndFunc

; Save registry keys to a file
Func RegKeySave($key, $regfile)
    ConsoleWrite("[REG-SAVE] Saving registry to file: " & $key & " -> " & $regfile & @CRLF)
    
    If Not StringRegExp($key, "^(HKEY_LOCAL_MACHINE|HKEY_CURRENT_USER|HKEY_CLASSES_ROOT|HKEY_USERS|HKEY_CURRENT_CONFIG)") Then
        ConsoleWrite("[REG-SAVE] ! Invalid registry key: " & $key & @CRLF)
        Return
    EndIf
    
    Local $h = FileOpen($regfile, $FO_APPEND)
    If $h = -1 Then
        ConsoleWrite("[REG-SAVE] ! Error: Unable to open file for writing: " & $regfile & @CRLF)
        MsgBox($MB_ICONERROR, "Error", "Unable to open file for writing: " & $regfile)
        Return
    EndIf
    
    Local $valueCount = 0
    Local $keyCount = 0
    
    ; Save values in this key
    Local $instance = 1
    Do
        $value = RegEnumVal($key, $instance)
        $type = @extended
        If @error <> 0 Then ExitLoop
        
        FileWriteLine($h, $key)
        FileWriteLine($h, $value)
        FileWriteLine($h, $type)
        
        If $type == 3 Then
            FileWriteLine($h, str2hex(RegRead($key, $value)))
        Else
            FileWriteLine($h, RegRead($key, $value))
        EndIf
        
        $instance += 1
        $valueCount += 1
    Until False
    
    ; Process subkeys recursively
    $instance = 1
    Do
        $newkey = RegEnumKey($key, $instance)
        If @error <> 0 Then ExitLoop
        
        ConsoleWrite("[REG-SAVE] Processing subkey: " & $key & "\" & $newkey & @CRLF)
        RegKeySave($key & "\" & $newkey, $regfile)
        
        $instance += 1
        $keyCount += 1
    Until False
    
    FileClose($h)
    ConsoleWrite("[REG-SAVE] ✓ Saved " & $valueCount & " values from key: " & $key & " (+" & $keyCount & " subkeys)" & @CRLF)
EndFunc

;======================================================================================
; MAIN EXIT AND RESTORE FUNCTION 
;======================================================================================

; Restore function - called on exit to clean up and restore original state
Func restore()
    ConsoleWrite(@CRLF & "========== PAL: Exiting and Restoring ==========" & @CRLF)
    
    ; STEP 1: Wait for application to exit
    If ProcessExists($pid) Then
        ConsoleWrite("[STEP 1] Waiting for portable application to exit (PID: " & $pid & ")" & @CRLF)
        ProgressOn("PAL", "Waiting for portable program to exit...", "", Default, Default, $DLG_MOVEABLE)
        ProcessWaitClose($pid, 30)
        If ProcessExists($pid) Then
            ConsoleWrite("[STEP 1] ! Application didn't exit after 30s timeout, force closing..." & @CRLF)
            ProcessClose($pid)
        EndIf
        ProgressOff()
        ConsoleWrite("[STEP 1] ✓ Application process terminated" & @CRLF)
    Else
        ConsoleWrite("[STEP 1] No running application process found" & @CRLF)
    EndIf
    
    ProgressOn("PAL", "Saving portable application data...", "", Default, Default, $DLG_MOVEABLE)
    ConsoleWrite("[STEP 2] Starting application data preservation" & @CRLF)
    
    ; STEP 3: Remove old PortableData directory
    ProgressSet(30, "Removing old PortableData directory...")
    If FileExists(@ScriptDir & "\PortableData") Then
        ConsoleWrite("[STEP 3] Removing old PortableData directory" & @CRLF)
        DirRemove(@ScriptDir & "\PortableData", 1)
        If @error Then
            ConsoleWrite("[STEP 3] ! Error removing PortableData directory: " & @error & @CRLF)
        Else
            ConsoleWrite("[STEP 3] ✓ Successfully removed PortableData directory" & @CRLF)
        EndIf
    Else
        ConsoleWrite("[STEP 3] No existing PortableData directory to remove" & @CRLF)
    EndIf
    
    ; STEP 4: Copy application files to PortableData
    ProgressSet(40, "Copying files from application to PortableData...")
    If FileExists($filespath) Then
        ConsoleWrite("[STEP 4] Copying files from " & $filespath & " to " & @ScriptDir & "\PortableData" & @CRLF)
        DirCreate(@ScriptDir & "\PortableData")
        DirCopy($filespath, @ScriptDir & "\PortableData", 1)
        If @error Then
            ConsoleWrite("[STEP 4] ! Error copying application files to PortableData: " & @error & @CRLF)
        Else
            ConsoleWrite("[STEP 4] ✓ Successfully copied application files to PortableData" & @CRLF)
        EndIf
    Else
        ConsoleWrite("[STEP 4] ! Application directory not found: " & $filespath & @CRLF)
        DirCreate(@ScriptDir & "\PortableData")
        ConsoleWrite("[STEP 4] Created empty PortableData directory" & @CRLF)
    EndIf
    
    ; STEP 5: Save registry to file
    ProgressSet(50, "Saving registry data...")
    ConsoleWrite("[STEP 5] Saving registry data to PortableRegistry.dat" & @CRLF)
    FileDelete("PortableRegistry.dat")
    RegKeySave($regpath, "PortableRegistry.dat")
    If FileExists("PortableRegistry.dat") Then
        ConsoleWrite("[STEP 5] ✓ Successfully saved registry data" & @CRLF)
    Else
        ConsoleWrite("[STEP 5] ! Warning: PortableRegistry.dat may not have been created" & @CRLF)
    EndIf
    
    ; STEP 6: Remove application files
    ProgressSet(70, "Removing application files...")
    If FileExists($filespath) Then
        ConsoleWrite("[STEP 6] Removing application files from " & $filespath & @CRLF)
        DirRemove($filespath, 1)
        If @error Then
            ConsoleWrite("[STEP 6] ! Error removing application files: " & @error & @CRLF)
        Else
            ConsoleWrite("[STEP 6] ✓ Successfully removed application files" & @CRLF)
        EndIf
    Else
        ConsoleWrite("[STEP 6] No application files to remove" & @CRLF)
    EndIf
    
    ; STEP 7: Restore local data
    ProgressSet(80, "Restoring local data...")
    If FileExists(@ScriptDir & "\LocalData") Then
        ConsoleWrite("[STEP 7] Restoring local data from " & @ScriptDir & "\LocalData to " & $filespath & @CRLF)
        DirCreate($filespath)
        DirCopy(@ScriptDir & "\LocalData", $filespath, 1)
        If @error Then
            ConsoleWrite("[STEP 7] ! Error restoring local data: " & @error & @CRLF)
        Else
            ConsoleWrite("[STEP 7] ✓ Successfully restored local data" & @CRLF)
        EndIf
    Else
        ConsoleWrite("[STEP 7] ! Warning: LocalData directory not found" & @CRLF)
        DirCreate($filespath)
        ConsoleWrite("[STEP 7] Created empty application directory" & @CRLF)
    EndIf
    
    ; STEP 8: Remove LocalData directory
    ConsoleWrite("[STEP 8] Removing LocalData directory" & @CRLF)
    If FileExists(@ScriptDir & "\LocalData") Then
        DirRemove(@ScriptDir & "\LocalData", 1)
        If @error Then
            ConsoleWrite("[STEP 8] ! Error removing LocalData directory: " & @error & @CRLF)
        Else
            ConsoleWrite("[STEP 8] ✓ Successfully removed LocalData directory" & @CRLF)
        EndIf
    Else
        ConsoleWrite("[STEP 8] No LocalData directory to remove" & @CRLF)
    EndIf
    
    ; STEP 9: Delete portable registry key
    ProgressSet(90, "Restoring registry...")
    ConsoleWrite("[STEP 9] Removing portable registry key: " & $regpath & @CRLF)
    RegDelete($regpath)
    ConsoleWrite("[STEP 9] ✓ Registry key removed" & @CRLF)
    
    ; STEP 10: Restore registry from file
    If FileExists("LocalRegistry.dat") Then
        ConsoleWrite("[STEP 10] Restoring local registry from LocalRegistry.dat" & @CRLF)
        RegKeyLoad("LocalRegistry.dat")
        ConsoleWrite("[STEP 10] ✓ Registry restored from file" & @CRLF)
    Else
        ConsoleWrite("[STEP 10] ! Warning: LocalRegistry.dat not found, registry not restored" & @CRLF)
    EndIf
    
    ; STEP 11: Clean up registry file
    If FileExists("LocalRegistry.dat") Then
        ConsoleWrite("[STEP 11] Cleaning up by deleting LocalRegistry.dat" & @CRLF)
        FileDelete("LocalRegistry.dat")
        If @error Then
            ConsoleWrite("[STEP 11] ! Error deleting LocalRegistry.dat: " & @error & @CRLF)
        Else
            ConsoleWrite("[STEP 11] ✓ Successfully deleted LocalRegistry.dat" & @CRLF)
        EndIf
    Else
        ConsoleWrite("[STEP 11] No LocalRegistry.dat file to delete" & @CRLF)
    EndIf
    
    ProgressSet(100, "Completed!")
    ProgressOff()
    
    ConsoleWrite("========== PAL: Restoration Complete ==========" & @CRLF)
EndFunc

;======================================================================================
; MAIN SCRIPT EXECUTION
;======================================================================================

; --- Build command line arguments properly ---
$cmdl = ""
For $i = 1 To $CmdLine[0]
    $cmdl &= ' "' & $CmdLine[$i] & '"'
Next

; --- Read configuration from INI file ---
ConsoleWrite("[CONFIG] Reading configuration from PAL.ini" & @CRLF)
$exe = IniRead("PAL.ini", "PALOptions", "Executable", "")
If $exe == "" Then
    ConsoleWrite("[CONFIG] ! Error: Executable not defined in the INI file" & @CRLF)
    MsgBox($MB_ICONERROR, "PAL", "You have not setup the main executable in the INI file.")
    Exit 2
EndIf
ConsoleWrite("[CONFIG] Executable: " & $exe & @CRLF)

$regpath = IniRead("PAL.ini", "PALOptions", "RegistryPath", "")
If $regpath == "" Then
    $regpath = "HKEY_CURRENT_USER\Software\" & StringReplace(StringReplace($exe, ".exe", ""), " ", "")
    ConsoleWrite("[CONFIG] Using default registry path: " & $regpath & @CRLF)
Else
    ConsoleWrite("[CONFIG] Registry Path: " & $regpath & @CRLF)
EndIf

$filespath = IniRead("PAL.ini", "PALOptions", "FilesPath", "")
If $filespath == "" Then
    ConsoleWrite("[CONFIG] ! Error: FilesPath not defined in the INI file" & @CRLF)
    MsgBox($MB_ICONERROR, "PAL", "FilesPath not defined in the INI file.")
    Exit 3
EndIf
ConsoleWrite("[CONFIG] Files Path: " & $filespath & @CRLF)

; --- Setup Portable Environment ---
ProgressOn("PAL", "Loading portable application data...", "", Default, Default, $DLG_MOVEABLE)
ConsoleWrite("[PROGRESS] Started progress dialog" & @CRLF)

ConsoleWrite("[STARTUP] Checking for first run..." & @CRLF)
If Not FileExists("LocalRegistry.dat") And Not FileExists("LocalData") Then
    ConsoleWrite("[STARTUP] First run detected - preparing portable environment" & @CRLF)
    
    ; Create a backup ZIP of PortableData if it exists
    If FileExists(@ScriptDir & "\PortableData") And IsDir(@ScriptDir & "\PortableData") Then
        Local $backupZip = @ScriptDir & "\PortableData.zip"
        ProgressSet(20, "Creating backup ZIP of PortableData...")
        
        ; Try to create the backup zip using PowerShell
        If CreateBackupZip(@ScriptDir & "\PortableData", $backupZip) Then
            ConsoleWrite("[STARTUP-1] ✓ Successfully created backup of PortableData" & @CRLF)
        Else
            ConsoleWrite("[STARTUP-1] ! Failed to create backup, but continuing with other operations" & @CRLF)
        EndIf
    Else
        ConsoleWrite("[STARTUP-1] No existing PortableData directory found to backup" & @CRLF)
    EndIf
    
    ProgressSet(40, "Backing up application data...")
    If FileExists($filespath) Then
        ConsoleWrite("[STARTUP-2] Backing up application data from " & $filespath & " to LocalData" & @CRLF)
        DirCopy($filespath, @ScriptDir & "\LocalData", 1)
        ConsoleWrite("[STARTUP-2] ✓ Application data backup complete" & @CRLF)
    Else
        ConsoleWrite("[STARTUP-2] No existing application data found at " & $filespath & @CRLF)
        DirCreate(@ScriptDir & "\LocalData")
        ConsoleWrite("[STARTUP-2] Created empty LocalData directory" & @CRLF)
    EndIf
    
    ProgressSet(50, "Saving registry...")
    ConsoleWrite("[STARTUP-3] Saving registry key " & $regpath & " to LocalRegistry.dat" & @CRLF)
    RegKeySave($regpath, "LocalRegistry.dat")
    ConsoleWrite("[STARTUP-3] ✓ Registry backup complete" & @CRLF)
    
    ProgressSet(70, "Removing application data...")
    If FileExists($filespath) Then
        ConsoleWrite("[STARTUP-4] Removing application data from " & $filespath & @CRLF)
        DirRemove($filespath, 1)
        ConsoleWrite("[STARTUP-4] ✓ Application data removed" & @CRLF)
    Else
        ConsoleWrite("[STARTUP-4] No application data to remove" & @CRLF)
    EndIf
    
    ProgressSet(80, "Restoring registry...")
    ConsoleWrite("[STARTUP-5] Removing registry key: " & $regpath & @CRLF)
    RegDelete($regpath)
    ConsoleWrite("[STARTUP-5] ✓ Registry cleaned" & @CRLF)
    
    ProgressSet(90, "Copying PortableData to application...")
    ConsoleWrite("[STARTUP-6] Checking PortableData directory" & @CRLF)
    If FileExists(@ScriptDir & "\PortableData") Then
        ConsoleWrite("[STARTUP-6] Copying PortableData to " & $filespath & @CRLF)
        DirCreate($filespath)
        DirCopy(@ScriptDir & "\PortableData", $filespath, 1)
        ConsoleWrite("[STARTUP-6] ✓ PortableData copied" & @CRLF)
    Else
        ConsoleWrite("[STARTUP-6] No PortableData directory found, creating empty app directory" & @CRLF)
        DirCreate($filespath)
    EndIf
    
    If FileExists("PortableRegistry.dat") Then
        ConsoleWrite("[STARTUP-7] Loading PortableRegistry.dat" & @CRLF)
        RegKeyLoad("PortableRegistry.dat")
        ConsoleWrite("[STARTUP-7] ✓ Portable registry loaded" & @CRLF)
    Else
        ConsoleWrite("[STARTUP-7] No PortableRegistry.dat found" & @CRLF)
    EndIf
    
    If FileExists("PortableRegistryConsts.dat") Then
        ConsoleWrite("[STARTUP-8] Loading PortableRegistryConsts.dat" & @CRLF)
        RegKeyLoad("PortableRegistryConsts.dat")
        ConsoleWrite("[STARTUP-8] ✓ Portable registry constants loaded" & @CRLF)
    Else
        ConsoleWrite("[STARTUP-8] No PortableRegistryConsts.dat found" & @CRLF)
    EndIf
    
    ProgressSet(100, "Completed!")
    ConsoleWrite("[STARTUP] ✓ Portable environment setup complete" & @CRLF)
Else
    ConsoleWrite("[STARTUP] Portable environment already prepared" & @CRLF)
    ConsoleWrite("[STARTUP] LocalRegistry.dat and LocalData exist - using existing backup" & @CRLF)
EndIf

ProgressOff()
ConsoleWrite("[PROGRESS] Progress dialog closed" & @CRLF)

; --- Run the Portable Application ---
ConsoleWrite(@CRLF & "========== PAL: Starting Portable Application ==========" & @CRLF)
ConsoleWrite("[EXECUTE] Running command: " & $exe & $cmdl & @CRLF)
$pid = RunWait($exe & $cmdl)
ConsoleWrite("[EXECUTE] Application exited with code: " & $pid & @CRLF)

Exit 0