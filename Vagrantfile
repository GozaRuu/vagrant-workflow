# -*- mode: ruby -*-
# vi: set ft=ruby :

# This vagrant file is for generating the packaging the initial box that will
# be uploaded for the first time.
# 
# First, create the box page with Vagrant Cloud Account
# This URL shoud exist https://https://app.vagrantup.com/YOUR_ACCOUNT_NAME/boxes/YOUR_BOX_NAME
# YOUR_ACCOUNT_NAME and YOUR_BOX_NAME should match what's in `deploy.sh`
#
# Second, run `DRY_RUN=false ACCESS_TOKEN=yourtoken ./deploy --minor`
# to package your box for the fist time under the version 0.1.0

Vagrant.configure("2") do |config|
  config.vm.box = "StefanScherer/windows_10"
  config.vm.box_version = "2020.02.26"
  config.vm.guest = :windows
  config.vm.network "private_network", type: "dhcp"

  config.vm.define :base_box do |node|
    node.vm.provider "virtualbox" do |vb|
      vb.name = 'Base Box'
      vb.gui = true
      vb.cpus = 4
      vb.memory = 4096
      vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    end

    node.vm.provision "shell", privileged: "true", powershell_elevated_interactive: "true", inline: <<-SHELL
      iwr -useb https://chocolatey.org/install.ps1 | iex
    SHELL

    node.vm.provision :reload

    node.vm.provision "shell", privileged: "true", powershell_elevated_interactive: "true", inline: <<-SHELL
      choco install --no-progress --limit-output --yes git python2 nsis putty notepad2-mod rsync curl sed vscode fiddler firefox GoogleChrome autohotkey autoit autoit.commandline autoit.install openssh
      choco install --no-progress --limit-output --yes --forcex86 nodejs --version 10.17.0
      choco install --no-progress --limit-output --yes --forcex86 yarn
    SHELL
  end
end

