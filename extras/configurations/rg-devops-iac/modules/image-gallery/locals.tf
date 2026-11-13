locals {
  #region image-gallery
  # Scripts the image templates run, delivered inline. The install scripts are shared with the root modules, so
  # deploy-time and image-build installs stay identical. Templates are immutable, so a change to any script they
  # use replaces the template (see replace_triggers_refs in compute.tf).
  image_scripts = {
    enable_microsoft_update = {
      content  = file("${path.module}/scripts/Enable-MicrosoftUpdate.ps1")
      filename = "Enable-MicrosoftUpdate.ps1"
    }
    install_jumplinux_packages = {
      content  = file("${path.module}/../../../../../modules/vm-jumpbox-linux/scripts/install-vm-jumpbox-linux-packages.sh")
      filename = "install-vm-jumpbox-linux-packages.sh"
    }
    install_software = {
      content  = file("${path.module}/../../../../../modules/vnet-app/scripts/Install-Software.ps1")
      filename = "Install-Software.ps1"
    }
    install_windows_features = {
      content  = file("${path.module}/../../../../../modules/vnet-app/scripts/Install-WindowsFeatures.ps1")
      filename = "Install-WindowsFeatures.ps1"
    }
    set_automatic_updates = {
      content  = file("${path.module}/scripts/Set-AutomaticUpdates.ps1")
      filename = "Set-AutomaticUpdates.ps1"
    }
    test_image_jumplinux = {
      content  = file("${path.module}/scripts/test-image-jumplinux.sh")
      filename = "test-image-jumplinux.sh"
    }
    test_image_windows = {
      content  = file("${path.module}/scripts/Test-ImageWindows.ps1")
      filename = "Test-ImageWindows.ps1"
    }
  }

  # The jumplinux validation checks every package in the shared install script's 'packages' array, so the list
  # has a single source.
  image_jumplinux_packages = compact(split("\n", replace(
    regex("(?s)\\npackages=\\(\\n(.*?)\\n\\)", local.image_scripts.install_jumplinux_packages.content)[0], " ", ""
  )))

  # A PowerShell customizer or validation step that writes a script to the build VM and runs it as SYSTEM with
  # the given arguments. Scripts are base64 encoded so they are written byte for byte, with no quoting issues.
  image_powershell_steps = {
    for key, script in local.image_scripts : key => [
      "$ErrorActionPreference = 'Stop'",
      "$path = Join-Path -Path $env:TEMP -ChildPath '${script.filename}'",
      "[System.IO.File]::WriteAllBytes($path, [System.Convert]::FromBase64String('${base64encode(script.content)}'))",
    ] if endswith(script.filename, ".ps1")
  }

  # The shell equivalent of image_powershell_steps. The script is run with sudo by the step that uses it.
  image_shell_steps = {
    for key, script in local.image_scripts : key => [
      "echo '${base64encode(script.content)}' | base64 -d > '/tmp/${script.filename}'",
    ] if endswith(script.filename, ".sh")
  }

  # Windows Update search criteria for Critical Updates and Security Updates that aren't installed or hidden.
  # Used by the WindowsUpdate customizers and by Test-ImageWindows.ps1, so the build and its validation agree.
  image_windows_update_search_criteria = join(" or ", [
    for category_id in [
      "E6CF1350-C01B-414D-A61F-263D14D133B4", # Critical Updates
      "0FA1201D-4330-4FA8-8AE9-B877473B6441", # Security Updates
    ] : "IsInstalled=0 and IsHidden=0 and CategoryIDs contains '${category_id}'"
  ])

  image_windows_update = {
    type           = "WindowsUpdate"
    searchCriteria = local.image_windows_update_search_criteria
    filters        = ["exclude:$_.Title -like '*Preview*'", "include:$true"]
  }

  image_windows_restart = {
    type           = "WindowsRestart"
    restartTimeout = "30m"
  }

  # Windows images are patched last, so updates also cover anything the build installed. Configure Automatic Updates
  # is set after the final restart, so Windows Update doesn't start installing on its own during the build.
  image_windows_patch_steps = [
    merge(local.image_windows_update, { name = "windows-update-1" }),
    merge(local.image_windows_restart, { name = "restart-after-windows-update-1" }),
    merge(local.image_windows_update, { name = "windows-update-2" }),
    merge(local.image_windows_restart, { name = "restart-after-windows-update-2" }),
  ]

  image_set_automatic_updates_step = {
    type        = "PowerShell"
    name        = "set-automatic-updates"
    runElevated = true
    runAsSystem = true
    inline      = concat(local.image_powershell_steps.set_automatic_updates, ["& $path", "exit $LASTEXITCODE"])
  }

  # The images to build, keyed by image definition name. The names are the contract with the Azure Sandbox
  # configuration, so don't change them. Source images match the root modules' platform image defaults.
  images = {
    adds = {
      description = "Domain controller (adds1): Windows Server 2025 Datacenter Azure Edition Core, fully patched. AD DS is installed at deploy time because Sysprep doesn't support the AD DS role."
      os_type     = "Windows"
      source = {
        publisher = "MicrosoftWindowsServer"
        offer     = "WindowsServer"
        sku       = "2025-datacenter-azure-edition-core"
      }

      # Patching only. Configure Automatic Updates is left alone; adds1 sets it at deploy time, after the forest
      # promotion restart.
      customize = local.image_windows_patch_steps
    }

    jumpwin = {
      description = "Windows jumpbox (jumpwin1): Windows Server 2025 Datacenter Azure Edition with RSAT, VS Code, SSMS and MySQL Workbench, fully patched."
      os_type     = "Windows"
      source = {
        publisher = "MicrosoftWindowsServer"
        offer     = "WindowsServer"
        sku       = "2025-datacenter-azure-edition"
      }

      customize = concat(
        [
          {
            type        = "PowerShell"
            name        = "install-windows-features"
            runElevated = true
            runAsSystem = true
            inline      = concat(local.image_powershell_steps.install_windows_features, ["& $path", "exit $LASTEXITCODE"])
          },
          {
            type        = "PowerShell"
            name        = "install-software"
            runElevated = true
            runAsSystem = true
            inline      = concat(local.image_powershell_steps.install_software, ["& $path -InstallAll true", "exit $LASTEXITCODE"])
          },
          merge(local.image_windows_restart, { name = "restart-after-install" }),
        ],
        local.image_windows_patch_steps,
        [local.image_set_automatic_updates_step]
      )
    }

    jumplinux = {
      description = "Linux jumpbox (jumplinux1): Ubuntu Server 24.04 LTS with the jumpbox packages, fully upgraded."
      os_type     = "Linux"
      source = {
        publisher = "Canonical"
        offer     = "ubuntu-24_04-lts"
        sku       = "server"
      }

      # Azure VM Image Builder has no Linux restart customizer, and a Shell step that reboots the VM fails the build.
      # The upgraded kernel takes effect when a VM is first deployed from the image.
      customize = [
        {
          type = "Shell"
          name = "install-jumplinux-packages"
          inline = concat(local.image_shell_steps.install_jumplinux_packages, [
            "sudo cloud-init status --wait > /dev/null || true",
            "sudo bash /tmp/${local.image_scripts.install_jumplinux_packages.filename} --image-build",
            "rm -f /tmp/${local.image_scripts.install_jumplinux_packages.filename}",
          ])
        },
      ]
    }

    mssqlwin = {
      description = "SQL Server VM (mssqlwin1): SQL Server 2025 Enterprise Developer on Windows Server 2025, fully patched including SQL Server updates from Microsoft Update."
      os_type     = "Windows"
      source = {
        publisher = "MicrosoftSQLServer"
        offer     = "sql2025-ws2025"
        sku       = "entdev-gen2"
      }

      # Opting into Microsoft Update first lets the Windows Update passes install SQL Server updates too.
      customize = concat(
        [
          {
            type        = "PowerShell"
            name        = "enable-microsoft-update"
            runElevated = true
            runAsSystem = true
            inline      = concat(local.image_powershell_steps.enable_microsoft_update, ["& $path", "exit $LASTEXITCODE"])
          },
        ],
        local.image_windows_patch_steps,
        [local.image_set_automatic_updates_step]
      )
    }
  }

  # In-VM validation for each image. A failure stops the build before the image is distributed. The two for
  # expressions are merged, rather than using a conditional, because the Windows and Linux steps have different types.
  image_validations = merge(
    {
      for key, image in local.images : key => [
        {
          type        = "PowerShell"
          name        = "test-image-${key}"
          runElevated = true
          runAsSystem = true
          inline = concat(local.image_powershell_steps.test_image_windows, [
            "& $path -ImageName '${key}' -UpdateSearchCriteria \"${local.image_windows_update_search_criteria}\"",
            "exit $LASTEXITCODE",
          ])
        },
      ] if image.os_type == "Windows"
    },
    {
      for key, image in local.images : key => [
        {
          type = "Shell"
          name = "test-image-${key}"
          inline = concat(local.image_shell_steps.test_image_jumplinux, [
            "sudo bash /tmp/${local.image_scripts.test_image_jumplinux.filename} ${join(" ", local.image_jumplinux_packages)}",
            "rm -f /tmp/${local.image_scripts.test_image_jumplinux.filename}",
          ])
        },
      ] if image.os_type == "Linux"
    }
  )
  #endregion

}
