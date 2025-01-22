param(
    [Parameter(Mandatory=$true)]
    [string] $FilePath
)

# 
# 1. Resolve the path if it's relative. This ensures CreateFile sees a full path.
#    If the user types ".\SomeFile.exe", we'll convert it to "C:\Full\Path\SomeFile.exe"
#
$ResolvedPath = (Resolve-Path $FilePath).ProviderPath

#
# 2. Dynamically add the .NET type that wraps our native calls. 
#    Use -TypeDefinition instead of -MemberDefinition, so that "using" statements go at the top
#
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class NativeMethods
{
    // CreateFile
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr CreateFile(
        string lpFileName,
        int dwDesiredAccess,
        int dwShareMode,
        IntPtr lpSecurityAttributes,
        int dwCreationDisposition,
        int dwFlagsAndAttributes,
        IntPtr hTemplateFile
    );

    // GetFinalPathNameByHandle
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern uint GetFinalPathNameByHandle(
        IntPtr hFile,
        StringBuilder lpszFilePath,
        uint cchFilePath,
        uint dwFlags
    );

    // CloseHandle
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool CloseHandle(IntPtr hObject);
}
"@

#
# 3. Define constants (typical read/open flags)
#
$GENERIC_READ        = 0x80000000
$FILE_SHARE_READ     = 0x00000001
$OPEN_EXISTING       = 3
$FILE_ATTRIBUTE_NORMAL = 0x80
$INVALID_HANDLE_VALUE = -1

# 
# 4. Get a handle to the file
#
$handle = [NativeMethods]::CreateFile(
    $ResolvedPath,
    $GENERIC_READ,
    $FILE_SHARE_READ,
    [IntPtr]::Zero,
    $OPEN_EXISTING,
    $FILE_ATTRIBUTE_NORMAL,
    [IntPtr]::Zero
)

if (($handle -eq [IntPtr]::Zero) -or ($handle.ToInt32() -eq $INVALID_HANDLE_VALUE)) {
    Write-Error "Unable to open handle for '$ResolvedPath'. Check path or permissions."
    return
}

try {
    #
    # 5. Get the final path name
    #
    $sb = New-Object System.Text.StringBuilder(1024)
    $result = [NativeMethods]::GetFinalPathNameByHandle($handle, $sb, $sb.Capacity, 0)

    if ($result -eq 0) {
        Write-Error "GetFinalPathNameByHandle failed for '$ResolvedPath' (error code: $($Error[0].Exception.HResult))"
    }
    else {
        # Typically, Windows adds a prefix like \\?\; strip it if you want a "normal" path
        $finalPath = $sb.ToString()
        if ($finalPath.StartsWith("\\\\?\\")) {
            $finalPath = $finalPath.Substring(4)
        }

        Write-Host "Final path for '$FilePath':"
        Write-Host $finalPath
    }
}
finally {
    # 6. Close the handle
    [NativeMethods]::CloseHandle($handle) | Out-Null
}
