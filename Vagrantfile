Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-22.04"
  config.vm.box_version = "202502.21.0"
  config.vm.hostname = "petclinic-prod"

  config.vm.network "private_network", ip: "192.168.56.10"
  config.vm.network "forwarded_port", guest: 8080, host: 8082

  config.vm.provider "vmware_desktop" do |v|
    v.memory = "2048"
    v.cpus = 2
    v.vmx["displayname"] = "petclinic-prod"
  end

  config.vm.provider "virtualbox" do |vb|
    vb.memory = "2048"
    vb.cpus = 2
    vb.name = "petclinic-prod"
  end

  config.vm.provision "shell", inline: <<-SHELL
    apt-get update
    apt-get install -y openjdk-17-jre-headless
  SHELL
end
