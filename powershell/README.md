# Shyake PowerShell module

Script Shyake mail from PowerShell via `shyake.dll`. No client
application required. Works on Windows PowerShell 5.1 and
PowerShell 7+.

## Install

1. Download the release zip for your architecture and extract
   `shyake.dll` and `Shyake.psm1` into one directory
   (the DLL must sit next to the module or on `PATH`).
2. `Import-Module .\Shyake.psm1`

## Profile directory

The module operates on a standard shyake profile directory,
the same format as `~/.config/shyake/` on Unix and
`%APPDATA%\Natsuzake\profiles\<name>\` from the Natsuzake GUI.
Directories are freely copyable between all three.

## Passphrase

Pass `-Passphrase` to `Connect-Shyake`, or set the
`SHYAKE_PASSPHRASE` environment variable (mirrors the Unix CLI).
For unattended scripts prefer the environment variable so the
passphrase never appears in command history:

```powershell
$env:SHYAKE_PASSPHRASE = Read-Host -AsSecureString |
    ConvertFrom-SecureString -AsPlainText   # PS7
```

## Quick start

```powershell
Import-Module .\Shyake.psm1

Connect-Shyake `
    -ConfigDir "$env:APPDATA\Natsuzake\profiles\default" `
    -Instance  'https://shyake.example.com' `
    -Username  'alice'

# list inbox
Get-ShyakeInbox | Format-Table Id, Party, Subject, Date

# read the newest mail
Get-ShyakeInbox | Select-Object -First 1 | Receive-ShyakeMail

# send a file as mail body
Get-Content .\note.txt -Raw |
    Send-ShyakeMail -To bob -Subject 'notes'

# burn everything from a sender (pipeline all the way)
Get-ShyakeInbox | Where-Object Party -eq 'spammer' |
    Remove-ShyakeMail -Confirm:$false

Disconnect-Shyake
```

## Cmdlets

| Cmdlet | Maps to | Notes |
|---|---|---|
| `Connect-Shyake` | `shyake_init_ctx` + `shyake_set_passphrase` | one context per session |
| `Get-ShyakeInbox` / `Get-ShyakeSent` | `shyake_check` | objects with `Id/Party/Subject/Size/Date` |
| `Receive-ShyakeMail -Id` | `shyake_fetch` | pipeline-bindable by `Id` |
| `Send-ShyakeMail -To -Subject -Body` | `shyake_send` | `Body` from pipeline; CRLF normalized to LF |
| `Remove-ShyakeMail -Id` | `shyake_burn` | `-Confirm` by default (irreversible) |
| `Disconnect-Shyake` | `shyake_free_ctx` | zeroizes the passphrase |

## Notes

- Strings cross the FFI boundary as UTF-8; the module handles the
  conversion, so CJK content works in both directions.
- All calls are synchronous; libcurl network timeouts apply.
- Binary attachments follow the shyake convention: base64 the data
  into the body yourself.
