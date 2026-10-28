# 0JayShop Sunshine installer

Install the shop's Sunshine build on a client machine with one line, straight
from GitHub. Nothing to carry but the command.

```powershell
iwr -useb https://raw.githubusercontent.com/fbpinote-svg/0jayshop-sunshine-installer/main/install.ps1 | iex
```

Run it in an **elevated** Windows PowerShell (Start menu, type PowerShell,
right-click, Run as administrator).

## What it does

1. Downloads the program from this repo's release.
2. **Checks its SHA256 against a value pinned inside `install.ps1`** — a tampered
   or intercepted download is refused before the machine is touched.
3. Removes any previous Sunshine, lays the new build down, runs the portable
   installer and the service.
4. Checks that the virtual display can actually create monitors (the
   `IndirectKmd` problem) and offers the known fix.

## The shop config is not in this repo

The program published here is **generic**: no shop IP map, no web login. The real
config is two small files you keep on a USB stick. To seed them while installing:

```powershell
& ([scriptblock]::Create((iwr -useb https://raw.githubusercontent.com/fbpinote-svg/0jayshop-sunshine-installer/main/install.ps1))) -ShopConfig 'E:\shop-config'
```

`-ShopConfig` points at a folder (or a `.zip`) that holds `sunshine.conf` and
`sunshine_state.json`. The same two files work on every machine — each one picks
its own profile by matching its IP. Without `-ShopConfig` the machine installs
and shows the first-run web setup instead.

## Switches

| Switch | Meaning |
|---|---|
| `-ShopConfig <path>` | seed the real shop config from this folder or zip |
| `-Target <path>` | install into this folder (default: the existing install, else `C:\Users\AdminDemo\Sunshine`) |
| `-DryRun` | show what would happen, change nothing |

## Diskless machines

Switch to **Super Mode** before installing, or everything is lost on the next
reboot. Do not install while a customer is streaming.

## License

The program is Sunshine (GPL-3.0), via Sunshine-Foundation and
foundation-sunshine. This installer script is under the same license.
