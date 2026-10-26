# The winget packages for this machine, installed as ~\.config\winget\tools.psd1.
# https://learn.microsoft.com/windows/package-manager/winget/install
#
# The winget-tools setup step runs install-tools.ps1, which installs or upgrades
# every package listed here; run it yourself any time, or without homeskillet:
#   install-tools.ps1 [-NoUpgrade] [-DryRun]
# Each entry needs an Id, matched with `winget install --exact`, which compares
# case too, so copy IDs from `winget show`. Key and Name are for people.
#
# Make and MSYS2 put their commands on PATH only after a PATH edit: add
# C:\Program Files (x86)\GnuWin32\bin for make, and for gcc run
# C:\msys64\usr\bin\pacman.exe -S --needed mingw-w64-ucrt-x86_64-gcc and add
# C:\msys64\ucrt64\bin.
@{
    WingetPackages = @(
        @{ Key = 'PowerShell';      Id = 'Microsoft.PowerShell';          Name = 'PowerShell 7' }
        @{ Key = 'Git';             Id = 'Git.Git';                       Name = 'Git' }
        @{ Key = 'GnuPG';           Id = 'GnuPG.GnuPG';                   Name = 'GnuPG' }
        @{ Key = 'OhMyPosh';        Id = 'JanDeDobbeleer.OhMyPosh';       Name = 'Oh My Posh' }
        @{ Key = 'WindowsTerminal'; Id = 'Microsoft.WindowsTerminal';     Name = 'Windows Terminal' }
        @{ Key = 'Make';            Id = 'GnuWin32.Make';                 Name = 'Make (GnuWin32)' }
        @{ Key = 'MSYS2';           Id = 'MSYS2.MSYS2';                   Name = 'MSYS2' }
        @{ Key = 'Coreutils';       Id = 'Microsoft.Coreutils';           Name = 'Coreutils' }
        @{ Key = 'uv';              Id = 'astral-sh.uv';                  Name = 'uv' }
        @{ Key = 'OpenTofu';        Id = 'OpenTofu.Tofu';                 Name = 'OpenTofu' }
        @{ Key = 'TerraformDocs';   Id = 'Terraform-docs.Terraform-docs'; Name = 'terraform-docs' }
        @{ Key = 'TFLint';          Id = 'TerraformLinters.tflint';       Name = 'TFLint' }
    )
}
