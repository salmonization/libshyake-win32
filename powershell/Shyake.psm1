# Shyake.psm1 - PowerShell module over shyake.dll (P/Invoke).
# Official scripting interface for Windows: no client needed.
# Requires shyake.dll in the module directory or on PATH.

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace Shyake
{
    [StructLayout(LayoutKind.Sequential)]
    public struct Config
    {
        public IntPtr instance_url;
        public IntPtr config_dir;
        public IntPtr username;
        public int plain;
        public int debug;
        public int no_color;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MailEntry
    {
        public IntPtr mail_id;
        public IntPtr party;
        public IntPtr subject;
        public int size;
        public long timestamp;
        public long created;
        public int is_sent;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MailList
    {
        public IntPtr entries;
        public int count;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MailDetail
    {
        public IntPtr mail_id;
        public IntPtr sender;
        public IntPtr recipient;
        public IntPtr subject;
        public IntPtr body;
        public long timestamp;
        public long created;
        public int size;
    }

    public static class Native
    {
        [DllImport("shyake.dll", CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr shyake_init_ctx(ref Config config);

        [DllImport("shyake.dll", CallingConvention = CallingConvention.Cdecl)]
        public static extern void shyake_free_ctx(IntPtr ctx);

        [DllImport("shyake.dll", CallingConvention = CallingConvention.Cdecl)]
        public static extern void shyake_set_passphrase(IntPtr ctx, byte[] passphrase);

        [DllImport("shyake.dll", CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr shyake_last_error(IntPtr ctx);

        [DllImport("shyake.dll", CallingConvention = CallingConvention.Cdecl)]
        public static extern int shyake_generate_keys(IntPtr ctx);

        [DllImport("shyake.dll", CallingConvention = CallingConvention.Cdecl)]
        public static extern int shyake_register(IntPtr ctx, byte[] username);

        [DllImport("shyake.dll", CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr shyake_check(IntPtr ctx, byte[] type);

        [DllImport("shyake.dll", CallingConvention = CallingConvention.Cdecl)]
        public static extern void shyake_free_mail_list(IntPtr list);

        [DllImport("shyake.dll", CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr shyake_fetch(IntPtr ctx, byte[] mail_id);

        [DllImport("shyake.dll", CallingConvention = CallingConvention.Cdecl)]
        public static extern void shyake_free_mail_detail(IntPtr detail);

        [DllImport("shyake.dll", CallingConvention = CallingConvention.Cdecl)]
        public static extern int shyake_send(IntPtr ctx, byte[] recipient,
            byte[] subject, byte[] body, UIntPtr body_len);

        [DllImport("shyake.dll", CallingConvention = CallingConvention.Cdecl)]
        public static extern int shyake_burn(IntPtr ctx, byte[] mail_id);

        public static byte[] Utf8(string s)
        {
            if (s == null) s = "";
            byte[] raw = Encoding.UTF8.GetBytes(s);
            byte[] z = new byte[raw.Length + 1];
            Array.Copy(raw, z, raw.Length);
            return z;
        }

        public static string FromUtf8(IntPtr p)
        {
            if (p == IntPtr.Zero) return null;
            int len = 0;
            while (Marshal.ReadByte(p, len) != 0) len++;
            byte[] buf = new byte[len];
            Marshal.Copy(p, buf, 0, len);
            return Encoding.UTF8.GetString(buf);
        }

        public static IntPtr Utf8Ptr(string s)
        {
            byte[] z = Utf8(s);
            IntPtr p = Marshal.AllocHGlobal(z.Length);
            Marshal.Copy(z, 0, p, z.Length);
            return p;
        }
    }
}
"@

$script:Ctx = [IntPtr]::Zero
$script:CfgPtrs = @()

function Get-LastShyakeError {
    if ($script:Ctx -ne [IntPtr]::Zero) {
        [Shyake.Native]::FromUtf8([Shyake.Native]::shyake_last_error($script:Ctx))
    }
}

function Connect-Shyake {
    <#
    .SYNOPSIS
    Open a shyake context against a profile directory.
    .PARAMETER ConfigDir
    Directory holding config/keys, e.g. $env:APPDATA\Natsuzake\profiles\default
    or a directory copied from ~/.config/shyake.
    .PARAMETER Passphrase
    Key passphrase; falls back to $env:SHYAKE_PASSPHRASE.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ConfigDir,
        [Parameter(Mandatory)] [string]$Instance,
        [Parameter(Mandatory)] [string]$Username,
        [string]$Passphrase
    )
    if ($script:Ctx -ne [IntPtr]::Zero) { Disconnect-Shyake }

    $cfg = New-Object Shyake.Config
    $cfg.instance_url = [Shyake.Native]::Utf8Ptr($Instance)
    $cfg.config_dir   = [Shyake.Native]::Utf8Ptr($ConfigDir)
    $cfg.username     = [Shyake.Native]::Utf8Ptr($Username)
    $script:CfgPtrs = @($cfg.instance_url, $cfg.config_dir, $cfg.username)

    $script:Ctx = [Shyake.Native]::shyake_init_ctx([ref]$cfg)
    if ($script:Ctx -eq [IntPtr]::Zero) {
        throw "shyake_init_ctx failed"
    }

    if (-not $Passphrase) { $Passphrase = $env:SHYAKE_PASSPHRASE }
    if ($Passphrase) {
        [Shyake.Native]::shyake_set_passphrase($script:Ctx,
            [Shyake.Native]::Utf8($Passphrase))
    }
}

function Disconnect-Shyake {
    [CmdletBinding()]
    param()
    if ($script:Ctx -ne [IntPtr]::Zero) {
        [Shyake.Native]::shyake_free_ctx($script:Ctx)
        $script:Ctx = [IntPtr]::Zero
    }
    foreach ($p in $script:CfgPtrs) {
        [System.Runtime.InteropServices.Marshal]::FreeHGlobal($p)
    }
    $script:CfgPtrs = @()
}

function Assert-Connected {
    if ($script:Ctx -eq [IntPtr]::Zero) {
        throw "Not connected. Run Connect-Shyake first."
    }
}

function Get-ShyakeBox {
    param([string]$Type)
    Assert-Connected
    $listPtr = [Shyake.Native]::shyake_check($script:Ctx,
        [Shyake.Native]::Utf8($Type))
    if ($listPtr -eq [IntPtr]::Zero) {
        throw "check failed: $(Get-LastShyakeError)"
    }
    try {
        $list = [System.Runtime.InteropServices.Marshal]::PtrToStructure(
            $listPtr, [type][Shyake.MailList])
        $entrySize = [System.Runtime.InteropServices.Marshal]::SizeOf(
            [type][Shyake.MailEntry])
        for ($i = 0; $i -lt $list.count; $i++) {
            $p = [IntPtr]($list.entries.ToInt64() + $i * $entrySize)
            $e = [System.Runtime.InteropServices.Marshal]::PtrToStructure(
                $p, [type][Shyake.MailEntry])
            [pscustomobject]@{
                Id      = [Shyake.Native]::FromUtf8($e.mail_id)
                Party   = [Shyake.Native]::FromUtf8($e.party)
                Subject = [Shyake.Native]::FromUtf8($e.subject)
                Size    = $e.size
                Date    = [DateTimeOffset]::FromUnixTimeSeconds(
                              $e.timestamp).LocalDateTime
            }
        }
    } finally {
        [Shyake.Native]::shyake_free_mail_list($listPtr)
    }
}

function Get-ShyakeInbox {
    <# .SYNOPSIS List inbox mail (decrypted subjects). #>
    [CmdletBinding()] param()
    Get-ShyakeBox -Type 'inbox'
}

function Get-ShyakeSent {
    <# .SYNOPSIS List sent mail. #>
    [CmdletBinding()] param()
    Get-ShyakeBox -Type 'sent'
}

function Receive-ShyakeMail {
    <#
    .SYNOPSIS
    Fetch and decrypt one mail by id. Accepts pipeline input from
    Get-ShyakeInbox.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Id
    )
    process {
        Assert-Connected
        $ptr = [Shyake.Native]::shyake_fetch($script:Ctx,
            [Shyake.Native]::Utf8($Id))
        if ($ptr -eq [IntPtr]::Zero) {
            throw "fetch failed: $(Get-LastShyakeError)"
        }
        try {
            $d = [System.Runtime.InteropServices.Marshal]::PtrToStructure(
                $ptr, [type][Shyake.MailDetail])
            [pscustomobject]@{
                Id        = [Shyake.Native]::FromUtf8($d.mail_id)
                From      = [Shyake.Native]::FromUtf8($d.sender)
                To        = [Shyake.Native]::FromUtf8($d.recipient)
                Subject   = [Shyake.Native]::FromUtf8($d.subject)
                Body      = [Shyake.Native]::FromUtf8($d.body)
                Date      = [DateTimeOffset]::FromUnixTimeSeconds(
                                $d.timestamp).LocalDateTime
            }
        } finally {
            [Shyake.Native]::shyake_free_mail_detail($ptr)
        }
    }
}

function Send-ShyakeMail {
    <#
    .SYNOPSIS
    Encrypt and send a mail. Body accepts pipeline input, so
    `Get-Content note.txt -Raw | Send-ShyakeMail -To bob` works.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$To,
        [string]$Subject = '',
        [Parameter(Mandatory, ValueFromPipeline)] [string]$Body
    )
    process {
        Assert-Connected
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes(
            $Body -replace "`r`n", "`n")
        $rc = [Shyake.Native]::shyake_send($script:Ctx,
            [Shyake.Native]::Utf8($To),
            [Shyake.Native]::Utf8($Subject),
            $bodyBytes, [UIntPtr]$bodyBytes.Length)
        if ($rc -ne 0) {
            throw "send failed ($rc): $(Get-LastShyakeError)"
        }
    }
}

function Remove-ShyakeMail {
    <# .SYNOPSIS Burn a mail on the server (irreversible). #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Id
    )
    process {
        Assert-Connected
        if ($PSCmdlet.ShouldProcess($Id, 'Burn')) {
            $rc = [Shyake.Native]::shyake_burn($script:Ctx,
                [Shyake.Native]::Utf8($Id))
            if ($rc -ne 0) {
                throw "burn failed ($rc): $(Get-LastShyakeError)"
            }
        }
    }
}

Export-ModuleMember -Function Connect-Shyake, Disconnect-Shyake,
    Get-ShyakeInbox, Get-ShyakeSent, Receive-ShyakeMail,
    Send-ShyakeMail, Remove-ShyakeMail
